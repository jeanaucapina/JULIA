# ============================================================
# GIF Animado — Propagación de rutas sobre topología
# Muestra: saltos BFS/DFS frame a frame + estado de batería
# Cada GIF: 4 rondas clave (1, 20, 60, 100) × sensores activos
# Autor: Jean Carlo Aucapina
# Fecha: 2026-05-20
# ============================================================

using Graphs
using Plots
using Statistics
using StatsBase
using Random
using Printf
using Colors

gr(size=(1100, 600), dpi=130)
Random.seed!(42)

mkpath("imgs")

# ============================================================
# REPRODUCIR RED (misma seed que scripts anteriores)
# ============================================================

const N_SENSORES    = 35
const N_REPETIDORES = 12
const N_GATEWAY     = 3
const N_TOTAL       = N_SENSORES + N_REPETIDORES + N_GATEWAY

function tipo_nodo(id::Int)
    id <= N_SENSORES                          && return :sensor
    id <= N_SENSORES + N_REPETIDORES          && return :repetidor
    return :gateway
end

function nombre_nodo(id::Int)
    t = tipo_nodo(id)
    t == :sensor    && return "S$(lpad(id, 2, '0'))"
    t == :repetidor && return "R$(lpad(id - N_SENSORES, 2, '0'))"
    return "GW$(id - N_SENSORES - N_REPETIDORES)"
end

bateria_inicial = Dict{Int,Float64}()
for i in 1:N_TOTAL
    if tipo_nodo(i) == :gateway
        bateria_inicial[i] = 100.0
    elseif tipo_nodo(i) == :repetidor
        bateria_inicial[i] = rand(40.0:5.0:90.0)
    else
        bateria_inicial[i] = rand(20.0:5.0:85.0)
    end
end

g = SimpleGraph(N_TOTAL)
aristas_peso_base = Dict{Tuple{Int,Int}, Float64}()

function peso_arista_init(v::Int, bat::Dict)
    base = rand(0.5:0.1:3.0)
    penalizacion = 100.0 / bat[v]
    ruido = rand(0.9:0.05:1.1)
    return round(base * penalizacion * ruido, digits=3)
end

function add_arista!(g, u, v, pesos, bat)
    if !has_edge(g, u, v)
        add_edge!(g, u, v)
        w = peso_arista_init(v, bat)
        pesos[(min(u,v), max(u,v))] = w
    end
end

for s in 1:N_SENSORES
    reps = sample(N_SENSORES+1 : N_SENSORES+N_REPETIDORES, rand(1:2), replace=false)
    for r in reps; add_arista!(g, s, r, aristas_peso_base, bateria_inicial); end
end
for r in N_SENSORES+1 : N_SENSORES+N_REPETIDORES
    gws = sample(N_SENSORES+N_REPETIDORES+1 : N_TOTAL, rand(1:2), replace=false)
    for gw in gws; add_arista!(g, r, gw, aristas_peso_base, bateria_inicial); end
end
for _ in 1:15
    u = rand(1:N_SENSORES); v = rand(1:N_SENSORES)
    u != v && add_arista!(g, u, v, aristas_peso_base, bateria_inicial)
end
for _ in 1:8
    u = rand(N_SENSORES+1 : N_SENSORES+N_REPETIDORES)
    v = rand(N_SENSORES+1 : N_REPETIDORES+N_SENSORES)
    u != v && add_arista!(g, u, v, aristas_peso_base, bateria_inicial)
end

gateways = collect(N_SENSORES+N_REPETIDORES+1 : N_TOTAL)

# ============================================================
# LAYOUT FIJO — posiciones calculadas una vez con spring layout
# Usamos Fruchterman-Reingold via iteraciones manuales simples
# ============================================================

# Layout jerárquico por capa: sensores abajo, repetidores medio, gateways arriba
Random.seed!(99)  # seed diferente solo para posiciones

pos_x = zeros(N_TOTAL)
pos_y = zeros(N_TOTAL)

# Sensores: capa inferior, distribuidos en arco
for i in 1:N_SENSORES
    θ = (i - 1) / N_SENSORES * 2π
    pos_x[i] = 0.85 * cos(θ)
    pos_y[i] = 0.85 * sin(θ) - 0.15
end

# Repetidores: capa media, círculo interior
for i in 1:N_REPETIDORES
    idx = N_SENSORES + i
    θ = (i - 1) / N_REPETIDORES * 2π + π/N_REPETIDORES
    pos_x[idx] = 0.42 * cos(θ)
    pos_y[idx] = 0.42 * sin(θ)
end

# Gateways: centro/top
gw_positions = [(-0.15, 0.3), (0.0, 0.45), (0.15, 0.3)]
for i in 1:N_GATEWAY
    idx = N_SENSORES + N_REPETIDORES + i
    pos_x[idx] = gw_positions[i][1]
    pos_y[idx] = gw_positions[i][2]
end

# ============================================================
# ALGORITMOS DE ROUTING
# ============================================================

function bfs_camino(g, origen, destinos, bat_activa)
    visitado   = falses(nv(g))
    predecesor = zeros(Int, nv(g))
    cola = Int[]
    dist = fill(-1, nv(g))
    visitado[origen] = true
    push!(cola, origen)
    dist[origen] = 0
    while !isempty(cola)
        actual = popfirst!(cola)
        actual in destinos && begin
            camino = Int[]
            nodo = actual
            while nodo != 0
                pushfirst!(camino, nodo)
                nodo = predecesor[nodo]
            end
            return dist[actual], camino
        end
        for vecino in neighbors(g, actual)
            if !visitado[vecino] && bat_activa[vecino] > 0.0
                visitado[vecino] = true
                dist[vecino] = dist[actual] + 1
                predecesor[vecino] = actual
                push!(cola, vecino)
            end
        end
    end
    return -1, Int[]
end

function dfs_mejor_ruta(g, origen, destinos, pesos, bat_activa; max_rutas=50)
    rutas = Vector{Vector{Int}}()
    visitado = Set{Int}()
    function dfs!(actual, camino)
        length(rutas) >= max_rutas && return
        if actual in destinos
            push!(rutas, copy(camino))
            return
        end
        for vecino in neighbors(g, actual)
            if !(vecino in visitado) && bat_activa[vecino] > 0.0
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
    isempty(rutas) && return -1, Int[]
    mejor = argmin([sum(get(pesos, (min(r[i],r[i+1]), max(r[i],r[i+1])), 999.0)
                        for i in 1:length(r)-1) for r in rutas])
    ruta = rutas[mejor]
    costo = sum(get(pesos, (min(ruta[i],ruta[i+1]), max(ruta[i],ruta[i+1])), 999.0)
                for i in 1:length(ruta)-1)
    return costo, ruta
end

function costo_camino(camino, pesos)
    isempty(camino) || length(camino) == 1 && return 0.0
    sum(get(pesos, (min(camino[i], camino[i+1]), max(camino[i], camino[i+1])), 999.0)
        for i in 1:length(camino)-1)
end

# ============================================================
# SIMULACIÓN CON HISTORIAL COMPLETO
# Guarda: batería por ronda + rutas elegidas por cada sensor
# ============================================================

const N_RONDAS   = 120
const MAH_UMBRAL = 0.0

function simular_con_rutas(modo::Symbol; n_rondas=N_RONDAS)
    bat   = copy(bateria_inicial)
    pesos = copy(aristas_peso_base)

    # historial[r] = Dict(nodo => bat%)
    historial_bat = [copy(bat)]
    # rutas_por_ronda[r] = Vector de caminos (uno por sensor activo)
    rutas_por_ronda = Vector{Vector{Vector{Int}}}()

    for _ in 1:n_rondas
        rutas_ronda = Vector{Vector{Int}}()

        for s in 1:N_SENSORES
            bat[s] <= MAH_UMBRAL && continue
            if modo == :bfs
                _, camino = bfs_camino(g, s, gateways, bat)
            else
                _, camino = dfs_mejor_ruta(g, s, gateways, pesos, bat)
            end
            isempty(camino) && continue
            push!(rutas_ronda, camino)

            costo_arista_avg = costo_camino(camino, pesos) / max(length(camino)-1, 1)
            for nodo in camino
                tipo_nodo(nodo) == :gateway && continue
                bat[nodo] = max(0.0, bat[nodo] - costo_arista_avg * 0.8)
            end
        end

        for ((u,v), _) in pesos
            bat[v] <= 0.0 && continue
            base = rand(0.5:0.1:1.5)
            pesos[(u,v)] = round(base * (100.0 / bat[v]) * rand(0.95:0.01:1.05), digits=3)
        end

        push!(historial_bat, copy(bat))
        push!(rutas_por_ronda, rutas_ronda)
    end

    return historial_bat, rutas_por_ronda
end

println("Simulando BFS con historial de rutas...")
hist_bat_bfs, rutas_bfs = simular_con_rutas(:bfs)

println("Simulando DFS con historial de rutas...")
hist_bat_dfs, rutas_dfs = simular_con_rutas(:dfs)

# ============================================================
# HELPERS PARA DIBUJAR TOPOLOGÍA
# ============================================================

function color_bat(pct::Float64)
    pct <= 0.0  && return RGB(0.1, 0.1, 0.1)   # negro: muerto
    pct < 20.0  && return RGB(0.8, 0.0, 0.0)   # rojo oscuro
    pct < 30.0  && return RGB(1.0, 0.2, 0.2)   # rojo
    pct < 50.0  && return RGB(1.0, 0.55, 0.0)  # naranja
    pct < 70.0  && return RGB(0.9, 0.8, 0.1)   # amarillo
    return RGB(0.2, 0.75, 0.2)                 # verde
end

function tamaño_nodo(id::Int)
    tipo_nodo(id) == :gateway   && return 14
    tipo_nodo(id) == :repetidor && return 9
    return 6
end

function draw_topologia!(p, bat_dict, camino_activo, sensor_origen, titulo)
    # Aristas de fondo (gris)
    for e in edges(g)
        u, v = src(e), dst(e)
        plot!(p,
            [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
            color=:gray70, lw=0.5, alpha=0.4, label="")
    end

    # Aristas de la ruta activa (resaltadas)
    if length(camino_activo) >= 2
        for i in 1:length(camino_activo)-1
            u, v = camino_activo[i], camino_activo[i+1]
            plot!(p,
                [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
                color=:cyan, lw=3.0, alpha=0.9, label="")
        end
    end

    # Nodos
    for i in 1:N_TOTAL
        col = color_bat(bat_dict[i])
        sz  = tamaño_nodo(i)
        ms  = i == sensor_origen ? sz * 2.5 :
              i in camino_activo ? sz * 1.8 : sz

        scatter!(p, [pos_x[i]], [pos_y[i]],
            color=col,
            markerstrokewidth=(i in camino_activo || i == sensor_origen ? 1.5 : 0.3),
            markerstrokecolor=:white,
            markersize=ms,
            label="")
    end

    # Indicar la punta del avance del paquete (último nodo animado)
    if !isempty(camino_activo)
        tip = camino_activo[end]
        scatter!(p, [pos_x[tip]], [pos_y[tip]],
            color=:yellow, markersize=tamaño_nodo(tip)+4,
            markerstrokewidth=2, markerstrokecolor=:white,
            marker=:star5, label="")
    end

    plot!(p, title=titulo,
        xlim=(-1.1, 1.1), ylim=(-1.2, 0.65),
        xticks=false, yticks=false,
        framestyle=:none,
        background_color=RGB(0.07, 0.07, 0.12),
        titlefontsize=8, titlefontcolor=:white)
end

# ============================================================
# GIF 1: fig20_rutas_bfs_topologia.gif
# Anima: rondas clave × primeros 8 sensores activos
# Frame por frame = un salto adicional de la ruta
# ============================================================

println("Generando GIF BFS (topología con rutas)...")

# Todas las rondas, frame por frame
rondas_clave = collect(1:N_RONDAS)
# Para cada ronda, tomar los primeros N_RUTAS_MUESTRA sensores con ruta encontrada
N_RUTAS_MUESTRA = 6

anim_bfs = @animate for ronda in rondas_clave
    bat_actual = hist_bat_bfs[ronda + 1]  # ronda 0 = índice 1
    rutas_esta_ronda = rutas_bfs[ronda]

    # Sensores activos con ruta válida
    rutas_validas = filter(r -> length(r) >= 2, rutas_esta_ronda)
    n_activos = count(bat_actual[s] > 0 for s in 1:N_SENSORES)
    n_muertos = N_SENSORES - n_activos

    # Tomar muestra de rutas para mostrar simultáneamente
    rutas_muestra = rutas_validas[1:min(N_RUTAS_MUESTRA, length(rutas_validas))]

    # Sub-frames: animar hop a hop para cada ruta en la muestra
    # (aquí mostramos todas simultáneamente para el GIF entre rondas)
    plot_ronda = plot(
        background_color=RGB(0.07, 0.07, 0.12),
        foreground_color=:white,
        legend=false, framestyle=:none,
        xlim=(-1.1, 1.1), ylim=(-1.2, 0.65),
        title="BFS — Ronda $ronda/$N_RONDAS | Activos: $n_activos/$N_SENSORES | Muertos: $n_muertos",
        titlefontsize=9, titlefontcolor=:white,
        xticks=false, yticks=false,
    )

    # Aristas de fondo
    for e in edges(g)
        u, v = src(e), dst(e)
        plot!(plot_ronda,
            [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
            color=:gray50, lw=0.4, alpha=0.35, label="")
    end

    # Resaltar todas las rutas de muestra
    colores_ruta = [:cyan, :deepskyblue, :dodgerblue, :steelblue, :cornflowerblue, :royalblue]
    for (idx, ruta) in enumerate(rutas_muestra)
        col = colores_ruta[mod1(idx, length(colores_ruta))]
        for i in 1:length(ruta)-1
            u, v = ruta[i], ruta[i+1]
            plot!(plot_ronda,
                [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
                color=col, lw=2.5, alpha=0.85, label="")
        end
    end

    # Nodos
    for i in 1:N_TOTAL
        col = color_bat(bat_actual[i])
        sz  = tamaño_nodo(i)
        en_alguna_ruta = any(i in r for r in rutas_muestra)
        ms = en_alguna_ruta ? sz * 1.7 : sz
        scatter!(plot_ronda, [pos_x[i]], [pos_y[i]],
            color=col,
            markersize=ms,
            markerstrokewidth=(en_alguna_ruta ? 1.2 : 0.2),
            markerstrokecolor=:white,
            label="")
    end

    # Estrella en sensor origen de cada ruta
    for ruta in rutas_muestra
        s_orig = ruta[1]
        scatter!(plot_ronda, [pos_x[s_orig]], [pos_y[s_orig]],
            color=:yellow, markersize=tamaño_nodo(s_orig)+3,
            markerstrokewidth=1.5, markerstrokecolor=:white,
            marker=:star5, label="")
    end

    # Leyenda manual (texto)
    annotate!(plot_ronda, -1.0, 0.62, text("● Verde >70%  ● Amarillo 50-70%  ● Naranja 30-50%  ● Rojo <30%  ● Negro = Muerto  ★ Origen",
        :white, :left, 5))
    annotate!(plot_ronda, -1.0, 0.52, text("Mostrando $(length(rutas_muestra)) rutas BFS activas de $(length(rutas_validas)) totales en esta ronda",
        :gray80, :left, 5))

    plot_ronda
end

gif(anim_bfs, "imgs/fig20_rutas_bfs_topologia.gif", fps=8)
println("fig20_rutas_bfs_topologia.gif guardado")

# ============================================================
# GIF 2: fig21_rutas_dfs_topologia.gif
# Igual pero con DFS (rutas más largas, más sinuosas)
# ============================================================

println("Generando GIF DFS (topología con rutas)...")

anim_dfs = @animate for ronda in rondas_clave
    bat_actual = hist_bat_dfs[ronda + 1]
    rutas_esta_ronda = rutas_dfs[ronda]

    rutas_validas = filter(r -> length(r) >= 2, rutas_esta_ronda)
    n_activos = count(bat_actual[s] > 0 for s in 1:N_SENSORES)
    n_muertos = N_SENSORES - n_activos

    rutas_muestra = rutas_validas[1:min(N_RUTAS_MUESTRA, length(rutas_validas))]

    plot_ronda = plot(
        background_color=RGB(0.07, 0.07, 0.12),
        foreground_color=:white,
        legend=false, framestyle=:none,
        xlim=(-1.1, 1.1), ylim=(-1.2, 0.65),
        title="DFS — Ronda $ronda/$N_RONDAS | Activos: $n_activos/$N_SENSORES | Muertos: $n_muertos",
        titlefontsize=9, titlefontcolor=:white,
        xticks=false, yticks=false,
    )

    for e in edges(g)
        u, v = src(e), dst(e)
        plot!(plot_ronda,
            [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
            color=:gray50, lw=0.4, alpha=0.35, label="")
    end

    colores_ruta_dfs = [:tomato, :salmon, :orangered, :coral, :lightsalmon, :firebrick]
    for (idx, ruta) in enumerate(rutas_muestra)
        col = colores_ruta_dfs[mod1(idx, length(colores_ruta_dfs))]
        for i in 1:length(ruta)-1
            u, v = ruta[i], ruta[i+1]
            plot!(plot_ronda,
                [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
                color=col, lw=2.5, alpha=0.85, label="")
        end
    end

    for i in 1:N_TOTAL
        col = color_bat(bat_actual[i])
        sz  = tamaño_nodo(i)
        en_alguna_ruta = any(i in r for r in rutas_muestra)
        ms = en_alguna_ruta ? sz * 1.7 : sz
        scatter!(plot_ronda, [pos_x[i]], [pos_y[i]],
            color=col,
            markersize=ms,
            markerstrokewidth=(en_alguna_ruta ? 1.2 : 0.2),
            markerstrokecolor=:white,
            label="")
    end

    for ruta in rutas_muestra
        s_orig = ruta[1]
        scatter!(plot_ronda, [pos_x[s_orig]], [pos_y[s_orig]],
            color=:yellow, markersize=tamaño_nodo(s_orig)+3,
            markerstrokewidth=1.5, markerstrokecolor=:white,
            marker=:star5, label="")
    end

    annotate!(plot_ronda, -1.0, 0.62, text("● Verde >70%  ● Amarillo 50-70%  ● Naranja 30-50%  ● Rojo <30%  ● Negro = Muerto  ★ Origen",
        :white, :left, 5))
    annotate!(plot_ronda, -1.0, 0.52, text("Mostrando $(length(rutas_muestra)) rutas DFS activas de $(length(rutas_validas)) totales en esta ronda",
        :gray80, :left, 5))

    plot_ronda
end

gif(anim_dfs, "imgs/fig21_rutas_dfs_topologia.gif", fps=8)
println("fig21_rutas_dfs_topologia.gif guardado")

# ============================================================
# GIF 3: fig22_comparacion_topologia.gif — BFS vs DFS lado a lado
# Rondas clave × layout dual panel
# ============================================================

println("Generando GIF comparativo BFS vs DFS (topología lado a lado)...")

anim_cmp = @animate for ronda in rondas_clave
    bat_b = hist_bat_bfs[ronda + 1]
    bat_d = hist_bat_dfs[ronda + 1]
    rutas_b = filter(r -> length(r) >= 2, rutas_bfs[ronda])
    rutas_d = filter(r -> length(r) >= 2, rutas_dfs[ronda])

    rutas_mb = rutas_b[1:min(5, length(rutas_b))]
    rutas_md = rutas_d[1:min(5, length(rutas_d))]

    n_act_b = count(bat_b[s] > 0 for s in 1:N_SENSORES)
    n_act_d = count(bat_d[s] > 0 for s in 1:N_SENSORES)

    p = plot(layout=(1,2), size=(1200, 560), dpi=120,
        background_color=RGB(0.07, 0.07, 0.12),
        foreground_color=:white,
        plot_title="Ronda $ronda / $N_RONDAS — Propagación de rutas en topología WSN",
        plot_titlefontsize=9, plot_titlefontcolor=:white)

    for (panel, bat_act, rutas_m, titulo_p, colores_rt) in [
        (p[1], bat_b, rutas_mb, "BFS — Vivos: $n_act_b/$N_SENSORES",
         [:cyan, :deepskyblue, :dodgerblue, :steelblue, :cornflowerblue]),
        (p[2], bat_d, rutas_md, "DFS — Vivos: $n_act_d/$N_SENSORES",
         [:tomato, :salmon, :orangered, :coral, :lightsalmon])
    ]
        # Aristas fondo
        for e in edges(g)
            u, v = src(e), dst(e)
            plot!(panel,
                [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
                color=:gray50, lw=0.4, alpha=0.30, label="")
        end

        # Rutas resaltadas
        for (idx, ruta) in enumerate(rutas_m)
            col = colores_rt[mod1(idx, length(colores_rt))]
            for i in 1:length(ruta)-1
                u, v = ruta[i], ruta[i+1]
                plot!(panel,
                    [pos_x[u], pos_x[v]], [pos_y[u], pos_y[v]],
                    color=col, lw=2.2, alpha=0.9, label="")
            end
        end

        # Nodos
        for i in 1:N_TOTAL
            col = color_bat(bat_act[i])
            sz  = tamaño_nodo(i)
            en_ruta = any(i in r for r in rutas_m)
            scatter!(panel, [pos_x[i]], [pos_y[i]],
                color=col,
                markersize=(en_ruta ? sz*1.6 : sz),
                markerstrokewidth=(en_ruta ? 1.0 : 0.2),
                markerstrokecolor=:white,
                label="")
        end

        # Origen estrella
        for ruta in rutas_m
            s0 = ruta[1]
            scatter!(panel, [pos_x[s0]], [pos_y[s0]],
                color=:yellow, markersize=tamaño_nodo(s0)+3,
                markerstrokewidth=1.2, markerstrokecolor=:white,
                marker=:star5, label="")
        end

        plot!(panel,
            title=titulo_p,
            xlim=(-1.15, 1.15), ylim=(-1.25, 0.7),
            xticks=false, yticks=false,
            framestyle=:none,
            background_color=RGB(0.07, 0.07, 0.12),
            titlefontsize=8, titlefontcolor=:white)
    end

    p
end

gif(anim_cmp, "imgs/fig22_comparacion_topologia.gif", fps=8)
println("fig22_comparacion_topologia.gif guardado")

println()
println("=" ^ 55)
println("GIFs de topología generados:")
println("  imgs/fig20_rutas_bfs_topologia.gif")
println("  imgs/fig21_rutas_dfs_topologia.gif")
println("  imgs/fig22_comparacion_topologia.gif  ← comparativo")
println("=" ^ 55)
