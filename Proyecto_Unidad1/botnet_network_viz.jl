using Graphs
using Plots
using Statistics
using Printf
using DecisionTree
using Random

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

function parse_label(raw::AbstractString)
    m = match(r"(?i)\b(malicious|benign)\b", raw)
    isnothing(m) && return "other"
    return lowercase(m.captures[1])
end

function main(; seed::Int = 42)
    cap_name = capture_name()
    cap_path = capture_path(cap_name)
    isfile(cap_path) || error("No se encontro archivo: $(cap_path)")

    # Por cada IP acumular estadísticas bidireccionales
    out_total  = Dict{String,Int}()   # conexiones salientes
    in_total   = Dict{String,Int}()   # conexiones entrantes
    out_mal    = Dict{String,Int}()   # salientes etiquetadas malicious
    in_mal     = Dict{String,Int}()   # entrantes etiquetadas malicious
    out_ports  = Dict{String,Set{Int}}()  # puertos destino usados por src
    in_ports   = Dict{String,Set{Int}}()  # puertos destino recibidos por dst
    out_bytes  = Dict{String,Float64}()
    in_bytes   = Dict{String,Float64}()
    edge_freq  = Dict{Tuple{String,String},Int}()
    edge_mal   = Dict{Tuple{String,String},Int}()
    ip_votes   = Dict{String,Dict{String,Int}}()
    all_ips    = Set{String}()

    n_read = 0
    open(cap_path, "r") do fh
        for line in eachline(fh)
            startswith(line, '#') && continue
            n_read += 1

            cols = split(line, '\t')
            length(cols) < 21 && continue

            src   = cols[3]
            dst   = cols[5]
            dport = tryparse(Int, cols[6])
            obytes = tryparse(Float64, cols[10])
            rbytes = tryparse(Float64, cols[11])
            label = parse_label(cols[21])

            push!(all_ips, src)
            push!(all_ips, dst)

            # Conteos salientes (src)
            out_total[src] = get(out_total, src, 0) + 1
            if label == "malicious"
                out_mal[src] = get(out_mal, src, 0) + 1
            end
            if !haskey(out_ports, src); out_ports[src] = Set{Int}(); end
            !isnothing(dport) && push!(out_ports[src], dport)
            out_bytes[src] = get(out_bytes, src, 0.0) + (isnothing(obytes) ? 0.0 : obytes)

            # Conteos entrantes (dst)
            in_total[dst] = get(in_total, dst, 0) + 1
            if label == "malicious"
                in_mal[dst] = get(in_mal, dst, 0) + 1
            end
            if !haskey(in_ports, dst); in_ports[dst] = Set{Int}(); end
            !isnothing(dport) && push!(in_ports[dst], dport)
            in_bytes[dst] = get(in_bytes, dst, 0.0) + (isnothing(rbytes) ? 0.0 : rbytes)

            # Votos gt por ip src
            if !haskey(ip_votes, src); ip_votes[src] = Dict("malicious"=>0,"benign"=>0,"other"=>0); end
            ip_votes[src][label] = get(ip_votes[src], label, 0) + 1

            edge = (src, dst)
            edge_freq[edge] = get(edge_freq, edge, 0) + 1
            if label == "malicious"
                edge_mal[edge] = get(edge_mal, edge, 0) + 1
            end
        end
    end

    ips = sort(collect(all_ips))
    n   = length(ips)
    n == 0 && error("No hay nodos")

    ip_idx = Dict(ip => i for (i, ip) in enumerate(ips))

    # Grafo no dirigido para centralidad de grado
    g = SimpleGraph(n)
    for ((s, d), _) in edge_freq
        if haskey(ip_idx, s) && haskey(ip_idx, d) && s != d
            add_edge!(g, ip_idx[s], ip_idx[d])
        end
    end

    # --- Features por nodo ---
    # f1: tasa salientes malicious
    f_out_mal_rate = [begin
        t = get(out_total, ip, 0)
        t > 0 ? get(out_mal, ip, 0) / t : 0.0
    end for ip in ips]

    # f2: tasa entrantes malicious
    f_in_mal_rate = [begin
        t = get(in_total, ip, 0)
        t > 0 ? get(in_mal, ip, 0) / t : 0.0
    end for ip in ips]

    # f3: grado normalizado
    deg_raw = [degree(g, ip_idx[ip]) for ip in ips]
    max_deg = max(maximum(deg_raw), 1)
    f_deg = deg_raw ./ max_deg

    # f4: puertos destino únicos salientes (normalizado)
    op = [haskey(out_ports, ip) ? length(out_ports[ip]) : 0 for ip in ips]
    max_op = max(maximum(op), 1)
    f_out_ports = op ./ max_op

    # f5: puertos destino únicos entrantes (normalizado)
    ip2 = [haskey(in_ports, ip) ? length(in_ports[ip]) : 0 for ip in ips]
    max_ip2 = max(maximum(ip2), 1)
    f_in_ports = ip2 ./ max_ip2

    # f6: ratio out_bytes / (in_bytes+1) — botnet suele enviar mas de lo que recibe
    f_byte_ratio = [log1p(get(out_bytes, ip, 0.0)) / log1p(get(in_bytes, ip, 0.0) + 1.0) for ip in ips]
    max_br = max(maximum(f_byte_ratio), 1.0)
    f_byte_ratio ./= max_br

    # f7: fan-out: destinos únicos / conexiones totales salientes
    f_fanout = [begin
        tot = get(out_total, ip, 0)
        tot > 0 ? length(get(out_ports, ip, Set())) / tot : 0.0
    end for ip in ips]

    X = Float32.(hcat(f_out_mal_rate, f_in_mal_rate, f_deg, f_out_ports, f_in_ports, f_byte_ratio, f_fanout))

    # Ground truth: mayoría de votos en conexiones salientes
    gt_label = Vector{String}(undef, n)
    for (i, ip) in enumerate(ips)
        votes = get(ip_votes, ip, Dict("malicious"=>0,"benign"=>0,"other"=>0))
        if get(votes,"malicious",0) > get(votes,"benign",0)
            gt_label[i] = "malicious"
        elseif get(votes,"benign",0) > get(votes,"malicious",0)
            gt_label[i] = "benign"
        else
            gt_label[i] = "other"
        end
    end

    # Solo nodos con label conocido (malicious o benign) para entrenar
    known_idx = findall(x -> x ∈ ("malicious","benign"), gt_label)
    length(known_idx) < 10 && error("Muy pocos nodos etiquetados: $(length(known_idx))")

    # Split estratificado 70/30: asegura botnet en ambas particiones
    Random.seed!(seed)
    bot_known = filter(i -> gt_label[i] == "malicious", known_idx)
    ben_known = filter(i -> gt_label[i] == "benign",    known_idx)

    shuffle!(bot_known); shuffle!(ben_known)
    n_bot_train = max(1, round(Int, 0.70 * length(bot_known)))
    n_ben_train = round(Int, 0.70 * length(ben_known))

    train_idx = vcat(bot_known[1:n_bot_train], ben_known[1:n_ben_train])
    test_idx  = vcat(
        length(bot_known) > n_bot_train ? bot_known[n_bot_train+1:end] : Int[],
        ben_known[n_ben_train+1:end]
    )

    # Oversample botnet en train para balancear
    n_bot = sum(gt_label[train_idx] .== "malicious")
    n_ben = sum(gt_label[train_idx] .== "benign")
    if n_bot > 0 && n_bot < n_ben
        bot_t = filter(i -> gt_label[i] == "malicious", train_idx)
        ratio = div(n_ben, n_bot)
        train_idx = vcat(train_idx, repeat(bot_t, ratio - 1))
    end

    X_train = X[train_idx, :]
    y_train = gt_label[train_idx]
    X_test  = X[test_idx, :]
    y_test  = gt_label[test_idx]

    # Entrenar Random Forest
    model = DecisionTree.RandomForestClassifier(n_trees=200, max_depth=10, min_samples_leaf=1)
    DecisionTree.fit!(model, X_train, y_train)

    y_pred = DecisionTree.predict(model, X_test)

    # Métricas
    acc = mean(y_pred .== y_test)
    tp = sum((y_pred .== "malicious") .& (y_test .== "malicious"))
    fp = sum((y_pred .== "malicious") .& (y_test .!= "malicious"))
    fn = sum((y_pred .!= "malicious") .& (y_test .== "malicious"))
    precision = tp / max(tp + fp, 1)
    recall    = tp / max(tp + fn, 1)
    f1        = 2 * precision * recall / max(precision + recall, 1e-9)

    println("\n=== Modelo: Random Forest (100 árboles) ===")
    println("  Nodos etiquetados (conocidos): ", length(known_idx))
    println("  Train: ", length(train_idx), "  Test: ", length(test_idx))
    println("  Accuracy:  ", round(acc*100, digits=2), "%")
    println("  Precision: ", round(precision*100, digits=2), "%")
    println("  Recall:    ", round(recall*100, digits=2), "%")
    println("  F1-score:  ", round(f1*100, digits=2), "%")

    # Predecir TODO el grafo
    y_all = DecisionTree.predict(model, X)
    bot_idx = findall(==("malicious"), y_all)
    gt_bot  = findall(==("malicious"), gt_label)

    println("\n  Nodos predichos botnet (todos): ", length(bot_idx))
    println("  Nodos GT botnet:               ", length(gt_bot))

    # --- Visualización: solo nodos predichos botnet + vecinos directos ---
    neigh_idx = Set{Int}()
    for i in bot_idx
        push!(neigh_idx, i)
        for nb in neighbors(g, ip_idx[ips[i]])
            push!(neigh_idx, nb)
        end
    end
    vis_idx = sort(collect(neigh_idx))[1:min(300, length(neigh_idx))]

    old2new = Dict(old => new for (new, old) in enumerate(vis_idx))
    gvis    = SimpleGraph(length(vis_idx))
    for e in edges(g)
        s = src(e); d = dst(e)
        if haskey(old2new, s) && haskey(old2new, d)
            add_edge!(gvis, old2new[s], old2new[d])
        end
    end

    nvis = length(vis_idx)
    if nvis == 0
        println("  Sin nodos para visualizar.")
        return
    end
    ang  = nvis > 1 ? range(0, 2pi, length=nvis+1)[1:end-1] : [0.0]
    xc   = cos.(ang)
    yc   = sin.(ang)

    p = plot(
        xlims=(-1.3,1.3), ylims=(-1.3,1.3),
        legend=:bottomleft, aspect_ratio=:equal,
        axis=false, grid=false, size=(1200,900),
        background_color=:white,
        title="$(cap_name) — Predicción Botnet (RF)\nRojo★=predicho botnet | Verde◆=GT botnet | Azul●=vecinos",
    )

    # Suprimir hub si domina aristas
    deg_vis  = [degree(gvis, i) for i in 1:nvis]
    hub_loc  = argmax(deg_vis)
    suppress = deg_vis[hub_loc] / max(ne(gvis),1) > 0.3

    for e in edges(gvis)
        u = src(e); v = dst(e)
        (suppress && (u==hub_loc || v==hub_loc)) && continue
        plot!(p, [xc[u],xc[v]], [yc[u],yc[v]], color=:gray80, lw=0.4, alpha=0.4, label="")
    end

    bot_local  = [j for (j,i) in enumerate(vis_idx) if y_all[i]=="malicious" && gt_label[i]!="malicious"]
    gt_local   = [j for (j,i) in enumerate(vis_idx) if gt_label[i]=="malicious"]
    rest_local = [j for (j,i) in enumerate(vis_idx) if y_all[i]!="malicious" && gt_label[i]!="malicious"]

    !isempty(rest_local) && scatter!(p, xc[rest_local], yc[rest_local],
        marker=(:circle,3), color=:steelblue, markerstrokewidth=0, alpha=0.7, label="Vecinos")
    !isempty(bot_local) && scatter!(p, xc[bot_local], yc[bot_local],
        marker=(:star5,7), color=:crimson, markerstrokewidth=0, alpha=1.0, label="Pred botnet")
    !isempty(gt_local) && scatter!(p, xc[gt_local], yc[gt_local],
        marker=(:diamond,7), color=:green, markerstrokewidth=0.5, alpha=1.0, label="GT botnet")

    tag     = tagify(cap_name)
    out_png = joinpath(FIGURES_DIR, "botnet_$(tag)_red_botnet.png")
    savefig(p, out_png)
    println("\n  Figura: ", out_png)

    # --- Análisis por arista (cada fila = ocurrencia de arista) ---
    # score_edge prioriza tasa maliciosa y soporte (peso) para evitar sesgo por singleton.
    edge_rows = Vector{NamedTuple{(:src,:dst,:weight,:mal_count,:mal_ratio,:score_edge),
        Tuple{String,String,Int,Int,Float64,Float64}}}()
    for ((s, d), w) in edge_freq
        m = get(edge_mal, (s, d), 0)
        mal_ratio = w > 0 ? (m / w) : 0.0
        score_edge = ((m + 1.0) / (w + 2.0)) * log1p(w)
        push!(edge_rows, (src=s, dst=d, weight=w, mal_count=m, mal_ratio=mal_ratio, score_edge=score_edge))
    end

    sort!(edge_rows; by = r -> (r.score_edge, r.mal_ratio, r.mal_count, r.weight), rev = true)

    out_edges_csv = joinpath(TABLES_DIR, "botnet_$(tag)_aristas_ponderadas.csv")
    open(out_edges_csv, "w") do io
        println(io, "src,dst,weight,mal_count,mal_ratio,score_edge")
        for r in edge_rows
            @printf(io, "%s,%s,%d,%d,%.6f,%.6f\n", r.src, r.dst, r.weight, r.mal_count, r.mal_ratio, r.score_edge)
        end
    end

    top_edge_by_src = Dict{String,NamedTuple{(:src,:dst,:weight,:mal_count,:mal_ratio,:score_edge),
        Tuple{String,String,Int,Int,Float64,Float64}}}()
    for r in edge_rows
        if !haskey(top_edge_by_src, r.src)
            top_edge_by_src[r.src] = r
            continue
        end
        cur = top_edge_by_src[r.src]
        if (r.score_edge > cur.score_edge) ||
           (r.score_edge == cur.score_edge && r.mal_ratio > cur.mal_ratio) ||
           (r.score_edge == cur.score_edge && r.mal_ratio == cur.mal_ratio && r.mal_count > cur.mal_count) ||
           (r.score_edge == cur.score_edge && r.mal_ratio == cur.mal_ratio && r.mal_count == cur.mal_count && r.weight > cur.weight)
            top_edge_by_src[r.src] = r
        end
    end

    top_src_rows = collect(values(top_edge_by_src))
    sort!(top_src_rows; by = r -> (r.score_edge, r.mal_ratio, r.mal_count, r.weight), rev = true)

    out_top_src_csv = joinpath(TABLES_DIR, "botnet_$(tag)_arista_mas_maliciosa_por_src.csv")
    open(out_top_src_csv, "w") do io
        println(io, "src,best_dst,weight,mal_count,mal_ratio,score_edge")
        for r in top_src_rows
            @printf(io, "%s,%s,%d,%d,%.6f,%.6f\n", r.src, r.dst, r.weight, r.mal_count, r.mal_ratio, r.score_edge)
        end
    end

    # CSV con predicciones
    out_csv = joinpath(TABLES_DIR, "botnet_$(tag)_nodos_botnet.csv")
    open(out_csv, "w") do io
        println(io, "ip,gt_label,pred_label,out_mal_rate,in_mal_rate,degree_norm,out_ports,in_ports,byte_ratio,fanout")
        for i in sortperm(f_out_mal_rate, rev=true)
            @printf(io, "%s,%s,%s,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n",
                ips[i], gt_label[i], y_all[i],
                f_out_mal_rate[i], f_in_mal_rate[i], f_deg[i],
                f_out_ports[i], f_in_ports[i], f_byte_ratio[i], f_fanout[i])
        end
    end
    println("  CSV: ", out_csv)
    println("  CSV aristas ponderadas: ", out_edges_csv)
    println("  CSV mejor arista por src: ", out_top_src_csv)
    println("\nFilas leidas: ", n_read, "  Nodos totales: ", n)
end

main()
