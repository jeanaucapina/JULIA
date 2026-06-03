# ============================================================
# Red de Sensores Hídricos — BFS y DFS con peso por batería
# Caso: Transmisión eficiente de datos de caudal al gateway
# Autor: Jean Carlo Aucapina
# Fecha: 2026-05-13
# ============================================================

using Graphs
using DataFrames
using CSV
using Statistics
using StatsBase
using Dates
using Random
using Printf

Random.seed!(42)

# ============================================================
# SECCIÓN 1: GENERACIÓN DE RED SINTÉTICA
# ============================================================

const N_SENSORES    = 35   # sensores de caudal
const N_REPETIDORES = 12   # nodos repetidores intermedios
const N_GATEWAY     = 3    # gateways (sumideros de datos)
const N_TOTAL       = N_SENSORES + N_REPETIDORES + N_GATEWAY

println("=" ^ 60)
println("RED DE SENSORES HÍDRICOS — BFS y DFS")
println("Caso: Rutas de transmisión con restricción de batería")
println("=" ^ 60)
println()

# Tipos de nodo
# 1..35   → sensores de caudal
# 36..47  → repetidores
# 48..50  → gateways

function tipo_nodo(id::Int)
    if id <= N_SENSORES
        return :sensor
    elseif id <= N_SENSORES + N_REPETIDORES
        return :repetidor
    else
        return :gateway
    end
end

function nombre_nodo(id::Int)
    t = tipo_nodo(id)
    if t == :sensor
        return "S-$(lpad(id, 2, '0'))"
    elseif t == :repetidor
        return "R-$(lpad(id - N_SENSORES, 2, '0'))"
    else
        return "GW-$(id - N_SENSORES - N_REPETIDORES)"
    end
end

# Nivel de batería por nodo (porcentaje 20%–100%)
bateria = Dict{Int,Float64}()
for i in 1:N_TOTAL
    if tipo_nodo(i) == :gateway
        bateria[i] = 100.0   # gateways conectados a red eléctrica
    elseif tipo_nodo(i) == :repetidor
        bateria[i] = rand(40.0:5.0:90.0)
    else
        bateria[i] = rand(20.0:5.0:85.0)
    end
end

# ─── Construcción del grafo ───────────────────────────────────
# Topología: árbol con redundancias (típico WSN hídrica)
# Cada sensor conecta a 1-3 repetidores o gateways cercanos
# Cada repetidor conecta a 1-2 gateways o repetidores upstream

g = SimpleGraph(N_TOTAL)

# Aristas sensor → repetidor (cada sensor a 1-2 repetidores aleatorios)
aristas_peso = Dict{Tuple{Int,Int}, Float64}()

function peso_arista(_u::Int, v::Int)
    # Consumo en mAh para transmitir desde u a v
    # Fórmula: base_tx / (batería_destino/100) * factor_ruido
    bat_dest = bateria[v]
    base = rand(0.5:0.1:3.0)       # consumo base 0.5–3 mAh
    penalizacion = 100.0 / bat_dest # nodo con poca batería cuesta más enrutar
    ruido = rand(0.9:0.05:1.1)
    return round(base * penalizacion * ruido, digits=3)
end

function add_arista!(g, u, v, aristas_peso)
    if !has_edge(g, u, v)
        add_edge!(g, u, v)
        w = peso_arista(u, v)
        aristas_peso[(min(u,v), max(u,v))] = w
    end
end

# Sensores → repetidores
for s in 1:N_SENSORES
    # cada sensor conecta a 1 o 2 repetidores
    reps = sample(N_SENSORES+1 : N_SENSORES+N_REPETIDORES, rand(1:2), replace=false)
    for r in reps
        add_arista!(g, s, r, aristas_peso)
    end
end

# Repetidores → gateways
for r in N_SENSORES+1 : N_SENSORES+N_REPETIDORES
    gws = sample(N_SENSORES+N_REPETIDORES+1 : N_TOTAL, rand(1:2), replace=false)
    for gw in gws
        add_arista!(g, r, gw, aristas_peso)
    end
end

# Algunas aristas sensor-sensor para rutas alternativas (mesh parcial)
for _ in 1:15
    u = rand(1:N_SENSORES)
    v = rand(1:N_SENSORES)
    if u != v
        add_arista!(g, u, v, aristas_peso)
    end
end

# Algunas aristas repetidor-repetidor
for _ in 1:8
    u = rand(N_SENSORES+1 : N_SENSORES+N_REPETIDORES)
    v = rand(N_SENSORES+1 : N_SENSORES+N_REPETIDORES)
    if u != v
        add_arista!(g, u, v, aristas_peso)
    end
end

println("Nodos totales  : $N_TOTAL")
println("  Sensores     : $N_SENSORES")
println("  Repetidores  : $N_REPETIDORES")
println("  Gateways     : $N_GATEWAY")
println("Aristas totales: $(ne(g))")
println()

# ============================================================
# SECCIÓN 2: BFS — CAMINO MÍNIMO EN SALTOS
# ============================================================
# Pregunta: ¿Cuántos saltos necesita cada sensor para llegar
# al gateway más cercano? BFS garantiza mínimo de saltos.

println("=" ^ 60)
println("BFS — CAMINO MÍNIMO EN SALTOS AL GATEWAY")
println("=" ^ 60)

function bfs_camino(g::SimpleGraph, origen::Int, destinos::Vector{Int})
    """
    BFS desde origen. Devuelve (distancia_saltos, camino) al destino
    más cercano entre los nodos en `destinos`.
    """
    visitado  = falses(nv(g))
    predecesor = zeros(Int, nv(g))
    cola = Int[]

    visitado[origen] = true
    push!(cola, origen)
    dist = fill(-1, nv(g))
    dist[origen] = 0

    while !isempty(cola)
        actual = popfirst!(cola)
        if actual in destinos
            # Reconstruir camino
            camino = Int[]
            nodo = actual
            while nodo != 0
                pushfirst!(camino, nodo)
                nodo = predecesor[nodo]
            end
            return dist[actual], camino
        end
        for vecino in neighbors(g, actual)
            if !visitado[vecino]
                visitado[vecino] = true
                dist[vecino] = dist[actual] + 1
                predecesor[vecino] = actual
                push!(cola, vecino)
            end
        end
    end
    return -1, Int[]  # no conectado
end

gateways = collect(N_SENSORES+N_REPETIDORES+1 : N_TOTAL)

# BFS para todos los sensores
resultados_bfs = DataFrame(
    sensor     = String[],
    saltos     = Int[],
    camino     = String[],
    bat_media  = Float64[],
    gateway    = String[]
)

sensores_sin_ruta = Int[]

for s in 1:N_SENSORES
    saltos, camino = bfs_camino(g, s, gateways)
    if saltos == -1
        push!(sensores_sin_ruta, s)
        continue
    end
    bat_media = mean([bateria[n] for n in camino])
    camino_str = join([nombre_nodo(n) for n in camino], " → ")
    push!(resultados_bfs, (
        nombre_nodo(s),
        saltos,
        camino_str,
        round(bat_media, digits=1),
        nombre_nodo(camino[end])
    ))
end

sort!(resultados_bfs, :saltos)

println("\nTop 10 sensores con menor número de saltos:")
println("-" ^ 60)
@printf("%-8s  %6s  %-8s  %s\n", "Sensor", "Saltos", "Bat.Med%", "Gateway")
println("-" ^ 60)
for row in eachrow(resultados_bfs[1:min(10,nrow(resultados_bfs)), :])
    @printf("%-8s  %6d  %8.1f  %s\n", row.sensor, row.saltos, row.bat_media, row.gateway)
end

println("\nTop 5 sensores MÁS LEJANOS (más saltos):")
println("-" ^ 60)
ultimos = resultados_bfs[end-min(4,nrow(resultados_bfs)-1):end, :]
for row in eachrow(ultimos)
    @printf("%-8s  %6d  %8.1f  %s\n", row.sensor, row.saltos, row.bat_media, row.gateway)
end

if !isempty(sensores_sin_ruta)
    println("\n⚠ Sensores sin ruta al gateway: $(length(sensores_sin_ruta))")
    println("  ", join([nombre_nodo(s) for s in sensores_sin_ruta], ", "))
end

avg_saltos = mean(resultados_bfs.saltos)
println("\nPromedio saltos red: $(@sprintf("%.2f", avg_saltos))")

# ============================================================
# SECCIÓN 3: DFS — EXPLORACIÓN COMPLETA DE RUTAS
# ============================================================
# Pregunta: ¿Qué rutas alternativas existen desde un sensor
# crítico? DFS mapea TODAS las rutas posibles y calcula
# el costo total de batería de cada una.

println()
println("=" ^ 60)
println("DFS — EXPLORACIÓN DE RUTAS POR CONSUMO DE BATERÍA")
println("=" ^ 60)

function costo_camino(camino::Vector{Int}, aristas_peso::Dict)
    costo = 0.0
    for i in 1:length(camino)-1
        u, v = min(camino[i], camino[i+1]), max(camino[i], camino[i+1])
        costo += get(aristas_peso, (u,v), 999.0)
    end
    return costo
end

function dfs_todas_rutas(g::SimpleGraph, origen::Int, destinos::Vector{Int},
                          aristas_peso::Dict; max_rutas::Int=200)
    """
    DFS recursivo. Encuentra todas las rutas desde origen a cualquier
    nodo en destinos. Limita a max_rutas para evitar explosión combinatoria.
    """
    rutas = Vector{Vector{Int}}()
    visitado = Set{Int}()

    function dfs!(actual::Int, camino::Vector{Int})
        length(rutas) >= max_rutas && return
        if actual in destinos
            push!(rutas, copy(camino))
            return
        end
        for vecino in neighbors(g, actual)
            if !(vecino in visitado)
                push!(visitado, vecino)
                push!(camino, vecino)
                dfs!(vecino, camino)
                pop!(camino)
                delete!(visitado, vecino)
            end
        end
    end

    push!(visitado, origen)
    dfs!(origen, [origen])
    return rutas
end

# Elegir sensor con más conexiones (más interesante para DFS)
sensor_dfs = argmax([degree(g, s) for s in 1:N_SENSORES])
println("\nSensor analizado con DFS: $(nombre_nodo(sensor_dfs))")
println("Grado (conexiones): $(degree(g, sensor_dfs))")
println("Nivel batería     : $(bateria[sensor_dfs])%")
println("\nBuscando todas las rutas al gateway (max 200)...")

rutas_dfs = dfs_todas_rutas(g, sensor_dfs, gateways, aristas_peso)

println("Rutas encontradas : $(length(rutas_dfs))")

if !isempty(rutas_dfs)
    # Calcular costo de cada ruta
    rutas_con_costo = [(r, costo_camino(r, aristas_peso), length(r)-1) for r in rutas_dfs]
    sort!(rutas_con_costo, by=x->x[2])  # ordenar por costo batería

    println("\n--- Top 5 rutas con MENOR consumo de batería ---")
    println("-" ^ 65)
    @printf("%-4s  %-6s  %-8s  %s\n", "Rk", "Saltos", "mAh", "Ruta")
    println("-" ^ 65)
    for (i, (ruta, costo, saltos)) in enumerate(rutas_con_costo[1:min(5,end)])
        ruta_str = join([nombre_nodo(n) for n in ruta], "→")
        @printf("%-4d  %-6d  %-8.3f  %s\n", i, saltos, costo, ruta_str)
    end

    println("\n--- Top 5 rutas con MAYOR consumo de batería ---")
    println("-" ^ 65)
    @printf("%-4s  %-6s  %-8s  %s\n", "Rk", "Saltos", "mAh", "Ruta")
    println("-" ^ 65)
    peores = rutas_con_costo[max(1,end-4):end]
    for (i, (ruta, costo, saltos)) in enumerate(reverse(peores))
        ruta_str = join([nombre_nodo(n) for n in ruta], "→")
        @printf("%-4d  %-6d  %-8.3f  %s\n", i, saltos, costo, ruta_str)
    end

    costos = [c for (_,c,_) in rutas_con_costo]
    saltos_lista = [s for (_,_,s) in rutas_con_costo]
    println("\nEstadísticas de todas las rutas DFS:")
    @printf("  Costo mínimo   : %.3f mAh\n", minimum(costos))
    @printf("  Costo máximo   : %.3f mAh\n", maximum(costos))
    @printf("  Costo promedio : %.3f mAh\n", mean(costos))
    @printf("  Saltos mínimos : %d\n", minimum(saltos_lista))
    @printf("  Saltos máximos : %d\n", maximum(saltos_lista))
end

# ============================================================
# SECCIÓN 4: ANÁLISIS COMPARATIVO BFS vs DFS
# ============================================================

println()
println("=" ^ 60)
println("ANÁLISIS COMPARATIVO BFS vs DFS")
println("=" ^ 60)

# Para el mismo sensor_dfs, comparar ruta BFS vs mejor ruta DFS
saltos_bfs, camino_bfs = bfs_camino(g, sensor_dfs, gateways)
costo_bfs = costo_camino(camino_bfs, aristas_peso)

println("\nSensor: $(nombre_nodo(sensor_dfs))")
println()
println("BFS (mínimos saltos):")
@printf("  Saltos : %d\n", saltos_bfs)
@printf("  Costo  : %.3f mAh\n", costo_bfs)
println("  Ruta   : $(join([nombre_nodo(n) for n in camino_bfs], " → "))")

if !isempty(rutas_dfs)
    rutas_con_costo = [(r, costo_camino(r, aristas_peso), length(r)-1) for r in rutas_dfs]
    sort!(rutas_con_costo, by=x->x[2])
    mejor_ruta_dfs, mejor_costo_dfs, mejor_saltos_dfs = rutas_con_costo[1]

    println("\nDFS (mejor ruta por batería encontrada):")
    @printf("  Saltos : %d\n", mejor_saltos_dfs)
    @printf("  Costo  : %.3f mAh\n", mejor_costo_dfs)
    println("  Ruta   : $(join([nombre_nodo(n) for n in mejor_ruta_dfs], " → "))")

    ahorro = costo_bfs - mejor_costo_dfs
    println()
    if ahorro > 0
        @printf("✓ DFS encontró ruta %.1f%% más eficiente en batería\n",
                abs(ahorro)/costo_bfs*100)
        println("  (BFS prioriza saltos, no batería — trade-off esperado)")
    elseif ahorro < 0
        @printf("✓ BFS resultó %.1f%% más eficiente en este caso\n",
                abs(ahorro)/mejor_costo_dfs*100)
    else
        println("✓ Ambos algoritmos encontraron la misma ruta óptima")
    end
end

# ============================================================
# SECCIÓN 5: ESTADO DE LA RED — SENSORES CRÍTICOS
# ============================================================

println()
println("=" ^ 60)
println("ESTADO DE LA RED — SENSORES CRÍTICOS POR BATERÍA")
println("=" ^ 60)

println("\nSensores con batería CRÍTICA (< 30%):")
println("-" ^ 45)
criticos = [(s, bateria[s]) for s in 1:N_SENSORES if bateria[s] < 30.0]
sort!(criticos, by=x->x[2])
if isempty(criticos)
    println("  Ninguno en estado crítico.")
else
    for (s, bat) in criticos
        saltos, _ = bfs_camino(g, s, gateways)
        @printf("  %-8s  Batería: %5.1f%%  Saltos al GW: %d\n",
                nombre_nodo(s), bat, saltos)
    end
end

println("\nSensores con batería BAJA (30%–50%):")
println("-" ^ 45)
bajos = [(s, bateria[s]) for s in 1:N_SENSORES if 30.0 <= bateria[s] < 50.0]
sort!(bajos, by=x->x[2])
println("  Total: $(length(bajos)) sensores")

println("\nDistribución de batería en sensores:")
baterias_sensores = [bateria[s] for s in 1:N_SENSORES]
@printf("  Media   : %.1f%%\n", mean(baterias_sensores))
@printf("  Mínima  : %.1f%%\n", minimum(baterias_sensores))
@printf("  Máxima  : %.1f%%\n", maximum(baterias_sensores))

# ============================================================
# SECCIÓN 6: EXPORTAR DATOS
# ============================================================

println()
println("=" ^ 60)
println("EXPORTANDO DATOS")
println("=" ^ 60)

# CSV de aristas con pesos
aristas_df = DataFrame(
    nodo_u  = String[],
    nodo_v  = String[],
    tipo_u  = String[],
    tipo_v  = String[],
    bat_u   = Float64[],
    bat_v   = Float64[],
    costo_mah = Float64[]
)
for ((u,v), w) in aristas_peso
    push!(aristas_df, (
        nombre_nodo(u), nombre_nodo(v),
        string(tipo_nodo(u)), string(tipo_nodo(v)),
        bateria[u], bateria[v], w
    ))
end
CSV.write("aristas_red.csv", aristas_df)  # necesita using CSV arriba
println("  aristas_red.csv exportado ($(nrow(aristas_df)) aristas)")

# CSV de nodos
nodos_df = DataFrame(
    id     = 1:N_TOTAL,
    nombre = [nombre_nodo(i) for i in 1:N_TOTAL],
    tipo   = [string(tipo_nodo(i)) for i in 1:N_TOTAL],
    bateria = [bateria[i] for i in 1:N_TOTAL],
    grado  = [degree(g, i) for i in 1:N_TOTAL],
    saltos_gw = [bfs_camino(g, i, gateways)[1] for i in 1:N_TOTAL]
)
CSV.write("nodos_red.csv", nodos_df)
println("  nodos_red.csv exportado ($N_TOTAL nodos)")

# CSV resultados BFS
CSV.write("resultados_bfs.csv", resultados_bfs)
println("  resultados_bfs.csv exportado")

println()
println("=" ^ 60)
println("EJECUCIÓN COMPLETADA — $(Dates.now())")
println("=" ^ 60)
