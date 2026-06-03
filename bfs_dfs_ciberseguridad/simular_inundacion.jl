# ============================================================
# Simulación de Inundación — Red de Sensores Hídricos
# Escenario ESP-NOW: nodos inundados fallan, BFS y DFS re-enrutan
# Autor: Jean Carlo Aucapina
# Fecha: 2026-05-13
# ============================================================

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
# REPRODUCIR RED (misma seed que scripts principales)
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
# HELPERS (BFS / DFS / costo)
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

# Subgrafo que excluye nodos fallidos
function grafo_sin_nodos(g_orig, nodos_fallidos::Set{Int})
    g_nuevo = SimpleGraph(nv(g_orig))
    for e in edges(g_orig)
        u, v = src(e), dst(e)
        (u in nodos_fallidos || v in nodos_fallidos) && continue
        add_edge!(g_nuevo, u, v)
    end
    return g_nuevo
end

# ============================================================
# ESCENARIO DE INUNDACIÓN
# ============================================================
# ESP-NOW opera en 2.4 GHz. Con agua (permitividad ~80) el enlace
# se atenúa ~20 dB. Nodos sumergidos pierden enlace físico.
# Simulamos 3 zonas inundadas, cada una elimina 3-4 nodos.

println("=" ^ 60)
println("ESCENARIO: INUNDACIÓN DE CUENCA HÍDRICA")
println("Protocolo ESP-NOW — Re-enrutamiento BFS vs DFS")
println("=" ^ 60)

# Definir zonas de inundación (subsets de sensores y repetidores)
# Zona A: sector norte — 4 sensores + 1 repetidor
# Zona B: sector central — 3 sensores + 1 repetidor
# Zona C: sector sur — 3 sensores
nodos_fallidos = Set{Int}([
    3, 7, 11, 15,          # zona A — sensores norte
    36,                    # zona A — repetidor R-01
    20, 24, 28,            # zona B — sensores central
    41,                    # zona B — repetidor R-06
    32, 34, 35,            # zona C — sensores sur
])

n_caidos = length(nodos_fallidos)
n_sensores_caidos = length([n for n in nodos_fallidos if n <= N_SENSORES])
n_reps_caidos     = length([n for n in nodos_fallidos if N_SENSORES < n <= N_SENSORES+N_REPETIDORES])

println("\nNodos inundados ($(n_caidos) total):")
println("  Sensores caídos   : $n_sensores_caidos — $(join([nombre_nodo(n) for n in sort(collect(nodos_fallidos)) if n <= N_SENSORES], ", "))")
println("  Repetidores caídos: $n_reps_caidos  — $(join([nombre_nodo(n) for n in sort(collect(nodos_fallidos)) if N_SENSORES < n <= N_SENSORES+N_REPETIDORES], ", "))")

# Grafo degradado post-inundación
g_flood = grafo_sin_nodos(g, nodos_fallidos)
sensores_activos = [s for s in 1:N_SENSORES if !(s in nodos_fallidos)]
gateways_activos = [gw for gw in gateways if !(gw in nodos_fallidos)]

println("\nNodos activos post-inundación:")
println("  Sensores activos : $(length(sensores_activos))/$(N_SENSORES)")
println("  Repetidores activos: $(N_REPETIDORES - n_reps_caidos)/$(N_REPETIDORES)")
println("  Gateways activos : $(length(gateways_activos))/$(N_GATEWAY)")
println("  Aristas en red normal  : $(ne(g))")
println("  Aristas en red degradada: $(ne(g_flood))")

# ============================================================
# ANÁLISIS BFS: normal vs inundación
# ============================================================

println("\n" * "=" ^ 60)
println("BFS — ANTES vs DESPUÉS DE INUNDACIÓN")
println("=" ^ 60)

resultados_comparacion = []

for s in sensores_activos
    saltos_antes, camino_antes = bfs_camino(g, s, gateways)
    saltos_despues, camino_despues = bfs_camino(g_flood, s, gateways_activos)

    costo_antes   = saltos_antes   != -1 ? costo_ruta(camino_antes)   : Inf
    costo_despues = saltos_despues != -1 ? costo_ruta(camino_despues) : Inf

    # Detectar si la ruta cambió (algún nodo del camino original cayó)
    ruta_afectada = any(n in nodos_fallidos for n in camino_antes)

    push!(resultados_comparacion, (
        sensor         = nombre_nodo(s),
        saltos_antes   = saltos_antes,
        saltos_despues = saltos_despues,
        costo_antes    = round(costo_antes, digits=3),
        costo_despues  = round(costo_despues, digits=3),
        ruta_afectada  = ruta_afectada,
        sin_ruta       = saltos_despues == -1,
    ))
end

# Sensores que perdieron ruta
sin_ruta = [r for r in resultados_comparacion if r.sin_ruta]
con_reroute = [r for r in resultados_comparacion if r.ruta_afectada && !r.sin_ruta]
sin_cambio  = [r for r in resultados_comparacion if !r.ruta_afectada]

println("\nResumen BFS post-inundación:")
@printf("  Sensores sin ruta al gateway : %d\n", length(sin_ruta))
@printf("  Sensores con re-enrutamiento : %d (ruta original afectada, nueva ruta encontrada)\n", length(con_reroute))
@printf("  Sensores sin cambio de ruta  : %d\n", length(sin_cambio))

if !isempty(con_reroute)
    println("\n--- Sensores re-enrutados por BFS ---")
    println("-" ^ 70)
    @printf("%-8s  %-10s  %-12s  %-10s  %-12s\n",
            "Sensor", "Saltos-ant", "mAh-ant", "Saltos-post", "mAh-post")
    println("-" ^ 70)
    for r in con_reroute[1:min(8, end)]
        @printf("%-8s  %10d  %12.3f  %11d  %12.3f\n",
                r.sensor, r.saltos_antes, r.costo_antes, r.saltos_despues, r.costo_despues)
    end
end

if !isempty(sin_ruta)
    println("\n--- Sensores AISLADOS (sin ruta al gateway) ---")
    for r in sin_ruta
        println("  $(r.sensor)")
    end
end

# ============================================================
# ANÁLISIS DFS: rutas alternativas para sensores afectados
# ============================================================

println("\n" * "=" ^ 60)
println("DFS — DESCUBRIMIENTO DE RUTAS ALTERNATIVAS POST-INUNDACIÓN")
println("=" ^ 60)

# Elegir el sensor más conectado que NO cayó y cuya ruta original fue afectada
sensores_reroute_ids = [s for s in sensores_activos
    if any(r.sensor == nombre_nodo(s) && r.ruta_afectada && !r.sin_ruta
           for r in resultados_comparacion)]

if isempty(sensores_reroute_ids)
    sensor_demo = first(sensores_activos)
else
    sensor_demo = sensores_reroute_ids[argmax([degree(g_flood, s) for s in sensores_reroute_ids])]
end

println("\nSensor demo (mayor grado, ruta afectada por inundación): $(nombre_nodo(sensor_demo))")

# DFS en red normal
rutas_normal = dfs_todas_rutas(g, sensor_demo, gateways; max_rutas=100)
costos_normal = [costo_ruta(r) for r in rutas_normal]

# DFS en red degradada
rutas_flood = dfs_todas_rutas(g_flood, sensor_demo, gateways_activos; max_rutas=100)
costos_flood = [costo_ruta(r) for r in rutas_flood]

_, camino_bfs_normal = bfs_camino(g, sensor_demo, gateways)
_, camino_bfs_flood  = bfs_camino(g_flood, sensor_demo, gateways_activos)
costo_bfs_normal = costo_ruta(camino_bfs_normal)
costo_bfs_flood  = camino_bfs_flood == [] ? Inf : costo_ruta(camino_bfs_flood)

println("\nRutas encontradas por DFS:")
@printf("  Red normal   : %d rutas | costo mín %.3f mAh | costo máx %.3f mAh\n",
        length(rutas_normal),
        isempty(costos_normal) ? 0.0 : minimum(costos_normal),
        isempty(costos_normal) ? 0.0 : maximum(costos_normal))
@printf("  Red inundada : %d rutas | costo mín %.3f mAh | costo máx %.3f mAh\n",
        length(rutas_flood),
        isempty(costos_flood) ? 0.0 : minimum(costos_flood),
        isempty(costos_flood) ? 0.0 : maximum(costos_flood))

println("\nComparación BFS vs DFS (mejor ruta) en red inundada:")
@printf("  BFS (mínimos saltos) : %d saltos, %.3f mAh\n",
        length(camino_bfs_flood)-1, costo_bfs_flood)
if !isempty(rutas_flood)
    mejor_ruta_flood = rutas_flood[argmin(costos_flood)]
    mejor_costo_flood = minimum(costos_flood)
    @printf("  DFS (menor costo)    : %d saltos, %.3f mAh\n",
            length(mejor_ruta_flood)-1, mejor_costo_flood)
    ahorro = costo_bfs_flood - mejor_costo_flood
    if ahorro > 0
        @printf("  -> DFS ahorra %.1f%% de batería vs BFS en red degradada\n",
                ahorro/costo_bfs_flood*100)
    else
        @printf("  -> BFS sigue siendo %.1f%% más eficiente en red degradada\n",
                abs(ahorro)/mejor_costo_flood*100)
    end
end

# ============================================================
# FIGURA 9 — Grafo red degradada con nodos fallidos y rutas
# ============================================================

println("\nFigura 9: red degradada post-inundación...")

color_sensor    = colorant"steelblue"
color_rep       = colorant"darkorange"
color_gw        = colorant"forestgreen"
color_fallido   = colorant"gray25"
color_origen    = colorant"crimson"
color_reroute   = colorant"deeppink"

# Colores de nodo: gris oscuro si caído, color normal si activo
nfill_flood = [
    i in nodos_fallidos ? color_fallido :
    tipo_nodo(i) == :sensor    ? color_sensor :
    tipo_nodo(i) == :repetidor ? color_rep : color_gw
    for i in 1:N_TOTAL
]

# Resaltar sensor demo y su nueva ruta BFS
en_nueva_ruta = Set(camino_bfs_flood)
nfill_flood = [
    i in nodos_fallidos ? color_fallido :
    i == sensor_demo ? color_origen :
    (i in en_nueva_ruta && !(i in nodos_fallidos)) ?
        (tipo_nodo(i) == :gateway ? color_gw : color_reroute) :
    tipo_nodo(i) == :sensor    ? color_sensor :
    tipo_nodo(i) == :repetidor ? color_rep : color_gw
    for i in 1:N_TOTAL
]

nsize_flood = [
    i in nodos_fallidos ? 0.6 :
    i == sensor_demo ? 3.8 :
    i in en_nueva_ruta ? 3.2 :
    tipo_nodo(i) == :gateway ? 3.5 :
    tipo_nodo(i) == :repetidor ? 2.5 : 1.8
    for i in 1:N_TOTAL
]

# Aristas: roja si en nueva ruta BFS, gris tenue si arista perdida (nodo caído)
aristas_nueva_ruta = Set{Tuple{Int,Int}}()
for i in 1:length(camino_bfs_flood)-1
    push!(aristas_nueva_ruta, (min(camino_bfs_flood[i], camino_bfs_flood[i+1]),
                                max(camino_bfs_flood[i], camino_bfs_flood[i+1])))
end

efill_flood = [
    begin
        u, v = src(e), dst(e)
        key = (min(u,v), max(u,v))
        if key in aristas_nueva_ruta
            colorant"crimson"
        elseif u in nodos_fallidos || v in nodos_fallidos
            colorant"gray85"
        else
            colorant"gray70"
        end
    end
    for e in edges(g)   # iterar sobre grafo ORIGINAL para mostrar aristas perdidas
]

p9 = gplot(g;          # grafo original — muestra también aristas cortadas
    nodefillc     = nfill_flood,
    nodesize      = nsize_flood,
    nodelabel     = [nombre_nodo(i) for i in 1:N_TOTAL],
    nodelabelsize = 1.3,
    edgestrokec   = efill_flood,
    EDGELINEWIDTH = 0.4,
    layout        = spring_layout,
)
draw(PNG("imgs/fig9_inundacion_red.png", 24cm, 19cm), p9)
println("  -> imgs/fig9_inundacion_red.png")

# ============================================================
# FIGURA 10 — Comparación: rutas DFS disponibles antes vs después
# ============================================================

println("Figura 10: comparacion rutas antes/despues inundacion...")

# Subplot 1: histograma de costos DFS antes vs después
p10a = histogram(costos_normal;
    bins=15, color=:steelblue, alpha=0.6, label="Red normal",
    xlabel="Consumo (mAh)", ylabel="Numero de rutas",
    title="Distribucion DFS — $(nombre_nodo(sensor_demo))",
)
histogram!(costos_flood;
    bins=15, color=:crimson, alpha=0.6, label="Red inundada",
)
vline!([costo_bfs_normal]; color=:blue, linewidth=2, linestyle=:dash, label="BFS normal")
if isfinite(costo_bfs_flood)
    vline!([costo_bfs_flood]; color=:red, linewidth=2, linestyle=:dash, label="BFS inundada")
end

# Subplot 2: barras de sensores afectados — saltos antes vs después
n_muestra = min(12, length(con_reroute))
if n_muestra > 0
    nombres_afect = [r.sensor for r in con_reroute[1:n_muestra]]
    saltos_ant    = [r.saltos_antes for r in con_reroute[1:n_muestra]]
    saltos_post   = [r.saltos_despues for r in con_reroute[1:n_muestra]]

    xs = 1:n_muestra
    p10b = bar(xs .- 0.2, saltos_ant;
        bar_width=0.35, color=:steelblue, alpha=0.8,
        label="Antes", ylabel="Saltos BFS", title="Re-enrutamiento BFS",
        xticks=(xs, nombres_afect), xrotation=45,
    )
    bar!(xs .+ 0.2, saltos_post;
        bar_width=0.35, color=:crimson, alpha=0.8, label="Despues (flood)",
    )
else
    p10b = bar(["Sin datos"], [0]; legend=false, title="Sin sensores re-enrutados")
end

plot(p10a, p10b;
    layout=Plots.grid(1,2),
    plot_title="Impacto de Inundacion: BFS y DFS en Red ESP-NOW",
    size=(1100, 480),
)
savefig("imgs/fig10_impacto_inundacion.png")
println("  -> imgs/fig10_impacto_inundacion.png")

# ============================================================
# FIGURA 11 — Scatter: disponibilidad de rutas DFS antes vs después
# ============================================================

println("Figura 11: scatter rutas DFS antes vs despues...")

n_saltos_normal = [length(r)-1 for r in rutas_normal]
n_saltos_flood  = [length(r)-1 for r in rutas_flood]

scatter(n_saltos_normal, costos_normal;
    color=:steelblue, alpha=0.5, markersize=5, label="Red normal ($(length(rutas_normal)) rutas)",
    xlabel="Saltos", ylabel="Consumo (mAh)",
    title="Espacio de rutas DFS — $(nombre_nodo(sensor_demo))",
)
scatter!(n_saltos_flood, costos_flood;
    color=:crimson, alpha=0.5, markersize=5, label="Red inundada ($(length(rutas_flood)) rutas)",
)
# Marcar ruta BFS en cada escenario
scatter!([length(camino_bfs_normal)-1], [costo_bfs_normal];
    color=:blue, markersize=12, markershape=:star5, label="BFS normal")
if !isempty(camino_bfs_flood)
    scatter!([length(camino_bfs_flood)-1], [costo_bfs_flood];
        color=:red, markersize=12, markershape=:star5, label="BFS inundada")
end
savefig("imgs/fig11_scatter_rutas_flood.png")
println("  -> imgs/fig11_scatter_rutas_flood.png")

# ============================================================
# RESUMEN FINAL
# ============================================================

println()
println("=" ^ 60)
println("RESUMEN — IMPACTO DE INUNDACIÓN EN COMUNICACIÓN WSN")
println("=" ^ 60)

pct_caidos    = round(n_sensores_caidos / N_SENSORES * 100, digits=1)
pct_sin_ruta  = round(length(sin_ruta) / length(sensores_activos) * 100, digits=1)
pct_reroute   = round(length(con_reroute) / length(sensores_activos) * 100, digits=1)

@printf("Sensores inundados/caídos   : %d / %d (%.1f%%)\n", n_sensores_caidos, N_SENSORES, pct_caidos)
@printf("Repetidores caídos          : %d / %d\n", n_reps_caidos, N_REPETIDORES)
@printf("Aristas perdidas            : %d\n", ne(g) - ne(g_flood))
@printf("\nDe los sensores activos (%d):\n", length(sensores_activos))
@printf("  Sin ruta al gateway       : %d (%.1f%%)\n", length(sin_ruta), pct_sin_ruta)
@printf("  Re-enrutados por BFS      : %d (%.1f%%)\n", length(con_reroute), pct_reroute)
@printf("  Sin impacto en ruta       : %d\n", length(sin_cambio))

if !isempty(rutas_flood) && !isempty(rutas_normal)
    @printf("\nDFS — Capacidad de descubrimiento:\n")
    @printf("  Rutas disponibles normal  : %d\n", length(rutas_normal))
    @printf("  Rutas disponibles flood   : %d\n", length(rutas_flood))
    @printf("  Reduccion de rutas        : %.1f%%\n",
            (1 - length(rutas_flood)/length(rutas_normal)) * 100)
end

println("\nFiguras generadas:")
println("  imgs/fig9_inundacion_red.png")
println("  imgs/fig10_impacto_inundacion.png")
println("  imgs/fig11_scatter_rutas_flood.png")
println()
println("=" ^ 60)
println("SIMULACION COMPLETADA")
println("=" ^ 60)
