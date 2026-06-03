using Statistics, DataFrames, LinearAlgebra, Random, Printf

# ── K-Means from scratch ──────────────────────────────────────────────────────

"""
    dist2(x, c) -> Float64

Squared Euclidean distance ‖x − c‖². Avoids sqrt; argmin unchanged.
"""
@inline dist2(x::AbstractVector, c::AbstractVector)::Float64 = sum((x .- c).^2)

"""
    init_plusplus(X, K; seed) -> Vector{Vector{Float64}}

K-means++ initialization. First centroid random; subsequent centroids chosen
with probability ∝ D(x)² (distance to nearest existing centroid).
Produces well-separated initial centroids → fewer iterations, better optima.
"""
function init_plusplus(X::Matrix{Float64}, K::Int; seed::Int=42)::Vector{Vector{Float64}}
    Random.seed!(seed)
    n  = size(X, 1)
    μ  = Vector{Vector{Float64}}()
    push!(μ, X[rand(1:n), :])
    for _ in 2:K
        D     = [minimum(dist2(X[i, :], c) for c in μ) for i in 1:n]
        total = sum(D)
        total == 0.0 && break
        probs = D ./ total
        r     = rand()
        j     = findfirst(cumsum(probs) .>= r)
        push!(μ, X[isnothing(j) ? n : j, :])
    end
    return μ
end

"""
    assign_labels(X, centroids) -> Vector{Int}

E-step: assign each point to nearest centroid. O(n·K·d).
"""
function assign_labels(X::Matrix{Float64}, centroids::Vector{Vector{Float64}})::Vector{Int}
    n = size(X, 1)
    [argmin([dist2(X[i, :], c) for c in centroids]) for i in 1:n]
end

"""
    update_centroids(X, labels, K) -> Vector{Vector{Float64}}

M-step: recompute each centroid as cluster mean.
Empty clusters get a random point to avoid degenerate solutions.
"""
function update_centroids(X::Matrix{Float64}, labels::Vector{Int}, K::Int)::Vector{Vector{Float64}}
    [begin
        idx = findall(==(k), labels)
        isempty(idx) ? X[rand(1:size(X,1)), :] : vec(mean(X[idx, :], dims=1))
     end for k in 1:K]
end

"""
    inertia(X, labels, centroids) -> Float64

WCSS = Σᵢ ‖xᵢ − μ_{c(i)}‖²
"""
function inertia(X::Matrix{Float64}, labels::Vector{Int}, centroids::Vector{Vector{Float64}})::Float64
    sum(dist2(X[i, :], centroids[labels[i]]) for i in 1:size(X, 1))
end

"""
    kmeans_run(X, K; seed, maxiter, tol) -> NamedTuple

Single K-means run with K-means++ init.
Returns (labels, centroids, inertia_history, n_iter).
"""
function kmeans_run(
    X       ::Matrix{Float64},
    K       ::Int;
    seed    ::Int     = 42,
    maxiter ::Int     = 300,
    tol     ::Float64 = 1e-6
)::NamedTuple
    centroids = init_plusplus(X, K; seed=seed)
    labels    = assign_labels(X, centroids)
    history   = Float64[]
    n_iter    = maxiter

    for iter in 1:maxiter
        old_c     = deepcopy(centroids)
        labels    = assign_labels(X, centroids)
        centroids = update_centroids(X, labels, K)
        push!(history, inertia(X, labels, centroids))

        if all(norm(centroids[k] .- old_c[k]) < tol for k in 1:K)
            n_iter = iter
            break
        end
    end
    return (labels=labels, centroids=centroids, inertia_history=history, n_iter=n_iter)
end

"""
    kmeans_best(X, K; n_init, maxiter, tol) -> NamedTuple

Run K-means `n_init` times with different seeds, return run with lowest inertia.
"""
function kmeans_best(
    X       ::Matrix{Float64},
    K       ::Int;
    n_init  ::Int     = 10,
    maxiter ::Int     = 300,
    tol     ::Float64 = 1e-6
)::NamedTuple
    best = nothing
    for seed in 1:n_init
        r = kmeans_run(X, K; seed=seed, maxiter=maxiter, tol=tol)
        if isnothing(best) || last(r.inertia_history) < last(best.inertia_history)
            best = r
        end
    end
    return best
end

# ── Silhouette ────────────────────────────────────────────────────────────────

"""
    silhouette_score(X, labels) -> Float64

Mean silhouette coefficient s̄ ∈ [-1, 1].
s(i) = (b(i) − a(i)) / max(a(i), b(i))
  a(i) = mean intra-cluster distance
  b(i) = mean distance to nearest other cluster

Uses centroid-approximation for O(n·K·d) instead of O(n²·d).
Exact for large n; exact O(n²) only needed for tiny datasets.
"""
function silhouette_score(X::Matrix{Float64}, labels::Vector{Int})::Float64
    K = length(unique(labels))
    K < 2 && return -1.0
    n = size(X, 1)

    # cluster centroids and sizes
    centroids = [begin
        idx = findall(==(k), labels)
        isempty(idx) ? zeros(size(X, 2)) : vec(mean(X[idx, :], dims=1))
    end for k in 1:K]
    sizes = [count(==(k), labels) for k in 1:K]

    s = zeros(Float64, n)
    for i in 1:n
        ci = labels[i]
        xi = X[i, :]

        # a(i): mean distance to other points in same cluster (centroid approx)
        a = sizes[ci] > 1 ? sqrt(dist2(xi, centroids[ci])) : 0.0

        # b(i): mean distance to nearest other cluster centroid
        other = filter(k -> k != ci, 1:K)
        b = minimum(sqrt(dist2(xi, centroids[k])) for k in other)

        denom = max(a, b)
        s[i]  = denom == 0.0 ? 0.0 : (b - a) / denom
    end
    return mean(s)
end

# ── Automatic K selection ─────────────────────────────────────────────────────

"""
    auto_select_k(X; k_range, n_init, maxiter) -> (best_k, stats_df)

Select K automatically without ground truth using two criteria:

1. **Silhouette maximum** — K with highest mean silhouette coefficient.
2. **Elbow (2nd derivative)** — K where marginal inertia reduction drops most.

Final choice: silhouette-argmax, with elbow as tiebreaker.
Both metrics are purely internal (no labels needed).

Returns best_k and DataFrame with columns: k, inertia, silhouette, elbow_score.
"""
function auto_select_k(
    X       ::Matrix{Float64};
    k_range ::UnitRange{Int} = 2:8,
    n_init  ::Int            = 10,
    maxiter ::Int            = 300
)::Tuple{Int, DataFrame, NamedTuple}
    n  = size(X, 1)
    ks = [k for k in k_range if k < n]

    inertias    = Float64[]
    silhouettes = Float64[]
    best_runs   = []

    for k in ks
        r = kmeans_best(X, k; n_init=n_init, maxiter=maxiter)
        push!(inertias,    last(r.inertia_history))
        push!(silhouettes, silhouette_score(X, r.labels))
        push!(best_runs,   r)
    end

    # elbow: 2nd discrete derivative of inertia curve
    elbow_scores = zeros(length(ks))
    if length(ks) >= 3
        for i in 2:(length(ks)-1)
            elbow_scores[i] = inertias[i-1] - 2*inertias[i] + inertias[i+1]
        end
    end

    # primary: max silhouette
    best_idx = argmax(silhouettes)
    best_k   = ks[best_idx]

    stats = DataFrame(
        k            = ks,
        inertia      = round.(inertias,    digits=2),
        silhouette   = round.(silhouettes, digits=4),
        elbow_score  = round.(elbow_scores, digits=4)
    )
    return best_k, stats, best_runs[best_idx]
end

"""
    print_k_stats(stats, best_k)

Pretty-print K-selection table to stdout.
"""
function print_k_stats(stats::DataFrame, best_k::Int)
    println("\n── K-selection ──────────────────────────────────────")
    println("  k    inertia      silhouette   elbow_score  selected")
    println("  ─────────────────────────────────────────────────────")
    for r in eachrow(stats)
        mark = r.k == best_k ? "  ◄ optimal" : ""
        @printf("  %-4d %-12.1f %-12.4f %-12.4f%s\n",
            r.k, r.inertia, r.silhouette, r.elbow_score, mark)
    end
    println("─────────────────────────────────────────────────────\n")
end
