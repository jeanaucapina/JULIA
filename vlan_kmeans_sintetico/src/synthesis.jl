using Random, DataFrames, CSV

# ── VLAN profiles ─────────────────────────────────────────────────────────────
# Each profile defines realistic traffic behavior for a network segment type.
# Profiles map latent_vlan index → named tuple of traffic characteristics.
const VLAN_PROFILES = Dict(
    1 => (name="Web/App",    dst_ports=80:443,    proto="TCP", byte_range=500:15000,  pkt_range=3:80,  dur_range=50:5000),
    2 => (name="VoIP/Media", dst_ports=5000:5100, proto="UDP", byte_range=40:220,     pkt_range=1:10,  dur_range=10:60),
    3 => (name="SSH/Mgmt",   dst_ports=22:22,     proto="TCP", byte_range=200:3000,   pkt_range=2:30,  dur_range=100:8000),
    4 => (name="DB/Backend", dst_ports=3306:5432, proto="TCP", byte_range=1000:50000, pkt_range=5:200, dur_range=5:500),
    5 => (name="IoT/Sensor", dst_ports=1883:1884, proto="UDP", byte_range=20:150,     pkt_range=1:5,   dur_range=1:30),
)

"""
    make_hosts(n_vlans, hosts_per_vlan) -> DataFrame

Build host table. Each VLAN gets its own /24 subnet (10.v.0.x).
Columns: host_id, ip, subnet, latent_vlan, vlan_name
"""
function make_hosts(n_vlans::Int, hosts_per_vlan::Int)::DataFrame
    n_vlans = min(n_vlans, length(VLAN_PROFILES))
    ips        = String[]
    latent     = Int[]
    subnets    = String[]
    names      = String[]
    for v in 1:n_vlans
        profile = VLAN_PROFILES[v]
        for h in 1:hosts_per_vlan
            push!(ips,     "10.$v.0.$(h + 9)")
            push!(latent,  v)
            push!(subnets, "10.$v.0.0/24")
            push!(names,   profile.name)
        end
    end
    return DataFrame(
        host_id    = 1:length(ips),
        ip         = ips,
        subnet     = subnets,
        latent_vlan = latent,
        vlan_name  = names
    )
end

"""
    synthetic_flows(hosts; n_flows, p_intra, seed) -> DataFrame

Generate realistic flow records with per-VLAN port/protocol/size profiles.
p_intra = probability a flow stays within its VLAN (typical corporate: 0.75-0.90).

Returns DataFrame with columns matching a tshark CSV export:
  ts, src_id, dst_id, src_ip, dst_ip,
  src_port, dst_port, protocol,
  packets, bytes, duration_ms
"""
function synthetic_flows(
    hosts    ::DataFrame;
    n_flows  ::Int     = 3000,
    p_intra  ::Float64 = 0.85,
    seed     ::Int     = 42
)::DataFrame
    Random.seed!(seed)

    ts_v    = Int[];   src_id_v  = Int[];    dst_id_v   = Int[]
    sip_v   = String[]; dip_v   = String[]
    sp_v    = Int[];   dp_v     = Int[];    proto_v    = String[]
    pkts_v  = Int[];   bytes_v  = Int[];    dur_v      = Int[]

    n_hosts = nrow(hosts)
    vlan_idx = Dict(v => findall(hosts.latent_vlan .== v) for v in unique(hosts.latent_vlan))

    for t in 1:n_flows
        src      = rand(1:n_hosts)
        sv       = hosts.latent_vlan[src]
        profile  = get(VLAN_PROFILES, sv, VLAN_PROFILES[1])

        candidates = if rand() < p_intra
            filter(x -> x != src, vlan_idx[sv])
        else
            other_vlans = filter(v -> v != sv, keys(vlan_idx))
            isempty(other_vlans) && continue
            target_vlan = rand(collect(other_vlans))
            vlan_idx[target_vlan]
        end
        isempty(candidates) && continue
        dst = rand(candidates)

        # port/proto from profile, with 15% random noise to simulate real traffic
        if rand() < 0.85
            dp    = rand(profile.dst_ports)
            proto = profile.proto
            nb    = rand(profile.byte_range)
            pkts  = rand(profile.pkt_range)
            dur   = rand(profile.dur_range)
        else
            dp    = rand(1024:65535)
            proto = rand(["TCP","UDP","ICMP"])
            nb    = rand(40:65000)
            pkts  = rand(1:100)
            dur   = rand(1:10000)
        end
        sp = rand(1024:65535)

        push!(ts_v,   t);   push!(src_id_v, src); push!(dst_id_v, dst)
        push!(sip_v,  hosts.ip[src]); push!(dip_v, hosts.ip[dst])
        push!(sp_v,   sp);  push!(dp_v, dp);    push!(proto_v, proto)
        push!(pkts_v, pkts); push!(bytes_v, nb); push!(dur_v, dur)
    end

    return DataFrame(
        ts          = ts_v,
        src_id      = src_id_v,
        dst_id      = dst_id_v,
        src_ip      = sip_v,
        dst_ip      = dip_v,
        src_port    = sp_v,
        dst_port    = dp_v,
        protocol    = proto_v,
        packets     = pkts_v,
        bytes       = bytes_v,
        duration_ms = dur_v
    )
end

"""
    train_test_split(flows; train_ratio, seed) -> (train_df, test_df)

Split flows chronologically (by ts). Train = first `train_ratio` fraction.
Simulates having historical PCAP for training and new capture for testing.
"""
function train_test_split(
    flows       ::DataFrame;
    train_ratio ::Float64 = 0.70,
    seed        ::Int     = 42
)::Tuple{DataFrame, DataFrame}
    sorted = sort(flows, :ts)
    n      = nrow(sorted)
    cutoff = floor(Int, n * train_ratio)
    return sorted[1:cutoff, :], sorted[cutoff+1:end, :]
end
