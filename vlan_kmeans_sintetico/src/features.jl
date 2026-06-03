using DataFrames, Statistics

# ── Feature list (10 features) ────────────────────────────────────────────────
#
#  # | Feature           | Discriminates
#  --+-------------------+------------------------------------------------------
#  1 | out_flows         | volume
#  2 | in_flows          | volume
#  3 | out_bytes         | volume
#  4 | in_bytes          | volume
#  5 | unique_peers      | fan-out (servers vs. clients)
#  6 | bytes_per_flow    | app type: VoIP=small, DB=large
#  7 | ratio_intra       | KEY — same /24 fraction (VLAN signal)
#  8 | tcp_ratio         | app type: TCP=web/ssh, UDP=voip/iot
#  9 | entropy_ports     | role: server (low) vs. client (high)
# 10 | median_duration   | session type: short=dns/voip, long=ssh/db
#
# ratio_intra is weighted ×2 before z-score to amplify VLAN separation.
# ─────────────────────────────────────────────────────────────────────────────

"""
    compute_features(hosts, flows) -> (Xz::Matrix{Float64}, feat_df::DataFrame)

Extract 10 host-level features from flow records.
Returns z-score normalized matrix Xz (n × 10) and raw feature DataFrame.
ratio_intra is weighted ×2 before normalization.
"""
function compute_features(hosts::DataFrame, flows::DataFrame)::Tuple{Matrix{Float64}, DataFrame}
    n = nrow(hosts)

    subnet_of = Dict(
        hosts.ip[i] => join(split(hosts.ip[i], ".")[1:3], ".") for i in 1:n
    )

    out_flows    = zeros(Float64, n)
    in_flows     = zeros(Float64, n)
    out_bytes    = zeros(Float64, n)
    in_bytes     = zeros(Float64, n)
    intra_flows  = zeros(Float64, n)
    tcp_out      = zeros(Float64, n)
    peers        = [Set{Int}() for _ in 1:n]
    dst_ports    = [Int[] for _ in 1:n]       # for port entropy
    durations    = [Float64[] for _ in 1:n]   # for median duration

    for r in eachrow(flows)
        s = r.src_id
        d = r.dst_id
        out_flows[s] += 1
        in_flows[d]  += 1
        out_bytes[s] += r.bytes
        in_bytes[d]  += r.bytes
        push!(peers[s], d)
        push!(peers[d], s)
        push!(dst_ports[s], r.dst_port)
        push!(durations[s], Float64(r.duration_ms))

        if subnet_of[r.src_ip] == subnet_of[r.dst_ip]
            intra_flows[s] += 1
        end
        if r.protocol == "TCP"
            tcp_out[s] += 1
        end
    end

    unique_peers   = Float64[length(peers[i]) for i in 1:n]
    bytes_per_flow = out_bytes ./ max.(out_flows, 1.0)
    ratio_intra    = intra_flows ./ max.(out_flows, 1.0)
    tcp_ratio      = tcp_out ./ max.(out_flows, 1.0)
    port_entropy   = Float64[shannon_entropy(dst_ports[i]) for i in 1:n]
    med_duration   = Float64[isempty(durations[i]) ? 0.0 : median(durations[i]) for i in 1:n]

    X = hcat(
        out_flows,
        in_flows,
        out_bytes,
        in_bytes,
        unique_peers,
        bytes_per_flow,
        ratio_intra,
        tcp_ratio,
        port_entropy,
        med_duration
    )  # n × 10

    Xz = zscore_normalize(X; weights=feature_weights())

    feat_df = DataFrame(
        host_id       = hosts.host_id,
        ip            = hosts.ip,
        out_flows     = out_flows,
        in_flows      = in_flows,
        out_bytes     = out_bytes,
        in_bytes      = in_bytes,
        unique_peers  = unique_peers,
        bytes_per_flow= bytes_per_flow,
        ratio_intra   = ratio_intra,
        tcp_ratio     = tcp_ratio,
        port_entropy  = port_entropy,
        med_duration  = med_duration
    )

    return Xz, feat_df
end

"""
    feature_weights() -> Vector{Float64}

Per-feature multipliers applied before z-score.
ratio_intra ×2 dominates VLAN separation.
tcp_ratio ×1.5 reinforces protocol profile.
port_entropy ×1.5 reinforces role separation.
"""
function feature_weights()::Vector{Float64}
    return [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 2.0, 1.5, 1.5, 1.0]
end

"""
    zscore_normalize(X; weights) -> Matrix{Float64}

Column-wise z-score with optional per-column weight multipliers.
Columns with σ=0 become zero. weights applied after normalization.
"""
function zscore_normalize(X::Matrix{Float64}; weights::Vector{Float64}=ones(size(X,2)))::Matrix{Float64}
    μ = mean(X, dims=1)
    σ = std(X,  dims=1)
    σ[σ .== 0.0] .= 1.0
    Xz = (X .- μ) ./ σ
    return Xz .* reshape(weights, 1, :)
end

"""
    shannon_entropy(ports) -> Float64

Shannon entropy of port distribution (bits).
Low = server (always same port), high = client (many random ports).
"""
function shannon_entropy(ports::Vector{Int})::Float64
    isempty(ports) && return 0.0
    counts = values(countmap(ports))
    total  = length(ports)
    probs  = [c / total for c in counts]
    return -sum(p * log2(p) for p in probs if p > 0)
end

"""
    countmap(v) -> Dict

Count occurrences of each unique value in v.
"""
function countmap(v::Vector{T}) where T
    d = Dict{T,Int}()
    for x in v
        d[x] = get(d, x, 0) + 1
    end
    return d
end

"""
    assign_new_flows(hosts, new_flows, centroids, feat_df_train) -> Vector{Int}

Classify new hosts from test flows using trained centroids.
Hosts not seen in train get assigned by nearest centroid in feature space.
Returns vlan assignments aligned with hosts DataFrame.
"""
function assign_new_flows(
    hosts        ::DataFrame,
    new_flows    ::DataFrame,
    centroids    ::Vector{Vector{Float64}}
)::Vector{Int}
    n = nrow(hosts)
    Xz, _ = compute_features(hosts, new_flows)
    labels = Vector{Int}(undef, n)
    for i in 1:n
        x = Xz[i, :]
        labels[i] = argmin([sum((x .- c).^2) for c in centroids])
    end
    return labels
end

