"""
Pipeline: Clustering de Actuadores Robóticos con K-Means

Uso:
  julia --project=. run_pipeline.jl [opciones]

Opciones:
  --n-piezas N     Total de piezas sintéticas (default: 120)
  --seed N         Semilla RNG (default: 42)
  --k-min N        K mínimo a evaluar (default: 2)
  --k-max N        K máximo a evaluar (default: 6)
  --k-fixed N      Usar K fijo, omitir auto-selección
  --n-init N       Corridas K-means por K (default: 10)
  --train-ratio F  Fracción de entrenamiento (default: 0.70)
  --output DIR     Directorio de salida (default: results)
  --no-anim        Omitir generación de GIFs
"""

# ── Dependencias ───────────────────────────────────────────────────────────────
using Pkg
# Silently activate project if not already active
if !isfile(joinpath(@__DIR__, "Manifest.toml"))
    Pkg.activate(@__DIR__)
    Pkg.instantiate()
else
    Pkg.activate(@__DIR__)
end

include(joinpath(@__DIR__, "src", "synthesis.jl"))
include(joinpath(@__DIR__, "src", "features.jl"))
include(joinpath(@__DIR__, "src", "clustering.jl"))
include(joinpath(@__DIR__, "src", "animation.jl"))
include(joinpath(@__DIR__, "src", "reporting.jl"))

using CSV, DataFrames, Dates

# ── Parseo de argumentos ───────────────────────────────────────────────────────

function parse_args(args)
    cfg = Dict{Symbol,Any}(
        :n_piezas    => 120,
        :seed        => 42,
        :k_min       => 2,
        :k_max       => 6,
        :k_fixed     => nothing,
        :n_init      => 10,
        :train_ratio => 0.70,
        :output      => joinpath(@__DIR__, "results"),
        :no_anim     => false,
    )
    i = 1
    while i <= length(args)
        a = args[i]
        if     a == "--n-piezas"    cfg[:n_piezas]    = parse(Int,     args[i+1]); i += 2
        elseif a == "--seed"        cfg[:seed]        = parse(Int,     args[i+1]); i += 2
        elseif a == "--k-min"       cfg[:k_min]       = parse(Int,     args[i+1]); i += 2
        elseif a == "--k-max"       cfg[:k_max]       = parse(Int,     args[i+1]); i += 2
        elseif a == "--k-fixed"     cfg[:k_fixed]     = parse(Int,     args[i+1]); i += 2
        elseif a == "--n-init"      cfg[:n_init]      = parse(Int,     args[i+1]); i += 2
        elseif a == "--train-ratio" cfg[:train_ratio] = parse(Float64, args[i+1]); i += 2
        elseif a == "--output"      cfg[:output]      = args[i+1];                 i += 2
        elseif a == "--no-anim"     cfg[:no_anim]     = true;                      i += 1
        else
            @warn "Argumento desconocido: $a"
            i += 1
        end
    end
    return cfg
end

# ── Pipeline principal ─────────────────────────────────────────────────────────

function run_pipeline(cfg::Dict)
    println("\n" * "━"^60)
    println("  PIPELINE CLUSTERING — ACTUADORES ROBÓTICOS")
    println("  Fecha: $(Dates.today())")
    println("━"^60)

    out_dir   = cfg[:output]
    anim_dir  = joinpath(out_dir, "animations")
    raw_dir   = joinpath(out_dir, "raw")
    mkpath(anim_dir)
    mkpath(raw_dir)

    # ── 1. Generar datos sintéticos ───────────────────────────────────────────
    println("\n[1/6] Generando dataset sintético…")
    df = generate_actuators(cfg[:n_piezas]; seed=cfg[:seed])
    println("  Total piezas: $(nrow(df))")
    println("  Distribución clases: " *
        join(["C$c=$(count(==(c), df.clase_latente))" for c in sort(unique(df.clase_latente))], "  "))

    train_df, test_df = train_test_split(df;
        train_ratio=cfg[:train_ratio], seed=cfg[:seed])
    println("  Train: $(nrow(train_df))  |  Test: $(nrow(test_df))")

    # Guardar raw CSV
    CSV.write(joinpath(raw_dir, "piezas_completo.csv"), df)
    CSV.write(joinpath(raw_dir, "piezas_train.csv"),   train_df)
    CSV.write(joinpath(raw_dir, "piezas_test.csv"),    test_df)

    # ── 2. Extraer features ───────────────────────────────────────────────────
    println("\n[2/6] Extrayendo y normalizando features…")
    X_train, _, fit_stats = compute_features(train_df)
    X_test,  _, _         = compute_features(test_df; fit_stats=fit_stats)
    println("  Matriz train: $(size(X_train))  |  test: $(size(X_test))")

    # ── 3. Selección de K ─────────────────────────────────────────────────────
    println("\n[3/6] Seleccionando K óptimo…")
    best_k, k_stats, best_run = if !isnothing(cfg[:k_fixed])
        k = cfg[:k_fixed]
        r = kmeans_best(X_train, k; n_init=cfg[:n_init])
        sil_only = DataFrame(k=[k], inertia=[last(r.inertia_history)],
                             silhouette=[silhouette_score(X_train, r.labels)],
                             elbow_score=[0.0])
        k, sil_only, r
    else
        auto_select_k(X_train;
            k_range = cfg[:k_min]:cfg[:k_max],
            n_init  = cfg[:n_init]
        )
    end

    sil = silhouette_score(X_train, best_run.labels)
    print_k_stats(k_stats, best_k)

    # ── 4. Asignar clusters a train y test ────────────────────────────────────
    println("\n[4/6] Asignando clusters…")
    train_assignments = best_run.labels
    test_assignments  = assign_labels(X_test, best_run.centroids)

    # Construir tablas
    cluster_tbl = build_cluster_table(train_df, train_assignments;
                                      latent_ref=train_df.clase_latente)
    piece_map   = build_piece_map(train_df, train_assignments)
    test_eval   = evaluate_test(train_assignments, test_assignments)

    # Guardar CSVs y consola
    report_dir = save_reports(cluster_tbl, k_stats, best_k, sil, out_dir;
        piece_map=piece_map, test_eval=test_eval, mode=:sim)
    println("  CSVs → $report_dir")

    # ── 5. Generar GIFs ───────────────────────────────────────────────────────
    if !cfg[:no_anim]
        println("\n[5/6] Generando animaciones…")

        animate_kmeans(X_train, best_k,
            joinpath(anim_dir, "kmeans_convergencia.gif");
            seed=cfg[:seed], fps=3, pause_frames=8)

        ks  = k_stats.k
        ins = Float64.(k_stats.inertia)
        sis = Float64.(k_stats.silhouette)
        animate_elbow(ks, ins, sis, best_k,
            joinpath(anim_dir, "k_selection.gif"); fps=4)

        animate_feature_scatter(train_df, train_assignments,
            CLUSTER_NAMES[1:min(best_k, length(CLUSTER_NAMES))],
            joinpath(anim_dir, "feature_scatter.gif"); fps=2)
    else
        println("\n[5/6] Animaciones omitidas (--no-anim)")
    end

    # ── 6. Generar reporte.md ─────────────────────────────────────────────────
    println("\n[6/6] Generando reporte.md…")
    write_reporte_md(cluster_tbl, k_stats, piece_map, best_k, sil, out_dir;
        test_eval = test_eval,
        n_total   = nrow(df),
        n_train   = nrow(train_df),
        n_test    = nrow(test_df),
        mode      = :sim
    )

    println("\n" * "━"^60)
    println("  ✓ Pipeline completado")
    println("  Resultados en: $out_dir")
    println("━"^60 * "\n")
end

# ── Entry point ────────────────────────────────────────────────────────────────
cfg = parse_args(ARGS)
run_pipeline(cfg)
