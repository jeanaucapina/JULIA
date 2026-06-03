# ============================================================
# Generador de figuras — BFS y DFS en Red de Sensores Hídricos
# GraphPlot para grafos, Plots para charts estadísticos
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

gr(size=(900,620), dpi=150)
Random.seed!(42)

mkpath("imgs")

# ============================================================
# REPRODUCIR RED (misma seed que script principal)
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
    t == :sensor    && return "S$(lpad(id,2,'0'))"
    t == :repetidor && return "R$(lpad(id-N_SENSORES,2,'0'))"
    return "GW$(id-N_SENSORES-N_REPETIDORES)"
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
# HELPERS
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

# Paleta de colores por tipo de nodo
color_sensor    = colorant"steelblue"
color_rep       = colorant"darkorange"
color_gw        = colorant"forestgreen"
color_origen    = colorant"crimson"
color_camino    = colorant"orange"
color_gris      = colorant"lightgray"

node_fill = [
    tipo_nodo(i) == :sensor    ? color_sensor :
    tipo_nodo(i) == :repetidor ? color_rep : color_gw
    for i in 1:N_TOTAL
]

node_size_base = [
    tipo_nodo(i) == :gateway   ? 3.5 :
    tipo_nodo(i) == :repetidor ? 2.5 : 1.8
    for i in 1:N_TOTAL
]

# ============================================================
# FIGURA 1 — Grafo completo coloreado por tipo
# ============================================================

println("Figura 1: grafo completo...")

p1 = gplot(g;
    nodefillc    = node_fill,
    nodesize     = node_size_base,
    nodelabel    = [nombre_nodo(i) for i in 1:N_TOTAL],
    nodelabelsize = 1.5,
    edgestrokec  = colorant"gray70",
    EDGELINEWIDTH = 0.3,
    layout       = spring_layout,
)
draw(PNG("imgs/fig1_red_completa.png", 22cm, 18cm), p1)
println("  -> imgs/fig1_red_completa.png")

# ============================================================
# FIGURA 2 — BFS didáctico (grafo 9 nodos)
# ============================================================

println("Figura 2: BFS didáctico...")

gbfs = SimpleGraph(9)
for (u, v) in [(1,2),(1,3),(2,4),(2,5),(3,6),(3,7),(4,8),(5,8),(6,9)]
    add_edge!(gbfs, u, v)
end

nivel = fill(-1, 9)
nivel[1] = 0
cola_bfs = [1]
while !isempty(cola_bfs)
    n = popfirst!(cola_bfs)
    for v in neighbors(gbfs, n)
        nivel[v] == -1 && (nivel[v] = nivel[n]+1; push!(cola_bfs, v))
    end
end

paleta_bfs = [
    colorant"lightyellow",
    colorant"deepskyblue",
    colorant"dodgerblue",
    colorant"royalblue"
]
bfs_fill  = [paleta_bfs[nivel[i]+1] for i in 1:9]
bfs_names = ["ORIGEN", "Niv1-A", "Niv1-B", "Niv2-A", "Niv2-B",
             "Niv2-C", "Niv2-D", "Niv3-A", "Niv3-B"]

p2 = gplot(gbfs;
    nodefillc     = bfs_fill,
    nodesize      = fill(3.0, 9),
    nodelabel     = bfs_names,
    nodelabelsize = 2.0,
    edgestrokec   = colorant"gray40",
    EDGELINEWIDTH = 1.0,
    layout        = spring_layout,
)
draw(PNG("imgs/fig2_bfs_didactico.png", 18cm, 15cm), p2)
println("  -> imgs/fig2_bfs_didactico.png")

# ============================================================
# FIGURA 3 — BFS ruta real resaltada
# ============================================================

println("Figura 3: BFS ruta real...")

sensor_ej = 4
_, camino_bfs = bfs_camino(g, sensor_ej, gateways)
en_ruta = Set(camino_bfs)

nfill_bfs = [
    i == sensor_ej          ? color_origen :
    i in en_ruta            ? (tipo_nodo(i)==:gateway ? color_gw : color_camino) :
    node_fill[i]
    for i in 1:N_TOTAL
]
nsize_bfs = [i in en_ruta || i == sensor_ej ? node_size_base[i]*1.6 : node_size_base[i]
             for i in 1:N_TOTAL]

aristas_ruta = Set{Tuple{Int,Int}}()
for i in 1:length(camino_bfs)-1
    push!(aristas_ruta, (min(camino_bfs[i],camino_bfs[i+1]),
                          max(camino_bfs[i],camino_bfs[i+1])))
end

efill = [
    (min(src(e),dst(e)), max(src(e),dst(e))) in aristas_ruta ?
        colorant"crimson" : colorant"lightgray"
    for e in edges(g)
]

p3 = gplot(g;
    nodefillc     = nfill_bfs,
    nodesize      = nsize_bfs,
    nodelabel     = [nombre_nodo(i) for i in 1:N_TOTAL],
    nodelabelsize = 1.5,
    edgestrokec   = efill,
    EDGELINEWIDTH = 0.5,
    layout        = spring_layout,
)
draw(PNG("imgs/fig3_bfs_ruta_real.png", 22cm, 18cm), p3)
println("  -> imgs/fig3_bfs_ruta_real.png")

# ============================================================
# FIGURA 4 — DFS didáctico (grafo 9 nodos)
# ============================================================

println("Figura 4: DFS didáctico...")

gdfs = SimpleGraph(9)
for (u, v) in [(1,2),(1,3),(2,4),(2,5),(3,6),(3,7),(4,8),(5,8),(6,9)]
    add_edge!(gdfs, u, v)
end

orden_dfs = Int[]
vis = falses(9)
function dfs_orden!(n)
    vis[n] = true
    push!(orden_dfs, n)
    for v in neighbors(gdfs, n)
        !vis[v] && dfs_orden!(v)
    end
end
dfs_orden!(1)

dfs_shades = [
    colorant"lightyellow",   colorant"lightskyblue",
    colorant"skyblue",       colorant"cornflowerblue",
    colorant"steelblue",     colorant"royalblue",
    colorant"blue",          colorant"mediumblue",
    colorant"darkblue"
]
dfs_fill  = [dfs_shades[findfirst(==(i), orden_dfs)] for i in 1:9]
dfs_names = [i==1 ? "ORIGEN(v=1)" : "N$i(v=$(findfirst(==(i),orden_dfs)))" for i in 1:9]

p4 = gplot(gdfs;
    nodefillc     = dfs_fill,
    nodesize      = fill(3.0, 9),
    nodelabel     = dfs_names,
    nodelabelsize = 1.8,
    edgestrokec   = colorant"gray40",
    EDGELINEWIDTH = 1.0,
    layout        = spring_layout,
)
draw(PNG("imgs/fig4_dfs_didactico.png", 18cm, 15cm), p4)
println("  -> imgs/fig4_dfs_didactico.png")

# ============================================================
# FIGURA 5 — Histograma costos DFS
# ============================================================

println("Figura 5: histograma costos DFS...")

sensor_dfs        = argmax([degree(g, s) for s in 1:N_SENSORES])
rutas             = dfs_todas_rutas(g, sensor_dfs, gateways)
costos            = [costo_ruta(r) for r in rutas]
n_saltos          = [length(r)-1 for r in rutas]
_, camino_bfs_ref = bfs_camino(g, sensor_dfs, gateways)
costo_bfs_ref     = costo_ruta(camino_bfs_ref)

histogram(costos;
    bins    = 20,
    color   = :steelblue,
    alpha   = 0.8,
    xlabel  = "Consumo total (mAh)",
    ylabel  = "Numero de rutas",
    title   = "DFS — Distribucion de Consumo: $(length(rutas)) rutas desde $(nombre_nodo(sensor_dfs))",
    label   = "Rutas DFS",
    legend  = :topright,
)
vline!([costo_bfs_ref];
    color=:red, linewidth=2.5, linestyle=:dash,
    label="BFS ($(round(costo_bfs_ref,digits=1)) mAh)")
vline!([minimum(costos)];
    color=:green, linewidth=2, linestyle=:dot,
    label="Mejor DFS ($(round(minimum(costos),digits=1)) mAh)")
savefig("imgs/fig5_dfs_histograma.png")
println("  -> imgs/fig5_dfs_histograma.png")

# ============================================================
# FIGURA 6 — Scatter: saltos vs consumo (DFS)
# ============================================================

println("Figura 6: scatter saltos vs mAh...")

scatter(n_saltos, costos;
    xlabel     = "Numero de saltos",
    ylabel     = "Consumo (mAh)",
    title      = "DFS — Saltos vs Consumo (cada punto = una ruta posible)",
    label      = "Rutas DFS",
    color      = :steelblue,
    alpha      = 0.55,
    markersize = 5,
    legend     = :topleft,
)
scatter!([length(camino_bfs_ref)-1], [costo_bfs_ref];
    color=:red, markersize=12, markershape=:star5,
    label="Ruta BFS ($(round(costo_bfs_ref,digits=1)) mAh, $(length(camino_bfs_ref)-1) saltos)")
savefig("imgs/fig6_scatter_saltos_mah.png")
println("  -> imgs/fig6_scatter_saltos_mah.png")

# ============================================================
# FIGURA 7 — Barras estado de batería sensores
# ============================================================

println("Figura 7: barras bateria sensores...")

bats      = [bateria[s] for s in 1:N_SENSORES]
nombres_s = [nombre_nodo(s) for s in 1:N_SENSORES]
colors_bat = [b < 30 ? :crimson : b < 50 ? :darkorange : b < 70 ? :gold : :forestgreen
              for b in bats]

bar(nombres_s, bats;
    color     = colors_bat,
    xlabel    = "Sensor",
    ylabel    = "Bateria (%)",
    title     = "Estado de Bateria — 35 Sensores de Caudal (Rojo<30% | Naranja 30-50% | Verde>70%)",
    xrotation = 70,
    legend    = false,
    ylims     = (0, 115),
    fontsize  = 7,
    bar_width = 0.7,
)
hline!([30]; color=:crimson,    linestyle=:dash, linewidth=1.5)
hline!([50]; color=:darkorange, linestyle=:dash, linewidth=1.5)
savefig("imgs/fig7_bateria_sensores.png")
println("  -> imgs/fig7_bateria_sensores.png")

# ============================================================
# FIGURA 8 — Comparación BFS vs top-5 rutas DFS
# ============================================================

println("Figura 8: comparacion BFS vs DFS...")

rutas_ord   = sort([(costo_ruta(r), length(r)-1) for r in rutas], by=x->x[1])
top5_costos = [x[1] for x in rutas_ord[1:5]]
top5_saltos = [x[2] for x in rutas_ord[1:5]]

categorias = vcat(["BFS"], ["DFS-$i" for i in 1:5])
costos_bar = vcat([costo_bfs_ref], top5_costos)
saltos_bar = vcat([length(camino_bfs_ref)-1], top5_saltos)

p_c = bar(categorias, costos_bar;
    color=vcat([:crimson], fill(:steelblue, 5)),
    ylabel="Consumo (mAh)", title="Consumo de Bateria",
    legend=false, xrotation=25)

p_s = bar(categorias, saltos_bar;
    color=vcat([:crimson], fill(:darkorange, 5)),
    ylabel="Saltos", title="Numero de Saltos",
    legend=false, xrotation=25)

plot(p_c, p_s;
    layout=Plots.grid(1,2),
    plot_title="BFS vs Top-5 Rutas DFS desde $(nombre_nodo(sensor_dfs))  [Rojo=BFS]",
    size=(950, 460),
)
savefig("imgs/fig8_comparacion_bfs_dfs.png")
println("  -> imgs/fig8_comparacion_bfs_dfs.png")

println("\nTodas las figuras generadas en imgs/")
