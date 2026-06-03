using Plots, Statistics, LinearAlgebra, Random

# ── PCA 2D ────────────────────────────────────────────────────────────────────

function pca2d(X::Matrix{Float64})::Tuple{Matrix{Float64}, Float64}
    n  = size(X, 1)
    μ  = mean(X, dims=1)
    Xc = X .- μ
    C  = (Xc' * Xc) ./ (n - 1)
    F  = eigen(Symmetric(C))
    idx = [size(F.vectors, 2), size(F.vectors, 2) - 1]
    V2  = F.vectors[:, idx]
    Z   = Xc * V2
    explained = sum(F.values[idx]) / sum(abs.(F.values))
    return Z, explained
end

function project_centroids(
    centroids ::Vector{Vector{Float64}},
    X         ::Matrix{Float64}
)::Matrix{Float64}
    n  = size(X, 1)
    μ  = mean(X, dims=1)
    Xc = X .- μ
    C  = (Xc' * Xc) ./ (n - 1)
    F  = eigen(Symmetric(C))
    idx = [size(F.vectors, 2), size(F.vectors, 2) - 1]
    V2  = F.vectors[:, idx]
    rows = [vec((c .- vec(μ))' * V2) for c in centroids]
    return reduce(hcat, rows)'
end

# ── K-means con historial ─────────────────────────────────────────────────────

function kmeans_animated(
    X       ::Matrix{Float64},
    K       ::Int;
    seed    ::Int     = 42,
    maxiter ::Int     = 50,
    tol     ::Float64 = 1e-6
)::NamedTuple
    Random.seed!(seed)
    n = size(X, 1)
    μ = Vector{Vector{Float64}}()
    push!(μ, X[rand(1:n), :])
    for _ in 2:K
        D     = [minimum(sum((X[i,:] .- c).^2) for c in μ) for i in 1:n]
        total = sum(D)
        total == 0.0 && break
        probs = D ./ total
        r     = rand()
        j     = findfirst(cumsum(probs) .>= r)
        push!(μ, X[isnothing(j) ? n : j, :])
    end

    labels_hist    = Vector{Vector{Int}}()
    centroids_hist = Vector{Vector{Vector{Float64}}}()
    inertia_hist   = Float64[]

    push!(centroids_hist, deepcopy(μ))
    init_labels = [argmin([sum((X[i,:] .- c).^2) for c in μ]) for i in 1:n]
    push!(labels_hist, init_labels)
    push!(inertia_hist, sum(sum((X[i,:] .- μ[init_labels[i]]).^2) for i in 1:n))

    labels = copy(init_labels)
    n_iter = maxiter

    for iter in 1:maxiter
        old_μ = deepcopy(μ)
        for k in 1:K
            idx = findall(==(k), labels)
            μ[k] = isempty(idx) ? X[rand(1:n), :] : vec(mean(X[idx, :], dims=1))
        end
        labels = [argmin([sum((X[i,:] .- c).^2) for c in μ]) for i in 1:n]
        iner   = sum(sum((X[i,:] .- μ[labels[i]]).^2) for i in 1:n)
        push!(centroids_hist, deepcopy(μ))
        push!(labels_hist, copy(labels))
        push!(inertia_hist, iner)
        if all(norm(μ[k] .- old_μ[k]) < tol for k in 1:K)
            n_iter = iter
            break
        end
    end

    return (
        labels_history    = labels_hist,
        centroids_history = centroids_hist,
        inertia_history   = inertia_hist,
        n_iter            = n_iter,
        K                 = K,
        final_labels      = labels,
        final_centroids   = μ
    )
end

# ── Colores y etiquetas por cluster ──────────────────────────────────────────

const CLUSTER_COLORS = [:seagreen, :darkorange, :tomato, :dodgerblue, :purple, :brown]
const CLUSTER_LABELS = ["Mant. Programado", "Mant. Urgente", "Reemplazo", "C4", "C5", "C6"]

# ── GIF convergencia K-means ──────────────────────────────────────────────────

"""
    animate_kmeans(X, K, output_path; seed, fps, pause_frames) -> String

GIF mostrando cómo K-means converge: puntos coloreados por cluster,
centroides como estrellas con trail, barra de progreso de inercia.
"""
function animate_kmeans(
    X            ::Matrix{Float64},
    K            ::Int,
    output_path  ::String;
    seed         ::Int = 42,
    fps          ::Int = 3,
    pause_frames ::Int = 6
)::String
    mkpath(dirname(output_path))

    Z, var_exp = pca2d(X)
    pct = round(100 * var_exp, digits=1)

    hist = kmeans_animated(X, K; seed=seed)
    cent_proj_hist = [project_centroids(c, X) for c in hist.centroids_history]

    x_min, x_max = minimum(Z[:,1]) - 0.5, maximum(Z[:,1]) + 0.5
    y_min, y_max = minimum(Z[:,2]) - 0.5, maximum(Z[:,2]) + 0.5

    colors = CLUSTER_COLORS[1:K]
    labels_txt = CLUSTER_LABELS[1:K]
    n_frames = length(hist.labels_history)

    anim = Animation()

    for frame_idx in 1:n_frames
        labels    = hist.labels_history[frame_idx]
        cent_proj = cent_proj_hist[frame_idx]
        iner      = hist.inertia_history[frame_idx]
        is_init   = frame_idx == 1
        is_final  = frame_idx == n_frames

        iter_label = is_init  ? "Inicialización (K-means++)" :
                     is_final ? "Convergido (iter $(frame_idx-1))" :
                                "Iteración $(frame_idx - 1)"

        p = plot(
            xlims  = (x_min, x_max),
            ylims  = (y_min, y_max),
            xlabel = "PC1",
            ylabel = "PC2",
            title  = "K-Means Actuadores Robóticos — $iter_label\nInercia: $(round(iner, digits=1))  |  Varianza PCA: $pct%",
            titlefontsize = 9,
            size   = (820, 580),
            dpi    = 110,
            legend = :topright,
            grid   = true,
            gridalpha   = 0.3,
            framestyle  = :box,
            background_color = :white
        )

        for k in 1:K
            mask = findall(==(k), labels)
            isempty(mask) && continue
            scatter!(p,
                Z[mask, 1], Z[mask, 2],
                color             = colors[k],
                alpha             = is_init ? 0.20 : 0.60,
                markersize        = 5,
                markerstrokewidth = 0.3,
                label             = labels_txt[k]
            )
        end

        # trail de centroides
        if frame_idx > 1
            trail_start = max(1, frame_idx - 3)
            for k in 1:K
                trail_x = [cent_proj_hist[t][k, 1] for t in trail_start:frame_idx]
                trail_y = [cent_proj_hist[t][k, 2] for t in trail_start:frame_idx]
                plot!(p, trail_x, trail_y,
                    color=colors[k], alpha=0.35, linewidth=1.5, label=false)
            end
        end

        # centroides como estrellas
        for k in 1:K
            scatter!(p,
                [cent_proj[k, 1]], [cent_proj[k, 2]],
                color             = colors[k],
                markersize        = is_init ? 14 : 16,
                markershape       = :star5,
                markerstrokecolor = :black,
                markerstrokewidth = 1.5,
                label             = false
            )
        end

        if !is_init
            max_iner = hist.inertia_history[1]
            pct_done = 1.0 - iner / max_iner
            annotate!(p, x_min + 0.1, y_min + 0.25,
                text("Reducción inercia: $(round(100*pct_done, digits=0))%",
                     :left, 7, :gray40))
        end

        frame(anim)
        if is_final
            for _ in 1:pause_frames
                frame(anim)
            end
        end
    end

    gif(anim, output_path; fps=fps)
    println("  GIF convergencia: $output_path  ($n_frames frames, fps=$fps)")
    return output_path
end

# ── GIF selección de K ────────────────────────────────────────────────────────

"""
    animate_elbow(ks, inertias, silhouettes, best_k, output_path; fps) -> String

Revela K valores uno a uno mostrando inercia y silhouette en barras.
"""
function animate_elbow(
    ks          ::Vector{Int},
    inertias    ::Vector{Float64},
    silhouettes ::Vector{Float64},
    best_k      ::Int,
    output_path ::String;
    fps         ::Int = 4
)::String
    mkpath(dirname(output_path))
    anim = Animation()

    max_iner = maximum(inertias)
    max_sil  = maximum(silhouettes)

    for reveal in 1:length(ks)
        k_shown  = ks[1:reveal]
        in_shown = inertias[1:reveal]
        si_shown = silhouettes[1:reveal]
        bar_cols = [k == best_k ? :tomato : :steelblue for k in k_shown]

        p1 = bar(k_shown, in_shown,
            color     = bar_cols,
            alpha     = 0.8,
            xlabel    = "K (clusters)",
            ylabel    = "Inercia (WCSS)",
            title     = "Método del Codo",
            legend    = false,
            xlims     = (ks[1]-0.5, ks[end]+0.5),
            ylims     = (0, max_iner * 1.1),
            titlefontsize = 10,
            xticks    = ks
        )
        reveal > 1 && plot!(p1, k_shown, in_shown,
            color=:navy, linewidth=1.5, marker=:circle, markersize=4, label=false)

        p2 = bar(k_shown, si_shown,
            color     = bar_cols,
            alpha     = 0.8,
            xlabel    = "K (clusters)",
            ylabel    = "Silhouette score",
            title     = "Silhouette (mayor = mejor)",
            legend    = false,
            xlims     = (ks[1]-0.5, ks[end]+0.5),
            ylims     = (0, min(1.0, max_sil * 1.35)),
            titlefontsize = 10,
            xticks    = ks
        )
        if reveal == length(ks)
            hline!(p2, [max_sil], color=:red, linestyle=:dash,
                   linewidth=1.5, label=false)
            annotate!(p2, best_k, max_sil * 1.12,
                text("K=$best_k ◄ óptimo", :center, 9, :red))
        end

        plot(p1, p2,
            layout     = (1, 2),
            size       = (920, 420),
            dpi        = 110,
            plot_title = "Selección de K — Actuadores Robóticos"
        )
        frame(anim)
    end

    for _ in 1:6
        frame(anim)
    end

    gif(anim, output_path; fps=fps)
    println("  GIF K-selection: $output_path")
    return output_path
end

# ── GIF scatter por feature ───────────────────────────────────────────────────

"""
    animate_feature_scatter(df, assignments, cluster_names, output_path; fps) -> String

Muestra scatter de features clave coloreados por cluster asignado:
  pct_vida_util vs tasa_fallo, vibracion vs temperatura, drift vs eficiencia.
"""
function animate_feature_scatter(
    df            ::Any,   # DataFrame con columnas de features
    assignments   ::Vector{Int},
    cluster_names ::Vector{String},
    output_path   ::String;
    fps           ::Int = 2
)::String
    mkpath(dirname(output_path))
    anim = Animation()
    K = length(unique(assignments))
    colors = CLUSTER_COLORS[1:K]

    pairs = [
        (:pct_vida_util,        :tasa_fallo_por_1000h, "% Vida Útil",          "Tasa Fallos/1000h"),
        (:vibracion_rms,        :temperatura_operacion_c, "Vibración RMS (mm/s)", "Temperatura (°C)"),
        (:drift_posicional_mm,  :eficiencia_energetica,   "Drift Posicional (mm)","Eficiencia Energética"),
        (:dias_desde_mantenimiento, :corriente_promedio_a, "Días sin Mantenimiento","Corriente Prom. (A)"),
    ]

    for (xcol, ycol, xlabel, ylabel) in pairs
        xv = Float64.(df[!, xcol])
        yv = Float64.(df[!, ycol])

        p = plot(
            xlabel = xlabel,
            ylabel = ylabel,
            title  = "Clusters — $xlabel vs $ylabel",
            titlefontsize = 10,
            size   = (750, 500),
            dpi    = 110,
            legend = :topright,
            grid   = true,
            gridalpha = 0.3,
            framestyle = :box
        )

        for k in sort(unique(assignments))
            mask = findall(==(k), assignments)
            isempty(mask) && continue
            lbl = k <= length(cluster_names) ? cluster_names[k] : "C$k"
            scatter!(p,
                xv[mask], yv[mask],
                color             = colors[k],
                alpha             = 0.65,
                markersize        = 6,
                markerstrokewidth = 0.3,
                label             = lbl
            )
        end

        frame(anim)
        frame(anim)   # hold each panel 2 frames
    end

    for _ in 1:4
        frame(anim)
    end

    gif(anim, output_path; fps=fps)
    println("  GIF feature scatter: $output_path")
    return output_path
end
