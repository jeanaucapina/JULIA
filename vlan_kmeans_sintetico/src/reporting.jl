using DataFrames, CSV, Statistics, Printf, Dates

# ── VLAN table ────────────────────────────────────────────────────────────────

"""
    build_vlan_table(hosts, flows, assignments; latent_ref) -> DataFrame

Per-VLAN metrics. If latent_ref provided (simulation mode), also computes purity.
In real PCAP mode, latent_ref = nothing → purity column omitted.
"""
function build_vlan_table(
    hosts       ::DataFrame,
    flows       ::DataFrame,
    assignments ::Vector{Int};
    latent_ref  ::Union{Vector{Int}, Nothing} = nothing
)::DataFrame
    vlans = sort(unique(assignments))
    rows  = []

    for v in vlans
        host_mask = assignments .== v
        host_ids  = hosts.host_id[host_mask]
        host_ips  = hosts.ip[host_mask]
        n_h       = length(host_ids)
        host_set  = Set(host_ids)

        intra_fl = 0; inter_fl = 0
        intra_by = 0; inter_by = 0

        for r in eachrow(flows)
            r.src_id in host_set || continue
            if assignments[r.src_id] == assignments[r.dst_id]
                intra_fl += 1; intra_by += r.bytes
            else
                inter_fl += 1; inter_by += r.bytes
            end
        end

        total_fl = intra_fl + inter_fl
        total_by = intra_by + inter_by
        pct_fl   = total_fl > 0 ? round(100.0 * intra_fl / total_fl, digits=1) : 0.0
        pct_by   = total_by > 0 ? round(100.0 * intra_by / total_by, digits=1) : 0.0
        avg_bpf  = total_fl > 0 ? round(total_by / total_fl, digits=1) : 0.0

        row = (
            vlan_id           = v,
            vlan_name         = "VLAN_$(v * 10)",
            n_hosts           = n_h,
            host_list         = join(host_ips, ";"),
            intra_flows       = intra_fl,
            inter_flows       = inter_fl,
            total_flows       = total_fl,
            pct_intra_flows   = pct_fl,
            intra_bytes       = intra_by,
            inter_bytes       = inter_by,
            total_bytes       = total_by,
            pct_intra_bytes   = pct_by,
            avg_bytes_per_flow= avg_bpf
        )

        if !isnothing(latent_ref)
            lat   = latent_ref[host_mask]
            dom   = argmax([count(==(l), lat) for l in unique(lat)])
            pur   = count(==(unique(lat)[dom]), lat) / n_h
            row   = merge(row, (purity=round(pur, digits=3),))
        end

        push!(rows, row)
    end

    return DataFrame(rows)
end

"""
    build_traffic_summary(flows, assignments) -> DataFrame
"""
function build_traffic_summary(flows::DataFrame, assignments::Vector{Int})::DataFrame
    tf_i = 0; tf_e = 0; by_i = 0; by_e = 0
    for r in eachrow(flows)
        if assignments[r.src_id] == assignments[r.dst_id]
            tf_i += 1; by_i += r.bytes
        else
            tf_e += 1; by_e += r.bytes
        end
    end
    tf = tf_i + tf_e; by = by_i + by_e
    DataFrame(
        metric = ["total_flows","intra_flows","inter_flows","pct_intra_flows",
                  "total_bytes","intra_bytes","inter_bytes","pct_intra_bytes",
                  "avg_bytes_per_flow"],
        value  = [tf, tf_i, tf_e,
                  round(100.0*tf_i/max(tf,1), digits=1),
                  by, by_i, by_e,
                  round(100.0*by_i/max(by,1), digits=1),
                  round(by/max(tf,1), digits=1)]
    )
end

# ── Test-set evaluation ───────────────────────────────────────────────────────

"""
    evaluate_test(hosts, test_flows, test_assignments, train_assignments) -> DataFrame

Compare VLAN assignments on test vs train data.
Computes per-VLAN stability: fraction of test hosts that land in same cluster as train.
Only meaningful in simulation mode where hosts appear in both splits.
"""
function evaluate_test(
    test_assignments ::Vector{Int},
    train_assignments::Vector{Int}
)::DataFrame
    vlans = sort(unique(train_assignments))
    rows  = []
    for v in vlans
        train_mask = train_assignments .== v
        test_mask  = test_assignments  .== v
        overlap    = sum(train_mask .& test_mask)
        total_train= sum(train_mask)
        stability  = total_train > 0 ? round(overlap / total_train, digits=3) : 0.0
        push!(rows, (vlan_id=v, vlan_name="VLAN_$(v*10)",
                     train_hosts=total_train, test_hosts=sum(test_mask),
                     stable_hosts=overlap, stability=stability))
    end
    return DataFrame(rows)
end

# ── IP → VLAN mapping table ───────────────────────────────────────────────────

"""
    build_ip_vlan_map(hosts, assignments, feat_df) -> DataFrame

Produces the actionable table an admin would use:
  IP address → inferred VLAN → key traffic profile features.
"""
function build_ip_vlan_map(
    hosts       ::DataFrame,
    assignments ::Vector{Int},
    feat_df     ::DataFrame
)::DataFrame
    DataFrame(
        ip            = hosts.ip,
        inferred_vlan = ["VLAN_$(assignments[i]*10)" for i in 1:nrow(hosts)],
        subnet        = hosts.subnet,
        out_flows     = feat_df.out_flows,
        in_flows      = feat_df.in_flows,
        bytes_per_flow= round.(feat_df.bytes_per_flow, digits=1),
        tcp_ratio     = round.(feat_df.tcp_ratio,      digits=3),
        ratio_intra   = round.(feat_df.ratio_intra,    digits=3),
        port_entropy  = round.(feat_df.port_entropy,   digits=3),
        med_duration  = round.(feat_df.med_duration,   digits=1)
    )
end

# ── Save all outputs ──────────────────────────────────────────────────────────

"""
    save_reports(vlan_tbl, traffic_sum, k_stats, best_k, sil, output_dir;
                 test_eval, ip_map, mode) -> String

Write all CSVs, print console summary, return report_dir path.
mode: :sim (has ground truth) | :real (no ground truth)
"""
function save_reports(
    vlan_tbl    ::DataFrame,
    traffic_sum ::DataFrame,
    k_stats     ::DataFrame,
    best_k      ::Int,
    sil         ::Float64,
    output_dir  ::String;
    test_eval   ::Union{DataFrame,Nothing} = nothing,
    ip_map      ::Union{DataFrame,Nothing} = nothing,
    mode        ::Symbol = :sim
)::String
    report_dir = joinpath(output_dir, "report")
    mkpath(report_dir)

    CSV.write(joinpath(report_dir, "tabla_vlans.csv"),       vlan_tbl)
    CSV.write(joinpath(report_dir, "resumen_trafico.csv"),   traffic_sum)
    CSV.write(joinpath(report_dir, "k_selection_stats.csv"), k_stats)
    !isnothing(test_eval) && CSV.write(joinpath(report_dir, "test_evaluation.csv"), test_eval)
    !isnothing(ip_map)    && CSV.write(joinpath(report_dir, "ip_vlan_map.csv"),     ip_map)

    _print_summary(vlan_tbl, traffic_sum, k_stats, best_k, sil, test_eval, mode)

    return report_dir
end

function _print_summary(vlan_tbl, traffic_sum, k_stats, best_k, sil, test_eval, mode)
    println("\n" * "═"^56)
    println("  VLAN INFERENCE REPORT")
    mode == :sim  && println("  Mode: Simulation (ground truth available)")
    mode == :real && println("  Mode: Real PCAP (unsupervised)")
    println("  Date: $(Dates.today())")
    println("═"^56)
    @printf("  K selected  : %d  (silhouette = %.4f)\n", best_k, sil)

    println("\n  K-selection:")
    println("  ─────────────────────────────────────────────────────")
    for r in eachrow(k_stats)
        mark = r.k == best_k ? "◄" : " "
        @printf("  %s K=%-2d  inertia=%-10.1f  sil=%.4f\n",
            mark, r.k, r.inertia, r.silhouette)
    end

    println("\n  Per-VLAN summary:")
    println("  ─────────────────────────────────────────────────────")
    for r in eachrow(vlan_tbl)
        pur_str = hasproperty(vlan_tbl, :purity) ? @sprintf("  purity=%.3f", r.purity) : ""
        @printf("  %-10s  hosts=%-3d  intra=%.1f%%%s\n",
            r.vlan_name, r.n_hosts, r.pct_intra_flows, pur_str)
    end

    if !isnothing(test_eval)
        println("\n  Test-set stability (train→test host overlap):")
        println("  ─────────────────────────────────────────────────────")
        for r in eachrow(test_eval)
            @printf("  %-10s  train=%-3d  test=%-3d  stability=%.3f\n",
                r.vlan_name, r.train_hosts, r.test_hosts, r.stability)
        end
    end

    println("\n  Traffic summary:")
    println("  ─────────────────────────────────────────────────────")
    for r in eachrow(traffic_sum)
        @printf("  %-25s : %s\n", r.metric, r.value)
    end
    println("═"^56 * "\n")
end
