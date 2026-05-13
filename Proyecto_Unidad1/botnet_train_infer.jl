using DecisionTree
using Statistics
using Random
using Printf
using Serialization
using Plots
using Graphs

const BASE_IOT_PATH = joinpath(
    @__DIR__,
    "iot_23_datasets_small",
    "opt", "Malware-Project", "BigDataset", "IoTScenarios",
)

const RESULTS_DIR = joinpath(@__DIR__, "results")
const FIGURES_DIR = joinpath(RESULTS_DIR, "figures")
const TABLES_DIR = joinpath(RESULTS_DIR, "csv")
const MODELS_DIR = joinpath(RESULTS_DIR, "models")
const REPORTS_DIR = joinpath(@__DIR__, "reports")

for dir in (FIGURES_DIR, TABLES_DIR, MODELS_DIR, REPORTS_DIR)
    mkpath(dir)
end

capture_path(name::String) = joinpath(BASE_IOT_PATH, name, "bro", "conn.log.labeled")
tagify(name::String) = replace(name, r"[^A-Za-z0-9]+" => "_")

function parse_label(raw::AbstractString)
    m = match(r"(?i)\b(malicious|benign)\b", raw)
    isnothing(m) && return "other"
    return lowercase(m.captures[1])
end

function parse_capture_list(raw::String)
    parts = [String(strip(x)) for x in split(raw, ',') if !isempty(strip(x))]
    isempty(parts) && error("Debes indicar al menos una captura separada por comas")
    return parts
end

function safe_div(a::Real, b::Real)
    b == 0 && return 0.0
    return float(a) / float(b)
end

function count_data_lines(cap_path::String)
    n = 0
    open(cap_path, "r") do fh
        for line in eachline(fh)
            startswith(line, '#') && continue
            n += 1
        end
    end
    return n
end

function allocate_quotas(total::Int, max_lines::Int, n_strata::Int)
    n = max(1, n_strata)
    starts = [floor(Int, ((k - 1) * total) / n) + 1 for k in 1:n]
    ends = [floor(Int, (k * total) / n) for k in 1:n]
    spans = [max(0, ends[k] - starts[k] + 1) for k in 1:n]

    raw = [max_lines * (spans[k] / max(total, 1)) for k in 1:n]
    quotas = [floor(Int, raw[k]) for k in 1:n]
    rem = max_lines - sum(quotas)

    order = sortperm([raw[k] - quotas[k] for k in 1:n], rev=true)
    for k in order
        rem <= 0 && break
        if quotas[k] < spans[k]
            quotas[k] += 1
            rem -= 1
        end
    end

    return starts, ends, spans, quotas
end

function build_stratified_selection(total::Int, max_lines::Int, n_strata::Int)
    selected = Set{Int}()
    total <= max_lines && return selected

    starts, ends, spans, quotas = allocate_quotas(total, max_lines, n_strata)
    for k in eachindex(starts)
        q = min(quotas[k], spans[k])
        q <= 0 && continue

        s0 = starts[k]
        span = spans[k]
        for j in 0:q-1
            pos = s0 + floor(Int, ((j + 0.5) * span) / q)
            pos = clamp(pos, starts[k], ends[k])
            push!(selected, pos)
        end
    end

    return selected
end

function extract_features(cap_name::String; max_lines::Int = 250_000, sampling::Symbol = :stratified, n_strata::Int = 20)
    cap_path = capture_path(cap_name)
    isfile(cap_path) || error("No se encontro archivo: $(cap_path)")

    total_data_lines = count_data_lines(cap_path)
    selected_lines = Set{Int}()
    sampling_used = sampling

    if max_lines > 0 && total_data_lines > max_lines
        if sampling == :stratified
            selected_lines = build_stratified_selection(total_data_lines, max_lines, n_strata)
        else
            sampling_used = :head
        end
    end

    out_total = Dict{String,Int}()
    in_total = Dict{String,Int}()
    out_mal = Dict{String,Int}()
    in_mal = Dict{String,Int}()
    out_ports = Dict{String,Set{Int}}()
    in_ports = Dict{String,Set{Int}}()
    out_bytes = Dict{String,Float64}()
    in_bytes = Dict{String,Float64}()
    neigh = Dict{String,Set{String}}()
    ip_votes = Dict{String,Dict{String,Int}}()
    all_ips = Set{String}()
    edge_freq = Dict{Tuple{String,String},Int}()
    edge_mal = Dict{Tuple{String,String},Int}()

    n_read = 0
    data_idx = 0
    open(cap_path, "r") do fh
        for line in eachline(fh)
            startswith(line, '#') && continue
            data_idx += 1

            if total_data_lines > max_lines && max_lines > 0
                if sampling_used == :stratified
                    !(data_idx in selected_lines) && continue
                elseif sampling_used == :head
                    data_idx > max_lines && break
                end
            end
            n_read += 1

            cols = split(line, '\t')
            length(cols) < 21 && continue

            src = cols[3]
            dst = cols[5]
            dport = tryparse(Int, cols[6])
            obytes = tryparse(Float64, cols[10])
            rbytes = tryparse(Float64, cols[11])
            label = parse_label(cols[21])

            push!(all_ips, src)
            push!(all_ips, dst)

            out_total[src] = get(out_total, src, 0) + 1
            in_total[dst] = get(in_total, dst, 0) + 1

            if label == "malicious"
                out_mal[src] = get(out_mal, src, 0) + 1
                in_mal[dst] = get(in_mal, dst, 0) + 1
            end

            if !haskey(out_ports, src)
                out_ports[src] = Set{Int}()
            end
            if !haskey(in_ports, dst)
                in_ports[dst] = Set{Int}()
            end
            if !isnothing(dport)
                push!(out_ports[src], dport)
                push!(in_ports[dst], dport)
            end

            out_bytes[src] = get(out_bytes, src, 0.0) + (isnothing(obytes) ? 0.0 : obytes)
            in_bytes[dst] = get(in_bytes, dst, 0.0) + (isnothing(rbytes) ? 0.0 : rbytes)

            if !haskey(neigh, src)
                neigh[src] = Set{String}()
            end
            if !haskey(neigh, dst)
                neigh[dst] = Set{String}()
            end
            if src != dst
                push!(neigh[src], dst)
                push!(neigh[dst], src)
            end

            if !haskey(ip_votes, src)
                ip_votes[src] = Dict("malicious" => 0, "benign" => 0, "other" => 0)
            end
            ip_votes[src][label] = get(ip_votes[src], label, 0) + 1

            e = (src, dst)
            edge_freq[e] = get(edge_freq, e, 0) + 1
            if label == "malicious"
                edge_mal[e] = get(edge_mal, e, 0) + 1
            end
        end
    end

    ips = sort(collect(all_ips))
    isempty(ips) && error("No hay nodos en $(cap_name)")

    f_out_mal_rate = [safe_div(get(out_mal, ip, 0), get(out_total, ip, 0)) for ip in ips]
    f_in_mal_rate = [safe_div(get(in_mal, ip, 0), get(in_total, ip, 0)) for ip in ips]

    deg_raw = [haskey(neigh, ip) ? length(neigh[ip]) : 0 for ip in ips]
    max_deg = max(maximum(deg_raw), 1)
    f_deg = deg_raw ./ max_deg

    op = [haskey(out_ports, ip) ? length(out_ports[ip]) : 0 for ip in ips]
    max_op = max(maximum(op), 1)
    f_out_ports = op ./ max_op

    ip2 = [haskey(in_ports, ip) ? length(in_ports[ip]) : 0 for ip in ips]
    max_ip2 = max(maximum(ip2), 1)
    f_in_ports = ip2 ./ max_ip2

    f_byte_ratio = [log1p(get(out_bytes, ip, 0.0)) / log1p(get(in_bytes, ip, 0.0) + 1.0) for ip in ips]
    max_br = max(maximum(f_byte_ratio), 1.0)
    f_byte_ratio ./= max_br

    f_fanout = [begin
        tot = get(out_total, ip, 0)
        tot > 0 ? safe_div(haskey(out_ports, ip) ? length(out_ports[ip]) : 0, tot) : 0.0
    end for ip in ips]

    X = Float32.(hcat(f_out_mal_rate, f_in_mal_rate, f_deg, f_out_ports, f_in_ports, f_byte_ratio, f_fanout))

    gt_label = Vector{String}(undef, length(ips))
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

    risk_score = [
        min(1.0,
            0.35 * f_out_mal_rate[i] +
            0.15 * f_in_mal_rate[i] +
            0.20 * f_out_ports[i] +
            0.10 * f_fanout[i] +
            0.20 * f_byte_ratio[i]
        ) for i in eachindex(ips)
    ]

    return (
        cap_name = cap_name,
        n_read = n_read,
        total_data_lines = total_data_lines,
        sampling = String(sampling_used),
        n_strata = n_strata,
        ips = ips,
        X = X,
        gt_label = gt_label,
        risk_score = risk_score,
        edge_freq = edge_freq,
        edge_mal = edge_mal,
        f_out_mal_rate = f_out_mal_rate,
        f_in_mal_rate = f_in_mal_rate,
        f_deg = f_deg,
        f_out_ports = f_out_ports,
        f_in_ports = f_in_ports,
        f_byte_ratio = f_byte_ratio,
        f_fanout = f_fanout,
    )
end

function train_mode(train_caps::Vector{String}; max_lines::Int = 250_000, seed::Int = 42, sampling::Symbol = :stratified, n_strata::Int = 20)
    println("\n=== Entrenamiento multi-captura ===")
    println("Capturas train: ", join(train_caps, ", "))
    println("Max lineas por captura: ", max_lines)
    println("Muestreo: ", sampling, "  Estratos: ", n_strata)

    X_parts = Matrix{Float32}[]
    y_all = String[]
    origin_cap = String[]

    for cap in train_caps
        feat = extract_features(cap; max_lines=max_lines, sampling=sampling, n_strata=n_strata)
        known_idx = findall(x -> x in ("malicious", "benign"), feat.gt_label)

        if isempty(known_idx)
            println("  [WARN] $(cap): sin nodos conocidos, se omite")
            continue
        end

        push!(X_parts, feat.X[known_idx, :])
        append!(y_all, feat.gt_label[known_idx])
        append!(origin_cap, fill(cap, length(known_idx)))

        n_mal = sum(feat.gt_label[known_idx] .== "malicious")
        n_ben = sum(feat.gt_label[known_idx] .== "benign")
        println("  $(cap): nodos usados=$(length(known_idx)) mal=$(n_mal) ben=$(n_ben) lineas_muestra=$(feat.n_read)/$(feat.total_data_lines)")
    end

    isempty(X_parts) && error("No hay datos suficientes para entrenar")

    X = vcat(X_parts...)
    y = copy(y_all)

    known_idx = collect(eachindex(y))
    Random.seed!(seed)

    bot_idx = filter(i -> y[i] == "malicious", known_idx)
    ben_idx = filter(i -> y[i] == "benign", known_idx)

    isempty(bot_idx) && error("No hay nodos malicious en train")
    isempty(ben_idx) && error("No hay nodos benign en train")

    shuffle!(bot_idx)
    shuffle!(ben_idx)

    n_bot_train = max(1, round(Int, 0.70 * length(bot_idx)))
    n_ben_train = max(1, round(Int, 0.70 * length(ben_idx)))

    train_idx = vcat(bot_idx[1:n_bot_train], ben_idx[1:n_ben_train])
    test_idx = vcat(
        length(bot_idx) > n_bot_train ? bot_idx[n_bot_train+1:end] : Int[],
        length(ben_idx) > n_ben_train ? ben_idx[n_ben_train+1:end] : Int[]
    )

    if isempty(test_idx)
        error("Test vacio. Usa mas datos de entrenamiento")
    end

    n_bot = sum(y[train_idx] .== "malicious")
    n_ben = sum(y[train_idx] .== "benign")
    if n_bot > 0 && n_bot < n_ben
        bot_t = filter(i -> y[i] == "malicious", train_idx)
        ratio = max(1, div(n_ben, n_bot))
        if ratio > 1
            train_idx = vcat(train_idx, repeat(bot_t, ratio - 1))
        end
    end

    X_train = X[train_idx, :]
    y_train = y[train_idx]
    X_test = X[test_idx, :]
    y_test = y[test_idx]

    model = DecisionTree.RandomForestClassifier(n_trees=250, max_depth=12, min_samples_leaf=1)
    DecisionTree.fit!(model, X_train, y_train)

    y_pred = DecisionTree.predict(model, X_test)

    acc = mean(y_pred .== y_test)
    tp = sum((y_pred .== "malicious") .& (y_test .== "malicious"))
    fp = sum((y_pred .== "malicious") .& (y_test .!= "malicious"))
    fn = sum((y_pred .!= "malicious") .& (y_test .== "malicious"))
    precision = safe_div(tp, tp + fp)
    recall = safe_div(tp, tp + fn)
    f1 = (precision + recall) > 0 ? 2 * precision * recall / (precision + recall) : 0.0

    println("\nMétricas holdout:")
    println("  Train: ", length(train_idx), "  Test: ", length(test_idx))
    println("  Accuracy:  ", round(acc * 100, digits=2), "%")
    println("  Precision: ", round(precision * 100, digits=2), "%")
    println("  Recall:    ", round(recall * 100, digits=2), "%")
    println("  F1-score:  ", round(f1 * 100, digits=2), "%")

    models_dir = MODELS_DIR
    mkpath(models_dir)

    train_tag = tagify(join(train_caps, "_"))
    model_path = joinpath(models_dir, "botnet_rf_$(train_tag)_ml$(max_lines).jls")

    state = Dict(
        "model" => model,
        "feature_names" => [
            "out_mal_rate",
            "in_mal_rate",
            "degree_norm",
            "out_ports_norm",
            "in_ports_norm",
            "byte_ratio_norm",
            "fanout",
        ],
        "train_caps" => train_caps,
        "max_lines" => max_lines,
        "sampling" => String(sampling),
        "n_strata" => n_strata,
        "seed" => seed,
        "metrics" => Dict(
            "accuracy" => acc,
            "precision" => precision,
            "recall" => recall,
            "f1" => f1,
            "train_size" => length(train_idx),
            "test_size" => length(test_idx),
        ),
    )

    serialize(model_path, state)
    println("\nModelo guardado: ", model_path)

    p = bar(
        ["train_mal", "train_ben", "test_mal", "test_ben"],
        [
            sum(y_train .== "malicious"),
            sum(y_train .== "benign"),
            sum(y_test .== "malicious"),
            sum(y_test .== "benign"),
        ],
        color = [:crimson, :steelblue, :orange, :seagreen],
        legend = false,
        xlabel = "Conjunto",
        ylabel = "Nodos",
        title = "Balance de clases en entrenamiento/validación",
        size = (1000, 650),
        background_color = :white,
    )

    plot_path = joinpath(FIGURES_DIR, "botnet_rf_$(train_tag)_proceso_train.png")
    savefig(p, plot_path)
    println("Grafico entrenamiento: ", plot_path)

    return model_path
end

function write_edge_reports(feat, tag::String)
    edge_rows = Vector{NamedTuple{(:src,:dst,:weight,:mal_count,:mal_ratio,:score_edge),Tuple{String,String,Int,Int,Float64,Float64}}}()

    for ((s, d), w) in feat.edge_freq
        m = get(feat.edge_mal, (s, d), 0)
        mal_ratio = safe_div(m, w)
        score_edge = ((m + 1.0) / (w + 2.0)) * log1p(w)
        push!(edge_rows, (src = s, dst = d, weight = w, mal_count = m, mal_ratio = mal_ratio, score_edge = score_edge))
    end

    sort!(edge_rows; by = r -> (r.score_edge, r.mal_ratio, r.mal_count, r.weight), rev = true)

    out_edges_csv = joinpath(TABLES_DIR, "botnet_$(tag)_aristas_ponderadas.csv")
    open(out_edges_csv, "w") do io
        println(io, "src,dst,weight,mal_count,mal_ratio,score_edge")
        for r in edge_rows
            @printf(io, "%s,%s,%d,%d,%.6f,%.6f\n", r.src, r.dst, r.weight, r.mal_count, r.mal_ratio, r.score_edge)
        end
    end

    top_edge_by_src = Dict{String,NamedTuple{(:src,:dst,:weight,:mal_count,:mal_ratio,:score_edge),Tuple{String,String,Int,Int,Float64,Float64}}}()
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

    return out_edges_csv, out_top_src_csv, edge_rows, top_src_rows
end

function write_network_graph(feat, y_pred, tag::String)
    ip_idx = Dict(ip => i for (i, ip) in enumerate(feat.ips))
    node_base = [feat.risk_score[i] + (y_pred[i] == "malicious" ? 0.35 : 0.0) for i in eachindex(feat.ips)]
    node_rank = sortperm(node_base, rev=true)
    top_nodes = node_rank[1:min(120, length(node_rank))]
    selected = Set(top_nodes)

    selected_edges = Vector{Tuple{Int,Int,Int,Int}}()
    for ((s, d), w) in feat.edge_freq
        if haskey(ip_idx, s) && haskey(ip_idx, d)
            u = ip_idx[s]
            v = ip_idx[d]
            if (u in selected) && (v in selected) && u != v
                m = get(feat.edge_mal, (s, d), 0)
                push!(selected_edges, (u, v, w, m))
            end
        end
    end

    if isempty(selected_edges)
        return ""
    end

    old_to_new = Dict(old => new for (new, old) in enumerate(collect(selected)))
    new_to_old = collect(selected)
    g = SimpleGraph(length(new_to_old))
    ew = Dict{Tuple{Int,Int},Tuple{Int,Int}}()

    for (u0, v0, w, m) in selected_edges
        u = old_to_new[u0]
        v = old_to_new[v0]
        if u != v
            add_edge!(g, u, v)
            key = u < v ? (u, v) : (v, u)
            if haskey(ew, key)
                prev_w, prev_m = ew[key]
                ew[key] = (prev_w + w, prev_m + m)
            else
                ew[key] = (w, m)
            end
        end
    end

    n = nv(g)
    ang = n > 1 ? range(0, 2pi, length=n+1)[1:end-1] : [0.0]
    xc = cos.(ang)
    yc = sin.(ang)

    p = plot(
        xlims=(-1.35, 1.35), ylims=(-1.35, 1.35),
        legend=:bottomleft, aspect_ratio=:equal,
        axis=false, grid=false,
        size=(1400, 950),
        background_color=:white,
        title="Grafo de red (inferencia transfer)\nRojo=pred botnet, Azul=otros, Arista roja=tiene trafico malicious",
    )

    max_w = 1
    for (_, (w, _)) in ew
        max_w = max(max_w, w)
    end

    for e in edges(g)
        u = src(e)
        v = dst(e)
        key = u < v ? (u, v) : (v, u)
        w, m = get(ew, key, (1, 0))
        lw = 0.4 + 2.8 * sqrt(safe_div(w, max_w))
        color_edge = m > 0 ? :orangered3 : :gray75
        alpha_edge = m > 0 ? 0.9 : 0.45
        plot!(p, [xc[u], xc[v]], [yc[u], yc[v]], color=color_edge, lw=lw, alpha=alpha_edge, label="")
    end

    mal_nodes = Int[]
    benign_nodes = Int[]
    for i in 1:n
        old_i = new_to_old[i]
        if y_pred[old_i] == "malicious"
            push!(mal_nodes, i)
        else
            push!(benign_nodes, i)
        end
    end

    !isempty(benign_nodes) && scatter!(p, xc[benign_nodes], yc[benign_nodes], marker=(:circle, 4), color=:steelblue, markerstrokewidth=0, alpha=0.8, label="No botnet")
    !isempty(mal_nodes) && scatter!(p, xc[mal_nodes], yc[mal_nodes], marker=(:star5, 9), color=:crimson, markerstrokewidth=0, alpha=1.0, label="Pred botnet")

    out_path = joinpath(FIGURES_DIR, "botnet_$(tag)_grafo_red_transfer.png")
    savefig(p, out_path)
    return out_path
end

function write_inference_report(model_path::String, state, feat, y_pred, cap_name::String, max_lines::Int, out_pred_csv::String, out_edges_csv::String, out_top_src_csv::String, out_plot::String, out_graph::String, edge_rows, top_src_rows)
    tag = tagify(cap_name)
    out_report = joinpath(REPORTS_DIR, "botnet_$(tag)_reporte_transfer.md")

    metrics = state["metrics"]
    train_caps = state["train_caps"]
    train_sampling = get(state, "sampling", "head")
    train_strata = get(state, "n_strata", 1)
    train_caps_str = join(train_caps, ", ")
    train_max_lines = state["max_lines"]
    train_seed = state["seed"]
    metric_acc = round(metrics["accuracy"] * 100, digits=2)
    metric_prec = round(metrics["precision"] * 100, digits=2)
    metric_rec = round(metrics["recall"] * 100, digits=2)
    metric_f1 = round(metrics["f1"] * 100, digits=2)
    pred_bot = sum(y_pred .== "malicious")
    gt_bot = sum(feat.gt_label .== "malicious")

    idx_top = sortperm(feat.risk_score, rev=true)[1:min(10, length(feat.ips))]
    top_ip_lines = String[]
    for i in idx_top
        push!(top_ip_lines,
            @sprintf("| %s | %s | %s | %.4f | %.4f | %.4f |",
                feat.ips[i], feat.gt_label[i], y_pred[i], feat.risk_score[i], feat.f_out_mal_rate[i], feat.f_byte_ratio[i]))
    end

    edge_top_lines = String[]
    for r in edge_rows[1:min(10, length(edge_rows))]
        push!(edge_top_lines,
            @sprintf("| %s | %s | %d | %d | %.4f | %.4f |", r.src, r.dst, r.weight, r.mal_count, r.mal_ratio, r.score_edge))
    end

    src_top_lines = String[]
    for r in top_src_rows[1:min(10, length(top_src_rows))]
        push!(src_top_lines,
            @sprintf("| %s | %s | %d | %d | %.4f | %.4f |", r.src, r.dst, r.weight, r.mal_count, r.mal_ratio, r.score_edge))
    end

    open(out_report, "w") do io
        println(io, "# Reporte de Detección de Botnet por Transferencia")
        println(io)
        println(io, "## 1. Objetivo")
        println(io, "El objetivo de este experimento es entrenar un clasificador de botnet con múltiples capturas y aplicar el modelo en una captura diferente, reduciendo el costo computacional mediante muestreo estratificado de líneas.")
        println(io)
        println(io, "## 2. Metodología")
        println(io, "- Modelo: Random Forest (DecisionTree.jl).")
        println(io, "- Variables por nodo: tasa saliente maliciosa, tasa entrante maliciosa, grado normalizado, diversidad de puertos salientes/entrantes, razón de bytes, fanout.")
        println(io, "- Etiqueta de referencia del nodo: mayoría de etiquetas salientes (malicious/benign).")
        println(io, "- Muestreo: estratificado por posición temporal de línea, para cubrir todo el archivo y evitar sesgo por prefijo.")
        println(io, "- Aristas ponderadas: cada línea representa una ocurrencia de arista src->dst; se agrega por par para calcular peso, conteo malicioso y score de arista.")
        println(io)
        println(io, "## 3. Configuración de Entrenamiento")
        println(io, "- Capturas de entrenamiento: $(train_caps_str).")
        println(io, "- Máximo de líneas por captura: $(train_max_lines).")
        println(io, "- Tipo de muestreo: $(train_sampling).")
        println(io, "- Número de estratos: $(train_strata).")
        println(io, "- Semilla: $(train_seed).")
        println(io)
        println(io, "### 3.1 Métricas holdout")
        println(io, "- Accuracy: $(metric_acc)%.")
        println(io, "- Precision: $(metric_prec)%.")
        println(io, "- Recall: $(metric_rec)%.")
        println(io, "- F1-score: $(metric_f1)%.")
        println(io)
        println(io, "## 4. Configuración de Inferencia")
        println(io, "- Modelo cargado: $(model_path).")
        println(io, "- Captura evaluada: $(cap_name).")
        println(io, "- Líneas procesadas (muestra): $(feat.n_read) de $(feat.total_data_lines).")
        println(io, "- Muestreo aplicado en inferencia: $(feat.sampling), estratos=$(feat.n_strata).")
        println(io, "- Nodos totales analizados: $(length(feat.ips)).")
        println(io, "- Nodos predichos como botnet: $(pred_bot).")
        println(io, "- Nodos botnet en etiqueta de referencia: $(gt_bot).")
        println(io)
        println(io, "## 5. Resultados: Nodos Más Sospechosos")
        println(io, "| IP | GT | Predicción | Risk score | Out malicious rate | Byte ratio |")
        println(io, "|---|---|---|---:|---:|---:|")
        for l in top_ip_lines
            println(io, l)
        end
        println(io)
        println(io, "## 6. Resultados: Aristas Ponderadas")
        println(io, "| Src | Dst | Peso | Mal count | Mal ratio | Score arista |")
        println(io, "|---|---|---:|---:|---:|---:|")
        for l in edge_top_lines
            println(io, l)
        end
        println(io)
        println(io, "## 7. Mejor Arista por IP Origen")
        println(io, "| Src | Mejor Dst | Peso | Mal count | Mal ratio | Score arista |")
        println(io, "|---|---|---:|---:|---:|---:|")
        for l in src_top_lines
            println(io, l)
        end
        println(io)
        println(io, "## 8. Artefactos Generados")
        println(io, "- Predicciones por nodo: $(out_pred_csv)")
        println(io, "- Aristas ponderadas: $(out_edges_csv)")
        println(io, "- Mejor arista por fuente: $(out_top_src_csv)")
        println(io, "- Gráfico de nodos sospechosos: $(out_plot)")
        if !isempty(out_graph)
            println(io, "- Grafo de red de inferencia: $(out_graph)")
        end
        println(io)
        println(io, "## 9. Conclusiones")
        println(io, "El pipeline permite entrenar en múltiples escenarios y transferir detección a nuevas capturas con costo controlado. El muestreo estratificado mejora la representatividad temporal frente al recorte por prefijo. La evidencia por arista ponderada facilita identificar, por cada IP origen, la ruta de comunicación con mayor probabilidad de actividad maliciosa.")
    end

    return out_report
end

function infer_mode(model_path::String, cap_name::String; max_lines::Int = 200_000, sampling::Symbol = :stratified, n_strata::Int = 20)
    isfile(model_path) || error("No se encontro modelo: $(model_path)")

    state = deserialize(model_path)
    model = state["model"]

    println("\n=== Inferencia en captura nueva ===")
    println("Modelo: ", model_path)
    println("Captura test: ", cap_name)
    println("Max lineas procesadas: ", max_lines)
    println("Muestreo: ", sampling, "  Estratos: ", n_strata)

    feat = extract_features(cap_name; max_lines=max_lines, sampling=sampling, n_strata=n_strata)
    y_pred = DecisionTree.predict(model, feat.X)

    n_pred_bot = sum(y_pred .== "malicious")
    n_gt_bot = sum(feat.gt_label .== "malicious")

    println("  Nodos totales: ", length(feat.ips))
    println("  Nodos predichos botnet: ", n_pred_bot)
    println("  Nodos GT botnet: ", n_gt_bot)

    tag = tagify(cap_name)
    out_pred_csv = joinpath(TABLES_DIR, "botnet_$(tag)_predicciones_transfer.csv")
    open(out_pred_csv, "w") do io
        println(io, "ip,gt_label,pred_label,risk_score,out_mal_rate,in_mal_rate,degree_norm,out_ports,in_ports,byte_ratio,fanout")
        idx = sortperm(feat.risk_score, rev=true)
        for i in idx
            @printf(io, "%s,%s,%s,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                feat.ips[i], feat.gt_label[i], y_pred[i], feat.risk_score[i],
                feat.f_out_mal_rate[i], feat.f_in_mal_rate[i], feat.f_deg[i],
                feat.f_out_ports[i], feat.f_in_ports[i], feat.f_byte_ratio[i], feat.f_fanout[i])
        end
    end

    out_edges_csv, out_top_src_csv, edge_rows, top_src_rows = write_edge_reports(feat, tag)

    mal_idx = findall(y_pred .== "malicious")
    idx_plot = isempty(mal_idx) ? sortperm(feat.risk_score, rev=true)[1:min(20, length(feat.ips))] : mal_idx
    idx_plot = idx_plot[1:min(20, length(idx_plot))]

    labels = feat.ips[idx_plot]
    vals = feat.risk_score[idx_plot]
    colors = [y_pred[i] == "malicious" ? :crimson : :steelblue for i in idx_plot]

    p = bar(
        labels,
        vals,
        orientation = :h,
        color = colors,
        legend = false,
        xlabel = "Risk score",
        ylabel = "IP",
        title = "Top nodos sospechosos (transfer learning)",
        size = (1300, 800),
        background_color = :white,
        left_margin = 12Plots.mm,
    )

    out_plot = joinpath(FIGURES_DIR, "botnet_$(tag)_top_sospechosos_transfer.png")
    savefig(p, out_plot)

    out_graph = write_network_graph(feat, y_pred, tag)
    out_report = write_inference_report(
        model_path, state, feat, y_pred, cap_name, max_lines,
        out_pred_csv, out_edges_csv, out_top_src_csv, out_plot, out_graph,
        edge_rows, top_src_rows,
    )

    println("\nResultados inferencia:")
    println("  CSV predicciones: ", out_pred_csv)
    println("  CSV aristas ponderadas: ", out_edges_csv)
    println("  CSV mejor arista por src: ", out_top_src_csv)
    println("  Grafico top sospechosos: ", out_plot)
    !isempty(out_graph) && println("  Grafo de red: ", out_graph)
    println("  Reporte: ", out_report)
end

function usage()
    println("Uso:")
    println("  train: julia --project=Proyecto_Unidad1 Proyecto_Unidad1/botnet_train_infer.jl train <cap1,cap2,...> [max_lines] [seed] [sampling] [n_strata]")
    println("  infer: julia --project=Proyecto_Unidad1 Proyecto_Unidad1/botnet_train_infer.jl infer <modelo.jls> <capture_test> [max_lines] [sampling] [n_strata]")
    println("Ejemplo train:")
    println("  julia --project=Proyecto_Unidad1 Proyecto_Unidad1/botnet_train_infer.jl train CTU-IoT-Malware-Capture-1-1,CTU-IoT-Malware-Capture-3-1 250000 42 stratified 20")
    println("Ejemplo infer:")
    println("  julia --project=Proyecto_Unidad1 Proyecto_Unidad1/botnet_train_infer.jl infer Proyecto_Unidad1/results/models/botnet_rf_CTU_IoT_Malware_Capture_1_1_CTU_IoT_Malware_Capture_3_1_ml250000.jls CTU-IoT-Malware-Capture-60-1 200000 stratified 20")
end

function main()
    length(ARGS) < 1 && return usage()

    mode = lowercase(ARGS[1])

    if mode == "train"
        length(ARGS) < 2 && return usage()
        caps = parse_capture_list(ARGS[2])
        max_lines = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 250_000
        seed = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 42
        sampling = length(ARGS) >= 5 ? Symbol(lowercase(ARGS[5])) : :stratified
        n_strata = length(ARGS) >= 6 ? parse(Int, ARGS[6]) : 20
        train_mode(caps; max_lines=max_lines, seed=seed, sampling=sampling, n_strata=n_strata)
    elseif mode == "infer"
        length(ARGS) < 3 && return usage()
        model_path = ARGS[2]
        cap_name = ARGS[3]
        max_lines = length(ARGS) >= 4 ? parse(Int, ARGS[4]) : 200_000
        sampling = length(ARGS) >= 5 ? Symbol(lowercase(ARGS[5])) : :stratified
        n_strata = length(ARGS) >= 6 ? parse(Int, ARGS[6]) : 20
        infer_mode(model_path, cap_name; max_lines=max_lines, sampling=sampling, n_strata=n_strata)
    else
        usage()
    end
end

main()
