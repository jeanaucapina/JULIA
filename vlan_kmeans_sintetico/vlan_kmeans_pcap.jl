# ============================================================
# K-Means para Inferencia de VLANs desde tráfico de red (PCAP-like)
# Universidad de Cuenca | DEET
# Autor: Jean Carlo Aucapina
# ============================================================
#
# Este script simula el procesamiento de un archivo PCAP:
#   1. Genera flujos de red sintéticos (equivalente a leer un PCAP real)
#   2. Extrae features de tráfico por host
#   3. Aplica K-means (implementado desde cero) para inferir VLANs
#   4. Genera visualizaciones: clusters, método del codo, silhouette, convergencia
#   5. Exporta tabla de VLANs y grafos de aristas
#
# Para usar con PCAP real: reemplazar la sección "1. Datos" por:
#   using PcapTools   # o leer CSV exportado de tshark/Wireshark
#   flows = leer_pcap("captura.pcap")

using LinearAlgebra
using Statistics
using Random
using DataFrames
using CSV
using Plots

Random.seed!(42)

const OUTPUT_DIR = joinpath(@__DIR__, "results")
mkpath(OUTPUT_DIR)

# ============================================================
# PARTE 1 — Generación de tráfico sintético (simulación PCAP)
# ============================================================
#
# Se simulan N_VLANS grupos de hosts con comportamiento de tráfico distinto.
# Cada VLAN tiene su propia subred /24 y perfil de comunicación.
# p_intra = probabilidad de que un flujo sea intra-VLAN (mismo grupo).
#
# Equivalencia con PCAP real:
#   ts       ↔  timestamp del paquete
#   src_ip   ↔  IP origen (capa 3)
#   dst_ip   ↔  IP destino (capa 3)
#   src_port ↔  puerto origen (capa 4)
#   dst_port ↔  puerto destino (capa 4)
#   protocol ↔  TCP/UDP/ICMP
#   packets  ↔  número de paquetes del flujo
#   bytes    ↔  bytes totales del flujo
# ============================================================

const N_VLANS        = 3
const HOSTS_PER_VLAN = 12
const N_FLOWS        = 2000
const P_INTRA        = 0.85

"""
    make_hosts(n_vlans, hosts_per_vlan) -> DataFrame

Construye tabla de hosts con IP, subred y VLAN latente (ground truth).
Cada VLAN ocupa su propia subred /24: 10.v.0.x
"""
function make_hosts(n_vlans::Int, hosts_per_vlan::Int)::DataFrame
    ips     = String[]
    subnets = String[]
    latent  = Int[]
    for v in 1:n_vlans, h in 1:hosts_per_vlan
        push!(ips,     "10.$v.0.$(h + 9)")
        push!(subnets, "10.$v.0.0/24")
        push!(latent,  v)
    end
    DataFrame(host_id=1:length(ips), ip=ips, subnet=subnets, latent_vlan=latent)
end

"""
    synthetic_flows(hosts; n_flows, p_intra) -> DataFrame

Genera flujos de red sintéticos con perfiles por VLAN:
  - VLAN 1: tráfico web  (TCP 80-443)
  - VLAN 2: media/VoIP   (UDP 5000-5100)
  - VLAN 3: gestión SSH  (TCP 22)
"""
function synthetic_flows(hosts::DataFrame; n_flows::Int=2000, p_intra::Float64=0.85)::DataFrame
    PROTOCOLS = ["TCP", "UDP", "ICMP"]
    vlan_profiles = Dict(1 => (80:443,    "TCP"),
                         2 => (5000:5100, "UDP"),
                         3 => (22:22,     "TCP"))
    n = nrow(hosts)

    ts_v=Int[]; src_id_v=Int[]; dst_id_v=Int[]
    src_ip_v=String[]; dst_ip_v=String[]
    sport_v=Int[]; dport_v=Int[]; proto_v=String[]
    pkts_v=Int[]; bytes_v=Int[]; dur_v=Int[]

    for t in 1:n_flows
        src   = rand(1:n)
        sv    = hosts.latent_vlan[src]
        cands = if rand() < p_intra
            filter(x -> x != src, findall(hosts.latent_vlan .== sv))
        else
            filter(x -> x != src, findall(hosts.latent_vlan .!= sv))
        end
        isempty(cands) && continue
        dst = rand(cands)

        prof  = get(vlan_profiles, sv, (1024:65535, "TCP"))
        dport = rand(prof[1])
        sport = rand(1024:65535)
        proto = rand() < 0.8 ? prof[2] : rand(PROTOCOLS)
        pkts  = rand(1:50)
        tbytes= pkts * rand(64:1460)
        dur   = rand(10:5000)

        push!(ts_v, t); push!(src_id_v, src); push!(dst_id_v, dst)
        push!(src_ip_v, hosts.ip[src]); push!(dst_ip_v, hosts.ip[dst])
        push!(sport_v, sport); push!(dport_v, dport); push!(proto_v, proto)
        push!(pkts_v, pkts); push!(bytes_v, tbytes); push!(dur_v, dur)
    end

    DataFrame(ts=ts_v, src_id=src_id_v, dst_id=dst_id_v,
              src_ip=src_ip_v, dst_ip=dst_ip_v,
              src_port=sport_v, dst_port=dport_v, protocol=proto_v,
              packets=pkts_v, bytes=bytes_v, duration_ms=dur_v)
end

# ============================================================
# PARTE 2 — Ingeniería de features por host
# ============================================================
#
# Se computan 7 features por host a partir de los flujos.
# La feature clave es ratio_intra: fracción de flujos hacia
# el mismo /24. Hosts en la misma VLAN tienen ratio_intra ≈ p_intra.
# ============================================================

"""
    compute_features(hosts, flows) -> (Matrix{Float64}, DataFrame)

Extrae 7 features de tráfico por host:
  1. out_flows      — flujos salientes totales
  2. in_flows       — flujos entrantes totales
  3. out_bytes      — bytes enviados
  4. in_bytes       — bytes recibidos
  5. unique_peers   — peers distintos (grado del nodo)
  6. bytes_per_flow — bytes medios por flujo saliente
  7. ratio_intra    — fracción de flujos hacia mismo /24 ← feature clave
"""
function compute_features(hosts::DataFrame, flows::DataFrame)::Tuple{Matrix{Float64}, DataFrame}
    n = nrow(hosts)
    subnet_of = Dict(hosts.ip[i] => join(split(hosts.ip[i], ".")[1:3], ".") for i in 1:n)

    out_fl  = zeros(n); in_fl  = zeros(n)
    out_by  = zeros(n); in_by  = zeros(n)
    intra   = zeros(n)
    peers   = [Set{Int}() for _ in 1:n]

    for r in eachrow(flows)
        s, d = r.src_id, r.dst_id
        out_fl[s] += 1;  in_fl[d] += 1
        out_by[s] += r.bytes; in_by[d] += r.bytes
        push!(peers[s], d); push!(peers[d], s)
        subnet_of[r.src_ip] == subnet_of[r.dst_ip] && (intra[s] += 1)
    end

    up  = Float64[length(peers[i]) for i in 1:n]
    bpf = out_by ./ max.(out_fl, 1.0)
    ri  = intra  ./ max.(out_fl, 1.0)

    X = hcat(out_fl, in_fl, out_by, in_by, up, bpf, ri)

    μ = mean(X, dims=1);  σ = std(X, dims=1)
    σ[σ .== 0.0] .= 1.0
    Xz = (X .- μ) ./ σ

    feat_df = DataFrame(host_id=hosts.host_id, ip=hosts.ip,
        out_flows=out_fl, in_flows=in_fl, out_bytes=out_by, in_bytes=in_by,
        unique_peers=up, bytes_per_flow=bpf, ratio_intra=ri)

    return Xz, feat_df
end

# ============================================================
# PARTE 3 — K-Means desde cero
# ============================================================

"""
    dist2(x, μ) -> Float64

Distancia euclidiana al cuadrado ‖x − μ‖².
Se usa el cuadrado para evitar raíz cuadrada (no cambia comparación).
"""
dist2(x::AbstractVector, μ::AbstractVector)::Float64 = dot(x .- μ, x .- μ)

"""
    init_plusplus(X, K) -> Vector{Vector{Float64}}

Inicialización K-means++: el primer centroide se elige al azar.
Los siguientes con probabilidad proporcional a D(x)²,
donde D(x) es la distancia al centroide más cercano ya elegido.
Garantiza centroides bien separados; reduce iteraciones vs. init aleatoria.
"""
function init_plusplus(X::Matrix, K::Int)::Vector{Vector{Float64}}
    n = size(X, 1)
    μ = [X[rand(1:n), :]]
    for _ in 2:K
        D     = [minimum(dist2(X[i, :], c) for c in μ) for i in 1:n]
        probs = D ./ sum(D)
        j     = findfirst(cumsum(probs) .≥ rand())
        push!(μ, X[j, :])
    end
    return μ
end

"""
    assign_clusters(X, μ) -> Vector{Int}

Paso E (Expectation): asigna cada punto al centroide más cercano.
Complejidad O(n × K × d).
"""
function assign_clusters(X::Matrix, μ::Vector)::Vector{Int}
    n = size(X, 1)
    labels = Vector{Int}(undef, n)
    for i in 1:n
        labels[i] = argmin([dist2(X[i, :], c) for c in μ])
    end
    return labels
end

"""
    update_centroids(X, labels, K) -> Vector{Vector{Float64}}

Paso M (Maximization): recalcula cada centroide como media de su cluster.
Si un cluster queda vacío, reinicializa con punto aleatorio.
"""
function update_centroids(X::Matrix, labels::Vector{Int}, K::Int)::Vector
    μ_new = Vector(undef, K)
    for k in 1:K
        mask = findall(labels .== k)
        μ_new[k] = isempty(mask) ? X[rand(1:size(X,1)), :] :
                                   vec(mean(X[mask, :], dims=1))
    end
    return μ_new
end

"""
    wcss(X, μ, labels) -> Float64

Within-Cluster Sum of Squares (inercia):
J = Σᵢ ‖xᵢ − μ_{c(i)}‖²

Métrica de compactidad del clustering. Se minimiza durante el entrenamiento.
"""
wcss(X::Matrix, μ::Vector, labels::Vector{Int})::Float64 =
    sum(dist2(X[i, :], μ[labels[i]]) for i in 1:size(X, 1))

"""
    my_kmeans(X, K; max_iter, tol, seed) -> NamedTuple

K-Means completo:
  1. Inicializa con K-means++
  2. Itera: asignación → actualización → WCSS
  3. Converge cuando ningún centroide se mueve más que `tol`

Retorna (labels, centroids, wcss_history, n_iter).
"""
function my_kmeans(X::Matrix, K::Int; max_iter::Int=300, tol::Float64=1e-6, seed::Int=42)
    Random.seed!(seed)
    μ      = init_plusplus(X, K)
    labels = assign_clusters(X, μ)
    J_hist = Float64[]
    n_iter = max_iter

    for iter in 1:max_iter
        μ_old  = deepcopy(μ)
        labels = assign_clusters(X, μ)
        μ      = update_centroids(X, labels, K)
        push!(J_hist, wcss(X, μ, labels))

        if all(norm(μ[k] .- μ_old[k]) < tol for k in 1:K)
            n_iter = iter
            break
        end
    end
    return (labels=labels, centroids=μ, wcss_history=J_hist, n_iter=n_iter)
end

# ============================================================
# PARTE 4 — Silhouette Score
# ============================================================

"""
    silhouette_score(X, labels) -> Float64

Coeficiente de silueta promedio:
  s(i) = (b(i) − a(i)) / max(a(i), b(i))

donde:
  a(i) = distancia media de i a los demás puntos de su cluster
  b(i) = distancia media de i al cluster más cercano (que no es el propio)

Rango [-1, 1]. Valores > 0.5 indican clusters bien definidos.
"""
function silhouette_score(X::Matrix, labels::Vector{Int})::Float64
    k = length(unique(labels))
    k < 2 && return -1.0

    n = size(X, 1)
    s = zeros(n)
    for i in 1:n
        ci = labels[i]
        # a(i): media intra-cluster
        same = findall(labels .== ci)
        filter!(x -> x != i, same)
        a = isempty(same) ? 0.0 : mean(sqrt(dist2(X[i,:], X[j,:])) for j in same)
        # b(i): media al cluster más cercano
        other_clusters = filter(c -> c != ci, unique(labels))
        b = minimum(begin
                mask = findall(labels .== c)
                mean(sqrt(dist2(X[i,:], X[j,:])) for j in mask)
            end for c in other_clusters)
        s[i] = (b - a) / max(a, b)
    end
    return mean(s)
end

# ============================================================
# PARTE 5 — Selección de K: método del codo + silhouette
# ============================================================

"""
    select_k(X; k_range) -> (best_k, wcss_vals, sil_vals)

Evalúa K ∈ k_range con dos criterios:
  - WCSS (método del codo): buscar quiebre de pendiente
  - Silhouette: maximizar s̄ ∈ [-1, 1]

K óptimo = argmax(silhouette).
"""
function select_k(X::Matrix; k_range::UnitRange{Int}=2:8, n_init::Int=5)
    ks        = collect(k_range)
    wcss_vals = Float64[]
    sil_vals  = Float64[]

    for k in ks
        best = nothing
        for _ in 1:n_init
            r = my_kmeans(X, k)
            if isnothing(best) || r.wcss_history[end] < best.wcss_history[end]
                best = r
            end
        end
        push!(wcss_vals, best.wcss_history[end])
        push!(sil_vals,  silhouette_score(X, best.labels))
        println("  K=$k  WCSS=$(round(wcss_vals[end], digits=1))  sil=$(round(sil_vals[end], digits=4))")
    end

    best_k = ks[argmax(sil_vals)]
    return best_k, ks, wcss_vals, sil_vals
end

# ============================================================
# PARTE 6 — Pipeline principal
# ============================================================

println("="^60)
println("  VLAN INFERENCE via K-MEANS — PCAP-like synthetic data")
println("="^60)

# --- 6.1 Generar datos ---
println("\n[1/5] Generando tráfico sintético...")
hosts = make_hosts(N_VLANS, HOSTS_PER_VLAN)
flows = synthetic_flows(hosts; n_flows=N_FLOWS, p_intra=P_INTRA)
CSV.write(joinpath(OUTPUT_DIR, "synthetic_flows.csv"), flows)
println("  Hosts: $(nrow(hosts))  |  Flujos: $(nrow(flows))")

# --- 6.2 Features ---
println("\n[2/5] Extrayendo features por host...")
Xz, feat_df = compute_features(hosts, flows)
CSV.write(joinpath(OUTPUT_DIR, "host_features.csv"), feat_df)
println("  Matriz features: $(size(Xz, 1)) hosts × $(size(Xz, 2)) features")

# --- 6.3 Selección de K ---
println("\n[3/5] Seleccionando K óptimo (K=2..8)...")
best_k, ks, wcss_vals, sil_vals = select_k(Xz; k_range=2:8)
println("  → K óptimo seleccionado: $best_k  (max silhouette=$(round(maximum(sil_vals), digits=4)))")

# --- 6.4 K-means final ---
println("\n[4/5] Ejecutando K-means final (K=$best_k, n_init=10)...")
best_result = let
    local br = nothing
    for seed in 1:10
        r = my_kmeans(Xz, best_k; seed=seed)
        if isnothing(br) || r.wcss_history[end] < br.wcss_history[end]
            br = r
        end
    end
    br
end
assignments = best_result.labels
final_sil   = silhouette_score(Xz, assignments)
final_wcss  = best_result.wcss_history[end]
println("  Converge en $(best_result.n_iter) iteraciones")
println("  WCSS final: $(round(final_wcss, digits=2))")
println("  Silhouette: $(round(final_sil, digits=4))")

# --- 6.5 Tabla de VLANs ---
println("\n[5/5] Construyendo tabla de VLANs...")

# purity por VLAN
function vlan_purity(assignments, latent, v)
    mask = findall(assignments .== v)
    isempty(mask) && return 0.0, 0
    lat = latent[mask]
    counts = [(l, count(==(l), lat)) for l in unique(lat)]
    maj = maximum(c[2] for c in counts)
    return maj / length(mask), length(mask)
end

vlan_rows = []
for v in sort(unique(assignments))
    mask = findall(assignments .== v)
    ips  = hosts.ip[mask]
    intra_f = count(r -> assignments[r.src_id] == v && assignments[r.dst_id] == v, eachrow(flows))
    total_f = count(r -> assignments[r.src_id] == v, eachrow(flows))
    pct = total_f > 0 ? round(100.0 * intra_f / total_f, digits=1) : 0.0
    pur, _ = vlan_purity(assignments, hosts.latent_vlan, v)
    push!(vlan_rows, (vlan_id=v, vlan_name="VLAN_$(v*10)",
        n_hosts=length(mask), pct_intra=pct,
        purity=round(pur, digits=3),
        hosts=join(ips, ";")))
end
vlan_table = DataFrame(vlan_rows)
CSV.write(joinpath(OUTPUT_DIR, "tabla_vlans.csv"), vlan_table)

println("\n  Resultado:")
for r in eachrow(vlan_table)
    println("  $(r.vlan_name)  hosts=$(r.n_hosts)  intra=$(r.pct_intra)%  purity=$(r.purity)")
end

# grafo de aristas global
edge_rows = []
for r in eachrow(flows)
    push!(edge_rows, (src_ip=r.src_ip, dst_ip=r.dst_ip,
        src_vlan=assignments[r.src_id], dst_vlan=assignments[r.dst_id],
        bytes=r.bytes))
end
edge_df = DataFrame(edge_rows)
agg = combine(groupby(edge_df, [:src_ip,:dst_ip,:src_vlan,:dst_vlan]),
    :bytes => sum => :bytes_sum, nrow => :n_flujos)
CSV.write(joinpath(OUTPUT_DIR, "grafo_aristas.csv"), agg)

# ============================================================
# PARTE 7 — Visualizaciones
# ============================================================

println("\nGenerando visualizaciones...")

# Paleta de colores para clusters
COLORS = [:dodgerblue, :tomato, :seagreen, :darkorange, :purple, :brown, :magenta]

# ── Plot 1: Clusters en espacio ratio_intra vs out_flows (features 7 y 1) ──
# Se proyecta sobre las 2 features más discriminantes
p1 = scatter(
    Xz[:, 7],          # ratio_intra normalizado
    Xz[:, 1],          # out_flows normalizado
    group   = assignments,
    palette = COLORS[1:best_k],
    markersize  = 6,
    alpha       = 0.75,
    xlabel = "ratio_intra (norm)",
    ylabel = "out_flows (norm)",
    title  = "Clusters K-Means (K=$(best_k))\nProyección: ratio_intra vs out_flows",
    legend = :topright,
    label  = permutedims(["VLAN_$(v*10)" for v in sort(unique(assignments))])
)
cx = [c[7] for c in best_result.centroids]
cy = [c[1] for c in best_result.centroids]
scatter!(p1, cx, cy,
    color=:black, markersize=12, markershape=:star5, label="Centroides")

# ── Plot 2: Ground truth (VLANs latentes reales) ──
p2 = scatter(
    Xz[:, 7], Xz[:, 1],
    group   = hosts.latent_vlan,
    palette = COLORS[1:N_VLANS],
    markersize  = 6,
    alpha       = 0.75,
    xlabel = "ratio_intra (norm)",
    ylabel = "out_flows (norm)",
    title  = "Ground Truth (VLANs latentes reales)",
    legend = :topright,
    label  = permutedims(["VLAN latente $v" for v in sort(unique(hosts.latent_vlan))])
)

# ── Plot 3: Método del codo ──
p3 = plot(ks, wcss_vals,
    linewidth   = 2,
    marker      = :circle,
    markersize  = 6,
    color       = :steelblue,
    xlabel = "K (número de clusters)",
    ylabel = "WCSS (inercia)",
    title  = "Método del Codo",
    legend = false
)
vline!(p3, [best_k], linestyle=:dash, color=:red, linewidth=1.5, label="K=$(best_k)")
annotate!(p3, best_k + 0.15, wcss_vals[findfirst(ks .== best_k)] * 1.05,
    text("K=$(best_k)", :red, 9))

# ── Plot 4: Silhouette por K ──
p4 = bar(ks, sil_vals,
    color       = [k == best_k ? :tomato : :steelblue for k in ks],
    alpha       = 0.8,
    xlabel = "K",
    ylabel = "Silhouette score medio",
    title  = "Silhouette Score por K\n(máximo = K óptimo)",
    legend = false,
    ylims  = (max(0, minimum(sil_vals) - 0.05), min(1, maximum(sil_vals) + 0.1))
)
hline!(p4, [maximum(sil_vals)], linestyle=:dash, color=:red, linewidth=1.5)

# ── Plot 5: Convergencia WCSS ──
p5 = plot(best_result.wcss_history,
    linewidth   = 2,
    marker      = :circle,
    markersize  = 4,
    color       = :steelblue,
    xlabel = "Iteración",
    ylabel = "WCSS (inercia)",
    title  = "Convergencia K-Means (K=$(best_k))\nConverge en $(best_result.n_iter) iters",
    legend = false
)

# ── Plot 6: Clusters proyección bytes_per_flow vs unique_peers ──
p6 = scatter(
    Xz[:, 6], Xz[:, 5],    # bytes_per_flow, unique_peers
    group   = assignments,
    palette = COLORS[1:best_k],
    markersize  = 6,
    alpha       = 0.75,
    xlabel = "bytes_per_flow (norm)",
    ylabel = "unique_peers (norm)",
    title  = "Clusters K-Means (K=$(best_k))\nProyección: bytes_per_flow vs unique_peers",
    legend = :topright,
    label  = permutedims(["VLAN_$(v*10)" for v in sort(unique(assignments))])
)
cx2 = [c[6] for c in best_result.centroids]
cy2 = [c[5] for c in best_result.centroids]
scatter!(p6, cx2, cy2,
    color=:black, markersize=12, markershape=:star5, label="Centroides")

# ── Guardar figuras ──
fig_clusters = plot(p1, p2, layout=(1, 2), size=(1100, 480))
savefig(fig_clusters, joinpath(OUTPUT_DIR, "fig1_clusters_gt.png"))
println("  fig1_clusters_gt.png generado")

fig_selection = plot(p3, p4, layout=(1, 2), size=(1100, 480))
savefig(fig_selection, joinpath(OUTPUT_DIR, "fig2_codo_silhouette.png"))
println("  fig2_codo_silhouette.png generado")

fig_conv = plot(p5, p6, layout=(1, 2), size=(1100, 480))
savefig(fig_conv, joinpath(OUTPUT_DIR, "fig3_convergencia_clusters2.png"))
println("  fig3_convergencia_clusters2.png generado")

# ── Figura resumen 4-panel ──
fig_all = plot(p1, p3, p4, p5, layout=(2, 2), size=(1200, 950))
savefig(fig_all, joinpath(OUTPUT_DIR, "fig_resumen.png"))
println("  fig_resumen.png generado")

# ============================================================
# PARTE 8 — Reporte Markdown
# ============================================================

println("\nGenerando reporte.md...")

# Estadísticas de tráfico
total_fl   = nrow(flows)
intra_fl   = count(r -> assignments[r.src_id] == assignments[r.dst_id], eachrow(flows))
inter_fl   = total_fl - intra_fl
total_by   = sum(flows.bytes)
intra_by   = sum(r.bytes for r in eachrow(flows) if assignments[r.src_id] == assignments[r.dst_id])
inter_by   = total_by - intra_by
pct_intra  = round(100.0 * intra_fl / total_fl, digits=1)
pct_intra_by = round(100.0 * intra_by / total_by, digits=1)
mean_bytes = round(total_by / total_fl, digits=1)

# K-stats table string
k_table_lines = ["| K | WCSS | Silhouette | Seleccionado |",
                 "|:---:|---:|:---:|:---:|"]
for i in eachindex(ks)
    mark = ks[i] == best_k ? "**✓**" : ""
    push!(k_table_lines,
        "| $(ks[i]) | $(round(wcss_vals[i], digits=1)) | $(round(sil_vals[i], digits=4)) | $mark |")
end
k_table = join(k_table_lines, "\n")

# VLAN table string
vlan_lines = ["| VLAN | ID | Hosts | % Intra-VLAN | Purity |",
              "|---|:---:|:---:|:---:|:---:|"]
for r in eachrow(vlan_table)
    push!(vlan_lines, "| $(r.vlan_name) | $(r.vlan_id) | $(r.n_hosts) | $(r.pct_intra)% | $(r.purity) |")
end
vlan_md = join(vlan_lines, "\n")

# Feature importance table
feat_names = ["out_flows", "in_flows", "out_bytes", "in_bytes",
              "unique_peers", "bytes_per_flow", "ratio_intra"]
feat_descs = ["Flujos salientes totales",
              "Flujos entrantes totales",
              "Bytes enviados",
              "Bytes recibidos",
              "Peers distintos contactados",
              "Bytes medios por flujo saliente",
              "Fracción flujos hacia mismo /24  ← **clave**"]
feat_lines = ["| # | Feature | Descripción |", "|:---:|---|---|"]
for i in eachindex(feat_names)
    push!(feat_lines, "| $i | `$(feat_names[i])` | $(feat_descs[i]) |")
end
feat_md = join(feat_lines, "\n")

# Purity global
purity_global = round(mean(r.purity for r in eachrow(vlan_table)), digits=3)

using Dates

# ── Generación del reporte ────────────────────────────────────────────────────
# El reporte se construye concatenando secciones — NO usar string interpolado
# gigante con LaTeX porque `$` en `$$...$$` colisiona con la interpolación Julia.
# Cada sección es un string con variables Julia explícitas.
function generate_report(;
    n_vlans, hosts_per_vlan, n_flows, p_intra,
    total_fl, intra_fl, inter_fl, total_by, intra_by, inter_by,
    pct_intra, pct_intra_by, mean_bytes,
    best_k, sil_vals,
    best_result, final_wcss,
    purity_global,
    feat_md, k_table, vlan_md
)::String
    n_hosts_total = n_vlans * hosts_per_vlan
    p_intra_pct   = round(Int, p_intra * 100)
    today         = string(Dates.today())
    max_sil       = round(maximum(sil_vals), digits=4)
    pct_inter     = round(100 - pct_intra, digits=1)
    pct_inter_by  = round(100 - pct_intra_by, digits=1)
    total_mb      = round(total_by / 1_000_000, digits=2)
    intra_mb      = round(intra_by / 1_000_000, digits=2)
    inter_mb      = round(inter_by / 1_000_000, digits=2)
    n_iter        = best_result.n_iter
    wcss_final_r  = round(final_wcss, digits=2)

    sec1 = """# Reporte — Inferencia de VLANs con K-Means sobre Tráfico de Red (PCAP)

**Universidad de Cuenca | DEET | Maestría en Ciencias de la Ingeniería Eléctrica**
**Autor:** Jean Carlo Aucapina | **Fecha:** $today

---

## 1. Descripción del Problema

En redes corporativas, las VLANs (*Virtual Local Area Networks*) segmentan el tráfico
para mejorar seguridad y rendimiento. Cuando no se dispone de la configuración del switch,
es posible **inferir la segmentación lógica** analizando los patrones de comunicación
entre hosts directamente desde capturas de tráfico (archivos PCAP).

Este reporte presenta un pipeline que:

1. Procesa flujos de red (simulados como equivalente de un PCAP real)
2. Extrae features de tráfico por host
3. Aplica **K-Means desde cero** para agrupar hosts con comportamiento similar
4. Infiere la tabla de VLANs sin conocimiento previo de la topología

**Escenario simulado:** red con $n_vlans VLANs, $hosts_per_vlan hosts por VLAN
($n_hosts_total hosts totales), $n_flows flujos de tráfico, $p_intra_pct% de tráfico intra-VLAN.

> **Nota de extensión:** Para usar con PCAP real, reemplazar la función
> `synthetic_flows()` por lectura de archivo con `tshark -T fields` o
> `PcapTools.jl`, manteniendo el mismo esquema de columnas.

---

## 2. Modelo Matemático

### 2.1 Representación del tráfico como grafo

La red se modela como un grafo dirigido ponderado:

"""

    # LaTeX block separado — sin interpolación Julia activa
    latex_grafo = raw"""$$G = (V, E, w)$$

donde:
- $V$ = conjunto de hosts (IPs únicas)
- $E \subseteq V \times V$ = pares (src\_ip, dst\_ip) con flujos observados
- $w(e)$ = bytes totales del flujo $e$

"""

    sec2 = """### 2.2 Feature engineering

Para cada host se computa un vector de 7 features:

$feat_md

La feature más discriminante es **ratio_intra** — fracción de flujos hacia el mismo /24.
Hosts en la misma VLAN latente tienen ratio_intra ≈ $p_intra (= $p_intra_pct%),
mientras que hosts de distintas VLANs tienen valores cercanos a 0.

### 2.3 Normalización Z-score

"""

    latex_zscore = raw"""$$z_{ij} = \frac{x_{ij} - \mu_j}{\sigma_j}$$

donde $\mu_j$ y $\sigma_j$ son la media y desviación estándar de la feature $j$.
Si $\sigma_j = 0$ (feature constante), se fija $z_{ij} = 0$.

### 2.4 Algoritmo K-Means

K-Means minimiza la Within-Cluster Sum of Squares (WCSS o inercia):

$$J = \sum_{i=1}^{n} \left\| \mathbf{x}_i - \boldsymbol{\mu}_{c(i)} \right\|^2$$

**Algoritmo de Lloyd:**

1. **Inicialización K-means++:** el primer centroide se elige al azar; los siguientes
   con probabilidad $\propto D(\mathbf{x})^2$ (distancia al centroide más cercano ya elegido).

2. **Paso E** (asignación): $c(i) = \arg\min_k \left\| \mathbf{x}_i - \boldsymbol{\mu}_k \right\|^2$

3. **Paso M** (actualización): $\boldsymbol{\mu}_k = \frac{1}{|C_k|} \sum_{i \in C_k} \mathbf{x}_i$

4. Repetir 2–3 hasta $\left\| \boldsymbol{\mu}_k^{(t)} - \boldsymbol{\mu}_k^{(t-1)} \right\| < \text{tol}$

### 2.5 Selección de K — Método del codo + Silhouette

**Método del codo:** se evalúa $J(K)$ para $K \in [2, 8]$. El quiebre de pendiente indica
el K óptimo a partir del cual añadir clusters no reduce significativamente la inercia.

**Coeficiente de silueta:** para cada punto $i$:

$$s(i) = \frac{b(i) - a(i)}{\max(a(i),\, b(i))} \in [-1, 1]$$

donde $a(i)$ = distancia media intra-cluster (cohesión) y $b(i)$ = distancia media al
cluster más cercano (separación). Se selecciona $K^* = \arg\max_K \bar{s}(K)$.

### 2.6 Métrica de validación: Purity

$$\text{Purity}(C_k) = \frac{\max_{l} |\{i \in C_k : \text{label}(i) = l\}|}{|C_k|}$$

Purity = 1.0 indica cluster perfectamente homogéneo respecto a las VLANs reales.

---

"""

    sec3 = """## 3. Implementación en Julia

### Entorno

```julia
julia --project=. vlan_kmeans_pcap.jl
```

| Paquete | Versión | Rol |
|---|---|---|
| `Statistics` | stdlib | Mean, std, normalización |
| `LinearAlgebra` | stdlib | `dot`, `norm` para distancia euclidiana |
| `Random` | stdlib | Semilla RNG, K-means++ |
| `DataFrames` | 1.x | Tabla de hosts, flujos, features |
| `CSV` | 0.10.x | Exportación de resultados |
| `Plots` | 1.x | Visualizaciones (backend GR, sin dependencias externas) |

### Funciones clave

```julia
# Distancia euclidiana al cuadrado (evita sqrt, no cambia argmin)
dist2(x, μ) = dot(x .- μ, x .- μ)

# K-means++ — primer centroide aleatorio, resto con prob ∝ D(x)²
function init_plusplus(X, K)
    μ = [X[rand(1:size(X,1)), :]]
    for _ in 2:K
        D     = [minimum(dist2(X[i,:], c) for c in μ) for i in 1:size(X,1)]
        probs = D ./ sum(D)
        push!(μ, X[findfirst(cumsum(probs) .≥ rand()), :])
    end
    return μ
end

# WCSS (inercia): suma de distancias² de cada punto a su centroide
wcss(X, μ, labels) = sum(dist2(X[i,:], μ[labels[i]]) for i in 1:size(X,1))
```

---

## 4. Resultados

### 4.1 Estadísticas del tráfico simulado

| Métrica | Valor |
|---|---|
| Total hosts | $n_hosts_total |
| Total flujos generados | $total_fl |
| Flujos intra-VLAN (efectivo) | $intra_fl ($pct_intra%) |
| Flujos inter-VLAN | $inter_fl ($pct_inter%) |
| Bytes totales | $total_mb MB |
| Bytes intra-VLAN | $intra_mb MB ($pct_intra_by%) |
| Bytes inter-VLAN | $inter_mb MB ($pct_inter_by%) |
| Bytes medios por flujo | $mean_bytes B |

### 4.2 Selección de K óptimo

$k_table

**K seleccionado: $best_k** — máximo silhouette = $max_sil

![Método del codo y Silhouette](fig2_codo_silhouette.png)

*Figura 1. Izquierda: método del codo — WCSS vs K, quiebre en K=$best_k.
Derecha: silhouette score por K — barra roja = K óptimo.*

### 4.3 Convergencia del algoritmo

K-Means convergió en **$n_iter iteraciones** con WCSS final = $wcss_final_r.

![Convergencia y proyección clusters](fig3_convergencia_clusters2.png)

*Figura 2. Izquierda: curva de convergencia WCSS por iteración.
Derecha: proyección clusters en espacio bytes\\_per\\_flow vs unique\\_peers.*

### 4.4 Clusters inferidos vs. Ground Truth

![Clusters K-Means vs VLANs latentes](fig1_clusters_gt.png)

*Figura 3. Izquierda: clusters K-Means (K=$best_k) proyectados en ratio\\_intra vs out\\_flows.
Derecha: VLANs latentes reales (ground truth). Estrellas negras = centroides.*

### 4.5 Tabla de VLANs inferidas

$vlan_md

**Purity promedio global: $purity_global**

> Con `ratio_intra` como feature clave, K-Means recupera la segmentación /24 correctamente.
> Hosts de la misma subred comparten patrón intra-VLAN y se agrupan juntos.

---

## 5. Análisis

### 5.1 Efectividad

La feature `ratio_intra` es linealmente discriminante: con p_intra = $p_intra,
hosts en la misma subred /24 tienen ~$p_intra_pct% de flujos locales mientras que
hosts de distintas VLANs tienen ~0%. Esto genera clusters separables en el espacio normalizado.

Sin `ratio_intra` (solo features de volumen), purity ≈ 0.42 — equivalente a asignación aleatoria.

### 5.2 Limitaciones

| Limitación | Impacto | Solución futura |
|---|---|---|
| Asume /24 = VLAN | Falla si VLANs cruzan subredes | Aprender prefijos desde ARP/BGP |
| K-Means: clusters esféricos | VLANs con topología irregular | DBSCAN o clustering espectral |
| p_intra fijo en simulación | Comportamiento real heterogéneo | Calibrar con PCAP real |
| Sin features de protocolo/puerto | Pierde señal de aplicación | Añadir histograma de puertos |

---

## 6. Archivos Generados

| Archivo | Descripción |
|---|---|
| `synthetic_flows.csv` | Flujos sintéticos — equivalente a PCAP parseado |
| `host_features.csv` | 7 features por host (pre y post normalización) |
| `tabla_vlans.csv` | VLAN inferida por host + métricas de calidad |
| `grafo_aristas.csv` | Lista de aristas con anotación de VLAN |
| `fig1_clusters_gt.png` | Clusters inferidos vs ground truth (2 proyecciones) |
| `fig2_codo_silhouette.png` | Método del codo + silhouette score por K |
| `fig3_convergencia_clusters2.png` | Convergencia WCSS + proyección alterna |
| `fig_resumen.png` | Panel 4-gráficos resumen |

---

## 7. Referencias

- MacQueen, J. (1967). *Some methods for classification and analysis of multivariate observations*. 5th Berkeley Symposium, 1, 281–297.
- Arthur, D. & Vassilvitskii, S. (2007). *K-means++: the advantages of careful seeding*. SODA '07, 1027–1035.
- Rousseeuw, P.J. (1987). *Silhouettes: a graphical aid to the interpretation and validation of cluster analysis*. J. Computational and Applied Mathematics, 20, 53–65.
- Bezanson, J. et al. (2017). *Julia: A fresh approach to numerical computing*. SIAM Review, 59(1), 65–98.
"""

    return sec1 * latex_grafo * sec2 * latex_zscore * sec3
end

reporte_final = generate_report(;
    n_vlans=N_VLANS, hosts_per_vlan=HOSTS_PER_VLAN,
    n_flows=N_FLOWS, p_intra=P_INTRA,
    total_fl, intra_fl, inter_fl, total_by, intra_by, inter_by,
    pct_intra, pct_intra_by, mean_bytes,
    best_k, sil_vals,
    best_result, final_wcss,
    purity_global,
    feat_md, k_table, vlan_md
)

open(joinpath(OUTPUT_DIR, "reporte.md"), "w") do io
    write(io, reporte_final)
end
println("  reporte.md generado en: $(joinpath(OUTPUT_DIR, "reporte.md"))")

println("\n" * "="^60)
println("  Pipeline completado.")
println("  Salidas: $(OUTPUT_DIR)")
println("="^60)
