# ============================================================
# Simulación Temporal de Agotamiento de Batería
# BFS vs DFS: ¿cuál estrategia preserva mejor la red?
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

gr(size=(1000, 650), dpi=150)
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
    id <= N_SENSORES                          && return :sensor
    id <= N_SENSORES + N_REPETIDORES          && return :repetidor
    return :gateway
end

function nombre_nodo(id::Int)
    t = tipo_nodo(id)
    t == :sensor    && return "S-$(lpad(id, 2, '0'))"
    t == :repetidor && return "R-$(lpad(id - N_SENSORES, 2, '0'))"
    return "GW-$(id - N_SENSORES - N_REPETIDORES)"
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

function peso_arista(v::Int, bat::Dict)
    base = rand(0.5:0.1:3.0)
    penalizacion = 100.0 / bat[v]
    ruido = rand(0.9:0.05:1.1)
    return round(base * penalizacion * ruido, digits=3)
end

function add_arista!(g, u, v, pesos, bat)
    if !has_edge(g, u, v)
        add_edge!(g, u, v)
        w = peso_arista(v, bat)
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
    v = rand(N_SENSORES+1 : N_SENSORES+N_REPETIDORES)
    u != v && add_arista!(g, u, v, aristas_peso_base, bateria_inicial)
end

gateways = collect(N_SENSORES+N_REPETIDORES+1 : N_TOTAL)

# ============================================================
# ALGORITMOS DE ROUTING
# ============================================================

function bfs_camino(g, origen, destinos, bat_activa)
    # Solo usa nodos con batería > 0
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
    # DFS: encuentra la ruta de menor costo mAh (no mínimos saltos)
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

    # Elige la ruta de menor costo mAh
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
# SIMULACIÓN TEMPORAL
# Cada ronda: todos los sensores activos transmiten una vez.
# Se descuenta mAh de CADA nodo en la ruta (incluyendo relays).
# Nodo muere cuando batería <= 0.
# ============================================================

const N_RONDAS   = 120
const MAH_UMBRAL = 0.0   # batería mínima para operar

function simular_red(modo::Symbol; n_rondas=N_RONDAS)
    bat = copy(bateria_inicial)
    pesos = copy(aristas_peso_base)

    # Métricas por ronda
    sensores_activos_hist  = Int[]
    bat_media_hist         = Float64[]
    bat_min_hist           = Float64[]
    nodos_muertos_hist     = Int[]
    consumo_total_hist     = Float64[]

    for _ in 1:n_rondas
        consumo_ronda = 0.0

        # Cada sensor intenta transmitir
        for s in 1:N_SENSORES
            bat[s] <= MAH_UMBRAL && continue  # sensor muerto, salta

            if modo == :bfs
                _, camino = bfs_camino(g, s, gateways, bat)
            else  # :dfs
                _, camino = dfs_mejor_ruta(g, s, gateways, pesos, bat)
            end

            isempty(camino) && continue  # sin ruta disponible

            # Descontar mAh de cada nodo en la ruta (excepto gateway)
            costo_arista_avg = costo_camino(camino, pesos) / max(length(camino)-1, 1)
            for nodo in camino
                tipo_nodo(nodo) == :gateway && continue
                bat[nodo] = max(0.0, bat[nodo] - costo_arista_avg * 0.8)
            end
            consumo_ronda += costo_camino(camino, pesos)
        end

        # Actualizar pesos según batería actual (nodos con menos bat = más costo)
        for ((u,v), _) in pesos
            bat_v = bat[v]
            bat_v <= 0.0 && continue
            base = rand(0.5:0.1:1.5)
            pesos[(u,v)] = round(base * (100.0 / bat_v) * rand(0.95:0.01:1.05), digits=3)
        end

        sensores_vivos = count(bat[s] > MAH_UMBRAL for s in 1:N_SENSORES)
        bat_sensores   = [bat[s] for s in 1:N_SENSORES if bat[s] > MAH_UMBRAL]
        nodos_muertos  = count(bat[i] <= MAH_UMBRAL for i in 1:N_TOTAL if tipo_nodo(i) != :gateway)

        push!(sensores_activos_hist, sensores_vivos)
        push!(bat_media_hist, isempty(bat_sensores) ? 0.0 : mean(bat_sensores))
        push!(bat_min_hist,   isempty(bat_sensores) ? 0.0 : minimum(bat_sensores))
        push!(nodos_muertos_hist, nodos_muertos)
        push!(consumo_total_hist, consumo_ronda)
    end

    return (
        sensores_activos = sensores_activos_hist,
        bat_media        = bat_media_hist,
        bat_min          = bat_min_hist,
        nodos_muertos    = nodos_muertos_hist,
        consumo_total    = consumo_total_hist,
        bat_final        = bat
    )
end

# ============================================================
# EJECUTAR AMBAS SIMULACIONES
# ============================================================

println("Simulando BFS ($N_RONDAS rondas)...")
res_bfs = simular_red(:bfs)
println("  Sensores activos al final: $(res_bfs.sensores_activos[end]) / $N_SENSORES")

println("Simulando DFS ($N_RONDAS rondas)...")
res_dfs = simular_red(:dfs)
println("  Sensores activos al final: $(res_dfs.sensores_activos[end]) / $N_SENSORES")

rondas = 1:N_RONDAS

# ============================================================
# FIG 15: Sensores activos en el tiempo — BFS vs DFS
# ============================================================

p1 = plot(rondas, res_bfs.sensores_activos,
    label="BFS (mín. saltos)", color=:steelblue, lw=2.5,
    title="Sensores activos por ronda — BFS vs DFS",
    xlabel="Ronda de transmisión", ylabel="Sensores activos",
    legend=:bottomleft, grid=true, framestyle=:box)
plot!(p1, rondas, res_dfs.sensores_activos,
    label="DFS (mín. batería)", color=:tomato, lw=2.5, ls=:dash)
hline!(p1, [N_SENSORES * 0.5], color=:orange, lw=1.5, ls=:dot, label="50% umbral")
hline!(p1, [N_SENSORES * 0.2], color=:red, lw=1.5, ls=:dot, label="20% umbral crítico")

savefig(p1, "imgs/fig15_sensores_activos.png")
println("fig15_sensores_activos.png guardado")

# ============================================================
# FIG 16: Batería media y mínima — BFS vs DFS
# ============================================================

p2 = plot(layout=(1,2), size=(1100, 500), dpi=150)
plot!(p2[1], rondas, res_bfs.bat_media, label="BFS", color=:steelblue, lw=2,
    title="Batería media (sensores vivos)", xlabel="Ronda", ylabel="Batería (%)")
plot!(p2[1], rondas, res_dfs.bat_media, label="DFS", color=:tomato, lw=2, ls=:dash)
hline!(p2[1], [30.0], color=:red, lw=1.2, ls=:dot, label="30% crítico")

plot!(p2[2], rondas, res_bfs.bat_min, label="BFS", color=:steelblue, lw=2,
    title="Batería mínima (peor nodo)", xlabel="Ronda", ylabel="Batería (%)")
plot!(p2[2], rondas, res_dfs.bat_min, label="DFS", color=:tomato, lw=2, ls=:dash)
hline!(p2[2], [0.0], color=:black, lw=1.2, ls=:dot, label="Nodo muerto")

savefig(p2, "imgs/fig16_bateria_temporal.png")
println("fig16_bateria_temporal.png guardado")

# ============================================================
# FIG 17: Nodos muertos acumulados — BFS vs DFS
# ============================================================

p3 = plot(rondas, res_bfs.nodos_muertos,
    label="BFS", color=:steelblue, lw=2.5, fill=(0, 0.15, :steelblue),
    title="Nodos agotados acumulados — BFS vs DFS",
    xlabel="Ronda", ylabel="Nodos con batería = 0",
    legend=:topleft, grid=true)
plot!(p3, rondas, res_dfs.nodos_muertos,
    label="DFS", color=:tomato, lw=2.5, ls=:dash, fill=(0, 0.15, :tomato))

savefig(p3, "imgs/fig17_nodos_muertos.png")
println("fig17_nodos_muertos.png guardado")

# ============================================================
# FIG 18: GIF animado — batería por nodo, ronda a ronda
# Cada frame = snapshot del nivel de batería de los 35 sensores
# ============================================================

println("Generando GIF animado (puede tardar ~30s)...")

# Re-ejecutar con historia completa de batería por ronda
function simular_con_historial(modo::Symbol; n_rondas=N_RONDAS)
    bat = copy(bateria_inicial)
    pesos = copy(aristas_peso_base)
    historial = [copy(bat)]   # ronda 0 = estado inicial

    for _ in 1:n_rondas
        for s in 1:N_SENSORES
            bat[s] <= MAH_UMBRAL && continue
            if modo == :bfs
                _, camino = bfs_camino(g, s, gateways, bat)
            else
                _, camino = dfs_mejor_ruta(g, s, gateways, pesos, bat)
            end
            isempty(camino) && continue
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
        push!(historial, copy(bat))
    end
    return historial
end

hist_bfs = simular_con_historial(:bfs)
hist_dfs = simular_con_historial(:dfs)

function color_bateria(pct::Float64)
    pct <= 0.0  && return :black
    pct < 20.0  && return :darkred
    pct < 30.0  && return :red
    pct < 50.0  && return :orange
    pct < 70.0  && return :gold
    return :green
end

# Frames cada 5 rondas para gif manejable
frame_indices = vcat(0:2:10, 15:5:N_RONDAS)

anim = @animate for fi in frame_indices
    bat_b = hist_bfs[fi+1]   # +1 porque historial empieza en ronda 0
    bat_d = hist_dfs[fi+1]

    bats_bfs = [bat_b[s] for s in 1:N_SENSORES]
    bats_dfs = [bat_d[s] for s in 1:N_SENSORES]
    colores_bfs = [color_bateria(b) for b in bats_bfs]
    colores_dfs = [color_bateria(b) for b in bats_dfs]

    vivos_bfs = count(b > 0 for b in bats_bfs)
    vivos_dfs = count(b > 0 for b in bats_dfs)
    vivos_bfs_list = filter(>(0), bats_bfs)
    vivos_dfs_list = filter(>(0), bats_dfs)
    media_bfs = isempty(vivos_bfs_list) ? 0.0 : mean(vivos_bfs_list)
    media_dfs = isempty(vivos_dfs_list) ? 0.0 : mean(vivos_dfs_list)

    p = plot(layout=(1,2), size=(1100, 520), dpi=120)

    # Panel BFS
    scatter!(p[1],
        1:N_SENSORES, bats_bfs,
        color=colores_bfs, markerstrokewidth=0, markersize=8,
        title="BFS — Ronda $fi  |  Vivos: $vivos_bfs/$N_SENSORES  |  Media: $(@sprintf("%.1f", media_bfs))%",
        xlabel="Sensor (índice)", ylabel="Batería (%)",
        ylim=(-5, 105), legend=false, grid=true)
    hline!(p[1], [30.0], color=:red, lw=1.2, ls=:dash, label="")
    hline!(p[1], [50.0], color=:orange, lw=1.2, ls=:dash, label="")

    # Panel DFS
    scatter!(p[2],
        1:N_SENSORES, bats_dfs,
        color=colores_dfs, markerstrokewidth=0, markersize=8,
        title="DFS — Ronda $fi  |  Vivos: $vivos_dfs/$N_SENSORES  |  Media: $(@sprintf("%.1f", media_dfs))%",
        xlabel="Sensor (índice)", ylabel="",
        ylim=(-5, 105), legend=false, grid=true)
    hline!(p[2], [30.0], color=:red, lw=1.2, ls=:dash, label="")
    hline!(p[2], [50.0], color=:orange, lw=1.2, ls=:dash, label="")

    plot!(p, plot_title="Agotamiento de batería por sensor — BFS vs DFS (Ronda $fi/$N_RONDAS)",
          plot_titlefontsize=11)
end

gif(anim, "imgs/fig18_agotamiento_gif.gif", fps=4)
println("fig18_agotamiento_gif.gif guardado")

# ============================================================
# FIG 19: Consumo acumulado total — BFS vs DFS
# ============================================================

consumo_acum_bfs = cumsum(res_bfs.consumo_total)
consumo_acum_dfs = cumsum(res_dfs.consumo_total)

p4 = plot(rondas, consumo_acum_bfs,
    label="BFS", color=:steelblue, lw=2.5,
    title="Consumo acumulado de batería — BFS vs DFS",
    xlabel="Ronda", ylabel="mAh consumidos (acumulado)",
    legend=:topleft, grid=true)
plot!(p4, rondas, consumo_acum_dfs,
    label="DFS", color=:tomato, lw=2.5, ls=:dash)

# Marcar ronda donde muere el primer nodo en cada modo
primer_muerto_bfs = findfirst(>(0), res_bfs.nodos_muertos)
primer_muerto_dfs = findfirst(>(0), res_dfs.nodos_muertos)
!isnothing(primer_muerto_bfs) && vline!(p4, [primer_muerto_bfs], color=:steelblue, lw=1.5, ls=:dot, label="1er nodo muerto BFS")
!isnothing(primer_muerto_dfs) && vline!(p4, [primer_muerto_dfs], color=:tomato, lw=1.5, ls=:dot, label="1er nodo muerto DFS")

savefig(p4, "imgs/fig19_consumo_acumulado.png")
println("fig19_consumo_acumulado.png guardado")

# ============================================================
# RESUMEN NUMÉRICO
# ============================================================

println()
println("=" ^ 60)
println("RESUMEN — SIMULACIÓN TEMPORAL ($N_RONDAS RONDAS)")
println("=" ^ 60)

function ronda_primera_baja(hist, umbral, n_sens=N_SENSORES)
    for (i, bat_dict) in enumerate(hist)
        any(bat_dict[s] <= umbral for s in 1:n_sens) && return i - 1
    end
    return N_RONDAS
end

println()
@printf("%-35s  %8s  %8s\n", "Métrica", "BFS", "DFS")
println("-" ^ 55)
@printf("%-35s  %8d  %8d\n", "Sensores vivos al final",
        res_bfs.sensores_activos[end], res_dfs.sensores_activos[end])
@printf("%-35s  %8.1f  %8.1f\n", "Batería media final (vivos) %",
        res_bfs.bat_media[end], res_dfs.bat_media[end])
@printf("%-35s  %8d  %8d\n", "Nodos agotados (sensores+reps)",
        res_bfs.nodos_muertos[end], res_dfs.nodos_muertos[end])
@printf("%-35s  %8.1f  %8.1f\n", "Consumo total red (mAh)",
        sum(res_bfs.consumo_total), sum(res_dfs.consumo_total))
@printf("%-35s  %8d  %8d\n", "Ronda 1er nodo bajo 30%",
        ronda_primera_baja(hist_bfs, 30.0),
        ronda_primera_baja(hist_dfs, 30.0))
@printf("%-35s  %8d  %8d\n", "Ronda 1er nodo muerto",
        something(findfirst(>(0), res_bfs.nodos_muertos), N_RONDAS),
        something(findfirst(>(0), res_dfs.nodos_muertos), N_RONDAS))

println()
println("Interpretación:")
activos_bfs = res_bfs.sensores_activos[end]
activos_dfs = res_dfs.sensores_activos[end]
if activos_bfs >= activos_dfs
    @printf("  BFS preservó %d sensores más que DFS tras %d rondas.\n",
            activos_bfs - activos_dfs, N_RONDAS)
    println("  BFS minimiza saltos → rutas cortas → menos nodos intermedios desgastados.")
else
    @printf("  DFS preservó %d sensores más que BFS tras %d rondas.\n",
            activos_dfs - activos_bfs, N_RONDAS)
    println("  DFS elige rutas de menor costo mAh → distribuye el gasto en más nodos.")
end

println()
println("Figuras generadas:")
println("  imgs/fig15_sensores_activos.png")
println("  imgs/fig16_bateria_temporal.png")
println("  imgs/fig17_nodos_muertos.png")
println("  imgs/fig18_agotamiento_gif.gif  ← animación")
println("  imgs/fig19_consumo_acumulado.png")
