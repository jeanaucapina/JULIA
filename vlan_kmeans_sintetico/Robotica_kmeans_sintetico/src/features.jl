using DataFrames, Statistics

# ── Feature weights ────────────────────────────────────────────────────────────
# Higher weight = stronger signal for maintenance cluster separation.
# pct_vida_util and tasa_fallo are the dominant signals.

const FEATURE_WEIGHTS = Dict(
    :pct_vida_util            => 2.5,
    :tasa_fallo_por_1000h     => 2.0,
    :drift_posicional_mm      => 2.0,
    :dias_desde_mantenimiento => 1.5,
    :vibracion_rms            => 1.5,
    :temperatura_operacion_c  => 1.2,
    :eficiencia_energetica    => 1.2,   # inverted: low = bad
    :corriente_promedio_a     => 1.0,
    :tiempo_uso_horas         => 1.0,
    :ciclos_completados       => 1.0,
)

const FEATURE_COLS = [
    :pct_vida_util,
    :tasa_fallo_por_1000h,
    :drift_posicional_mm,
    :dias_desde_mantenimiento,
    :vibracion_rms,
    :temperatura_operacion_c,
    :eficiencia_energetica,
    :corriente_promedio_a,
    :tiempo_uso_horas,
    :ciclos_completados,
]

"""
    compute_features(df; fit_stats) -> (X::Matrix{Float64}, feat_df::DataFrame, stats)

Extract and normalize features from actuator DataFrame.

- `df`: output of `generate_actuators`
- `fit_stats`: if provided (from training set), use those μ/σ for normalization (test mode)
- Returns normalized feature matrix X (n × 10), raw feature DataFrame, and fit stats

Normalization: weighted z-score  z_ij = w_j * (x_ij - μ_j) / σ_j
eficiencia_energetica is inverted (1 - x) so higher score = worse condition.
"""
function compute_features(
    df        ::DataFrame;
    fit_stats ::Union{Nothing, NamedTuple} = nothing
)::Tuple{Matrix{Float64}, DataFrame, NamedTuple}
    n = nrow(df)
    p = length(FEATURE_COLS)

    # Build raw feature matrix — invert eficiencia so all features: larger = worse
    raw = Matrix{Float64}(undef, n, p)
    for (j, col) in enumerate(FEATURE_COLS)
        vals = Float64.(df[!, col])
        if col == :eficiencia_energetica
            vals = 1.0 .- vals   # invert: low efficiency = high degradation score
        end
        raw[:, j] = vals
    end

    # Fit or apply normalization stats
    μ = isnothing(fit_stats) ? vec(mean(raw, dims=1))  : fit_stats.μ
    σ = isnothing(fit_stats) ? vec(std(raw,  dims=1))  : fit_stats.σ
    σ = max.(σ, 1e-8)   # avoid division by zero

    weights = [FEATURE_WEIGHTS[c] for c in FEATURE_COLS]

    X = Matrix{Float64}(undef, n, p)
    for j in 1:p
        X[:, j] = weights[j] .* (raw[:, j] .- μ[j]) ./ σ[j]
    end

    feat_df = DataFrame(raw, string.(FEATURE_COLS))

    stats = (μ=μ, σ=σ, weights=weights, feature_names=string.(FEATURE_COLS))
    return X, feat_df, stats
end
