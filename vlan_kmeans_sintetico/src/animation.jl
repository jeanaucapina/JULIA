using Plots, Statistics, LinearAlgebra, Random

# ── PCA 2D projection ─────────────────────────────────────────────────────────

"""
    pca2d(X) -> (Z::Matrix{Float64}, explained::Float64)

Project n×p matrix X to n×2 via PCA (first 2 principal components).
Returns projected matrix and variance explained ratio.
"""
function pca2d(X::Matrix{Float64})::Tuple{Matrix{Float64}, Float64}
    n   = size(X, 1)
    μ   = mean(X, dims=1)
    Xc  = X .- μ
    C   = (Xc' * Xc) ./ (n - 1)
    F   = eigen(Symmetric(C))
    # eigen returns ascending order — take last 2 (largest variance)
    idx = [size(F.vectors, 2), size(F.vectors, 2) - 1]
    V2  = F.vectors[:, idx]          # p × 2
    Z   = Xc * V2                    # n × 2
    explained = sum(F.values[idx]) / sum(F.values)
    return Z, explained
end

"""
    project_centroids(centroids, X, Z) -> Matrix{Float64}

Project cluster centroids into the same 2D PCA space as X.
centroids: K × p in original (normalized) feature space.
Returns K × 2 matrix.
"""
function project_centroids(
    centroids ::Vector{Vector{Float64}},
    X         ::Matrix{Float64}
)::Matrix{Float64}
    n  = size(X, 1)
    μ  = mean(X, dims=1)
    Xc = X .- μ
    # recompute PCA basis
    C  = (Xc' * Xc) ./ (n - 1)
    F  = eigen(Symmetric(C))
    idx = [size(F.vectors, 2), size(F.vectors, 2) - 1]
    V2  = F.vectors[:, idx]
    # project each centroid: (p,) → (2,) → stack into K×2
    rows = [vec((c .- vec(μ))' * V2) for c in centroids]
    return reduce(hcat, rows)'  # K × 2
end

# ── K-means with history capture ──────────────────────────────────────────────

"""
    kmeans_animated(X, K; seed, maxiter, tol) -> NamedTuple

Run K-means and record full history:
  - labels at each iteration
  - centroid positions at each iteration
  - inertia at each iteration

Used to generate animation frames.
"""
function kmeans_animated(
    X       ::Matrix{Float64},
    K       ::Int;
    seed    ::Int     = 42,
    maxiter ::Int     = 50,
    tol     ::Float64 = 1e-6
)::NamedTuple
    Random.seed!(seed)

    # K-means++ init
    n  = size(X, 1)
    μ  = Vector{Vector{Float64}}()
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

    # record init state (before first assignment)
    push!(centroids_hist, deepcopy(μ))
    init_labels = [argmin([sum((X[i,:] .- c).^2) for c in μ]) for i in 1:n]
    push!(labels_hist, init_labels)
    push!(inertia_hist, sum(sum((X[i,:] .- μ[init_labels[i]]).^2) for i in 1:n))

    labels = copy(init_labels)
    n_iter = maxiter

    for iter in 1:maxiter
        old_μ = deepcopy(μ)

        # M-step
        for k in 1:K
            idx = findall(==(k), labels)
            μ[k] = isempty(idx) ? X[rand(1:n), :] : vec(mean(X[idx, :], dims=1))
        end

        # E-step
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

# ── Animation ─────────────────────────────────────────────────────────────────

const CLUSTER_COLORS = [
    :dodgerblue, :tomato, :seagreen, :darkorange,
    :purple, :brown, :magenta, :teal
]

"""
    animate_kmeans(X, K, output_path;
                   seed, fps, pause_frames, feature_names) -> String

Generate animated GIF of K-means convergence.
X is the normalized feature matrix (n × p).
Projects to 2D via PCA for visualization.

Frames:
  1.  Initialization frame  — raw data, K-means++ centroids
  2…N. One frame per iteration — points colored by current assignment,
        centroids shown as large stars with trails
  N+1. Final frame — held for 2 seconds, purity summary if available

Returns path to saved GIF.
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

    # PCA projection
    Z, var_exp = pca2d(X)
    pct = round(100 * var_exp, digits=1)

    # run with history
    hist = kmeans_animated(X, K; seed=seed)

    # project all centroid histories
    cent_proj_hist = [project_centroids(c, X) for c in hist.centroids_history]

    x_min, x_max = minimum(Z[:,1]) - 0.5, maximum(Z[:,1]) + 0.5
    y_min, y_max = minimum(Z[:,2]) - 0.5, maximum(Z[:,2]) + 0.5

    colors = CLUSTER_COLORS[1:K]
    n_frames = length(hist.labels_history)

    anim = Animation()

    for frame_idx in 1:n_frames
        labels    = hist.labels_history[frame_idx]
        cent_proj = cent_proj_hist[frame_idx]
        iner      = hist.inertia_history[frame_idx]
        is_init   = frame_idx == 1
        is_final  = frame_idx == n_frames

        iter_label = is_init  ? "Init (K-means++)" :
                     is_final ? "Converged (iter $(frame_idx-1))" :
                                "Iteration $(frame_idx - 1)"

        # ── base scatter: data points colored by cluster ──────────────────
        p = plot(
            xlims  = (x_min, x_max),
            ylims  = (y_min, y_max),
            xlabel = "PC1",
            ylabel = "PC2",
            title  = "K-Means VLAN Inference — $iter_label\nInertia: $(round(iner, digits=1))  |  PCA variance: $pct%",
            titlefontsize = 10,
            size   = (800, 560),
            dpi    = 120,
            legend = :topright,
            grid   = true,
            gridalpha = 0.3,
            framestyle = :box
        )

        for k in 1:K
            mask = findall(==(k), labels)
            isempty(mask) && continue
            scatter!(p,
                Z[mask, 1], Z[mask, 2],
                color       = colors[k],
                alpha       = is_init ? 0.25 : 0.65,
                markersize  = 5,
                markerstrokewidth = 0.3,
                label       = "VLAN_$(k*10)"
            )
        end

        # ── centroid trail (last 3 positions) ────────────────────────────
        if frame_idx > 1
            trail_start = max(1, frame_idx - 3)
            for k in 1:K
                trail_x = [cent_proj_hist[t][k, 1] for t in trail_start:frame_idx]
                trail_y = [cent_proj_hist[t][k, 2] for t in trail_start:frame_idx]
                plot!(p, trail_x, trail_y,
                    color     = colors[k],
                    alpha     = 0.35,
                    linewidth = 1.5,
                    label     = false
                )
            end
        end

        # ── centroids as stars ────────────────────────────────────────────
        for k in 1:K
            scatter!(p,
                [cent_proj[k, 1]], [cent_proj[k, 2]],
                color            = colors[k],
                markersize       = is_init ? 14 : 16,
                markershape      = :star5,
                markerstrokecolor= :black,
                markerstrokewidth= 1.5,
                label            = false
            )
        end

        # ── inertia mini-bar on frame (bottom annotation) ─────────────────
        if !is_init
            max_iner = hist.inertia_history[1]
            pct_done = 1.0 - iner / max_iner
            annotate!(p, x_min + 0.1, y_min + 0.2,
                text("Progress: $(round(100*pct_done, digits=0))% inertia reduction",
                     :left, 7, :gray40))
        end

        frame(anim)

        # hold final frame
        if is_final
            for _ in 1:pause_frames
                frame(anim)
            end
        end
    end

    gif(anim, output_path; fps=fps)
    println("  Animation saved: $output_path  ($(n_frames) frames, fps=$fps)")
    return output_path
end

"""
    animate_elbow(ks, inertias, silhouettes, best_k, output_path; fps) -> String

Animate the K-selection process: bars grow one by one showing
inertia and silhouette for each K tested.
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
            color       = bar_cols,
            alpha       = 0.8,
            xlabel      = "K",
            ylabel      = "Inertia (WCSS)",
            title       = "Elbow Method",
            legend      = false,
            xlims       = (ks[1]-0.5, ks[end]+0.5),
            ylims       = (0, max_iner * 1.1),
            titlefontsize = 10
        )
        reveal > 1 && plot!(p1, k_shown, in_shown,
            color=:navy, linewidth=1.5, marker=:circle, markersize=4, label=false)

        p2 = bar(k_shown, si_shown,
            color       = bar_cols,
            alpha       = 0.8,
            xlabel      = "K",
            ylabel      = "Silhouette score",
            title       = "Silhouette (higher = better)",
            legend      = false,
            xlims       = (ks[1]-0.5, ks[end]+0.5),
            ylims       = (0, min(1.0, max_sil * 1.3)),
            titlefontsize = 10
        )
        if reveal == length(ks)
            hline!(p2, [max_sil], color=:red, linestyle=:dash,
                   linewidth=1.5, label="optimal")
            annotate!(p2, best_k, max_sil * 1.08,
                text("K=$best_k ◄", :center, 9, :red))
        end

        plot(p1, p2, layout=(1,2), size=(900, 400), dpi=110,
             plot_title="K-Selection: Elbow + Silhouette")
        frame(anim)
    end
    # hold last frame
    for _ in 1:6
        frame(anim)
    end

    gif(anim, output_path; fps=fps)
    println("  Animation saved: $output_path")
    return output_path
end
