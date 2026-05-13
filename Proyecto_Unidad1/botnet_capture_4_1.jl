using Graphs
using GraphRecipes
using Plots
using Statistics
using Printf

# Analisis focalizado de una captura IoT-23.
# Genera:
# 1) Figura de red con nodos seleccionados.
# 2) CSV con nodos botnet (ground truth) y sospechosos (z-score).

const BASE_IOT_PATH = joinpath(
    @__DIR__,
    "iot_23_datasets_small",
    "opt", "Malware-Project", "BigDataset", "IoTScenarios",
)

const RESULTS_DIR = joinpath(@__DIR__, "results")
const FIGURES_DIR = joinpath(RESULTS_DIR, "figures")
const TABLES_DIR = joinpath(RESULTS_DIR, "csv")

for dir in (FIGURES_DIR, TABLES_DIR)
    mkpath(dir)
end

capture_name() = length(ARGS) >= 1 ? ARGS[1] : "CTU-Honeypot-Capture-4-1"
capture_path(name::String) = joinpath(BASE_IOT_PATH, name, "bro", "conn.log.labeled")
tagify(name::String) = replace(name, r"[^A-Za-z0-9]+" => "_")
view_mode() = length(ARGS) >= 4 ? lowercase(ARGS[4]) : "focus"

function parse_label(raw::AbstractString)
    m = match(r"(?i)\b(malicious|benign)\b", raw)
    isnothing(m) && return "other"
    return lowercase(m.captures[1])
end

function main(; umbral_z::Float64 = 1.5, max_lines::Int = typemax(Int), min_conex::Int = 2)
    cap_name = capture_name()
    cap_path = capture_path(cap_name)
    isfile(cap_path) || error("No se encontro archivo: $(cap_path)")

    ip_total = Dict{String,Int}()
    ip_mal = Dict{String,Int}()
    ip_ports = Dict{String,Set{Int}}()
    edge_freq = Dict{Tuple{String,String},Int}()
    ip_votes = Dict{String,Dict{String,Int}}()
    all_ips = Set{String}()

    n_read = 0
    open(cap_path, "r") do fh
        for line in eachline(fh)
            startswith(line, '#') && continue
            n_read += 1
            n_read > max_lines && break

            cols = split(line, '\t')
            length(cols) < 21 && continue

            src = cols[3]
            dst = cols[5]
            p = tryparse(Int, cols[6])
            label = parse_label(cols[21])

            push!(all_ips, src)
            push!(all_ips, dst)

            ip_total[src] = get(ip_total, src, 0) + 1
            if !haskey(ip_ports, src)
                ip_ports[src] = Set{Int}()
            end
            if !isnothing(p)
                push!(ip_ports[src], p)
            end
            if !haskey(ip_votes, src)
                ip_votes[src] = Dict("malicious" => 0, "benign" => 0, "other" => 0)
            end
            ip_votes[src][label] = get(ip_votes[src], label, 0) + 1
            if label == "malicious"
                ip_mal[src] = get(ip_mal, src, 0) + 1
            end

            edge = (src, dst)
            edge_freq[edge] = get(edge_freq, edge, 0) + 1
        end
    end

    ips = sort([ip for ip in all_ips if get(ip_total, ip, 0) >= min_conex || get(ip_total, ip, 0) == 0])
    n = length(ips)
    n == 0 && error("No hay nodos para analizar")

    ip_idx = Dict(ip => i for (i, ip) in enumerate(ips))
    g = SimpleGraph(n)
    for ((s, d), _) in edge_freq
        if haskey(ip_idx, s) && haskey(ip_idx, d) && s != d
            add_edge!(g, ip_idx[s], ip_idx[d])
        end
    end

    dc = [degree(g, ip_idx[ip]) / max(n - 1, 1) for ip in ips]
    pct_mal = [get(ip_total, ip, 0) > 0 ? get(ip_mal, ip, 0) / ip_total[ip] : 0.0 for ip in ips]
    n_ports = [haskey(ip_ports, ip) ? length(ip_ports[ip]) : 0 for ip in ips]
    max_ports = maximum(n_ports)
    ports_n = max_ports > 0 ? n_ports ./ max_ports : zeros(Float64, n)

    score = [0.50 * pct_mal[i] + 0.35 * dc[i] + 0.15 * ports_n[i] for i in 1:n]
    mu = mean(score)
    sigma = std(score, corrected = false)
    z = sigma > 0 ? (score .- mu) ./ sigma : zeros(n)

    gt_label = Vector{String}(undef, n)
    for (i, ip) in enumerate(ips)
        votes = get(ip_votes, ip, Dict("malicious" => 0, "benign" => 0, "other" => 0))
        if get(votes, "malicious", 0) > get(votes, "benign", 0)
            gt_label[i] = "malicious"
        elseif get(votes, "benign", 0) > get(votes, "malicious", 0)
            gt_label[i] = "benign"
        else
            gt_label[i] = "other"
        end
    end

    idx_gt = findall(==("malicious"), gt_label)
    idx_z = findall(>(umbral_z), z)

    mode = view_mode()
    if mode == "full"
        vis_idx = collect(1:n)
    else
        top_z = sortperm(z, rev = true)[1:min(120, n)]
        vis_idx = sort(unique(vcat(idx_gt, idx_z, top_z)))
    end
    old2new = Dict(old => new for (new, old) in enumerate(vis_idx))

    gvis = SimpleGraph(length(vis_idx))
    for e in edges(g)
        s = src(e)
        d = dst(e)
        if haskey(old2new, s) && haskey(old2new, d)
            add_edge!(gvis, old2new[s], old2new[d])
        end
    end

    # Dibujo manual de red para mantener compatibilidad entre versiones de paquetes.
    nvis = length(vis_idx)
    ang = range(0, 2pi, length = nvis + 1)[1:end-1]
    x = cos.(ang)
    y = sin.(ang)

    p = plot(
        xlims = (-1.2, 1.2),
        ylims = (-1.2, 1.2),
        legend = :bottomleft,
        aspect_ratio = :equal,
        axis = false,
        grid = false,
        size = (1200, 900),
        background_color = :white,
        title = "$(cap_name) [$(uppercase(mode))]\nRojo★=GT malicious | Naranja◆=z > $(umbral_z) | Azul●=resto",
    )

    edge_alpha = mode == "full" ? 0.10 : 0.50
    edge_lw = mode == "full" ? 0.20 : 0.40
    for e in edges(gvis)
        u = src(e)
        v = dst(e)
        plot!(p, [x[u], x[v]], [y[u], y[v]], color = :gray75, lw = edge_lw, alpha = edge_alpha, label = "")
    end

    mal_local = [j for (j, i) in enumerate(vis_idx) if gt_label[i] == "malicious"]
    z_local = [j for (j, i) in enumerate(vis_idx) if gt_label[i] != "malicious" && z[i] > umbral_z]
    b_local = [j for (j, i) in enumerate(vis_idx) if gt_label[i] != "malicious" && z[i] <= umbral_z]

    msz_rest = mode == "full" ? 1.4 : 4
    msz_z = mode == "full" ? 2.0 : 6
    msz_gt = mode == "full" ? 2.4 : 8
    if !isempty(b_local)
        scatter!(p, x[b_local], y[b_local], marker = (:circle, msz_rest), color = :steelblue,
            markerstrokewidth = 0, alpha = 0.9, label = "Resto")
    end
    if !isempty(z_local)
        scatter!(p, x[z_local], y[z_local], marker = (:diamond, msz_z), color = :darkorange,
            markerstrokewidth = 0, alpha = 0.95, label = "z-score")
    end
    if !isempty(mal_local)
        scatter!(p, x[mal_local], y[mal_local], marker = (:star5, msz_gt), color = :crimson,
            markerstrokewidth = 0, alpha = 1.0, label = "GT malicious")
    end

    tag = tagify(cap_name)
    out_png = joinpath(FIGURES_DIR, "botnet_$(tag)_red_$(mode).png")
    savefig(p, out_png)

    out_csv = joinpath(TABLES_DIR, "botnet_$(tag)_nodos_botnet.csv")
    open(out_csv, "w") do io
        println(io, "ip,gt_label,score,zscore,degree_centrality,pct_malicious,unique_ports,selected_by")
        idx_order = sortperm(score, rev = true)
        for i in idx_order
            selected_by =
                (gt_label[i] == "malicious" && z[i] > umbral_z) ? "GT_AND_ZSCORE" :
                (gt_label[i] == "malicious") ? "GT_BOTNET" :
                (z[i] > umbral_z) ? "ZSCORE" : "NO"

            if selected_by != "NO"
                @printf(io, "%s,%s,%.6f,%.6f,%.6f,%.6f,%d,%s\n",
                    ips[i], gt_label[i], score[i], z[i], dc[i], pct_mal[i], n_ports[i], selected_by)
            end
        end
    end

    println("Resumen $(cap_name)")
    println("  Filas leidas: ", n_read)
    println("  Nodos (IPs): ", n)
    println("  Aristas: ", ne(g))
    println("  Modo visual: ", mode)
    println("  Nodos visualizados: ", length(vis_idx))
    println("  Nodos GT malicious: ", length(idx_gt))
    println("  Nodos z-score > $(umbral_z): ", length(idx_z))
    println("  Figura: ", out_png)
    println("  CSV: ", out_csv)
end

arg_max = length(ARGS) >= 2 ? tryparse(Int, ARGS[2]) : nothing
arg_z = length(ARGS) >= 3 ? tryparse(Float64, ARGS[3]) : nothing

main(
    max_lines = isnothing(arg_max) ? typemax(Int) : arg_max,
    umbral_z = isnothing(arg_z) ? 1.5 : arg_z,
)
