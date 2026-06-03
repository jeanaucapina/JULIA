# ============================================================
# ESP-NOW Broadcast Flood vs Enrutamiento Dirigido (BFS/DFS)
# Comparación de eficiencia en red de sensores hídricos
# Autor: Jean Carlo Aucapina
# Fecha: 2026-05-13
# ============================================================
#
# CONCEPTOS:
#   Broadcast Flood (ESP-NOW modo inundación):
#     Cada nodo que recibe el paquete lo reenvía a TODOS sus vecinos.
#     No hay estado de ruta. El paquete se propaga como ola.
#     Ventaja: simplicidad, resiliencia.
#     Desventaja: tormenta de broadcasts, consumo exponencial.
#
#   Enrutamiento Dirigido (BFS / DFS):
#     El paquete sigue UNA ruta calculada hacia el gateway.
#     Solo los nodos del camino transmiten.
#     Ventaja: mínimo consumo, sin colisiones.
#     Desventaja: requiere tabla de rutas, falla si ruta cae.

using Graphs
using GraphPlot
using Compose
import Cairo, Fontconfig
using Colors
using Plots
using Statistics
using StatsBase
using Random
using Printf

gr(size=(900,620), dpi=150)
Random.seed!(42)
mkpath("imgs")

# ============================================================
# REPRODUCIR RED (misma seed)
# ============================================================

const N_SENSORES    = 35
const N_REPETIDORES = 12
const N_GATEWAY     = 3
const N_TOTAL       = N_SENSORES + N_REPETIDORES + N_GATEWAY

function tipo_nodo(id::Int)
    id <= N_SENSORES                 && return :sensor
    id <= N_SENSORES + N_REPETIDORES && return :repetidor
    return :gateway
end

function nombre_nodo(id::Int)
    t = tipo_nodo(id)
    t == :sensor    && return "S-$(lpad(id, 2, '0'))"
    t == :repetidor && return "R-$(lpad(id-N_SENSORES, 2, '0'))"
    return "GW-$(id-N_SENSORES-N_REPETIDORES)"
end

bateria = Dict{Int,Float64}()
for i in 1:N_TOTAL
    if tipo_nodo(i) == :gateway
        bateria[i] = 100.0
    elseif tipo_nodo(i) == :repetidor
        bateria[i] = rand(40.0:5.0:90.0)
    else
        bateria[i] = rand(20.0:5.0:85.0)
    end
end

g = SimpleGraph(N_TOTAL)
aristas_peso = Dict{Tuple{Int,Int},Float64}()

function peso_arista(::Int, v::Int)
    base         = rand(0.5:0.1:3.0)
    penalizacion = 100.0 / bateria[v]
    ruido        = rand(0.9:0.05:1.1)
    return round(base * penalizacion * ruido, digits=3)
end

function add_arista!(g, u, v)
    if !has_edge(g, u, v)
        add_edge!(g, u, v)
        aristas_peso[(min(u,v), max(u,v))] = peso_arista(u, v)
    end
end

for s in 1:N_SENSORES
    reps = sample(N_SENSORES+1:N_SENSORES+N_REPETIDORES, rand(1:2), replace=false)
    for r in reps; add_arista!(g, s, r); end
end
for r in N_SENSORES+1:N_SENSORES+N_REPETIDORES
    gws = sample(N_SENSORES+N_REPETIDORES+1:N_TOTAL, rand(1:2), replace=false)
    for gw in gws; add_arista!(g, r, gw); end
end
for _ in 1:15
    u, v = rand(1:N_SENSORES), rand(1:N_SENSORES)
    u != v && add_arista!(g, u, v)
end
for _ in 1:8
    u = rand(N_SENSORES+1:N_SENSORES+N_REPETIDORES)
    v = rand(N_SENSORES+1:N_SENSORES+N_REPETIDORES)
    u != v && add_arista!(g, u, v)
end

gateways = collect(N_SENSORES+N_REPETIDORES+1:N_TOTAL)

# ============================================================
# HELPERS — BFS y costo
# ============================================================

function bfs_camino(g, origen, destinos)
    visitado   = falses(nv(g))
    predecesor = zeros(Int, nv(g))
    dist       = fill(-1, nv(g))
    cola       = Int[]
    visitado[origen] = true
    dist[origen] = 0
    push!(cola, origen)
    while !isempty(cola)
        actual = popfirst!(cola)
        if actual in destinos
            camino = Int[]
            nodo = actual
            while nodo != 0; pushfirst!(camino, nodo); nodo = predecesor[nodo]; end
            return dist[actual], camino
        end
        for v in neighbors(g, actual)
            visitado[v] && continue
            visitado[v]   = true
            dist[v]       = dist[actual] + 1
            predecesor[v] = actual
            push!(cola, v)
        end
    end
    return -1, Int[]
end

function costo_ruta(camino)
    s = 0.0
    for i in 1:length(camino)-1
        u, v = min(camino[i], camino[i+1]), max(camino[i], camino[i+1])
        s += get(aristas_peso, (u, v), 999.0)
    end
    return s
end

function dfs_todas_rutas(g, origen, destinos; max_rutas=200)
    rutas    = Vector{Vector{Int}}()
    visitado = Set{Int}()
    function dfs!(actual, camino)
        length(rutas) >= max_rutas && return
        if actual in destinos
            push!(rutas, copy(camino))
            return
        end
        for v in neighbors(g, actual)
            v in visitado && continue
            push!(visitado, v); push!(camino, v)
            dfs!(v, camino)
            pop!(camino); delete!(visitado, v)
        end
    end
    push!(visitado, origen)
    dfs!(origen, [origen])
    return rutas
end

# ============================================================
# BROADCAST FLOOD ESP-NOW — Simulación
# ============================================================
# Modelo: BFS por niveles, pero TODOS los nodos de cada nivel
# retransmiten simultáneamente (no solo los del camino óptimo).
# Registramos:
#   - transmisiones_total: cuántos paquetes se envían en la red
#   - nodos_activos:       cuántos nodos participan en la retransmisión
#   - latencia_saltos:     saltos hasta que el GW recibe el primer paquete
#   - consumo_total_mah:   suma de todas las aristas usadas

function espnow_flood(g, origen::Int, destinos::Set{Int})
    """
    Simula broadcast flood ESP-NOW desde origen.
    Cada nodo que recibe el paquete (por primera vez) lo reenvía
    a TODOS sus vecinos. Retorna:
      (saltos_hasta_gw, nodos_participantes, transmisiones, consumo_mah,
       orden_recepcion)  donde orden_recepcion[nodo] = salto en que llegó
    """
    recibido     = Dict{Int,Int}()   # nodo -> salto en que recibió
    recibido[origen] = 0

    transmisiones = 0
    consumo_mah   = 0.0
    gw_salto      = -1

    # Procesamiento por rondas (niveles de flood)
    frontera_actual = [origen]

    while !isempty(frontera_actual)
        frontera_siguiente = Int[]
        for nodo in frontera_actual
            salto_actual = recibido[nodo]
            for vecino in neighbors(g, nodo)
                # Siempre transmite (broadcast) — incluso si vecino ya recibió
                # pero solo cuenta nueva recepción si es primera vez
                transmisiones += 1
                u, v = min(nodo, vecino), max(nodo, vecino)
                consumo_mah += get(aristas_peso, (u, v), 1.0)

                if !haskey(recibido, vecino)
                    recibido[vecino] = salto_actual + 1
                    push!(frontera_siguiente, vecino)

                    if vecino in destinos && gw_salto == -1
                        gw_salto = salto_actual + 1
                    end
                end
                # En broadcast real: nodos ya visitados también reciben
                # duplicados (tormenta). Contamos la transmisión igual.
            end
        end
        frontera_actual = frontera_siguiente
    end

    nodos_part = length(recibido) - 1  # excluye origen
    return gw_salto, nodos_part, transmisiones, consumo_mah, recibido
end

# ============================================================
# COMPARACIÓN PARA TODOS LOS SENSORES
# ============================================================

println("=" ^ 65)
println("ESP-NOW BROADCAST FLOOD vs ENRUTAMIENTO DIRIGIDO (BFS/DFS)")
println("Red de Sensores Hídricos — 50 nodos")
println("=" ^ 65)

gateways_set = Set(gateways)

# Métricas por sensor
resultados = []

for s in 1:N_SENSORES
    # --- Enrutamiento dirigido BFS ---
    saltos_bfs, camino_bfs = bfs_camino(g, s, gateways)
    costo_bfs   = saltos_bfs == -1 ? Inf : costo_ruta(camino_bfs)
    tx_bfs      = saltos_bfs == -1 ? 0   : saltos_bfs          # 1 tx por salto
    nodos_bfs   = saltos_bfs == -1 ? 0   : length(camino_bfs)  # nodos en ruta

    # --- Broadcast flood ESP-NOW ---
    gw_salto_flood, nodos_flood, tx_flood, costo_flood, _ = espnow_flood(g, s, gateways_set)

    push!(resultados, (
        sensor       = nombre_nodo(s),
        # BFS
        saltos_bfs   = saltos_bfs,
        tx_bfs       = tx_bfs,
        nodos_bfs    = nodos_bfs,
        costo_bfs    = round(costo_bfs, digits=3),
        # Flood
        saltos_flood = gw_salto_flood,
        tx_flood     = tx_flood,
        nodos_flood  = nodos_flood,
        costo_flood  = round(costo_flood, digits=3),
        # Overhead
        overhead_tx  = tx_flood - tx_bfs,
        overhead_mah = round(costo_flood - costo_bfs, digits=3),
    ))
end

# Promedios globales
avg_saltos_bfs   = mean(r.saltos_bfs   for r in resultados)
avg_saltos_flood = mean(r.saltos_flood for r in resultados)
avg_tx_bfs       = mean(r.tx_bfs       for r in resultados)
avg_tx_flood     = mean(r.tx_flood     for r in resultados)
avg_mah_bfs      = mean(r.costo_bfs    for r in resultados)
avg_mah_flood    = mean(r.costo_flood  for r in resultados)
overhead_medio   = round((avg_tx_flood / avg_tx_bfs - 1) * 100, digits=1)

println("\n--- Resumen global (promedio sobre 35 sensores) ---")
println("-" ^ 65)
@printf("%-28s  %10s  %10s\n", "Métrica", "Dirigido BFS", "Flood ESP-NOW")
println("-" ^ 65)
@printf("%-28s  %10.2f  %10.2f\n", "Saltos al gateway",        avg_saltos_bfs,   avg_saltos_flood)
@printf("%-28s  %10.2f  %10.2f\n", "Transmisiones por paquete", avg_tx_bfs,       avg_tx_flood)
@printf("%-28s  %10.2f  %10.2f\n", "Nodos participantes",       mean(r.nodos_bfs for r in resultados), mean(r.nodos_flood for r in resultados))
@printf("%-28s  %10.3f  %10.3f\n", "Consumo total (mAh)",       avg_mah_bfs,      avg_mah_flood)
println("-" ^ 65)
@printf("Overhead transmisiones flood vs BFS: %.1f%%\n", overhead_medio)
@printf("Overhead consumo mAh flood vs BFS  : %.1f%%\n", (avg_mah_flood/avg_mah_bfs - 1)*100)

# Top 5 peores overhead
println("\n--- Top 5 sensores con mayor overhead de flood ---")
println("-" ^ 65)
@printf("%-8s  %6s  %6s  %8s  %10s  %12s\n",
        "Sensor", "TX-BFS", "TX-Flood", "OH-TX", "mAh-BFS", "mAh-Flood")
println("-" ^ 65)
ord = sort(resultados, by=r->r.overhead_tx, rev=true)
for r in ord[1:5]
    @printf("%-8s  %6d  %8d  %8d  %10.3f  %12.3f\n",
            r.sensor, r.tx_bfs, r.tx_flood, r.overhead_tx, r.costo_bfs, r.costo_flood)
end

# ============================================================
# DFS vs FLOOD: rutas alternativas
# ============================================================

println("\n" * "=" ^ 65)
println("DFS vs FLOOD — Descubrimiento de rutas (sensor S-04)")
println("=" ^ 65)

sensor_demo = 4
rutas_dfs = dfs_todas_rutas(g, sensor_demo, gateways; max_rutas=200)
costos_dfs = [costo_ruta(r) for r in rutas_dfs]
_, _, tx_flood_demo, mah_flood_demo, recibido_demo = espnow_flood(g, sensor_demo, gateways_set)
_, camino_bfs_demo = bfs_camino(g, sensor_demo, gateways)
costo_bfs_demo = costo_ruta(camino_bfs_demo)

@printf("\nSensor S-04:\n")
@printf("  BFS dirigido       : %d saltos, %.3f mAh, %d transmisiones\n",
        length(camino_bfs_demo)-1, costo_bfs_demo, length(camino_bfs_demo)-1)
@printf("  DFS mejor ruta     : %d saltos, %.3f mAh (de %d rutas exploradas)\n",
        length(rutas_dfs[argmin(costos_dfs)])-1, minimum(costos_dfs), length(rutas_dfs))
@printf("  Flood ESP-NOW      : %d saltos (1er GW), %.3f mAh, %d transmisiones totales\n",
        recibido_demo[gateways[1]], mah_flood_demo, tx_flood_demo)

# ============================================================
# FIGURA 12 — Comparación transmisiones y mAh: BFS vs Flood
# ============================================================

println("\nFigura 12: transmisiones BFS vs Flood por sensor...")

nombres_s = [r.sensor for r in resultados]
tx_bfs_v  = [r.tx_bfs    for r in resultados]
tx_fl_v   = [r.tx_flood  for r in resultados]
mah_bfs_v = [r.costo_bfs  for r in resultados]
mah_fl_v  = [r.costo_flood for r in resultados]

xs = 1:N_SENSORES

p_tx = bar(xs .- 0.22, tx_bfs_v;
    bar_width=0.4, color=:steelblue, alpha=0.85,
    label="BFS dirigido",
    ylabel="Transmisiones por paquete",
    title="Transmisiones: BFS vs Flood",
    xticks=(xs, nombres_s), xrotation=70,
    ylims=(0, maximum(tx_fl_v)*1.12),
)
bar!(xs .+ 0.22, tx_fl_v;
    bar_width=0.4, color=:crimson, alpha=0.75,
    label="Flood ESP-NOW",
)

p_mah = bar(xs .- 0.22, mah_bfs_v;
    bar_width=0.4, color=:steelblue, alpha=0.85,
    label="BFS dirigido",
    ylabel="Consumo total (mAh)",
    title="Consumo bateria: BFS vs Flood",
    xticks=(xs, nombres_s), xrotation=70,
    ylims=(0, maximum(mah_fl_v)*1.12),
)
bar!(xs .+ 0.22, mah_fl_v;
    bar_width=0.4, color=:crimson, alpha=0.75,
    label="Flood ESP-NOW",
)

plot(p_tx, p_mah;
    layout=Plots.grid(1,2),
    plot_title="ESP-NOW Flood vs Enrutamiento Dirigido BFS",
    size=(1200, 500),
)
savefig("imgs/fig12_flood_vs_bfs_barras.png")
println("  -> imgs/fig12_flood_vs_bfs_barras.png")

# ============================================================
# FIGURA 13 — Scatter: overhead tx vs grado del nodo
# ============================================================

println("Figura 13: scatter overhead vs grado de nodo...")

grados_s  = [degree(g, s) for s in 1:N_SENSORES]
overhead_v = [r.overhead_tx for r in resultados]

scatter(grados_s, overhead_v;
    color=:darkorange, alpha=0.7, markersize=7,
    xlabel="Grado del sensor (num. conexiones)",
    ylabel="Overhead transmisiones (Flood - BFS)",
    title="Overhead ESP-NOW Flood vs Conectividad del Nodo",
    label="Sensores",
    legend=:topleft,
)
# línea tendencia simple
if length(grados_s) > 1
    x_ord = sort(unique(grados_s))
    # promedio de overhead por grado
    for gd in x_ord
        idxs = findall(==(gd), grados_s)
        scatter!([gd], [mean(overhead_v[idxs])];
            color=:crimson, markersize=11, markershape=:diamond,
            label= gd == x_ord[1] ? "Media por grado" : "")
    end
end
savefig("imgs/fig13_overhead_vs_grado.png")
println("  -> imgs/fig13_overhead_vs_grado.png")

# ============================================================
# FIGURA 14 — Propagación flood por niveles (grafo completo)
# ============================================================

println("Figura 14: propagacion flood por niveles desde S-04...")

color_sensor = colorant"steelblue"
color_rep    = colorant"darkorange"
color_gw     = colorant"forestgreen"
color_origen = colorant"crimson"

# Colores por salto de flood (gradiente azul → rojo según nivel)
paleta_flood = [
    colorant"gold",          # nivel 1
    colorant"orange",        # nivel 2
    colorant"darkorange",    # nivel 3
    colorant"orangered",     # nivel 4
    colorant"crimson",       # nivel 5+
]

max_nivel = maximum(values(recibido_demo))

nfill_flood = [
    i == sensor_demo ? colorant"black" :
    !haskey(recibido_demo, i) ? colorant"lightgray" :
    recibido_demo[i] == 0 ? colorant"black" :
    paleta_flood[min(recibido_demo[i], length(paleta_flood))]
    for i in 1:N_TOTAL
]

nsize_flood = [
    i == sensor_demo ? 4.0 :
    !haskey(recibido_demo, i) ? 1.0 :
    tipo_nodo(i) == :gateway ? 3.5 :
    tipo_nodo(i) == :repetidor ? 2.5 : 1.8
    for i in 1:N_TOTAL
]

p14 = gplot(g;
    nodefillc     = nfill_flood,
    nodesize      = nsize_flood,
    nodelabel     = [nombre_nodo(i) for i in 1:N_TOTAL],
    nodelabelsize = 1.3,
    edgestrokec   = colorant"gray75",
    EDGELINEWIDTH = 0.35,
    layout        = spring_layout,
)
draw(PNG("imgs/fig14_flood_propagacion.png", 24cm, 19cm), p14)
println("  -> imgs/fig14_flood_propagacion.png")

# ============================================================
# RESUMEN FINAL
# ============================================================

println()
println("=" ^ 65)
println("RESUMEN COMPARATIVO")
println("=" ^ 65)
@printf("\n%-35s  %12s  %12s\n", "Métrica", "BFS Dirigido", "Flood ESP-NOW")
println("-" ^ 65)
@printf("%-35s  %12.2f  %12.2f\n", "Saltos promedio al gateway",         avg_saltos_bfs,   avg_saltos_flood)
@printf("%-35s  %12.2f  %12.2f\n", "Transmisiones promedio por paquete", avg_tx_bfs,       avg_tx_flood)
@printf("%-35s  %12.3f  %12.3f\n", "Consumo promedio mAh",               avg_mah_bfs,      avg_mah_flood)
@printf("%-35s  %12s  %12s\n",     "Requiere tabla de rutas",            "Sí",             "No")
@printf("%-35s  %12s  %12s\n",     "Garantiza entrega sin ciclos",       "Sí",             "No (duplicados)")
@printf("%-35s  %12s  %12s\n",     "Resiliencia ante fallo de nodo",     "Re-calcula BFS", "Automática")
@printf("%-35s  %12s  %12s\n",     "Escalabilidad en redes grandes",     "Alta",           "Baja (tormenta)")
println("-" ^ 65)
@printf("Overhead medio de transmisiones flood: %+.1f%%\n", overhead_medio)
@printf("Overhead medio de consumo mAh flood  : %+.1f%%\n", (avg_mah_flood/avg_mah_bfs - 1)*100)
println("\nFiguras generadas:")
println("  imgs/fig12_flood_vs_bfs_barras.png")
println("  imgs/fig13_overhead_vs_grado.png")
println("  imgs/fig14_flood_propagacion.png")
println()
println("=" ^ 65)
println("SIMULACION COMPLETADA")
println("=" ^ 65)
