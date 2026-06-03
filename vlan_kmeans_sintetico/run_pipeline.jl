"""
run_pipeline.jl — VLAN inference pipeline

Usage:
    julia run_pipeline.jl [mode] [options]

Modes (pick one):
    --sim               Simulate synthetic traffic (default)
    --csv  <path>       Load flow CSV (tshark export or generic)
    --pcap <path>       Same as --csv; expects tshark-exported CSV

Simulation options (--sim mode):
    --vlans   N         Latent VLANs to simulate      (default: 3, max: 5)
    --hosts   N         Hosts per VLAN                (default: 12)
    --flows   N         Total synthetic flows          (default: 3000)
    --p-intra F         P(flow stays in same VLAN)    (default: 0.85)
    --seed    N         RNG seed                       (default: 42)
    --train-ratio F     Train/test split ratio         (default: 0.70)

Clustering options:
    --k-min   N         Min K to evaluate             (default: 2)
    --k-max   N         Max K to evaluate             (default: 8)
    --k-fixed N         Skip auto-selection, use this K
    --n-init  N         K-means restarts per K        (default: 10)

Output:
    --output  DIR       Output root directory          (default: results/)
    --no-graphs         Skip graph CSV/DOT export

Examples:
    julia run_pipeline.jl --sim --vlans 4 --flows 5000
    julia run_pipeline.jl --csv capture_flows.csv
    julia run_pipeline.jl --csv capture_flows.csv --k-fixed 3

tshark export command:
    tshark -r capture.pcap -T fields \\
      -e frame.number -e ip.src -e ip.dst \\
      -e tcp.srcport -e tcp.dstport \\
      -e udp.srcport -e udp.dstport \\
      -e ip.proto -e frame.len -e frame.time_relative \\
      -E header=y -E separator=, -E quote=d \\
      > capture_flows.csv
"""

const PROJ_DIR = @__DIR__
const SRC_DIR  = joinpath(PROJ_DIR, "src")

include(joinpath(SRC_DIR, "synthesis.jl"))
include(joinpath(SRC_DIR, "pcap_reader.jl"))
include(joinpath(SRC_DIR, "features.jl"))
include(joinpath(SRC_DIR, "clustering.jl"))
include(joinpath(SRC_DIR, "graphs.jl"))
include(joinpath(SRC_DIR, "reporting.jl"))
include(joinpath(SRC_DIR, "animation.jl"))

using CSV, DataFrames, Printf

# ── CLI argument parsing ──────────────────────────────────────────────────────

function parse_args(args)
    cfg = Dict{Symbol,Any}(
        :mode        => :sim,
        :input_path  => nothing,
        :n_vlans     => 3,
        :hosts_per_vlan => 12,
        :n_flows     => 3000,
        :p_intra     => 0.85,
        :seed        => 42,
        :train_ratio => 0.70,
        :k_min       => 2,
        :k_max       => 8,
        :k_fixed     => nothing,
        :n_init      => 10,
        :output_dir  => joinpath(PROJ_DIR, "results"),
        :no_graphs   => false,
    )
    i = 1
    while i <= length(args)
        a = args[i]
        if     a == "--sim"         cfg[:mode]          = :sim;                      i += 1
        elseif a == "--csv"         cfg[:mode]          = :csv;
                                    cfg[:input_path]    = args[i+1];                 i += 2
        elseif a == "--pcap"        cfg[:mode]          = :csv;
                                    cfg[:input_path]    = args[i+1];                 i += 2
        elseif a == "--vlans"       cfg[:n_vlans]       = parse(Int,     args[i+1]); i += 2
        elseif a == "--hosts"       cfg[:hosts_per_vlan]= parse(Int,     args[i+1]); i += 2
        elseif a == "--flows"       cfg[:n_flows]        = parse(Int,     args[i+1]); i += 2
        elseif a == "--p-intra"     cfg[:p_intra]        = parse(Float64, args[i+1]); i += 2
        elseif a == "--seed"        cfg[:seed]           = parse(Int,     args[i+1]); i += 2
        elseif a == "--train-ratio" cfg[:train_ratio]    = parse(Float64, args[i+1]); i += 2
        elseif a == "--k-min"       cfg[:k_min]          = parse(Int,     args[i+1]); i += 2
        elseif a == "--k-max"       cfg[:k_max]          = parse(Int,     args[i+1]); i += 2
        elseif a == "--k-fixed"     cfg[:k_fixed]        = parse(Int,     args[i+1]); i += 2
        elseif a == "--n-init"      cfg[:n_init]         = parse(Int,     args[i+1]); i += 2
        elseif a == "--output"      cfg[:output_dir]     = args[i+1];                 i += 2
        elseif a == "--no-graphs"   cfg[:no_graphs]      = true;                      i += 1
        else
            @warn "Unknown argument: $a"
            i += 1
        end
    end
    return cfg
end

# ── Pipeline stages ───────────────────────────────────────────────────────────

function stage_load(cfg)
    if cfg[:mode] == :sim
        println("[1/5] Generating synthetic traffic...")
        hosts  = make_hosts(cfg[:n_vlans], cfg[:hosts_per_vlan])
        flows  = synthetic_flows(hosts;
                     n_flows  = cfg[:n_flows],
                     p_intra  = cfg[:p_intra],
                     seed     = cfg[:seed])
        train_flows, test_flows = train_test_split(flows;
                     train_ratio = cfg[:train_ratio],
                     seed        = cfg[:seed])
        @printf("    %d hosts | %d total flows | train=%d test=%d\n",
            nrow(hosts), nrow(flows), nrow(train_flows), nrow(test_flows))
        return hosts, train_flows, test_flows, :sim
    else
        println("[1/5] Loading flow data from: $(cfg[:input_path])")
        flows, hosts = read_generic_csv(cfg[:input_path])
        train_flows, test_flows = train_test_split(flows;
                     train_ratio = cfg[:train_ratio],
                     seed        = cfg[:seed])
        @printf("    %d unique hosts | %d flows | train=%d test=%d\n",
            nrow(hosts), nrow(flows), nrow(train_flows), nrow(test_flows))
        return hosts, train_flows, test_flows, :real
    end
end

function stage_features(hosts, train_flows)
    println("[2/5] Computing host features (10 features per host)...")
    Xz, feat_df = compute_features(hosts, train_flows)
    @printf("    Feature matrix: %d × %d  (ratio_intra weight=×2)\n", size(Xz)...)
    return Xz, feat_df
end

function stage_cluster(Xz, cfg)
    println("[3/5] Selecting K and running K-means...")
    k_range = cfg[:k_min]:cfg[:k_max]

    if isnothing(cfg[:k_fixed])
        best_k, k_stats, best_run = auto_select_k(Xz;
            k_range = k_range,
            n_init  = cfg[:n_init])
        print_k_stats(k_stats, best_k)
    else
        best_k  = cfg[:k_fixed]
        best_run = kmeans_best(Xz, best_k; n_init=cfg[:n_init])
        k_stats  = DataFrame(k=[best_k],
                             inertia=[last(best_run.inertia_history)],
                             silhouette=[silhouette_score(Xz, best_run.labels)],
                             elbow_score=[0.0])
        println("    K fixed by user: $best_k")
    end

    sil = silhouette_score(Xz, best_run.labels)
    @printf("    K=%d | converged in %d iters | inertia=%.1f | silhouette=%.4f\n",
        best_k, best_run.n_iter, last(best_run.inertia_history), sil)

    return best_k, best_run, k_stats, sil
end

function stage_test_eval(hosts, test_flows, centroids, train_assignments)
    println("[4/5] Evaluating on test split...")
    test_assignments = assign_new_flows(hosts, test_flows, centroids)
    sil_test = silhouette_score(
        compute_features(hosts, test_flows)[1],
        test_assignments
    )
    @printf("    Test silhouette: %.4f\n", sil_test)

    eval_df = evaluate_test(test_assignments, train_assignments)
    return test_assignments, eval_df, sil_test
end

function stage_output(hosts, train_flows, train_assignments, feat_df,
                      best_k, best_run, k_stats, sil,
                      test_eval, mode, cfg, Xz)
    println("[5/5] Building outputs...")
    out = cfg[:output_dir]
    raw_dir = joinpath(out, "raw")
    mkpath(raw_dir)

    # raw data
    CSV.write(joinpath(raw_dir, "hosts.csv"),        hosts)
    CSV.write(joinpath(raw_dir, "train_flows.csv"),  train_flows)
    CSV.write(joinpath(raw_dir, "host_features.csv"), feat_df)

    # graph CSVs
    if !cfg[:no_graphs]
        edge_tbl = build_edge_table(train_flows, train_assignments)
        export_graph_csvs(edge_tbl, out)
        export_dot_files(edge_tbl, out)
        export_gexf(edge_tbl, out)
    end

    # reports
    latent_ref = mode == :sim ? hosts.latent_vlan : nothing
    vlan_tbl   = build_vlan_table(hosts, train_flows, train_assignments;
                     latent_ref = latent_ref)
    traffic_sum = build_traffic_summary(train_flows, train_assignments)
    ip_map      = build_ip_vlan_map(hosts, train_assignments, feat_df)

    save_reports(vlan_tbl, traffic_sum, k_stats, best_k, sil, out;
        test_eval = test_eval,
        ip_map    = ip_map,
        mode      = mode)

    # animations
    anim_dir = joinpath(out, "animations")
    println("  Generating animations...")
    animate_kmeans(Xz, best_k, joinpath(anim_dir, "kmeans_convergence.gif");
        seed=cfg[:seed], fps=3)
    animate_elbow(k_stats.k, k_stats.inertia, k_stats.silhouette, best_k,
        joinpath(anim_dir, "k_selection.gif"); fps=4)

    println("  Outputs written to: $out")
    println("  ├─ raw/                  hosts, flows, features")
    println("  ├─ graphs/               edge lists per VLAN")
    println("  ├─ plots/                DOT + GEXF (Gephi/Graphviz)")
    println("  ├─ animations/           kmeans_convergence.gif, k_selection.gif")
    println("  └─ report/               VLANs, traffic summary, ip_vlan_map.csv")
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main(args)
    println("=" ^ 56)
    println("  VLAN INFERENCE via K-MEANS (unsupervised)")
    println("  Universidad de Cuenca | DEET")
    println("=" ^ 56)

    cfg = parse_args(args)

    hosts, train_flows, test_flows, mode = stage_load(cfg)
    Xz, feat_df                          = stage_features(hosts, train_flows)
    best_k, best_run, k_stats, sil       = stage_cluster(Xz, cfg)

    train_assignments = best_run.labels

    test_eval = if nrow(test_flows) > 0
        _, ev, _ = stage_test_eval(
            hosts, test_flows, best_run.centroids, train_assignments)
        ev
    else
        nothing
    end

    stage_output(hosts, train_flows, train_assignments, feat_df,
                 best_k, best_run, k_stats, sil,
                 test_eval, mode, cfg, Xz)
end

main(ARGS)
