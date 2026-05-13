# =============================================================================
# DETECCIÓN DE ANOMALÍAS EN REDES — PROYECTO UNIDAD 1
# Universidad de Cuenca | DEET | Maestría en Ciencias de la Ingeniería Eléctrica
# Autor: Jean Carlo Aucapina
# Fecha: Abril 2026
# =============================================================================
# PARTE 1: CONSTRUCCIÓN DEL GRAFO DE RED CORPORATIVA
# =============================================================================
#
# CÓMO EJECUTAR:
#   julia --project=. practica_redes_aucapina.jl
#
# ENTORNO VIRTUAL:
#   Activar desde el REPL de Julia:
#     julia> ] activate .
#     julia> ] instantiate     (instala dependencias del Project.toml)
# =============================================================================

using Graphs
using SimpleWeightedGraphs
using Plots
using Printf
using Colors

const RESULTS_DIR = joinpath(@__DIR__, "results")
const FIGURES_DIR = joinpath(RESULTS_DIR, "figures")
mkpath(FIGURES_DIR)

figure_path(name::AbstractString) = joinpath(FIGURES_DIR, name)

# -----------------------------------------------------------------------------
# 1.1  DEFINICIÓN DE NODOS
#      Cada nodo = (tipo, nombre)
#      Tipos: "firewall", "router", "server", "host"
# -----------------------------------------------------------------------------

# Diccionario: id (1-indexado) => (tipo, nombre)
# Nota: Julia usa índices base-1; el spec usa base-0.
# Mantenemos id == spec_id + 1 para consistencia interna.
nodos = Dict(
    1  => ("firewall", "FW-Perimetral"),
    2  => ("router",   "Router-Core"),
    3  => ("router",   "Router-DMZ"),
    4  => ("server",   "Web-Server"),
    5  => ("server",   "DB-Server"),
    6  => ("server",   "Mail-Server"),
    7  => ("router",   "Router-LAN-A"),
    8  => ("router",   "Router-LAN-B"),
    9  => ("host",     "PC-Admin"),
    10 => ("host",     "PC-User1"),
    11 => ("host",     "PC-User2"),
    12 => ("host",     "PC-User3"),
    13 => ("host",     "PC-User4"),
    14 => ("host",     "PC-User5"),
    15 => ("host",     "Impresora"),
    16 => ("host",     "IoT-Device1"),
    17 => ("host",     "IoT-Device2"),
    18 => ("server",   "SIEM-Server"),
    19 => ("host",     "PC-User6"),
    20 => ("host",     "PC-User7"),
)

N = length(nodos)  # 20 nodos

# -----------------------------------------------------------------------------
# 1.2  DEFINICIÓN DE ARISTAS
#      Formato: (origen, destino, peso_Mbps)
#      Nota: ids ajustados a base-1 (spec_id + 1)
# -----------------------------------------------------------------------------

aristas = [
    (1, 2, 1000),   # FW-Perimetral  <-> Router-Core
    (2, 3, 500),    # Router-Core    <-> Router-DMZ
    (2, 7, 500),    # Router-Core    <-> Router-LAN-A
    (2, 8, 500),    # Router-Core    <-> Router-LAN-B
    (2, 18, 1000),  # Router-Core    <-> SIEM-Server
    (3, 4, 100),    # Router-DMZ     <-> Web-Server
    (3, 6, 100),    # Router-DMZ     <-> Mail-Server
    (7, 5, 100),    # Router-LAN-A   <-> DB-Server
    (7, 9, 100),    # Router-LAN-A   <-> PC-Admin
    (7, 10, 100),   # Router-LAN-A   <-> PC-User1
    (7, 11, 100),   # Router-LAN-A   <-> PC-User2
    (7, 15, 10),    # Router-LAN-A   <-> Impresora
    (8, 12, 100),   # Router-LAN-B   <-> PC-User3
    (8, 13, 100),   # Router-LAN-B   <-> PC-User4
    (8, 14, 100),   # Router-LAN-B   <-> PC-User5
    (8, 16, 10),    # Router-LAN-B   <-> IoT-Device1
    (8, 17, 10),    # Router-LAN-B   <-> IoT-Device2
    (8, 19, 100),   # Router-LAN-B   <-> PC-User6
    (8, 20, 100),   # Router-LAN-B   <-> PC-User7
    (9, 5, 100),    # PC-Admin       <-> DB-Server
    (4, 6, 100),    # Web-Server     <-> Mail-Server
    (18, 4, 100),   # SIEM-Server    <-> Web-Server
    (18, 6, 100),   # SIEM-Server    <-> Mail-Server
]

# -----------------------------------------------------------------------------
# 1.3  CONSTRUCCIÓN DEL GRAFO CON PESOS
#      SimpleWeightedGraph: grafo no dirigido con pesos en aristas
# -----------------------------------------------------------------------------

G = SimpleWeightedGraph(N)

for (u, v, w) in aristas
    add_edge!(G, u, v, Float64(w))
end

# -----------------------------------------------------------------------------
# 1.4  ESTADÍSTICAS DEL GRAFO
# -----------------------------------------------------------------------------

n_nodos   = nv(G)
n_aristas = ne(G)
# Densidad = aristas / aristas_posibles = |E| / (|V|*(|V|-1)/2)
densidad  = 2 * n_aristas / (n_nodos * (n_nodos - 1))
conectado = is_connected(G)

println("=" ^ 55)
println("  PARTE 1: CONSTRUCCIÓN DEL GRAFO DE RED CORPORATIVA")
println("=" ^ 55)
@printf("Nodos:     %d\n", n_nodos)
@printf("Aristas:   %d\n", n_aristas)
@printf("Densidad:  %.4f\n", densidad)
@printf("Conectado: %s\n", conectado ? "true" : "false")
println()

# Tabla de nodos ordenada por ID
println("  NODOS DEL GRAFO")
println("-" ^ 45)
@printf("%-5s %-10s %-20s %-6s\n", "ID", "Tipo", "Nombre", "Grado")
println("-" ^ 45)
for id in sort(collect(keys(nodos)))
    tipo, nombre = nodos[id]
    grado = degree(G, id)
    @printf("%-5d %-10s %-20s %-6d\n", id, tipo, nombre, grado)
end
println()

# Tabla de aristas
println("  ARISTAS DEL GRAFO (peso en Mbps)")
println("-" ^ 55)
@printf("%-20s %-20s %-10s\n", "Origen", "Destino", "Peso(Mbps)")
println("-" ^ 55)
for (u, v, w) in aristas
    @printf("%-20s %-20s %-10.0f\n", nodos[u][2], nodos[v][2], w)
end
println()

# -----------------------------------------------------------------------------
# 1.5  VISUALIZACIÓN DEL GRAFO
#      Layout manual con posiciones fijas por zona de red:
#        Zona perimetral (FW, Core), DMZ, LAN-A, LAN-B, SIEM
#      Colores por tipo: rojo=FW, naranja=router, azul=server, verde=host
# -----------------------------------------------------------------------------

println("Generando visualización del grafo...")

# Posiciones (x, y) por nodo — layout por zonas de red
pos = Dict(
    1  => (0.50, 0.95),   # FW-Perimetral   (centro-top)
    2  => (0.50, 0.80),   # Router-Core
    3  => (0.20, 0.65),   # Router-DMZ
    7  => (0.40, 0.60),   # Router-LAN-A
    8  => (0.70, 0.60),   # Router-LAN-B
    18 => (0.85, 0.80),   # SIEM-Server
    4  => (0.10, 0.50),   # Web-Server
    6  => (0.28, 0.50),   # Mail-Server
    5  => (0.38, 0.42),   # DB-Server
    9  => (0.30, 0.40),   # PC-Admin
    10 => (0.42, 0.28),   # PC-User1
    11 => (0.50, 0.40),   # PC-User2
    15 => (0.22, 0.30),   # Impresora
    12 => (0.58, 0.42),   # PC-User3
    13 => (0.68, 0.42),   # PC-User4
    14 => (0.78, 0.42),   # PC-User5
    16 => (0.62, 0.28),   # IoT-Device1
    17 => (0.72, 0.28),   # IoT-Device2
    19 => (0.82, 0.42),   # PC-User6
    20 => (0.88, 0.30),   # PC-User7
)

color_map = Dict(
    "firewall" => :firebrick,
    "router"   => :darkorange,
    "server"   => :steelblue,
    "host"     => :forestgreen,
)

marker_map = Dict(
    "firewall" => :diamond,
    "router"   => :hexagon,
    "server"   => :rect,
    "host"     => :circle,
)

size_map = Dict(
    "firewall" => 14,
    "router"   => 12,
    "server"   => 10,
    "host"     => 8,
)

p = plot(
    size        = (960, 720),
    title       = "Grafo de Red Corporativa | 20 nodos · 23 aristas\n■ server  ● host  ⬡ router  ◆ FW",
    titlefont   = font(9),
    legend      = false,
    axis        = false,
    grid        = false,
    xlims       = (-0.05, 1.10),
    ylims       = (0.18, 1.05),
    background_color = :white,
)

# Dibujar aristas
for (u, v, _) in aristas
    xu, yu = pos[u]
    xv, yv = pos[v]
    plot!(p, [xu, xv], [yu, yv]; color=:gray70, lw=1.2, alpha=0.7)
end

# Dibujar nodos
for id in 1:N
    tipo, nombre = nodos[id]
    x, y = pos[id]
    scatter!(p, [x], [y];
        markercolor  = color_map[tipo],
        markershape  = marker_map[tipo],
        markersize   = size_map[tipo],
        markerstrokewidth = 1,
        markerstrokecolor = :white,
    )
    # Etiqueta abreviada debajo del nodo
    label_short = length(nombre) > 12 ? nombre[1:12] * "…" : nombre
    annotate!(p, x, y - 0.030, text(label_short, 5, :center, :black))
    annotate!(p, x, y + 0.028, text(string(id), 5, :center, :gray40))
end

savefig(p, figure_path("grafo_red.png"))
println("Figura guardada: grafo_red.png")
println()
println("=" ^ 55)
println("  PARTE 1 COMPLETADA")
println("=" ^ 55)

# =============================================================================
# PARTE 2: MÉTRICAS DE CENTRALIDAD
# =============================================================================
# Métricas calculadas:
#   - Degree Centrality (DC)    : grado normalizado por (N-1)
#   - Betweenness Centrality (BC): fracción de caminos más cortos que pasan por v
#   - Closeness Centrality (CC) : inverso de distancia media al resto de nodos
#   - PageRank (PR)             : importancia relativa por autoridad de vecinos
# =============================================================================

println()
println("=" ^ 65)
println("  PARTE 2: MÉTRICAS DE CENTRALIDAD")
println("=" ^ 65)

# --- 2.1 Grafo simple (sin pesos) requerido por betweenness/closeness/pagerank ---
# Graphs.jl trabaja con SimpleGraph internamente; extraemos la estructura.
G_simple = SimpleGraph(N)
for (u, v, _) in aristas
    add_edge!(G_simple, u, v)
end

# --- 2.2 Calcular métricas ---

# Degree Centrality: DC(v) = deg(v) / (N-1)
dc = [degree(G_simple, v) / (N - 1) for v in 1:N]

# Betweenness Centrality (normalizada): usa Graphs.jl
bc_raw = betweenness_centrality(G_simple)   # normalizado por defecto

# Closeness Centrality: CC(v) = (N-1) / sum_u d(v,u)
cc_raw = closeness_centrality(G_simple)

# PageRank: α=0.85 (damping factor estándar)
pr_raw = pagerank(G_simple, 0.85)

# --- 2.3 Tabla completa de métricas ---
println()
println("  TABLA DE CENTRALIDAD (todos los nodos)")
println("-" ^ 75)
@printf("%-5s %-20s %8s %8s %8s %8s\n", "ID", "Nombre", "DC", "BC", "CC", "PR")
println("-" ^ 75)
for id in 1:N
    _, nombre = nodos[id]
    @printf("%-5d %-20s %8.4f %8.4f %8.4f %8.4f\n",
        id, nombre, dc[id], bc_raw[id], cc_raw[id], pr_raw[id])
end
println()

# --- 2.4 Top-5 por Betweenness Centrality ---
orden_bc = sortperm(bc_raw, rev=true)
println("  TOP-5 NODOS POR BETWEENNESS CENTRALITY")
println("-" ^ 65)
@printf("%-5s %-20s %8s %8s %8s %8s\n", "Rank", "Nombre", "DC", "BC", "CC", "PR")
println("-" ^ 65)
for (rank, id) in enumerate(orden_bc[1:5])
    _, nombre = nodos[id]
    @printf("%-5d %-20s %8.4f %8.4f %8.4f %8.4f\n",
        rank, nombre, dc[id], bc_raw[id], cc_raw[id], pr_raw[id])
end
println()

# --- 2.5 Visualización: grafo con nodos coloreados por Betweenness Centrality ---
println("Generando visualización de centralidad (betweenness)...")

bc_max = maximum(bc_raw)
bc_min = minimum(bc_raw)

function bc_to_size(bc_val)
    normalized = (bc_val - bc_min) / max(bc_max - bc_min, 1e-9)
    return 6 + round(Int, normalized * 20)   # rango: 6..26
end

# Paleta: bajo=azul claro, alto=rojo oscuro
function bc_to_color(bc_val)
    t = (bc_val - bc_min) / max(bc_max - bc_min, 1e-9)
    r = round(Int, 50  + t * 200)
    g = round(Int, 100 - t * 90)
    b = round(Int, 200 - t * 180)
    return RGB(r/255, g/255, b/255)
end

p2 = plot(
    size        = (960, 720),
    title       = "Centralidad (Betweenness) — Rojo intenso = mayor centralidad\nTamaño del nodo proporcional a BC",
    titlefont   = font(8),
    legend      = false,
    axis        = false,
    grid        = false,
    xlims       = (-0.05, 1.10),
    ylims       = (0.18, 1.05),
    background_color = :white,
)

for (u, v, _) in aristas
    xu, yu = pos[u]
    xv, yv = pos[v]
    plot!(p2, [xu, xv], [yu, yv]; color=:gray75, lw=1.0, alpha=0.6)
end

for id in 1:N
    _, nombre = nodos[id]
    x, y = pos[id]
    color_bc = bc_to_color(bc_raw[id])
    sz      = bc_to_size(bc_raw[id])
    scatter!(p2, [x], [y];
        markercolor       = color_bc,
        markershape       = :circle,
        markersize        = sz,
        markerstrokewidth = 1,
        markerstrokecolor = :white,
    )
    label_short = length(nombre) > 12 ? nombre[1:12] * "…" : nombre
    annotate!(p2, x, y - 0.032, text(label_short, 5, :center, :black))
    annotate!(p2, x, y + 0.000, text(@sprintf("%.3f", bc_raw[id]), 4, :center, :white))
end

savefig(p2, figure_path("grafo_centralidad_bc.png"))
println("Figura guardada: grafo_centralidad_bc.png")

# --- 2.6 Gráfico de barras comparativo: DC vs BC vs CC vs PR ---
println("Generando gráfico de barras de centralidad...")
nombres_short = [length(nodos[id][2]) > 10 ? nodos[id][2][1:10] * "…" : nodos[id][2] for id in 1:N]
x_ticks = (1:N, nombres_short)

p_bar = plot(layout=(2,2), size=(1200, 800),
    plot_title="Métricas de Centralidad — Red Corporativa 20 nodos",
    plot_titlefont=font(9), margin=5Plots.mm)

bar!(p_bar[1], 1:N, dc; title="Degree Centrality (DC)", color=:steelblue,
    xticks=x_ticks, xrotation=45, legend=false, ylabel="DC", ylims=(0,0.5))
bar!(p_bar[2], 1:N, bc_raw; title="Betweenness Centrality (BC)", color=:firebrick,
    xticks=x_ticks, xrotation=45, legend=false, ylabel="BC", ylims=(0,0.8))
bar!(p_bar[3], 1:N, cc_raw; title="Closeness Centrality (CC)", color=:darkorange,
    xticks=x_ticks, xrotation=45, legend=false, ylabel="CC", ylims=(0,0.7))
bar!(p_bar[4], 1:N, pr_raw; title="PageRank (PR, α=0.85)", color=:forestgreen,
    xticks=x_ticks, xrotation=45, legend=false, ylabel="PR", ylims=(0,0.22))

savefig(p_bar, figure_path("centralidad_barras.png"))
println("Figura guardada: centralidad_barras.png")

# --- 2.7 Gráfico radar / heatmap de métricas (top-5 BC) ---
println("Generando heatmap top-5 por betweenness...")
top5_ids = orden_bc[1:5]
top5_nombres = [nodos[id][2] for id in top5_ids]
metricas_matrix = hcat(
    [dc[id]     for id in top5_ids],
    [bc_raw[id] for id in top5_ids],
    [cc_raw[id] for id in top5_ids],
    [pr_raw[id] for id in top5_ids],
)'

p_heat = heatmap(top5_nombres, ["DC","BC","CC","PR"], metricas_matrix;
    title="Heatmap Centralidad — Top-5 nodos por BC",
    titlefont=font(9), color=:RdYlGn, clims=(0,0.8),
    size=(700,300), xrotation=20, colorbar_title="Valor",
    annotations=[(j, i, text(@sprintf("%.3f", metricas_matrix[i,j]), 7, :center, :black))
        for i in 1:4, j in 1:5])

savefig(p_heat, figure_path("centralidad_heatmap.png"))
println("Figura guardada: centralidad_heatmap.png")

println()
println("=" ^ 65)
println("  PARTE 2 COMPLETADA")
println("=" ^ 65)

# =============================================================================
# PARTE 3: DETECCIÓN DE ANOMALÍAS ESTADÍSTICAS (Z-SCORE)
# =============================================================================
# Score compuesto: score(v) = 0.5·BC(v) + 0.3·DC(v) + 0.2·PR(v)
# Z-score:         z(v)     = (score(v) - μ) / σ
# Umbral:          z > 1.5  → nodo anómalo
# =============================================================================

println()
println("=" ^ 65)
println("  PARTE 3: DETECCIÓN DE ANOMALÍAS ESTADÍSTICAS")
println("=" ^ 65)

using Statistics

# --- 3.1 Score compuesto ponderado ---
scores = [0.5 * bc_raw[v] + 0.3 * dc[v] + 0.2 * pr_raw[v] for v in 1:N]

mu_score    = mean(scores)
sigma_score = std(scores, corrected=false)   # población completa
umbral_z    = 1.5
umbral_score = mu_score + umbral_z * sigma_score

@printf("\nScore compuesto: μ=%.4f  σ=%.4f\n", mu_score, sigma_score)
@printf("Umbral anomalía: z > %.1f → score > %.4f\n\n", umbral_z, umbral_score)

# --- 3.2 Z-scores y clasificación ---
z_scores = [(scores[v] - mu_score) / sigma_score for v in 1:N]

println("  TABLA DE Z-SCORES (todos los nodos)")
println("-" ^ 70)
@printf("%-5s %-20s %8s %8s %12s\n", "ID", "Nombre", "Score", "Z-score", "Estado")
println("-" ^ 70)
for id in 1:N
    _, nombre = nodos[id]
    estado = z_scores[id] > umbral_z ? "⚠ ANÓMALO" : "Normal"
    @printf("%-5d %-20s %8.4f %8.4f %12s\n", id, nombre, scores[id], z_scores[id], estado)
end
println()

anomalos = [(id, z_scores[id]) for id in 1:N if z_scores[id] > umbral_z]
sort!(anomalos, by=x->x[2], rev=true)
println("  NODOS ANÓMALOS DETECTADOS (z > $(umbral_z))")
println("-" ^ 65)
for (id, z) in anomalos
    _, nombre = nodos[id]
    tipo = nodos[id][1]
    @printf("[ANÓMALO] ID=%2d | %-20s | %-10s | z=%.4f | score=%.4f\n",
        id, nombre, tipo, z, scores[id])
end
println()

# --- 3.3 Visualización 1: grafo con anomalías resaltadas ---
println("Generando visualización de anomalías sobre el grafo...")

ids_anomalos = Set([id for (id, _) in anomalos])

p3 = plot(
    size        = (960, 720),
    title       = "Detección de Anomalías (z-score) — Rojo = Anómalo (z > 1.5)\nScore = 0.5·BC + 0.3·DC + 0.2·PR",
    titlefont   = font(8),
    legend      = false,
    axis        = false,
    grid        = false,
    xlims       = (-0.05, 1.10),
    ylims       = (0.18, 1.05),
    background_color = :white,
)

for (u, v, _) in aristas
    xu, yu = pos[u]
    xv, yv = pos[v]
    # arista roja si conecta dos anómalos, gris si no
    edge_color = (u in ids_anomalos && v in ids_anomalos) ? :firebrick : :gray75
    edge_lw    = (u in ids_anomalos && v in ids_anomalos) ? 2.0 : 0.9
    plot!(p3, [xu, xv], [yu, yv]; color=edge_color, lw=edge_lw, alpha=0.7)
end

for id in 1:N
    _, nombre = nodos[id]
    x, y = pos[id]
    es_anomalo = id in ids_anomalos
    z_val = z_scores[id]
    node_color = es_anomalo ? :firebrick : :steelblue
    node_size  = es_anomalo ? 16 : 8
    node_shape = es_anomalo ? :star5 : :circle
    scatter!(p3, [x], [y];
        markercolor       = node_color,
        markershape       = node_shape,
        markersize        = node_size,
        markerstrokewidth = es_anomalo ? 2 : 1,
        markerstrokecolor = es_anomalo ? :darkred : :white,
    )
    label_short = length(nombre) > 12 ? nombre[1:12] * "…" : nombre
    annotate!(p3, x, y - 0.033, text(label_short, 5, :center, :black))
    z_label = @sprintf("z=%.2f", z_val)
    annotate!(p3, x, y + 0.030, text(z_label, 4, :center, es_anomalo ? :firebrick : :gray50))
end

savefig(p3, figure_path("grafo_anomalias.png"))
println("Figura guardada: grafo_anomalias.png")

# --- 3.4 Visualización 2: scatter BC vs DC con anotación de z-score ---
println("Generando scatter BC vs DC con anomalías...")

p3b = scatter(
    dc, bc_raw;
    zcolor      = z_scores,
    color       = cgrad([:steelblue, :yellow, :firebrick]),
    clims       = (-1.0, 3.0),
    markersize  = 8,
    markerstrokewidth = 0.5,
    title       = "BC vs DC — color = z-score (rojo = anómalo)",
    titlefont   = font(9),
    xlabel      = "Degree Centrality (DC)",
    ylabel      = "Betweenness Centrality (BC)",
    colorbar_title = "z-score",
    size        = (700, 500),
    legend      = false,
)
hline!(p3b, [0.0]; color=:transparent)
# Línea de umbral horizontal referencial
vline!(p3b, [umbral_score]; color=:gray50, lw=1, ls=:dash)

for id in 1:N
    _, nombre = nodos[id]
    if z_scores[id] > 0.5
        annotate!(p3b, dc[id] + 0.003, bc_raw[id] + 0.01,
            text(nombre, 6, :left, z_scores[id] > umbral_z ? :firebrick : :gray40))
    end
end

savefig(p3b, figure_path("anomalias_scatter.png"))
println("Figura guardada: anomalias_scatter.png")

# --- 3.5 Visualización 3: barras de z-score por nodo ---
println("Generando gráfico de barras de z-scores...")

orden_z = sortperm(z_scores, rev=true)
nombres_z = [let n=nodos[id][2]; length(n)>10 ? n[1:10]*"…" : n end for id in orden_z]
valores_z = z_scores[orden_z]
colores_z = [v > umbral_z ? :firebrick : (v > 0 ? :steelblue : :gray70) for v in valores_z]

p3c = bar(nombres_z, valores_z;
    color    = colores_z,
    title    = "Z-Score por nodo (umbral z = 1.5)",
    titlefont = font(9),
    xlabel   = "Nodo",
    ylabel   = "Z-score",
    xrotation = 45,
    legend   = false,
    size     = (900, 400),
    ylims    = (minimum(valores_z) - 0.2, maximum(valores_z) + 0.3),
)
hline!(p3c, [umbral_z]; color=:firebrick, lw=2, ls=:dash, label="Umbral z=1.5")

savefig(p3c, figure_path("zscore_barras.png"))
println("Figura guardada: zscore_barras.png")

println()
println("=" ^ 65)
println("  PARTE 3 COMPLETADA")
println("=" ^ 65)

# =============================================================================
# PARTE 4: SIMULACIÓN DE PROPAGACIÓN DE MALWARE — MODELO SIR
# =============================================================================
# Parámetros:
#   Nodo inicial : IoT-Device1 (ID=16 en Julia, spec ID=15 base-0)
#   β = 0.3      : tasa de infección por contacto
#   γ = 0.1      : tasa de recuperación espontánea
#   Pasos = 20
#   R₀ = β/γ = 3 → condición de epidemia (R₀ > 1)
# =============================================================================

using Random
Random.seed!(42)

println()
println("=" ^ 65)
println("  PARTE 4: SIMULACIÓN SIR DE PROPAGACIÓN DE MALWARE")
println("=" ^ 65)

# --- 4.1 Función SIR discreta sobre grafo ---
function simular_sir(grafo, nodo_inicial; beta=0.3, gamma=0.1, pasos=20, cuarentena_paso=nothing, cuarentena_nodo=nothing)
    estado = fill('S', nv(grafo))
    estado[nodo_inicial] = 'I'
    hS, hI, hR = Int[], Int[], Int[]
    g_sim = copy(grafo)   # copia mutable para cuarentena

    for paso in 1:pasos
        # Cuarentena: eliminar aristas del nodo más infectado en paso dado
        if !isnothing(cuarentena_paso) && paso == cuarentena_paso && !isnothing(cuarentena_nodo)
            for vecino in collect(neighbors(g_sim, cuarentena_nodo))
                rem_edge!(g_sim, cuarentena_nodo, vecino)
            end
        end

        nuevo_estado = copy(estado)
        for nodo in 1:nv(g_sim)
            if estado[nodo] == 'I'
                for vecino in neighbors(g_sim, nodo)
                    if estado[vecino] == 'S' && rand() < beta
                        nuevo_estado[vecino] = 'I'
                    end
                end
                if rand() < gamma
                    nuevo_estado[nodo] = 'R'
                end
            end
        end
        estado = nuevo_estado
        push!(hS, count(==(('S')), estado))
        push!(hI, count(==(('I')), estado))
        push!(hR, count(==(('R')), estado))
    end
    return hS, hI, hR, estado
end

# --- 4.2 Simulación base: origen IoT-Device1 (ID=16) ---
Random.seed!(42)
hS_iot, hI_iot, hR_iot, estado_iot = simular_sir(G_simple, 16)

println("\nSimulación 1: origen IoT-Device1 (ID=16), β=0.3, γ=0.1")
println("-" ^ 55)
@printf("%-6s %8s %8s %8s\n", "Paso", "S", "I", "R")
println("-" ^ 55)
for t in 1:20
    @printf("%-6d %8d %8d %8d\n", t, hS_iot[t], hI_iot[t], hR_iot[t])
end
tasa_ataque_iot = hR_iot[end] / N
@printf("\nTasa de ataque final IoT: %.2f%% (%d/%d nodos)\n",
    tasa_ataque_iot*100, hR_iot[end], N)

# --- 4.3 P8: comparar desde Router-Core (ID=2) ---
Random.seed!(42)
hS_core, hI_core, hR_core, estado_core = simular_sir(G_simple, 2)

tasa_ataque_core = hR_core[end] / N
println("\nSimulación 2 (P8): origen Router-Core (ID=2), β=0.3, γ=0.1")
println("-" ^ 55)
@printf("%-6s %8s %8s %8s\n", "Paso", "S", "I", "R")
println("-" ^ 55)
for t in 1:20
    @printf("%-6d %8d %8d %8d\n", t, hS_core[t], hI_core[t], hR_core[t])
end
@printf("\nTasa de ataque final Core: %.2f%% (%d/%d nodos)\n",
    tasa_ataque_core*100, hR_core[end], N)
@printf("Diferencia tasa ataque: %.2f pp (Core vs IoT)\n",
    (tasa_ataque_core - tasa_ataque_iot)*100)

# --- 4.4 P9: barrer β ∈ {0.1, 0.2, 0.3, 0.5} con γ=0.1 ---
betas_test = [0.1, 0.2, 0.3, 0.5]
println("\nP9: Barrido de β (γ=0.1, origen=IoT-Device1)")
println("-" ^ 60)
@printf("%-8s %-6s %8s %8s %8s\n", "β", "R₀", "S_fin", "I_fin", "R_fin")
println("-" ^ 60)
resultados_beta = []
for b in betas_test
    Random.seed!(42)
    hS_b, hI_b, hR_b, _ = simular_sir(G_simple, 16; beta=b, gamma=0.1)
    R0 = b / 0.1
    push!(resultados_beta, (b, R0, hS_b, hI_b, hR_b))
    @printf("%-8.1f %-6.1f %8d %8d %8d\n", b, R0, hS_b[end], hI_b[end], hR_b[end])
end

# --- 4.5 P10: cuarentena en paso 5 del nodo más infectado ---
# Nodo más conectado (Router-LAN-B, ID=8) es el más probable de infectarse primero
Random.seed!(42)
hS_q, hI_q, hR_q, _ = simular_sir(G_simple, 16;
    cuarentena_paso=5, cuarentena_nodo=8)
println("\nP10: Cuarentena Router-LAN-B (ID=8) en paso 5")
println("-" ^ 55)
@printf("%-6s %8s %8s %8s\n", "Paso", "S", "I", "R")
println("-" ^ 55)
for t in 1:20
    marca = t == 5 ? " ← cuarentena" : ""
    @printf("%-6d %8d %8d %8d%s\n", t, hS_q[t], hI_q[t], hR_q[t], marca)
end
@printf("\nTasa ataque con cuarentena: %.2f%% (sin cuarentena: %.2f%%)\n",
    hR_q[end]/N*100, tasa_ataque_iot*100)

# --- 4.6 Visualizaciones ---
println("\nGenerando figuras SIR...")
pasos_t = 1:20

# Figura 1: curvas SIR base (IoT) vs Core
p4a = plot(size=(900, 450),
    title="Curvas SIR — Malware propagation (β=0.3, γ=0.1, R₀=3)",
    titlefont=font(9), xlabel="Paso de tiempo", ylabel="Nodos",
    legend=:right, grid=true, gridalpha=0.3)

plot!(p4a, pasos_t, hS_iot;  color=:steelblue,  lw=2.5, label="S – origen IoT-Device1")
plot!(p4a, pasos_t, hI_iot;  color=:firebrick,   lw=2.5, label="I – origen IoT-Device1")
plot!(p4a, pasos_t, hR_iot;  color=:forestgreen, lw=2.5, label="R – origen IoT-Device1")
plot!(p4a, pasos_t, hS_core; color=:steelblue,   lw=1.5, ls=:dash, label="S – origen Core")
plot!(p4a, pasos_t, hI_core; color=:firebrick,   lw=1.5, ls=:dash, label="I – origen Core")
plot!(p4a, pasos_t, hR_core; color=:forestgreen, lw=1.5, ls=:dash, label="R – origen Core")

savefig(p4a, figure_path("sir_comparacion.png"))
println("Figura guardada: sir_comparacion.png")

# Figura 2: barrido de beta
p4b = plot(size=(900, 450),
    title="Infectados I(t) para distintos β (γ=0.1, R₀=β/γ)",
    titlefont=font(9), xlabel="Paso de tiempo", ylabel="Infectados I",
    legend=:topright, grid=true, gridalpha=0.3)

colores_b = [:gray70, :steelblue, :darkorange, :firebrick]
for (i, (b, R0, _, hI_b, _)) in enumerate(resultados_beta)
    plot!(p4b, pasos_t, hI_b; color=colores_b[i], lw=2,
        label="β=$(b), R₀=$(R0)")
end

savefig(p4b, figure_path("sir_betas.png"))
println("Figura guardada: sir_betas.png")

# Figura 3: cuarentena vs sin cuarentena
p4c = plot(size=(900, 450),
    title="Efecto cuarentena Router-LAN-B en paso 5 (β=0.3, γ=0.1)",
    titlefont=font(9), xlabel="Paso de tiempo", ylabel="Nodos",
    legend=:right, grid=true, gridalpha=0.3)

plot!(p4c, pasos_t, hI_iot; color=:firebrick,   lw=2,   label="I sin cuarentena")
plot!(p4c, pasos_t, hR_iot; color=:forestgreen, lw=2,   label="R sin cuarentena")
plot!(p4c, pasos_t, hI_q;   color=:firebrick,   lw=2,   ls=:dash, label="I con cuarentena")
plot!(p4c, pasos_t, hR_q;   color=:forestgreen, lw=2,   ls=:dash, label="R con cuarentena")
vline!(p4c, [5]; color=:gray40, lw=1.5, ls=:dot, label="Paso cuarentena")

savefig(p4c, figure_path("sir_cuarentena.png"))
println("Figura guardada: sir_cuarentena.png")

# Figura 4: estado final sobre el grafo (IoT base)
println("Generando grafo de estado final SIR...")
color_sir = Dict('S'=>:steelblue, 'I'=>:firebrick, 'R'=>:forestgreen)
shape_sir  = Dict('S'=>:circle,   'I'=>:star5,     'R'=>:rect)

p4d = plot(size=(960,720),
    title="Estado final SIR (paso 20) — origen IoT-Device1\n● Susceptible  ★ Infectado  ■ Recuperado",
    titlefont=font(8), legend=false, axis=false, grid=false,
    xlims=(-0.05,1.10), ylims=(0.18,1.05), background_color=:white)

for (u, v, _) in aristas
    xu, yu = pos[u]; xv, yv = pos[v]
    plot!(p4d, [xu,xv], [yu,yv]; color=:gray75, lw=1.0, alpha=0.6)
end

for id in 1:N
    _, nombre = nodos[id]
    x, y = pos[id]
    st = estado_iot[id]
    scatter!(p4d, [x], [y];
        markercolor=color_sir[st], markershape=shape_sir[st],
        markersize=10, markerstrokewidth=1, markerstrokecolor=:white)
    label_short = length(nombre) > 12 ? nombre[1:12]*"…" : nombre
    annotate!(p4d, x, y-0.032, text(label_short, 5, :center, :black))
    annotate!(p4d, x, y+0.000, text(string(st), 5, :center, :white))
end

savefig(p4d, figure_path("sir_estado_final.png"))
println("Figura guardada: sir_estado_final.png")

println()
println("=" ^ 65)
println("  PARTE 4 COMPLETADA")
println("=" ^ 65)

# =============================================================================
# PARTE 5: RESILIENCIA — NODOS DE ARTICULACIÓN Y PUENTES
# =============================================================================

println()
println("=" ^ 65)
println("  PARTE 5: RESILIENCIA — NODOS DE ARTICULACIÓN Y PUENTES")
println("=" ^ 65)
println()

# -----------------------------------------------------------------------------
# 5.1  NODOS DE ARTICULACIÓN (CUT VERTICES)
#      Un nodo de articulación es aquel cuya eliminación aumenta el número
#      de componentes conexas del grafo.
# -----------------------------------------------------------------------------

puntos_articulacion = articulation(G_simple)
sort!(puntos_articulacion)

println("Nodos de articulación (cut vertices):")
if isempty(puntos_articulacion)
    println("  Ninguno — grafo 2-conexo")
else
    for id in puntos_articulacion
        tipo, nombre = nodos[id]
        println(@sprintf("  ID=%2d | %-20s | %s", id, nombre, tipo))
    end
end
println()

# -----------------------------------------------------------------------------
# 5.2  PUENTES (BRIDGES)
#      Una arista puente es aquella cuya eliminación desconecta el grafo.
# -----------------------------------------------------------------------------

puentes = bridges(G_simple)

println("Puentes (bridge edges):")
if isempty(puentes)
    println("  Ninguno")
else
    for e in puentes
        u, v = src(e), dst(e)
        _, nu = nodos[u]; _, nv_ = nodos[v]
        println(@sprintf("  (%2d)%s — (%2d)%s", u, nu, v, nv_))
    end
end
println()

# -----------------------------------------------------------------------------
# 5.3  ANÁLISIS DE IMPACTO: ELIMINACIÓN DE ROUTER-CORE (ID=2)
#      Pregunta P11: ¿Qué nodos quedan aislados si Router-Core falla?
# -----------------------------------------------------------------------------

println("Análisis de impacto — eliminación de Router-Core (ID=2):")
G_sin_core = copy(G_simple)
for vecino in collect(neighbors(G_sin_core, 2))
    rem_edge!(G_sin_core, 2, vecino)
end
# Eliminar también el nodo marcándolo aislado (sin aristas equivale a componente propia)
# Usamos connected_components para ver qué segmentos quedan
comps_sin_core = connected_components(G_sin_core)
sort!(comps_sin_core, by=length, rev=true)

println("  Componentes resultantes: $(length(comps_sin_core))")
for (i, comp) in enumerate(comps_sin_core)
    nombres = [nodos[id][2] for id in sort(comp)]
    println(@sprintf("  Componente %d (%d nodos): %s", i, length(comp), join(nombres, ", ")))
end
println()

# -----------------------------------------------------------------------------
# 5.4  ANÁLISIS DE IMPACTO: ELIMINACIÓN DE ROUTER-LAN-B (ID=8)
# -----------------------------------------------------------------------------

println("Análisis de impacto — eliminación de Router-LAN-B (ID=8):")
G_sin_lanb = copy(G_simple)
for vecino in collect(neighbors(G_sin_lanb, 8))
    rem_edge!(G_sin_lanb, 8, vecino)
end
comps_sin_lanb = connected_components(G_sin_lanb)
sort!(comps_sin_lanb, by=length, rev=true)

println("  Componentes resultantes: $(length(comps_sin_lanb))")
for (i, comp) in enumerate(comps_sin_lanb)
    nombres = [nodos[id][2] for id in sort(comp)]
    println(@sprintf("  Componente %d (%d nodos): %s", i, length(comp), join(nombres, ", ")))
end
println()

# -----------------------------------------------------------------------------
# 5.5  MÉTRICAS DE RESILIENCIA
# -----------------------------------------------------------------------------

# Número de vértices de corte
n_art = length(puntos_articulacion)
# Número de puentes
n_puentes = length(puentes)
# Conectividad de vértice (κ) — mínimo grado de los cut vertices, o 1 si existen
kappa = n_art > 0 ? 1 : 2

println("Métricas de resiliencia:")
println(@sprintf("  Nodos de articulación: %d", n_art))
println(@sprintf("  Puentes (SPF edges):   %d", n_puentes))
println(@sprintf("  Conectividad vértice κ: %d", kappa))
println(@sprintf("  Red 2-conexa: %s", kappa >= 2 ? "Sí" : "No — existe SPOF"))
println()

# =============================================================================
# 5.6  VISUALIZACIONES
# =============================================================================

# --- Figura 5a: Grafo con nodos de articulación y puentes resaltados ----------

println("Generando figura: resilencia_grafo.png")

art_set = Set(puntos_articulacion)
puentes_set = Set([(min(src(e),dst(e)), max(src(e),dst(e))) for e in puentes])

p5a = plot(; size=(900,700), title="Resiliencia: Nodos de Articulación y Puentes",
           background_color=:white, legend=:topright)

# Aristas: puentes en rojo grueso, normales en gris
for (u, v, _) in aristas
    xu, yu = pos[u]; xv, yv = pos[v]
    key = (min(u,v), max(u,v))
    if key in puentes_set
        plot!(p5a, [xu,xv],[yu,yv]; color=:red, lw=3.5, alpha=0.9, label=(u==1 ? "Puente" : ""))
    else
        plot!(p5a, [xu,xv],[yu,yv]; color=:gray70, lw=1.2, alpha=0.5, label="")
    end
end

# Nodos: articulación = estrella naranja, normal = círculo azul
for id in 1:N
    _, nombre = nodos[id]
    x, y = pos[id]
    if id in art_set
        scatter!(p5a, [x],[y]; markercolor=:orangered, markershape=:star5,
                 markersize=16, markerstrokewidth=1.5, markerstrokecolor=:darkred,
                 label=(id==puntos_articulacion[1] ? "Articulación" : ""))
        annotate!(p5a, x, y+0.040, text("z=$(round(z_scores[id],digits=2))", 5, :center, :darkred))
    else
        scatter!(p5a, [x],[y]; markercolor=:steelblue, markershape=:circle,
                 markersize=10, markerstrokewidth=1, markerstrokecolor=:white, label="")
    end
    label_short = length(nombre) > 12 ? nombre[1:12]*"…" : nombre
    annotate!(p5a, x, y-0.032, text(label_short, 5, :center, :black))
end

savefig(p5a, figure_path("resiliencia_grafo.png"))
println("Figura guardada: resiliencia_grafo.png")

# --- Figura 5b: Impacto por eliminación (barras de nodos aislados) -----------

println("Generando figura: resiliencia_impacto.png")

# Para cada nodo de articulación, contar cuántos nodos quedarían aislados del componente mayor
function nodos_aislados_al_eliminar(g, id_eliminar)
    g_tmp = copy(g)
    for vecino in collect(neighbors(g_tmp, id_eliminar))
        rem_edge!(g_tmp, id_eliminar, vecino)
    end
    comps = connected_components(g_tmp)
    sort!(comps, by=length, rev=true)
    # Nodos que NO están en el componente mayor (excluir el nodo eliminado)
    mayor = comps[1]
    return N - length(mayor) - 1  # todos menos componente mayor menos el nodo eliminado
end

impacto_ids   = Int[]
impacto_vals  = Int[]
impacto_names = String[]

for id in sort(puntos_articulacion)
    aislados = nodos_aislados_al_eliminar(G_simple, id)
    push!(impacto_ids, id)
    push!(impacto_vals, aislados)
    _, nombre = nodos[id]
    push!(impacto_names, nombre)
end

p5b = bar(impacto_names, impacto_vals;
          title="Impacto por Eliminación de Nodos de Articulación\n(nodos que pierden conectividad con la red principal)",
          ylabel="Nodos aislados", xlabel="Nodo de articulación",
          color=:orangered, legend=false, size=(800,500),
          background_color=:white, ylims=(0, N))

for (i, v) in enumerate(impacto_vals)
    annotate!(p5b, i, v+0.3, text(string(v), 9, :center, :darkred))
end

savefig(p5b, figure_path("resiliencia_impacto.png"))
println("Figura guardada: resiliencia_impacto.png")

# --- Figura 5c: Comparación de componentes antes/después eliminación Core ----

println("Generando figura: resiliencia_componentes.png")

# Colores de componente para grafo sin Core
n_comps = length(comps_sin_core)
comp_colors_palette = [:steelblue, :darkorange, :green3, :purple, :crimson, :teal, :gold]
comp_color_map = Dict{Int,Symbol}()
for (ci, comp) in enumerate(comps_sin_core)
    col = comp_colors_palette[mod1(ci, length(comp_colors_palette))]
    for id in comp
        comp_color_map[id] = col
    end
end

p5c = plot(; size=(900,700),
           title="Red tras eliminar Router-Core (ID=2)\nComponentes desconectados",
           background_color=:white, legend=false)

# Aristas restantes (sin las que tocan a nodo 2)
for (u, v, _) in aristas
    if u == 2 || v == 2; continue; end
    xu, yu = pos[u]; xv, yv = pos[v]
    plot!(p5c, [xu,xv],[yu,yv]; color=:gray70, lw=1.2, alpha=0.5)
end

# Router-Core: X roja
xu2, yu2 = pos[2]
scatter!(p5c, [xu2],[yu2]; markercolor=:red, markershape=:xcross,
         markersize=18, markerstrokewidth=3, markerstrokecolor=:darkred)
annotate!(p5c, xu2, yu2-0.04, text("ELIMINADO", 7, :center, :red))

# Resto de nodos coloreados por componente
for id in 1:N
    if id == 2; continue; end
    _, nombre = nodos[id]
    x, y = pos[id]
    col = get(comp_color_map, id, :gray)
    scatter!(p5c, [x],[y]; markercolor=col, markershape=:circle,
             markersize=11, markerstrokewidth=1, markerstrokecolor=:white)
    label_short = length(nombre) > 12 ? nombre[1:12]*"…" : nombre
    annotate!(p5c, x, y-0.032, text(label_short, 5, :center, :black))
end

savefig(p5c, figure_path("resiliencia_componentes.png"))
println("Figura guardada: resiliencia_componentes.png")

println()
println("=" ^ 65)
println("  PARTE 5 COMPLETADA")
println("=" ^ 65)

# =============================================================================
# DESAFÍO EXTRA: DETECCIÓN DE BOTNET CON DATASET IoT-23 (MULTI-CAPTURE)
# =============================================================================
# Analiza tres capturas del dataset IoT-23:
#   Capture-1-1: Mirai (HorizontalPortScan)  ~150k líneas
#   Capture-3-1: Mirai variante              ~156k líneas
#   Capture-42-1: C&C FileDownload botnet    ~4k   líneas
# Construye grafo IP→IP por captura, calcula métricas, detecta botnet por
# score compuesto z-score y compara con ground truth del dataset.
# =============================================================================

println()
println("=" ^ 65)
println("  DESAFÍO EXTRA: DETECCIÓN DE BOTNET — IoT-23 MULTI-CAPTURE")
println("=" ^ 65)
println()

using Statistics
using Random
Random.seed!(42)

# -----------------------------------------------------------------------------
# BONUS.1  FUNCIÓN DE LECTURA DE UN CAPTURE
# -----------------------------------------------------------------------------

function leer_capture(path::String, max_lineas::Int)
    ip_out    = Dict{String,Int}()
    ip_in     = Dict{String,Int}()
    ip_mal    = Dict{String,Int}()
    ip_total  = Dict{String,Int}()
    ip_ports  = Dict{String,Set{Int}}()
    edge_freq = Dict{Tuple{String,String},Int}()
    ip_votes  = Dict{String,Dict{String,Int}}()

    leidas = Ref(0)
    open(path, "r") do fh
        for line in eachline(fh)
            startswith(line, '#') && continue
            leidas[] += 1
            leidas[] > max_lineas && break

            cols = split(line, '\t')
            length(cols) < 21 && continue

            src   = cols[3]
            dst   = cols[5]
            prt_s = cols[6]
            last_col = split(cols[21], r"\s{2,}")
            label = length(last_col) >= 2 ? strip(last_col[2]) : "-"

            prt = tryparse(Int, prt_s)

            ip_out[src]   = get(ip_out,   src, 0) + 1
            ip_total[src] = get(ip_total, src, 0) + 1
            ip_in[dst]    = get(ip_in,    dst, 0) + 1

            if !haskey(ip_ports, src); ip_ports[src] = Set{Int}(); end
            !isnothing(prt) && push!(ip_ports[src], prt)

            if !haskey(ip_votes, src)
                ip_votes[src] = Dict("Malicious"=>0,"Benign"=>0,"Other"=>0)
            end
            lkey = (label == "Malicious") ? "Malicious" :
                   (label == "Benign")    ? "Benign"    : "Other"
            ip_votes[src][lkey] += 1
            label == "Malicious" && (ip_mal[src] = get(ip_mal, src, 0) + 1)

            ekey = (src, dst)
            edge_freq[ekey] = get(edge_freq, ekey, 0) + 1
        end
    end
    return (ip_out=ip_out, ip_in=ip_in, ip_mal=ip_mal, ip_total=ip_total,
            ip_ports=ip_ports, edge_freq=edge_freq, ip_votes=ip_votes,
            lineas=leidas[])
end

# -----------------------------------------------------------------------------
# BONUS.2  FUNCIÓN DE ANÁLISIS: GRAFO + MÉTRICAS + EVALUACIÓN
# -----------------------------------------------------------------------------

function ground_truth(votes_dict, ip)
    !haskey(votes_dict, ip) && return "Unknown"
    d = votes_dict[ip]
    d["Malicious"] > d["Benign"] && return "Malicious"
    d["Benign"] > d["Malicious"] && return "Benign"
    return "Mixed"
end

function analizar_capture(data, nombre; umbral_z=1.5, min_conex=2)
    ip_out    = data.ip_out
    ip_total  = data.ip_total
    ip_mal    = data.ip_mal
    ip_ports  = data.ip_ports
    edge_freq = data.edge_freq
    ip_votes  = data.ip_votes

    # IPs activas
    ips = sort([ip for ip in keys(ip_out) if ip_total[ip] >= min_conex])
    n   = length(ips)

    println(@sprintf("  [%s] líneas=%d  IPs_origen=%d  IPs_activas=%d  aristas=%d",
        nombre, data.lineas, length(ip_out), n, length(edge_freq)))

    n == 0 && return nothing

    ip_map = Dict(ip => i for (i,ip) in enumerate(ips))

    # Grafo dirigido y no dirigido
    Gd = SimpleDiGraph(n)
    Gu = SimpleGraph(n)
    for ((s,d),_) in edge_freq
        if haskey(ip_map,s) && haskey(ip_map,d) && s != d
            add_edge!(Gd, ip_map[s], ip_map[d])
            add_edge!(Gu, ip_map[s], ip_map[d])
        end
    end

    # Métricas
    dc  = [outdegree(Gd, ip_map[ip]) / max(n-1,1) for ip in ips]
    bc_raw = n <= 500 ? betweenness_centrality(Gu) :
                        [outdegree(Gd, ip_map[ip]) / max(n-1,1) for ip in ips]
    bcmax  = maximum(bc_raw)
    bc     = bcmax > 0 ? bc_raw ./ bcmax : bc_raw

    pct_mal = [ip_total[ip] > 0 ? get(ip_mal,ip,0)/ip_total[ip] : 0.0 for ip in ips]
    n_ports = Float64[haskey(ip_ports,ip) ? length(ip_ports[ip]) : 0 for ip in ips]
    pmx     = maximum(n_ports)
    ports_n = pmx > 0 ? n_ports ./ pmx : n_ports

    # Score compuesto
    score = [0.35*pct_mal[i] + 0.25*dc[i] + 0.20*bc[i] + 0.20*ports_n[i] for i in 1:n]
    mu_s  = mean(score); sig_s = std(score, corrected=false)
    z     = sig_s > 0 ? (score .- mu_s) ./ sig_s : zeros(n)

    pred = [zi > umbral_z ? "Malicious" : "Benign" for zi in z]
    gt   = [ground_truth(ip_votes, ip) for ip in ips]

    # Confusión
    conf = [0,0,0,0]
    for i in 1:n
        if     gt[i]=="Malicious" && pred[i]=="Malicious"; conf[1]+=1
        elseif gt[i]=="Benign"    && pred[i]=="Malicious"; conf[2]+=1
        elseif gt[i]=="Benign"    && pred[i]=="Benign";    conf[3]+=1
        elseif gt[i]=="Malicious" && pred[i]=="Benign";    conf[4]+=1
        end
    end
    ctp,cfp,ctn,cfn = conf
    nev  = ctp+cfp+ctn+cfn
    acc  = nev>0 ? (ctp+ctn)/nev : 0.0
    prec = (ctp+cfp)>0 ? ctp/(ctp+cfp) : 0.0
    rec  = (ctp+cfn)>0 ? ctp/(ctp+cfn) : 0.0
    f1v  = (prec+rec)>0 ? 2*prec*rec/(prec+rec) : 0.0

    println(@sprintf("    TP=%d FP=%d TN=%d FN=%d  Acc=%.1f%%  Prec=%.1f%%  Rec=%.1f%%  F1=%.3f",
        ctp,cfp,ctn,cfn, 100*acc, 100*prec, 100*rec, f1v))

    # Label Propagation
    comm_raw  = let
        lbs = collect(1:n)
        for _ in 1:30
            changed = false
            for v in shuffle(1:n)
                nbrs = neighbors(Gu, v)
                isempty(nbrs) && continue
                freq = Dict{Int,Int}()
                for u in nbrs; freq[lbs[u]] = get(freq,lbs[u],0)+1; end
                bl = argmax(freq)
                if bl != lbs[v]; lbs[v]=bl; changed=true; end
            end
            !changed && break
        end
        lbs
    end
    ucomms = unique(comm_raw)
    csizes = Dict(c=>count(==(c),comm_raw) for c in ucomms)
    crank  = sort(ucomms, by=c->csizes[c], rev=true)
    cremap = Dict(c=>i for (i,c) in enumerate(crank))
    comm_f = [cremap[c] for c in comm_raw]
    n_comm = length(ucomms)

    println(@sprintf("    Comunidades (LabelProp): %d", n_comm))
    for ci in 1:min(n_comm,6)
        mbs  = ips[findall(==(ci), comm_f)]
        nm   = length(mbs)
        nmal = count(ip->ground_truth(ip_votes,ip)=="Malicious", mbs)
        println(@sprintf("      C%d: %d nodos | %.0f%% Malicious", ci, nm, nm>0 ? 100*nmal/nm : 0.0))
    end

    return (ips=ips, n=n, dc=dc, bc=bc, pct_mal=pct_mal, n_ports=n_ports,
            score=score, z=z, pred=pred, gt=gt,
            tp=ctp,fp=cfp,tn=ctn,fn=cfn,
            acc=acc,prec=prec,rec=rec,f1=f1v,
            comm=comm_f, n_comm=n_comm,
            Gd=Gd, Gu=Gu, umbral_z=umbral_z)
end

# -----------------------------------------------------------------------------
# BONUS.3  LEER Y ANALIZAR TRES CAPTURAS
# -----------------------------------------------------------------------------

base_iot = joinpath(@__DIR__, "iot_23_datasets_small",
    "opt","Malware-Project","BigDataset","IoTScenarios")

capturas = [
    ("CTU-IoT-Malware-Capture-1-1",  "Capture-1-1 (Mirai-scan)",    150_000),
    ("CTU-IoT-Malware-Capture-3-1",  "Capture-3-1 (Mirai-variant)", 150_000),
    ("CTU-IoT-Malware-Capture-42-1", "Capture-42-1 (C&C-Download)",   4_000),
]

resultados = Dict{String,Any}()

println("Procesando capturas IoT-23:")
println()
for (cap_dir, cap_nombre, max_lin) in capturas
    cap_path = joinpath(base_iot, cap_dir, "bro", "conn.log.labeled")
    if !isfile(cap_path)
        println("  [SKIP] No encontrado: $cap_path")
        continue
    end
    data = leer_capture(cap_path, max_lin)
    res  = analizar_capture(data, cap_nombre)
    if !isnothing(res)
        resultados[cap_nombre] = res
    end
    println()
end

# -----------------------------------------------------------------------------
# BONUS.4  VISUALIZACIONES POR CAPTURA
# -----------------------------------------------------------------------------

cap_keys = collect(keys(resultados))

# -----------------------------------------------------------------------------
# BONUS.4a  GRAFO DE RED BOTNET POR CAPTURA
# Muestra top-50 nodos por z-score + todos los Malicious.
# Rojo★ = Malicious | Azul● = Benign | Naranja◆ = Mixed/Unknown
# Tamaño nodo proporcional a z-score compuesto.
# -----------------------------------------------------------------------------

for cap_nombre in cap_keys
    r = resultados[cap_nombre]
    tag = replace(replace(cap_nombre, r"\s"=>"_"), r"[()/-]"=>"")

    # Seleccionar subconjunto representativo para visualizar
    mal_idx  = findall(g->g=="Malicious", r.gt)
    top_z    = sortperm(r.z, rev=true)[1:min(50, r.n)]
    vis_idx  = sort(unique(vcat(mal_idx, top_z)))
    n_vis    = length(vis_idx)
    old2new  = Dict(old=>new for (new,old) in enumerate(vis_idx))

    # Subgrafo inducido
    Gsub = SimpleGraph(n_vis)
    for e in edges(r.Gu)
        s, d = src(e), dst(e)
        if haskey(old2new,s) && haskey(old2new,d)
            add_edge!(Gsub, old2new[s], old2new[d])
        end
    end

    # Atributos visuales
    node_cols   = [r.gt[i]=="Malicious" ? :crimson :
                   r.gt[i]=="Benign"    ? :steelblue : :darkorange
                   for i in vis_idx]
    node_shapes = [r.gt[i]=="Malicious" ? :star5 :
                   r.gt[i]=="Benign"    ? :circle : :diamond
                   for i in vis_idx]
    z_vis  = r.z[vis_idx]
    zmin   = minimum(z_vis); zmax = maximum(z_vis)
    zrange = zmax - zmin > 0 ? zmax - zmin : 1.0
    node_sz = [6 + 18*(r.z[i]-zmin)/zrange for i in vis_idx]

    # Etiquetas solo para nodos Malicious (últimos 15 chars de IP)
    node_labels = [r.gt[i]=="Malicious" ?
                   (length(r.ips[i])>12 ? r.ips[i][end-11:end] : r.ips[i]) : ""
                   for i in vis_idx]

    println("Generando figura: botnet_$(tag)_red.png")
    pg = graphplot(Gsub;
        nodeshape    = node_shapes,
        nodecolor    = node_cols,
        nodesize     = node_sz ./ 35,
        nodestrokewidth = 0.5,
        names        = node_labels,
        fontsize     = 6,
        edgewidth    = 0.6,
        edgecolor    = :gray70,
        edgealpha    = 0.5,
        arrow         = false,
        layout        = :spring,
        title         = "$(cap_nombre)\nRed Botnet — Top-$(n_vis) nodos por z-score\n★rojo=Malicious  ●azul=Benign  ◆naranja=Mixed",
        size          = (900, 700),
        background_color = :white)
    savefig(pg, figure_path("botnet_$(tag)_red.png"))
    println("Figura guardada: botnet_$(tag)_red.png")
end

for cap_nombre in cap_keys
    r = resultados[cap_nombre]
    tag = replace(replace(cap_nombre, r"\s"=>"_"), r"[()/-]"=>"")

    # --- Figura: Scatter puertos vs %Malicious ---
    println("Generando figura: botnet_$(tag)_scatter.png")
    cols_sc = [g=="Malicious" ? :crimson : g=="Benign" ? :steelblue : :gray60 for g in r.gt]
    shps_sc = [g=="Malicious" ? :star5   : g=="Benign" ? :circle    : :diamond for g in r.gt]
    idx_pl  = r.n > 300 ? sample(1:r.n, 300, replace=false) : collect(1:r.n)
    ps = scatter(r.n_ports[idx_pl], r.pct_mal[idx_pl];
        markershape=shps_sc[idx_pl], markercolor=cols_sc[idx_pl],
        markersize=5, markerstrokewidth=0.4, alpha=0.75,
        xlabel="Puertos únicos contactados", ylabel="% Conexiones Maliciosas",
        title="$(cap_nombre)\nPuertos vs %Malicious  (★rojo=Malicious ●azul=Benign)",
        legend=false, size=(800,500), background_color=:white)
    hline!(ps, [0.5]; color=:orange, lw=1.5, linestyle=:dash)
    savefig(ps, figure_path("botnet_$(tag)_scatter.png"))
    println("Figura guardada: botnet_$(tag)_scatter.png")

    # --- Figura: Z-score top 30 ---
    println("Generando figura: botnet_$(tag)_zscore.png")
    idx_s  = sortperm(r.z, rev=true)
    top_n  = min(30, r.n)
    tidx   = idx_s[1:top_n]
    tshort = [length(ip)>15 ? ip[end-14:end] : ip for ip in r.ips[tidx]]
    tcols  = [g=="Malicious" ? :crimson : g=="Benign" ? :steelblue : :gray60
              for g in r.gt[tidx]]
    pz = bar(tshort, r.z[tidx];
        color=tcols, xrotation=60, legend=false,
        xlabel="IP", ylabel="Z-score botnet",
        title="$(cap_nombre) — Top $(top_n) Z-score\n(rojo=GT Malicious  azul=GT Benign)",
        size=(1000,500), background_color=:white)
    hline!(pz, [r.umbral_z]; color=:orange, lw=2, linestyle=:dash)
    savefig(pz, figure_path("botnet_$(tag)_zscore.png"))
    println("Figura guardada: botnet_$(tag)_zscore.png")
end

# --- Figura comparativa: F1 / Accuracy entre capturas ---
println("Generando figura: botnet_comparacion.png")
cap_names_plot = collect(keys(resultados))
acc_vals = [resultados[k].acc*100 for k in cap_names_plot]
f1_vals  = [resultados[k].f1*100  for k in cap_names_plot]
short_names = [replace(k, r"Capture-"=>"Cap-") for k in cap_names_plot]

pc = bar(short_names, acc_vals;
    color=:steelblue, alpha=0.8, label="Accuracy %",
    ylabel="% / F1×100", xlabel="Captura",
    title="Comparación Capturas IoT-23\nAccuracy y F1-score por capture",
    size=(800,500), background_color=:white, ylims=(0,110))
bar!(pc, short_names, f1_vals; color=:crimson, alpha=0.7, label="F1 %")
for (i,k) in enumerate(cap_names_plot)
    annotate!(pc, i, acc_vals[i]+2, text(@sprintf("%.0f%%",acc_vals[i]), 8, :center, :navy))
    annotate!(pc, i, f1_vals[i]+2,  text(@sprintf("%.1f",f1_vals[i]/100), 8, :center, :darkred))
end
savefig(pc, figure_path("botnet_comparacion.png"))
println("Figura guardada: botnet_comparacion.png")

# --- Figura: Matriz de confusión combinada (grilla) ---
println("Generando figura: botnet_confusion_multi.png")
n_caps = length(cap_keys)
plts_conf = []
for k in cap_keys
    r = resultados[k]
    cd = [r.tp r.fp; r.fn r.tn]
    pc2 = heatmap(["Pred:Mal","Pred:Ben"],["GT:Mal","GT:Ben"], cd;
        color=:RdYlGn, clims=(0, max(r.tp,r.tn,1)),
        title=@sprintf("%s\nAcc=%.0f%% F1=%.3f", k, 100*r.acc, r.f1),
        size=(400,300), background_color=:white, colorbar=false)
    for ci in 1:2, ri in 1:2
        annotate!(pc2, ci, ri, text(string(cd[ri,ci]), 12, :center, :black))
    end
    push!(plts_conf, pc2)
end
pconf_grid = plot(plts_conf...; layout=(1,n_caps), size=(420*n_caps, 320))
savefig(pconf_grid, figure_path("botnet_confusion_multi.png"))
println("Figura guardada: botnet_confusion_multi.png")

# --- Figura: Comunidades por captura (barras % malicious) ---
println("Generando figura: botnet_comunidades_multi.png")
plts_comm = []
for k in cap_keys
    r = resultados[k]
    ip_votes_local = Dict{String,Dict{String,Int}}()
    # Reconstruir ip_votes desde gt y ips (aproximación para la figura)
    n_show = min(r.n_comm, 6)
    cmal = Float64[]
    clab = String[]
    for ci in 1:n_show
        mbs  = r.ips[findall(==(ci), r.comm)]
        nm   = length(mbs)
        nmal = count(ip->r.gt[findfirst(==(ip),r.ips)]=="Malicious", mbs)
        push!(cmal, nm>0 ? 100*nmal/nm : 0.0)
        push!(clab, "C$ci\n($(nm))")
    end
    pc3 = bar(clab, cmal; color=:crimson, legend=false,
        xlabel="Comunidad", ylabel="% Malicious",
        title="$(k)\nComunidades LabelProp",
        size=(400,350), background_color=:white, ylims=(0,110))
    push!(plts_comm, pc3)
end
pcomm_grid = plot(plts_comm...; layout=(1,n_caps), size=(440*n_caps, 370))
savefig(pcomm_grid, figure_path("botnet_comunidades_multi.png"))
println("Figura guardada: botnet_comunidades_multi.png")

# Resumen final
println()
println("=" ^ 65)
println("  RESUMEN DESAFÍO EXTRA — MULTI-CAPTURE")
println("=" ^ 65)
println(@sprintf("  %-35s  %6s  %6s  %6s  %5s", "Captura","Acc%","Prec%","Rec%","F1"))
println("  " * "-"^63)
for k in cap_keys
    r = resultados[k]
    println(@sprintf("  %-35s  %5.1f%%  %5.1f%%  %5.1f%%  %.3f",
        k, 100*r.acc, 100*r.prec, 100*r.rec, r.f1))
end
println()
println("=" ^ 65)
println("  DESAFÍO EXTRA COMPLETADO")
println("=" ^ 65)
