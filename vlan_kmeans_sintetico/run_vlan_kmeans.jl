using Random
using Statistics
using CSV
using DataFrames
using Clustering

# Synthetic network with latent VLAN behavior; K-means recovers VLAN-like groups.
const OUTPUT_DIR = joinpath(@__DIR__, "results")
mkpath(OUTPUT_DIR)

Random.seed!(42)

"""
Build a stable list of private IPv4 addresses grouped by latent VLAN.
"""
function make_hosts(n_vlans::Int, hosts_per_vlan::Int)
    ips = String[]
    latent_vlan = Int[]
    for v in 1:n_vlans
        for h in 1:hosts_per_vlan
            push!(ips, "10.$v.0.$(h + 9)")
            push!(latent_vlan, v)
        end
    end
    return DataFrame(host_id = 1:length(ips), ip = ips, latent_vlan = latent_vlan)
end

"""
Generate flow records (PCAP-like table): src_ip, dst_ip, packets, bytes, timestamp.
"""
function synthetic_flows(hosts::DataFrame; n_flows::Int = 1500, p_intra::Float64 = 0.83)
    flows = DataFrame(
        ts = Int[],
        src_id = Int[],
        dst_id = Int[],
        src_ip = String[],
        dst_ip = String[],
        packets = Int[],
        bytes = Int[]
    )

    n_hosts = nrow(hosts)
    for t in 1:n_flows
        src = rand(1:n_hosts)
        src_vlan = hosts.latent_vlan[src]

        if rand() < p_intra
            candidates = findall(hosts.latent_vlan .== src_vlan)
        else
            candidates = findall(hosts.latent_vlan .!= src_vlan)
        end
        candidates = filter(x -> x != src, candidates)
        dst = rand(candidates)

        pkts = rand(2:20)
        avg_pkt = rand(180:1400)
        total_bytes = pkts * avg_pkt

        push!(flows, (
            ts = t,
            src_id = src,
            dst_id = dst,
            src_ip = hosts.ip[src],
            dst_ip = hosts.ip[dst],
            packets = pkts,
            bytes = total_bytes
        ))
    end

    return flows
end

"""
Compute host-level features from flows for unsupervised VLAN inference.
"""
function host_features(hosts::DataFrame, flows::DataFrame)
    n = nrow(hosts)
    out_flows = zeros(Float64, n)
    in_flows = zeros(Float64, n)
    out_bytes = zeros(Float64, n)
    in_bytes = zeros(Float64, n)
    peers = [Set{Int}() for _ in 1:n]

    for r in eachrow(flows)
        s = r.src_id
        d = r.dst_id
        out_flows[s] += 1
        in_flows[d] += 1
        out_bytes[s] += r.bytes
        in_bytes[d] += r.bytes
        push!(peers[s], d)
        push!(peers[d], s)
    end

    unique_peers = [length(peers[i]) for i in 1:n]

    X = hcat(out_flows, in_flows, out_bytes, in_bytes, unique_peers)
    μ = mean(X, dims = 1)
    σ = std(X, dims = 1)
    σ[σ .== 0.0] .= 1.0
    Xz = (X .- μ) ./ σ

    feat = DataFrame(
        host_id = hosts.host_id,
        ip = hosts.ip,
        out_flows = out_flows,
        in_flows = in_flows,
        out_bytes = out_bytes,
        in_bytes = in_bytes,
        unique_peers = unique_peers
    )

    return Xz, feat
end

"""
Export graph edge lists (global and per VLAN) as CSV files.
"""
function export_graph_tables(flows::DataFrame, predicted_vlan::Vector{Int})
    edge_tbl = DataFrame(src_ip = String[], dst_ip = String[], src_vlan = Int[], dst_vlan = Int[], bytes = Int[])
    for r in eachrow(flows)
        s_vlan = predicted_vlan[r.src_id]
        d_vlan = predicted_vlan[r.dst_id]
        push!(edge_tbl, (r.src_ip, r.dst_ip, s_vlan, d_vlan, r.bytes))
    end

    CSV.write(joinpath(OUTPUT_DIR, "flujos_con_vlan.csv"), edge_tbl)

    global_edges = combine(
        groupby(edge_tbl, [:src_ip, :dst_ip, :src_vlan, :dst_vlan]),
        :bytes => sum => :bytes_sum,
        nrow => :n_flujos
    )
    CSV.write(joinpath(OUTPUT_DIR, "grafo_global_aristas.csv"), global_edges)

    for v in sort(unique(predicted_vlan))
        intra = filter(r -> r.src_vlan == v && r.dst_vlan == v, global_edges)
        CSV.write(joinpath(OUTPUT_DIR, "grafo_vlan_$(v)_aristas.csv"), intra)
    end

    inter_vlan = filter(r -> r.src_vlan != r.dst_vlan, global_edges)
    CSV.write(joinpath(OUTPUT_DIR, "grafo_inter_vlan_aristas.csv"), inter_vlan)
end

function main()
    n_vlans = 3
    hosts_per_vlan = 12

    hosts = make_hosts(n_vlans, hosts_per_vlan)
    flows = synthetic_flows(hosts; n_flows = 1800, p_intra = 0.85)

    CSV.write(joinpath(OUTPUT_DIR, "synthetic_pcap_like_flows.csv"), flows)

    Xz, feat = host_features(hosts, flows)

    km = kmeans(permutedims(Xz), n_vlans; maxiter = 300, display = :none)
    predicted_vlan = vec(km.assignments)

    vlan_table = DataFrame(
        host_id = hosts.host_id,
        ip = hosts.ip,
        vlan_id = predicted_vlan,
        vlan_name = ["VLAN_$(10 * x)" for x in predicted_vlan],
        latent_vlan_ref = hosts.latent_vlan
    )
    sort!(vlan_table, [:vlan_id, :ip])
    CSV.write(joinpath(OUTPUT_DIR, "tabla_vlans.csv"), vlan_table)

    export_graph_tables(flows, predicted_vlan)

    println("Pipeline terminado.")
    println("Salidas en: ", OUTPUT_DIR)
    println("- synthetic_pcap_like_flows.csv")
    println("- tabla_vlans.csv")
    println("- flujos_con_vlan.csv")
    println("- grafo_global_aristas.csv")
    println("- grafo_vlan_1_aristas.csv, grafo_vlan_2_aristas.csv, grafo_vlan_3_aristas.csv")
    println("- grafo_inter_vlan_aristas.csv")
end

main()
