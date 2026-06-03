using DataFrames, CSV, Statistics, Printf, Dates

# Nombres canónicos de clusters (orden por severidad creciente)
const CLUSTER_NAMES = ["Mantenimiento Programado", "Mantenimiento Urgente", "Reemplazo"]
const CLUSTER_EMOJIS = ["🟢", "🟡", "🔴"]

# ── Tabla resumen por cluster ─────────────────────────────────────────────────

"""
    build_cluster_table(df, assignments; latent_ref) -> DataFrame

Estadísticas por cluster: tamaño, medias de features clave, pureza (si hay ground truth).
"""
function build_cluster_table(
    df          ::DataFrame,
    assignments ::Vector{Int};
    latent_ref  ::Union{Vector{Int}, Nothing} = nothing
)::DataFrame
    clusters = sort(unique(assignments))
    rows = []

    for c in clusters
        mask = findall(==(c), assignments)
        sub  = df[mask, :]
        n    = length(mask)

        name = c <= length(CLUSTER_NAMES) ? CLUSTER_NAMES[c] : "Cluster_$c"

        row = (
            cluster_id               = c,
            cluster_nombre           = name,
            n_piezas                 = n,
            pct_vida_util_media      = round(mean(sub.pct_vida_util),           digits=2),
            pct_vida_util_max        = round(maximum(sub.pct_vida_util),         digits=2),
            tiempo_uso_h_media       = round(mean(sub.tiempo_uso_horas),         digits=1),
            tasa_fallo_media         = round(mean(sub.tasa_fallo_por_1000h),     digits=3),
            vibracion_media          = round(mean(sub.vibracion_rms),            digits=3),
            temperatura_media_c      = round(mean(sub.temperatura_operacion_c),  digits=2),
            dias_sin_mantenimiento   = round(mean(Float64.(sub.dias_desde_mantenimiento)), digits=1),
            eficiencia_media         = round(mean(sub.eficiencia_energetica),    digits=4),
            drift_media_mm           = round(mean(sub.drift_posicional_mm),      digits=4),
            corriente_media_a        = round(mean(sub.corriente_promedio_a),     digits=3),
        )

        if !isnothing(latent_ref)
            lat   = latent_ref[mask]
            uniq  = unique(lat)
            dom   = uniq[argmax([count(==(l), lat) for l in uniq])]
            pur   = count(==(dom), lat) / n
            row   = merge(row, (pureza=round(pur, digits=3),))
        end

        push!(rows, row)
    end
    return DataFrame(rows)
end

# ── Tabla detalle piezas ──────────────────────────────────────────────────────

"""
    build_piece_map(df, assignments) -> DataFrame

Tabla pieza_id → cluster asignado + features relevantes.
"""
function build_piece_map(df::DataFrame, assignments::Vector{Int})::DataFrame
    n = nrow(df)
    cluster_nombres = [
        assignments[i] <= length(CLUSTER_NAMES) ? CLUSTER_NAMES[assignments[i]] : "Cluster_$(assignments[i])"
        for i in 1:n
    ]
    DataFrame(
        pieza_id                 = df.pieza_id,
        tipo_actuador            = df.tipo_actuador,
        fecha_adquisicion        = df.fecha_adquisicion,
        edad_dias                = df.edad_dias,
        cluster_id               = assignments,
        cluster_nombre           = cluster_nombres,
        pct_vida_util            = round.(df.pct_vida_util,           digits=2),
        tiempo_uso_horas         = round.(df.tiempo_uso_horas,        digits=1),
        dias_desde_mantenimiento = df.dias_desde_mantenimiento,
        tasa_fallo_por_1000h     = round.(df.tasa_fallo_por_1000h,    digits=3),
        vibracion_rms            = round.(df.vibracion_rms,           digits=3),
        temperatura_operacion_c  = round.(df.temperatura_operacion_c, digits=2),
        eficiencia_energetica    = round.(df.eficiencia_energetica,    digits=4),
        drift_posicional_mm      = round.(df.drift_posicional_mm,      digits=4),
        corriente_promedio_a     = round.(df.corriente_promedio_a,     digits=3),
    )
end

# ── Evaluación test set ───────────────────────────────────────────────────────

"""
    evaluate_test(train_assignments, test_assignments) -> DataFrame
"""
function evaluate_test(
    train_assignments ::Vector{Int},
    test_assignments  ::Vector{Int}
)::DataFrame
    # train and test sets may differ in size; compare only overlapping indices
    n_common = min(length(train_assignments), length(test_assignments))
    clusters = sort(unique(train_assignments))
    rows = []
    for c in clusters
        n_train   = count(==(c), train_assignments)
        n_test    = count(==(c), test_assignments)
        stable    = count(i -> train_assignments[i] == c && test_assignments[i] == c,
                          1:n_common)
        stability = n_train > 0 ? round(stable / n_train, digits=3) : 0.0
        name = c <= length(CLUSTER_NAMES) ? CLUSTER_NAMES[c] : "Cluster_$c"
        push!(rows, (
            cluster_id    = c,
            cluster_nombre= name,
            train_piezas  = n_train,
            test_piezas   = n_test,
            estables      = stable,
            estabilidad   = stability
        ))
    end
    return DataFrame(rows)
end

# ── Guardar CSV y consola ─────────────────────────────────────────────────────

function save_reports(
    cluster_tbl ::DataFrame,
    k_stats     ::DataFrame,
    best_k      ::Int,
    sil         ::Float64,
    output_dir  ::String;
    piece_map   ::Union{DataFrame,Nothing} = nothing,
    test_eval   ::Union{DataFrame,Nothing} = nothing,
    mode        ::Symbol = :sim
)::String
    report_dir = joinpath(output_dir, "report")
    mkpath(report_dir)

    CSV.write(joinpath(report_dir, "tabla_clusters.csv"),    cluster_tbl)
    CSV.write(joinpath(report_dir, "k_selection_stats.csv"), k_stats)
    !isnothing(piece_map)  && CSV.write(joinpath(report_dir, "mapa_piezas.csv"),     piece_map)
    !isnothing(test_eval)  && CSV.write(joinpath(report_dir, "test_evaluacion.csv"), test_eval)

    _print_summary(cluster_tbl, k_stats, best_k, sil, test_eval, mode)
    return report_dir
end

function _print_summary(cluster_tbl, k_stats, best_k, sil, test_eval, mode)
    println("\n" * "═"^60)
    println("  REPORTE — CLUSTERING DE ACTUADORES ROBÓTICOS")
    mode == :sim  && println("  Modo: Simulación (ground truth disponible)")
    println("  Fecha: $(Dates.today())")
    println("═"^60)
    @printf("  K seleccionado : %d  (silhouette = %.4f)\n", best_k, sil)

    println("\n  Selección de K:")
    for r in eachrow(k_stats)
        mark = r.k == best_k ? "◄" : " "
        @printf("  %s K=%-2d  inercia=%-10.1f  sil=%.4f\n",
            mark, r.k, r.inertia, r.silhouette)
    end

    println("\n  Resumen por cluster:")
    println("  ─────────────────────────────────────────────────────────")
    for r in eachrow(cluster_tbl)
        emo = r.cluster_id <= length(CLUSTER_EMOJIS) ? CLUSTER_EMOJIS[r.cluster_id] : "⚪"
        pur_str = hasproperty(cluster_tbl, :pureza) ? @sprintf("  pureza=%.3f", r.pureza) : ""
        @printf("  %s %-28s  piezas=%-4d  vida=%.1f%%  fallos/1kh=%.2f%s\n",
            emo, r.cluster_nombre, r.n_piezas,
            r.pct_vida_util_media, r.tasa_fallo_media, pur_str)
    end

    if !isnothing(test_eval)
        println("\n  Estabilidad train→test:")
        for r in eachrow(test_eval)
            @printf("  %-28s  train=%-3d  test=%-3d  estab=%.3f\n",
                r.cluster_nombre, r.train_piezas, r.test_piezas, r.estabilidad)
        end
    end
    println("═"^60 * "\n")
end

# ── reporte.md ────────────────────────────────────────────────────────────────

"""
    write_reporte_md(cluster_tbl, k_stats, piece_map, best_k, sil,
                     output_dir; test_eval, n_total, n_train, n_test, mode) -> String

Genera reporte.md con todos los resultados, tablas y referencias a GIFs.
"""
function write_reporte_md(
    cluster_tbl ::DataFrame,
    k_stats     ::DataFrame,
    piece_map   ::DataFrame,
    best_k      ::Int,
    sil         ::Float64,
    output_dir  ::String;
    test_eval   ::Union{DataFrame,Nothing} = nothing,
    n_total     ::Int    = 0,
    n_train     ::Int    = 0,
    n_test      ::Int    = 0,
    mode        ::Symbol = :sim
)::String
    path = joinpath(output_dir, "reporte.md")
    open(path, "w") do io
        println(io, "# Reporte: Clustering de Actuadores Robóticos")
        println(io, "")
        println(io, "> **Generado:** $(Dates.today())  |  **Modo:** $(mode == :sim ? "Simulación sintética" : "Real")")
        println(io, "")

        println(io, "---")
        println(io, "")
        println(io, "## 1. Descripción del Problema")
        println(io, "")
        println(io, "Se aplica **K-Means no supervisado** sobre un inventario de actuadores robóticos")
        println(io, "para clasificar automáticamente cada pieza en uno de tres estados de mantenimiento:")
        println(io, "")
        println(io, "| Cluster | Estado | Acción Recomendada |")
        println(io, "|---------|--------|--------------------|")
        println(io, "| 🟢 C1 | **Mantenimiento Programado** | Seguir calendario normal |")
        println(io, "| 🟡 C2 | **Mantenimiento Urgente** | Intervención en ≤2 semanas |")
        println(io, "| 🔴 C3 | **Reemplazo** | Retirar y reemplazar de inmediato |")
        println(io, "")

        println(io, "---")
        println(io, "")
        println(io, "## 2. Dataset Sintético")
        println(io, "")
        println(io, "| Parámetro | Valor |")
        println(io, "|-----------|-------|")
        println(io, "| Total de piezas | $n_total |")
        println(io, "| Set de entrenamiento | $n_train |")
        println(io, "| Set de prueba | $n_test |")
        println(io, "| Tipos de actuadores | Servo Industrial, Motor Brushless, Actuador Hidráulico, Motor Paso a Paso, Actuador Neumático |")
        println(io, "")
        println(io, "### Features utilizadas (10 variables)")
        println(io, "")
        println(io, "| Feature | Peso | Descripción |")
        println(io, "|---------|------|-------------|")
        println(io, "| `pct_vida_util` | 2.5 | Porcentaje de vida útil consumida |")
        println(io, "| `tasa_fallo_por_1000h` | 2.0 | Fallos acumulados por 1000 horas |")
        println(io, "| `drift_posicional_mm` | 2.0 | Desviación de posición respecto a nominal |")
        println(io, "| `dias_desde_mantenimiento` | 1.5 | Días desde último mantenimiento |")
        println(io, "| `vibracion_rms` | 1.5 | Vibración RMS (mm/s) |")
        println(io, "| `temperatura_operacion_c` | 1.2 | Temperatura promedio en operación (°C) |")
        println(io, "| `eficiencia_energetica` | 1.2 | Eficiencia relativa (invertida: baja = degradada) |")
        println(io, "| `corriente_promedio_a` | 1.0 | Corriente promedio (A) |")
        println(io, "| `tiempo_uso_horas` | 1.0 | Horas acumuladas de operación |")
        println(io, "| `ciclos_completados` | 1.0 | Ciclos de movimiento completados |")
        println(io, "")

        println(io, "---")
        println(io, "")
        println(io, "## 3. Selección Automática de K")
        println(io, "")
        println(io, "Se evaluaron K ∈ [2, 6] usando silhouette maximization + elbow tiebreaker.")
        println(io, "")
        println(io, "| K | Inercia | Silhouette | Elbow Score | Seleccionado |")
        println(io, "|---|---------|------------|-------------|:---:|")
        for r in eachrow(k_stats)
            mark = r.k == best_k ? "✅" : ""
            @printf(io, "| %d | %.1f | %.4f | %.4f | %s |\n",
                r.k, r.inertia, r.silhouette, r.elbow_score, mark)
        end
        println(io, "")
        println(io, "**K óptimo seleccionado: K = $best_k** (silhouette = $(round(sil, digits=4)))")
        println(io, "")
        println(io, "### Animaciones de selección de K")
        println(io, "")
        println(io, "![K-Selection GIF](animations/k_selection.gif)")
        println(io, "")

        println(io, "---")
        println(io, "")
        println(io, "## 4. Resultados de Clustering")
        println(io, "")
        println(io, "### 4.1 Resumen por Cluster")
        println(io, "")

        has_pureza = hasproperty(cluster_tbl, :pureza)
        header = "| Cluster | Nombre | Piezas | Vida Útil Media | Tiempo Uso (h) | Fallos/1000h | Vibración | Temp (°C) | Días sin Mant. | Eficiencia | Drift (mm) |"
        sep    = "|---------|--------|--------|-----------------|----------------|--------------|-----------|-----------|----------------|------------|------------|"
        if has_pureza
            header *= " Pureza |"
            sep    *= "--------|"
        end
        println(io, header)
        println(io, sep)

        for r in eachrow(cluster_tbl)
            emo = r.cluster_id <= length(CLUSTER_EMOJIS) ? CLUSTER_EMOJIS[r.cluster_id] : "⚪"
            line = @sprintf("| %s C%d | %s | %d | %.1f%% | %.1f | %.3f | %.3f | %.2f | %.1f | %.4f | %.4f |",
                emo, r.cluster_id, r.cluster_nombre, r.n_piezas,
                r.pct_vida_util_media, r.tiempo_uso_h_media,
                r.tasa_fallo_media, r.vibracion_media,
                r.temperatura_media_c, r.dias_sin_mantenimiento,
                r.eficiencia_media, r.drift_media_mm)
            if has_pureza
                line *= @sprintf(" %.3f |", r.pureza)
            end
            println(io, line)
        end
        println(io, "")

        println(io, "### 4.2 Animación de Convergencia K-Means")
        println(io, "")
        println(io, "![K-Means Convergencia GIF](animations/kmeans_convergencia.gif)")
        println(io, "")
        println(io, "#### ¿Qué son PC1 y PC2? — Cálculo PCA")
        println(io, "")
        println(io, "K-Means opera en **10 dimensiones** (una por feature). Para visualizar en 2D se aplica")
        println(io, "**Análisis de Componentes Principales (PCA)**, que proyecta al plano de mayor varianza.")
        println(io, "")
        println(io, "**Pasos del cálculo** (implementados en `src/animation.jl → pca2d()`):")
        println(io, "")
        println(io, "**1. Centrar la matriz de datos**")
        println(io, "")
        println(io, "```")
        println(io, "Xc = X - μ")
        println(io, "")
        println(io, "donde μ = mean(X, dims=1)   # media de cada feature (1×10)")
        println(io, "      X  es la matriz normalizada (n×10), n = número de piezas")
        println(io, "```")
        println(io, "")
        println(io, "**2. Calcular la matriz de covarianza**")
        println(io, "")
        println(io, "```")
        println(io, "C = (Xc' * Xc) / (n - 1)   # matriz 10×10")
        println(io, "```")
        println(io, "")
        println(io, "C[i,j] mide cuánto varían conjuntamente las features i y j entre todas las piezas.")
        println(io, "")
        println(io, "**3. Descomposición en valores propios (eigendecomposition)**")
        println(io, "")
        println(io, "```")
        println(io, "C = V · Λ · V'")
        println(io, "")
        println(io, "donde Λ = diag(λ₁, λ₂, …, λ₁₀)  # valores propios (varianza explicada por cada eje)")
        println(io, "      V = [v₁ | v₂ | … | v₁₀]    # vectores propios (direcciones principales), 10×10")
        println(io, "```")
        println(io, "")
        println(io, "Los valores propios se ordenan de menor a mayor; se toman los **2 últimos** (mayor varianza).")
        println(io, "")
        println(io, "**4. Proyectar a 2D**")
        println(io, "")
        println(io, "```")
        println(io, "V2 = [v₁₀ | v₉]          # las 2 columnas de mayor λ  →  matriz 10×2")
        println(io, "Z  = Xc · V2              # proyección final            →  matriz n×2")
        println(io, "")
        println(io, "PC1 = Z[:, 1]  ← coordenada de cada pieza en la 1ª componente principal")
        println(io, "PC2 = Z[:, 2]  ← coordenada de cada pieza en la 2ª componente principal")
        println(io, "```")
        println(io, "")
        println(io, "**5. Varianza explicada**")
        println(io, "")
        println(io, "```")
        println(io, "varianza_explicada = (λ₁₀ + λ₉) / Σλᵢ    # reportada en el título del GIF")
        println(io, "```")
        println(io, "")
        println(io, "| Componente | Significado | Captura principalmente |")
        println(io, "|------------|-------------|------------------------|")
        println(io, "| **PC1** | Dirección de **máxima varianza** global | Combinación de `pct_vida_util` (peso 2.5), `tasa_fallo` (2.0), `drift_posicional` (2.0) |")
        println(io, "| **PC2** | Dirección **ortogonal** a PC1 con 2ª mayor varianza | Señal residual de `vibracion_rms` (1.5), `temperatura` (1.2), `eficiencia` (1.2) |")
        println(io, "")
        println(io, "> ⚠️ **PC1 y PC2 no son features individuales** — son combinaciones lineales de las 10.")
        println(io, "> El clustering real ocurre en el espacio completo de 10D; PCA es **solo para visualización**.")
        println(io, "")
        println(io, "### 4.3 Scatter por Features Clave")
        println(io, "")
        println(io, "![Feature Scatter GIF](animations/feature_scatter.gif)")
        println(io, "")
        println(io, "> Estos scatters muestran las features **originales** (sin reducción dimensional),")
        println(io, "> coloreadas por el cluster asignado. Permiten interpretar directamente qué valores")
        println(io, "> de cada sensor/métrica corresponden a cada estado de mantenimiento.")
        println(io, "")

        if !isnothing(test_eval)
            println(io, "---")
            println(io, "")
            println(io, "## 5. Evaluación en Set de Prueba")
            println(io, "")
            println(io, "Estabilidad: fracción de piezas que caen en el mismo cluster en train y test.")
            println(io, "")
            println(io, "| Cluster | Nombre | Piezas Train | Piezas Test | Estables | Estabilidad |")
            println(io, "|---------|--------|:---:|:---:|:---:|:---:|")
            for r in eachrow(test_eval)
                bar = repeat("█", round(Int, r.estabilidad * 10)) * repeat("░", 10 - round(Int, r.estabilidad * 10))
                @printf(io, "| C%d | %s | %d | %d | %d | %.3f `%s` |\n",
                    r.cluster_id, r.cluster_nombre,
                    r.train_piezas, r.test_piezas, r.estables,
                    r.estabilidad, bar)
            end
            println(io, "")
        end

        println(io, "---")
        println(io, "")
        println(io, "## $(isnothing(test_eval) ? 5 : 6). Muestra de Piezas por Cluster")
        println(io, "")
        for c in sort(unique(piece_map.cluster_id))
            emo = c <= length(CLUSTER_EMOJIS) ? CLUSTER_EMOJIS[c] : "⚪"
            nombre = CLUSTER_NAMES[min(c, length(CLUSTER_NAMES))]
            sub = piece_map[piece_map.cluster_id .== c, :]
            sample_n = min(5, nrow(sub))
            println(io, "### $emo Cluster $c: $nombre (top $sample_n piezas)")
            println(io, "")
            println(io, "| ID | Tipo | Adquisición | Vida (%) | Días sin Mant. | Fallos/1kh | Vibración | Drift (mm) |")
            println(io, "|----|------|-------------|----------|----------------|------------|-----------|------------|")
            for row in eachrow(sub[1:sample_n, :])
                @printf(io, "| %d | %s | %s | %.1f | %d | %.3f | %.3f | %.4f |\n",
                    row.pieza_id, row.tipo_actuador, row.fecha_adquisicion,
                    row.pct_vida_util, row.dias_desde_mantenimiento,
                    row.tasa_fallo_por_1000h, row.vibracion_rms, row.drift_posicional_mm)
            end
            println(io, "")
        end

        println(io, "---")
        println(io, "")
        println(io, "## Archivos Generados")
        println(io, "")
        println(io, "```")
        println(io, "results/")
        println(io, "├── reporte.md                     ← este archivo")
        println(io, "├── animations/")
        println(io, "│   ├── kmeans_convergencia.gif    ← convergencia K-means")
        println(io, "│   ├── k_selection.gif            ← selección de K")
        println(io, "│   └── feature_scatter.gif        ← scatter features clave")
        println(io, "└── report/")
        println(io, "    ├── tabla_clusters.csv         ← resumen por cluster")
        println(io, "    ├── mapa_piezas.csv            ← pieza → cluster asignado")
        println(io, "    ├── k_selection_stats.csv      ← métricas K-selection")
        println(io, "    └── test_evaluacion.csv        ← estabilidad train→test")
        println(io, "```")
        println(io, "")
        println(io, "---")
        println(io, "*Generado automáticamente por el pipeline Julia de clustering robótico.*")
    end

    println("  reporte.md → $path")
    return path
end
