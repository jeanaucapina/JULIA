using DataFrames, Dates, Random, Statistics

# ── Perfiles de actuadores robóticos ──────────────────────────────────────────
#
# Cada perfil define el comportamiento típico de un tipo de actuador:
#   tipo, tiempo_uso_horas, ciclos, temp_operacion, vibracion, corriente,
#   fecha_adquisicion, intervalo_mantenimiento_dias, modo_falla_dominante
#
# Clusters objetivo:
#   1 → MANTENIMIENTO PROGRAMADO  (desgaste normal, parámetros dentro de rango)
#   2 → MANTENIMIENTO URGENTE     (parámetros degradados, riesgo inminente)
#   3 → REEMPLAZO                 (vida útil agotada, falla inminente o ya ocurrida)

const ACTUATOR_PROFILES = Dict(
    :servo_industrial => (
        tipo                  = "Servo Motor Industrial",
        vida_util_h           = 20_000,
        temp_nominal_c        = 65.0,
        temp_critica_c        = 90.0,
        vibracion_nominal     = 0.8,   # mm/s RMS
        vibracion_critica     = 3.5,
        corriente_nominal_a   = 12.0,
        corriente_critica_a   = 18.0,
        intervalo_mant_dias   = 180,
        ciclos_vida           = 500_000,
    ),
    :actuador_hidraulico => (
        tipo                  = "Actuador Hidráulico",
        vida_util_h           = 15_000,
        temp_nominal_c        = 55.0,
        temp_critica_c        = 80.0,
        vibracion_nominal     = 1.2,
        vibracion_critica     = 4.0,
        corriente_nominal_a   = 8.0,
        corriente_critica_a   = 14.0,
        intervalo_mant_dias   = 120,
        ciclos_vida           = 300_000,
    ),
    :motor_paso => (
        tipo                  = "Motor Paso a Paso",
        vida_util_h           = 25_000,
        temp_nominal_c        = 70.0,
        temp_critica_c        = 100.0,
        vibracion_nominal     = 0.5,
        vibracion_critica     = 2.5,
        corriente_nominal_a   = 5.0,
        corriente_critica_a   = 8.5,
        intervalo_mant_dias   = 240,
        ciclos_vida           = 800_000,
    ),
    :actuador_neumatico => (
        tipo                  = "Actuador Neumático",
        vida_util_h           = 10_000,
        temp_nominal_c        = 45.0,
        temp_critica_c        = 70.0,
        vibracion_nominal     = 1.5,
        vibracion_critica     = 5.0,
        corriente_nominal_a   = 3.5,
        corriente_critica_a   = 6.0,
        intervalo_mant_dias   = 90,
        ciclos_vida           = 200_000,
    ),
    :motor_brushless => (
        tipo                  = "Motor Brushless DC",
        vida_util_h           = 30_000,
        temp_nominal_c        = 75.0,
        temp_critica_c        = 105.0,
        vibracion_nominal     = 0.3,
        vibracion_critica     = 2.0,
        corriente_nominal_a   = 15.0,
        corriente_critica_a   = 22.0,
        intervalo_mant_dias   = 365,
        ciclos_vida           = 1_000_000,
    ),
)

const PROFILE_KEYS = collect(keys(ACTUATOR_PROFILES))

# ── Generación de datos sintéticos ────────────────────────────────────────────

"""
    generate_actuators(n_total; seed, fecha_inicio) -> DataFrame

Genera `n_total` registros de actuadores robóticos con features realistas.
Cada pieza recibe una clase latente:
  1 = MANTENIMIENTO PROGRAMADO (40% del total)
  2 = MANTENIMIENTO URGENTE    (35%)
  3 = REEMPLAZO                (25%)

Features generadas:
  - tiempo_uso_horas        : horas acumuladas de operación
  - ciclos_completados      : ciclos de movimiento
  - temperatura_operacion_c : temperatura promedio en operación (°C)
  - vibracion_rms           : vibración RMS (mm/s)
  - corriente_promedio_a    : corriente promedio (A)
  - dias_desde_mantenimiento: días desde último mantenimiento
  - pct_vida_util           : porcentaje de vida útil consumida (0-100+)
  - tasa_fallo_acumulada    : fallos por 1000 horas
  - eficiencia_energetica   : eficiencia relativa (0-1, degradada con uso)
  - drift_posicional_mm     : desviación de posición respecto a nominal (mm)
  - fecha_adquisicion       : fecha de compra (Date)
  - edad_dias               : días desde adquisición
  - tipo_actuador           : tipo de pieza
  - clase_latente           : 1=prog / 2=urgente / 3=reemplazo (ground truth)
"""
function generate_actuators(
    n_total ::Int = 120;
    seed    ::Int = 42
)::DataFrame
    Random.seed!(seed)
    today = Date(2024, 6, 1)   # fecha referencia fija para reproducibilidad

    n_prog    = round(Int, 0.40 * n_total)
    n_urgente = round(Int, 0.35 * n_total)
    n_reemplazo = n_total - n_prog - n_urgente

    rows = []

    # Helper: ruido gaussiano truncado en [lo, hi]
    function rclamp(mu, sigma, lo, hi)
        v = mu + sigma * randn()
        clamp(v, lo, hi)
    end

    piece_id = 1

    for (clase, n_clase) in [(1, n_prog), (2, n_urgente), (3, n_reemplazo)]
        for _ in 1:n_clase
            # Seleccionar tipo de actuador al azar
            pkey  = PROFILE_KEYS[rand(1:length(PROFILE_KEYS))]
            prof  = ACTUATOR_PROFILES[pkey]

            vida_total = prof.vida_util_h

            # ── pct_vida_util según clase ──────────────────────────────────
            pct_vida = if clase == 1
                rclamp(28.0, 10.0, 5.0, 55.0)           # 5-55% vida consumida
            elseif clase == 2
                rclamp(72.0, 7.0, 60.0, 85.0)           # 60-85% — zona urgente
            else
                rclamp(112.0, 10.0, 95.0, 145.0)        # >95%, muchos >100%
            end

            tiempo_uso = pct_vida / 100.0 * vida_total

            # ── fecha de adquisición ──────────────────────────────────────
            max_dias_adq = round(Int, tiempo_uso / 8.0 * 1.3)   # asumiendo ~8h/día
            dias_adq     = rand(max(30, max_dias_adq÷2) : max(31, max_dias_adq))
            fecha_adq    = today - Day(dias_adq)
            edad_dias    = (today - fecha_adq).value

            # ── ciclos completados ────────────────────────────────────────
            ciclos = round(Int, rclamp(
                pct_vida/100.0 * prof.ciclos_vida,
                prof.ciclos_vida * 0.08,
                0.0,
                prof.ciclos_vida * 1.5
            ))

            # ── temperatura de operación ──────────────────────────────────
            temp = if clase == 1
                rclamp(prof.temp_nominal_c * 0.85, 2.5,
                       prof.temp_nominal_c * 0.65, prof.temp_nominal_c * 0.98)
            elseif clase == 2
                rclamp(prof.temp_nominal_c * 1.18, 3.0,
                       prof.temp_nominal_c * 1.06, prof.temp_critica_c * 0.88)
            else
                rclamp(prof.temp_critica_c * 1.05, 4.0,
                       prof.temp_critica_c * 0.92, prof.temp_critica_c * 1.3)
            end

            # ── vibración RMS ─────────────────────────────────────────────
            vib = if clase == 1
                rclamp(prof.vibracion_nominal * 0.85, 0.06,
                       prof.vibracion_nominal * 0.4, prof.vibracion_nominal * 1.15)
            elseif clase == 2
                rclamp(prof.vibracion_nominal * 2.2, 0.18,
                       prof.vibracion_nominal * 1.5, prof.vibracion_critica * 0.80)
            else
                rclamp(prof.vibracion_critica * 1.15, 0.25,
                       prof.vibracion_critica * 0.90, prof.vibracion_critica * 2.0)
            end

            # ── corriente promedio ────────────────────────────────────────
            corr = if clase == 1
                rclamp(prof.corriente_nominal_a * 0.95, 0.3,
                       prof.corriente_nominal_a * 0.75, prof.corriente_nominal_a * 1.08)
            elseif clase == 2
                rclamp(prof.corriente_nominal_a * 1.25, 0.5,
                       prof.corriente_nominal_a * 1.10, prof.corriente_critica_a * 0.85)
            else
                rclamp(prof.corriente_critica_a * 1.10, 0.6,
                       prof.corriente_critica_a * 0.90, prof.corriente_critica_a * 1.40)
            end

            # ── días desde último mantenimiento ───────────────────────────
            intv = prof.intervalo_mant_dias
            dias_mant = if clase == 1
                rclamp(intv * 0.40, intv * 0.08, 5.0, intv * 0.75)
            elseif clase == 2
                rclamp(intv * 1.20, intv * 0.12, intv * 0.85, intv * 1.60)
            else
                rclamp(intv * 2.20, intv * 0.18, intv * 1.60, intv * 3.20)
            end
            dias_mant = round(Int, max(1.0, dias_mant))

            # ── tasa de fallos por 1000 h ─────────────────────────────────
            tasa_fallo = if clase == 1
                rclamp(0.25, 0.07, 0.02, 0.70)
            elseif clase == 2
                rclamp(3.50, 0.50, 2.00, 5.50)
            else
                rclamp(11.0, 1.50, 7.00, 18.0)
            end

            # ── eficiencia energética (1 = nueva, decrece con uso) ────────
            eficiencia = if clase == 1
                rclamp(0.91, 0.025, 0.83, 0.99)
            elseif clase == 2
                rclamp(0.70, 0.030, 0.62, 0.78)
            else
                rclamp(0.44, 0.040, 0.28, 0.56)
            end

            # ── drift posicional (mm) ─────────────────────────────────────
            drift = if clase == 1
                rclamp(0.04, 0.012, 0.005, 0.11)
            elseif clase == 2
                rclamp(0.42, 0.060, 0.25, 0.62)
            else
                rclamp(1.60, 0.200, 1.00, 3.00)
            end

            push!(rows, (
                pieza_id                 = piece_id,
                tipo_actuador            = prof.tipo,
                fecha_adquisicion        = fecha_adq,
                edad_dias                = edad_dias,
                tiempo_uso_horas         = round(tiempo_uso, digits=1),
                ciclos_completados       = ciclos,
                temperatura_operacion_c  = round(temp,        digits=2),
                vibracion_rms            = round(vib,         digits=3),
                corriente_promedio_a     = round(corr,        digits=3),
                dias_desde_mantenimiento = dias_mant,
                pct_vida_util            = round(pct_vida,    digits=2),
                tasa_fallo_por_1000h     = round(tasa_fallo,  digits=3),
                eficiencia_energetica    = round(eficiencia,  digits=4),
                drift_posicional_mm      = round(drift,       digits=4),
                clase_latente            = clase,
            ))
            piece_id += 1
        end
    end

    # Mezclar orden (para que no sea clase 1 / 2 / 3 en bloque)
    df = DataFrame(rows)
    idx = shuffle(1:nrow(df))
    return df[idx, :]
end

"""
    train_test_split(df; train_ratio, seed) -> (train_df, test_df)

Split estratificado por clase_latente.
"""
function train_test_split(df::DataFrame; train_ratio::Float64=0.70, seed::Int=42)
    Random.seed!(seed)
    train_idx = Int[]
    test_idx  = Int[]
    for clase in unique(df.clase_latente)
        idxs = findall(df.clase_latente .== clase)
        shuffle!(idxs)
        n_train = round(Int, train_ratio * length(idxs))
        append!(train_idx, idxs[1:n_train])
        append!(test_idx,  idxs[n_train+1:end])
    end
    return df[sort(train_idx), :], df[sort(test_idx), :]
end
