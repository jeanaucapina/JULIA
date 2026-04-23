using Graphs, Plots, Statistics, GraphPlot, Compose, Cairo, Colors, GraphCommunities

const DATASET_PATH = joinpath(@__DIR__, "facebook_combined.txt")
const REPORT_PATH = joinpath(@__DIR__, "informe_centralidad.md")
const HTML_REPORT_PATH = joinpath(@__DIR__, "informe_centralidad.html")
const PDF_REPORT_PATH = joinpath(@__DIR__, "informe_centralidad.pdf")
const GEXF_PATH = joinpath(@__DIR__, "facebook_network.gexf")
const TOP10_GEXF_PATH = joinpath(@__DIR__, "facebook_top10_populares.gexf")
const PLOTS_DIR = joinpath(@__DIR__, "plots")
const FULL_NETWORK_CAIRO_PNG_PATH = joinpath(PLOTS_DIR, "facebook_red_completa_cairo.png")
const FULL_NETWORK_CAIRO_SVG_PATH = joinpath(PLOTS_DIR, "facebook_red_completa_cairo.svg")

gr()

function xml_escape(value)
    text = string(value)
    text = replace(text, "&" => "&amp;")
    text = replace(text, "<" => "&lt;")
    text = replace(text, ">" => "&gt;")
    text = replace(text, '"' => "&quot;")
    return replace(text, "'" => "&apos;")
end

function load_facebook_graph(path)
    edges = Tuple{Int, Int}[]
    raw_ids = Set{Int}()

    open(path, "r") do io
        for (line_number, line) in enumerate(eachline(io))
            stripped = strip(line)
            isempty(stripped) && continue
            startswith(stripped, "#") && continue

            parts = split(stripped)
            length(parts) >= 2 || error("Invalid edge list at line $(line_number): $(line)")

            src_raw = parse(Int, parts[1])
            dst_raw = parse(Int, parts[2])

            push!(edges, (src_raw, dst_raw))
            push!(raw_ids, src_raw)
            push!(raw_ids, dst_raw)
        end
    end

    vertex_to_raw = sort!(collect(raw_ids))
    raw_to_vertex = Dict(raw_id => index for (index, raw_id) in enumerate(vertex_to_raw))

    graph = SimpleGraph(length(vertex_to_raw))
    for (src_raw, dst_raw) in edges
        src_vertex = raw_to_vertex[src_raw]
        dst_vertex = raw_to_vertex[dst_raw]
        src_vertex == dst_vertex && continue
        add_edge!(graph, src_vertex, dst_vertex)
    end

    return graph, vertex_to_raw
end

function top_n_rows(values, vertex_to_raw; n=10)
    count = min(n, length(values))
    ranked_vertices = sortperm(values; rev=true)[1:count]
    return [(rank, vertex_to_raw[vertex], values[vertex]) for (rank, vertex) in enumerate(ranked_vertices)]
end

function top_n_vertices(values; n=10)
    count = min(n, length(values))
    return sortperm(values; rev=true)[1:count]
end

function percentile(sorted_values, p)
    index = clamp(ceil(Int, p * length(sorted_values)), 1, length(sorted_values))
    return sorted_values[index]
end

function normalize01(values)
    min_value = minimum(values)
    max_value = maximum(values)
    span = max(max_value - min_value, eps())
    return (values .- min_value) ./ span
end

function write_markdown_table(io, title, rows)
    println(io, "## ", title)
    println(io)
    println(io, "| Rank | Nodo | Valor |")
    println(io, "| --- | --- | ---: |")
    for (rank, raw_id, value) in rows
        println(io, "| ", rank, " | ", raw_id, " | ", round(value; digits=6), " |")
    end
    println(io)
end

function write_html_table(io, rows)
    println(io, "<table>")
    println(io, "<thead><tr><th>Rank</th><th>Nodo</th><th>Valor</th></tr></thead>")
    println(io, "<tbody>")
    for (rank, raw_id, value) in rows
        println(io, "<tr><td>", rank, "</td><td>", raw_id, "</td><td>", round(value; digits=6), "</td></tr>")
    end
    println(io, "</tbody>")
    println(io, "</table>")
end

function write_markdown_kv_table(io, title, rows)
    println(io, "## ", title)
    println(io)
    println(io, "| Indicador | Valor |")
    println(io, "| --- | ---: |")
    for (label, value) in rows
        println(io, "| ", label, " | ", value, " |")
    end
    println(io)
end

function write_html_kv_table(io, rows)
    println(io, "<table>")
    println(io, "<thead><tr><th>Indicador</th><th>Valor</th></tr></thead>")
    println(io, "<tbody>")
    for (label, value) in rows
        println(io, "<tr><td>", label, "</td><td>", value, "</td></tr>")
    end
    println(io, "</tbody>")
    println(io, "</table>")
end

function plot_top_metric(rows, output_path, title, color)
    labels = [string(raw_id) for (_, raw_id, _) in rows]
    values = [value for (_, _, value) in rows]
    chart = bar(
        labels,
        values;
        title=title,
        xlabel="Nodo",
        ylabel="Centralidad",
        color=color,
        legend=false,
        size=(1200, 700),
        xrotation=35,
        bottom_margin=10Plots.mm,
    )
    savefig(chart, output_path)
end

function plot_centrality_relationships(output_path, degree_cent, between_cent, close_cent)
    chart = scatter(
        degree_cent,
        between_cent;
        zcolor=close_cent,
        xlabel="Degree centrality",
        ylabel="Betweenness centrality",
        title="Relacion entre degree, betweenness y closeness",
        colorbar_title="Closeness",
        markersize=4,
        markeralpha=0.65,
        markerstrokewidth=0,
        size=(1200, 800),
        legend=false,
    )
    savefig(chart, output_path)
end

function plot_degree_distribution(output_path, degrees)
    chart = histogram(
        degrees;
        bins=50,
        title="Distribucion de grados",
        xlabel="Grado",
        ylabel="Frecuencia",
        color=:slateblue,
        alpha=0.85,
        legend=false,
        size=(1200, 700),
    )
    savefig(chart, output_path)
end

function plot_degree_distribution_loglog(output_path, degrees)
    degree_counts = Dict{Int, Int}()
    for d in degrees
        degree_counts[d] = get(degree_counts, d, 0) + 1
    end
    n = length(degrees)
    ks = sort(collect(keys(degree_counts)))
    pk = [degree_counts[k] / n for k in ks]

    log_ks = log10.(ks)
    log_pk = log10.(pk)

    # Ajuste lineal (ley de potencia: log P(k) = -gamma * log k + C)
    valid = isfinite.(log_ks) .& isfinite.(log_pk)
    x_fit = log_ks[valid]
    y_fit = log_pk[valid]
    n_fit = length(x_fit)
    slope = (n_fit * sum(x_fit .* y_fit) - sum(x_fit) * sum(y_fit)) /
            (n_fit * sum(x_fit .^ 2) - sum(x_fit)^2)
    intercept = (sum(y_fit) - slope * sum(x_fit)) / n_fit
    y_line = intercept .+ slope .* x_fit

    chart = scatter(
        log_ks, log_pk;
        xlabel="log10(k)",
        ylabel="log10(P(k))",
        title="Distribucion de grados en escala log-log (ley de potencia)",
        label="P(k) empirico",
        color=:steelblue,
        markersize=4,
        alpha=0.7,
        size=(900, 550),
    )
    plot!(chart, x_fit, y_line;
        label="Ajuste lineal (gamma ~= $(round(-slope; digits=2)))",
        color=:crimson,
        linewidth=2,
    )
    savefig(chart, output_path)
    return slope
end

function plot_core_distribution(output_path, core_numbers)
    min_core = minimum(core_numbers)
    max_core = maximum(core_numbers)
    bins = min_core:max_core
    chart = histogram(
        core_numbers;
        bins=bins,
        title="Distribucion de k-core",
        xlabel="Core number",
        ylabel="Frecuencia",
        color=:indianred,
        alpha=0.85,
        legend=false,
        size=(1200, 700),
    )
    savefig(chart, output_path)
end

function build_top_popular_subgraph(graph, vertex_to_raw, degree_cent)
    top_vertices = top_n_vertices(degree_cent; n=min(10, nv(graph)))
    subgraph, vertex_map = induced_subgraph(graph, top_vertices)
    raw_ids = vertex_to_raw[vertex_map]
    global_scores = degree_cent[vertex_map]
    return (
        graph=subgraph,
        raw_ids=raw_ids,
        global_scores=global_scores,
        original_vertices=vertex_map,
    )
end

function plot_top_popular_subgraph(output_path, top_subgraph)
    subgraph = top_subgraph.graph
    raw_ids = top_subgraph.raw_ids
    scores = top_subgraph.global_scores
    node_count = nv(subgraph)

    angles = range(0, 2pi; length=node_count + 1)[1:end-1]
    x = cos.(angles)
    y = sin.(angles)

    min_score = minimum(scores)
    max_score = maximum(scores)
    scale = max(max_score - min_score, eps())
    marker_sizes = 12 .+ 24 .* ((scores .- min_score) ./ scale)

    chart = plot(
        title="Conexiones entre los 10 nodos mas populares",
        legend=false,
        aspect_ratio=:equal,
        size=(1000, 1000),
        xlims=(-1.35, 1.35),
        ylims=(-1.35, 1.35),
        axis=false,
        grid=false,
        background_color=:white,
    )

    for edge in edges(subgraph)
        src_index = src(edge)
        dst_index = dst(edge)
        plot!(chart, [x[src_index], x[dst_index]], [y[src_index], y[dst_index]]; color=:gray70, linewidth=2, alpha=0.8)
    end

    scatter!(chart, x, y; markersize=marker_sizes, color=:royalblue, alpha=0.95, markerstrokecolor=:white, markerstrokewidth=1.5)

    annotations = [(x[i], y[i] + 0.11, Plots.text(string(raw_ids[i]), 10, :black, :center)) for i in eachindex(raw_ids)]
    annotate!(chart, annotations)

    savefig(chart, output_path)
end

function plot_top_popular_heatmap(output_path, top_subgraph)
    subgraph = top_subgraph.graph
    raw_ids = top_subgraph.raw_ids
    adjacency = Matrix(adjacency_matrix(subgraph))
    labels = string.(raw_ids)

    chart = heatmap(
        labels,
        labels,
        adjacency;
        title="Mapa de calor de conexiones entre los 10 nodos mas populares",
        xlabel="Nodo",
        ylabel="Nodo",
        color=:blues,
        aspect_ratio=1,
        size=(1000, 900),
        xrotation=45,
        right_margin=8Plots.mm,
        bottom_margin=12Plots.mm,
    )

    for row in axes(adjacency, 1), col in axes(adjacency, 2)
        annotate!(chart, col, row, Plots.text(string(adjacency[row, col]), 8, :black))
    end

    savefig(chart, output_path)
end

function generate_full_network_cairo(output_png_path, output_svg_path, graph, vertex_to_raw, degree_cent, patterns)
    labels = fill("", nv(graph))
    top_vertices = top_n_vertices(degree_cent; n=min(10, nv(graph)))
    for vertex in top_vertices
        labels[vertex] = string(vertex_to_raw[vertex])
    end

    node_scale = normalize01(log.(patterns.degrees .+ 1))
    core_scale = normalize01(patterns.core_numbers)
    node_sizes = 0.35 .+ 1.85 .* node_scale
    node_colors = [RGB(0.15 + 0.55 * value, 0.35 + 0.2 * value, 0.82 - 0.42 * value) for value in core_scale]
    label_sizes = [vertex in top_vertices ? 2.8 : 0.2 for vertex in vertices(graph)]
    stroke_colors = [vertex in top_vertices ? RGBA(1, 1, 1, 0.95) : RGBA(1, 1, 1, 0.0) for vertex in vertices(graph)]
    stroke_widths = [vertex in top_vertices ? 0.6 : 0.0 for vertex in vertices(graph)]

    loc_x, loc_y = spectral_layout(graph)
    plot_context = gplot(
        graph,
        loc_x,
        loc_y;
        nodelabel=labels,
        nodelabelsize=label_sizes,
        NODELABELSIZE=8.0,
        nodelabeldist=1.5,
        nodesize=node_sizes,
        NODESIZE=0.08,
        nodefillc=node_colors,
        nodestrokec=stroke_colors,
        nodestrokelw=stroke_widths,
        edgestrokec=RGBA(0.35, 0.42, 0.52, 0.03),
        edgelinewidth=0.25,
    )

    draw(PNG(output_png_path, 28cm, 28cm), plot_context)
    draw(SVG(output_svg_path, 28cm, 28cm), plot_context)
end

function compute_network_patterns(graph)
    components = connected_components(graph)
    component_sizes = sort(length.(components); rev=true)
    degrees = degree(graph)
    sorted_degrees = sort(degrees)
    local_clustering = local_clustering_coefficient(graph)
    core_numbers = core_number(graph)

    largest_component_size = isempty(component_sizes) ? 0 : component_sizes[1]
    largest_component_share = nv(graph) == 0 ? 0.0 : largest_component_size / nv(graph)
    top_degree_vertices = top_n_vertices(degrees; n=min(10, nv(graph)))
    top_degree_share = sum(degrees[top_degree_vertices]) / sum(degrees)

    return (
        component_count=length(component_sizes),
        largest_component_size=largest_component_size,
        largest_component_share=largest_component_share,
        density=2 * ne(graph) / (nv(graph) * (nv(graph) - 1)),
        average_degree=2 * ne(graph) / nv(graph),
        median_degree=median(sorted_degrees),
        p90_degree=percentile(sorted_degrees, 0.90),
        max_degree=maximum(degrees),
        global_clustering=global_clustering_coefficient(graph),
        average_local_clustering=mean(local_clustering),
        assortativity=assortativity(graph),
        diameter=diameter(graph),
        radius=radius(graph),
        max_core=maximum(core_numbers),
        average_core=mean(core_numbers),
        top_degree_share=top_degree_share,
        degrees=degrees,
        core_numbers=core_numbers,
    )
end

function top_popular_indicator_rows(top_subgraph)
    return [
        ("Nodos en el subgrafo", nv(top_subgraph.graph)),
        ("Aristas entre los 10 mas populares", ne(top_subgraph.graph)),
        ("Densidad del subgrafo", round(2 * ne(top_subgraph.graph) / (nv(top_subgraph.graph) * (nv(top_subgraph.graph) - 1)); digits=6)),
    ]
end

function structural_indicator_rows(patterns)
    return [
        ("Componentes conectados", patterns.component_count),
        ("Tamano del componente gigante", patterns.largest_component_size),
        ("Porcentaje del componente gigante", string(round(100 * patterns.largest_component_share; digits=2), "%")),
        ("Densidad", round(patterns.density; digits=8)),
        ("Grado promedio", round(patterns.average_degree; digits=4)),
        ("Grado mediano", round(patterns.median_degree; digits=2)),
        ("Percentil 90 del grado", round(patterns.p90_degree; digits=2)),
        ("Grado maximo", patterns.max_degree),
        ("Clustering global", round(patterns.global_clustering; digits=6)),
        ("Clustering local promedio", round(patterns.average_local_clustering; digits=6)),
        ("Assortativity", round(patterns.assortativity; digits=6)),
        ("Diametro", patterns.diameter),
        ("Radio", patterns.radius),
        ("Maximo k-core", patterns.max_core),
        ("Promedio de k-core", round(patterns.average_core; digits=4)),
        ("Participacion de los 10 nodos mas conectados", string(round(100 * patterns.top_degree_share; digits=2), "%")),
    ]
end

function pattern_observations(patterns)
    observations = String[]

    if patterns.largest_component_share > 0.95
        push!(observations, "La red esta dominada por un componente gigante, lo que indica alta conectividad global entre usuarios.")
    end
    if patterns.density < 0.05 && patterns.diameter <= 10
        push!(observations, "La combinacion de baja densidad con diametro corto es consistente con un patron small-world.")
    end
    if patterns.global_clustering > patterns.density * 5
        push!(observations, "El clustering es mucho mayor que la densidad, una senal tipica de triadas y comunidades locales en redes sociales.")
    end
    if patterns.top_degree_share > 0.10
        push!(observations, "Una fraccion importante de las conexiones se concentra en pocos hubs, lo que sugiere distribucion desigual del grado.")
    end
    if patterns.assortativity > 0
        push!(observations, "La assortativity positiva sugiere que nodos con grado parecido tienden a conectarse entre si.")
    else
        push!(observations, "La assortativity no es positiva, por lo que la red no muestra una preferencia fuerte por conectar nodos de grado similar.")
    end

    return observations
end

function social_network_interpretations(patterns)
    interpretations = String[]

    push!(interpretations, "Desde el punto de vista de una red social, la presencia de un componente gigante del $(round(100 * patterns.largest_component_share; digits=2))% indica que la mayoria de los usuarios pertenece a una misma conversacion amplia y potencialmente interconectada.")
    push!(interpretations, "La distribucion de grados y el grado maximo de $(patterns.max_degree) sugieren una estructura con hubs: pocos usuarios concentran muchas conexiones y actuan como focos de atencion, visibilidad o influencia.")
    push!(interpretations, "El diametro de $(patterns.diameter) y el radio de $(patterns.radius) muestran que la informacion puede viajar en pocos pasos, lo que es coherente con dinamicas de difusion rapida, viralidad y alcance transversal.")
    push!(interpretations, "El clustering global de $(round(patterns.global_clustering; digits=4)) y el clustering local promedio de $(round(patterns.average_local_clustering; digits=4)) refuerzan la idea de microcomunidades o circulos sociales densos, donde amigos de amigos tambien tienden a estar conectados.")
    push!(interpretations, "La existencia de un maximo k-core de $(patterns.max_core) apunta a un nucleo central muy cohesionado. En terminos sociales, ese nucleo suele representar usuarios muy integrados en la red, con alta capacidad de mantener conversaciones persistentes o amplificar contenido.")

    if patterns.assortativity > 0
        push!(interpretations, "La assortativity positiva de $(round(patterns.assortativity; digits=4)) sugiere una ligera tendencia a que usuarios con niveles similares de conectividad se relacionen entre si, lo que favorece la formacion de estratos o capas sociales relativamente homogeneas.")
    else
        push!(interpretations, "La assortativity no positiva indica que la red mezcla con frecuencia usuarios muy conectados con usuarios perifericos, algo comun cuando cuentas altamente visibles atraen interacciones de muchos nodos pequenos.")
    end

    push!(interpretations, "La participacion del $(round(100 * patterns.top_degree_share; digits=2))% de las conexiones en solo los 10 nodos mas conectados apunta a una concentracion moderada de la atencion. Esto es relevante para marketing, difusion de mensajes y riesgos de sobredependencia de unos pocos actores.")

    return interpretations
end

function current_trend_observations(patterns)
    trends = String[]

    push!(trends, "Las redes sociales actuales suelen combinar fragmentacion en comunidades pequenas con una capa de hubs muy visibles. El contraste entre alto clustering y baja densidad observado aqui es compatible con esa tendencia.")
    push!(trends, "La logica de creadores, cuentas puente e intermediarios sigue siendo clave: los nodos con alta betweenness pueden conectar comunidades que de otro modo permanecerian separadas, influyendo en que contenidos cruzan fronteras tematicas.")
    push!(trends, "Las plataformas recientes muestran fuerte competencia por la atencion. En este contexto, los hubs identificados por degree centrality y los nodos cercanos al nucleo por k-core son candidatos naturales a concentrar alcance organico y acelerar cascadas de difusion.")
    push!(trends, "El patron small-world observado implica beneficios y riesgos: facilita descubrimiento de contenido y coordinacion social, pero tambien hace mas probable la propagacion rapida de desinformacion, rumores o comportamientos imitativos.")
    push!(trends, "El peso del componente gigante sugiere que la plataforma mantiene una base relacional comun. Eso suele favorecer recomendaciones, visibilidad cruzada y expansion de conversaciones, aunque tambien puede aumentar polarizacion cuando los puentes entre grupos son pocos y muy concentrados.")

    return trends
end

function compute_louvain_communities(graph)
    communities_dict = compute(Louvain(), graph)
    communities = [communities_dict[i] for i in 1:nv(graph)]

    community_sizes = Dict{Int, Int}()
    for community_id in communities
        community_sizes[community_id] = get(community_sizes, community_id, 0) + 1
    end
    sorted_community_sizes = sort(collect(community_sizes); by=entry -> entry[2], rev=true)

    largest_community_size = isempty(sorted_community_sizes) ? 0 : sorted_community_sizes[1][2]

    return (
        communities_dict=communities_dict,
        communities=communities,
        modularity_score=modularity(graph, communities),
        community_count=length(sorted_community_sizes),
        largest_community_size=largest_community_size,
        community_sizes=sorted_community_sizes,
    )
end

function top_community_assignments(vertex_to_raw, communities_dict; n=10)
    count = min(n, length(vertex_to_raw))
    rows = Tuple{Int, Int, Int}[]
    for vertex in 1:count
        push!(rows, (vertex, vertex_to_raw[vertex], communities_dict[vertex]))
    end
    return rows
end

function generate_community_plots(community_data)
    mkpath(PLOTS_DIR)

    top_n = min(15, length(community_data.community_sizes))
    top_communities = community_data.community_sizes[1:top_n]
    labels = [string(entry[1]) for entry in top_communities]
    sizes = [entry[2] for entry in top_communities]

    p1 = bar(
        1:top_n, sizes;
        xticks=(1:top_n, labels),
        xrotation=60,
        xlabel="ID de comunidad",
        ylabel="Numero de nodos",
        title="Top $(top_n) comunidades por tamano (Louvain)",
        color=:steelblue,
        legend=false,
        size=(900, 500),
        left_margin=5Plots.mm,
        bottom_margin=25Plots.mm,
    )
    community_sizes_top_path = joinpath(PLOTS_DIR, "community_sizes_top.png")
    savefig(p1, community_sizes_top_path)

    all_sizes = [entry[2] for entry in community_data.community_sizes]
    p2 = histogram(
        all_sizes;
        bins=30,
        xlabel="Tamano de comunidad (nodos)",
        ylabel="Frecuencia",
        title="Distribucion del tamano de comunidades ($(community_data.community_count) comunidades)",
        color=:darkorange,
        legend=false,
        size=(800, 450),
    )
    community_size_distribution_path = joinpath(PLOTS_DIR, "community_size_distribution.png")
    savefig(p2, community_size_distribution_path)

    return Dict(
        :community_sizes_top => community_sizes_top_path,
        :community_size_distribution => community_size_distribution_path,
    )
end

function generate_plots(graph, vertex_to_raw, degree_cent, between_cent, close_cent, patterns, community_data)
    mkpath(PLOTS_DIR)

    degree_top = top_n_rows(degree_cent, vertex_to_raw)
    between_top = top_n_rows(between_cent, vertex_to_raw)
    close_top = top_n_rows(close_cent, vertex_to_raw)

    degree_plot = joinpath(PLOTS_DIR, "top_degree.png")
    between_plot = joinpath(PLOTS_DIR, "top_betweenness.png")
    close_plot = joinpath(PLOTS_DIR, "top_closeness.png")
    relation_plot = joinpath(PLOTS_DIR, "centrality_relationships.png")
    degree_distribution_plot = joinpath(PLOTS_DIR, "degree_distribution.png")
    degree_distribution_loglog_plot = joinpath(PLOTS_DIR, "degree_distribution_loglog.png")
    core_distribution_plot = joinpath(PLOTS_DIR, "core_distribution.png")
    top10_popular_plot = joinpath(PLOTS_DIR, "top10_populares_subgrafo.png")
    top10_popular_heatmap = joinpath(PLOTS_DIR, "top10_populares_heatmap.png")
    top_subgraph = build_top_popular_subgraph(graph, vertex_to_raw, degree_cent)

    plot_top_metric(degree_top, degree_plot, "Top 10 por degree centrality", :steelblue)
    plot_top_metric(between_top, between_plot, "Top 10 por betweenness centrality", :darkorange)
    plot_top_metric(close_top, close_plot, "Top 10 por closeness centrality", :seagreen)
    plot_centrality_relationships(relation_plot, degree_cent, between_cent, close_cent)
    plot_degree_distribution(degree_distribution_plot, patterns.degrees)
    loglog_slope = plot_degree_distribution_loglog(degree_distribution_loglog_plot, patterns.degrees)
    plot_core_distribution(core_distribution_plot, patterns.core_numbers)
    plot_top_popular_subgraph(top10_popular_plot, top_subgraph)
    plot_top_popular_heatmap(top10_popular_heatmap, top_subgraph)
    generate_full_network_cairo(FULL_NETWORK_CAIRO_PNG_PATH, FULL_NETWORK_CAIRO_SVG_PATH, graph, vertex_to_raw, degree_cent, patterns)
    community_plots = generate_community_plots(community_data)

    return Dict(
        :degree_plot => degree_plot,
        :between_plot => between_plot,
        :close_plot => close_plot,
        :relation_plot => relation_plot,
        :degree_distribution_plot => degree_distribution_plot,
        :degree_distribution_loglog_plot => degree_distribution_loglog_plot,
        :loglog_slope => loglog_slope,
        :core_distribution_plot => core_distribution_plot,
        :top10_popular_plot => top10_popular_plot,
        :top10_popular_heatmap => top10_popular_heatmap,
        :top_subgraph => top_subgraph,
        :full_network_cairo_png => FULL_NETWORK_CAIRO_PNG_PATH,
        :full_network_cairo_svg => FULL_NETWORK_CAIRO_SVG_PATH,
        :community_sizes_top => community_plots[:community_sizes_top],
        :community_size_distribution => community_plots[:community_size_distribution],
    )
end

function write_markdown_image(io, title, path, caption)
    relative_path = replace(relpath(path, @__DIR__), '\\' => '/')
    println(io, "### ", title)
    println(io)
    println(io, "![", title, "](", relative_path, ")")
    println(io)
    println(io, caption)
    println(io)
end

function write_html_image(io, title, path, caption)
    relative_path = replace(relpath(path, @__DIR__), '\\' => '/')
    println(io, "<section class=\"figure-block\">")
    println(io, "<h3>", title, "</h3>")
    println(io, "<img src=\"", relative_path, "\" alt=\"", xml_escape(title), "\" />")
    println(io, "<p class=\"caption\">", caption, "</p>")
    println(io, "</section>")
end

function write_report(path, graph, vertex_to_raw, degree_cent, between_cent, close_cent, patterns, plot_paths, community_data)
    degree_top = top_n_rows(degree_cent, vertex_to_raw)
    between_top = top_n_rows(between_cent, vertex_to_raw)
    close_top = top_n_rows(close_cent, vertex_to_raw)
    observations = pattern_observations(patterns)
    social_interpretations = social_network_interpretations(patterns)
    current_trends = current_trend_observations(patterns)
    community_rows = top_community_assignments(vertex_to_raw, community_data.communities_dict)

    open(path, "w") do io
        println(io, "# Informe de centralidad en la red de Facebook")
        println(io)
        println(io, "## Resumen de la red")
        println(io)
        println(io, "- Nodos: ", nv(graph))
        println(io, "- Aristas: ", ne(graph))
        println(io, "- Componentes conectados: ", patterns.component_count)
        println(io, "- Grado promedio: ", round(patterns.average_degree; digits=4))
        println(io, "- Densidad: ", round(patterns.density; digits=8))
        println(io)
        println(io, "## Interpretacion")
        println(io)
        println(io, "- Degree centrality destaca usuarios con muchas conexiones directas.")
        println(io, "- Betweenness centrality resalta usuarios puente entre comunidades.")
        println(io, "- Closeness centrality favorece usuarios con acceso rapido al resto de la red.")
        println(io)
        println(io, "## Comunidades detectadas con Louvain")
        println(io)
        println(io, "- Comunidades detectadas: ", community_data.community_count)
        println(io, "- Modularidad (Louvain): ", round(community_data.modularity_score; digits=6))
        println(io, "- Tamano de la comunidad mas grande: ", community_data.largest_community_size)
        println(io)
        write_markdown_image(io, "Top comunidades por tamano", plot_paths[:community_sizes_top], "Las $(min(15, community_data.community_count)) comunidades mas grandes detectadas por el algoritmo Louvain, ordenadas por numero de nodos.")
        write_markdown_image(io, "Distribucion del tamano de comunidades", plot_paths[:community_size_distribution], "Histograma que muestra cuantas comunidades tienen cada rango de tamano. Una distribucion sesgada indica la presencia de unas pocas comunidades grandes y muchas pequeñas.")
        println(io, "### Asignacion de comunidad por nodo (primeros 10 nodos)")
        println(io)
        println(io, "| Vertice interno | Nodo original | Comunidad |")
        println(io, "| ---: | ---: | ---: |")
        for (vertex, raw_id, community_id) in community_rows
            println(io, "| ", vertex, " | ", raw_id, " | ", community_id, " |")
        end
        println(io)

        println(io, "## Graficos explicativos")
        println(io)
        write_markdown_image(io, "Top 10 por degree centrality", plot_paths[:degree_plot], "Muestra los usuarios con mayor numero de conexiones directas dentro de la red.")
        write_markdown_image(io, "Top 10 por betweenness centrality", plot_paths[:between_plot], "Destaca los nodos que actuan como puentes entre regiones de la red social.")
        write_markdown_image(io, "Top 10 por closeness centrality", plot_paths[:close_plot], "Resume los nodos con acceso mas rapido al resto de usuarios de la red.")
        write_markdown_image(io, "Relacion entre centralidades", plot_paths[:relation_plot], "Cada punto representa un usuario. El color corresponde a closeness centrality y permite comparar tres metricas a la vez.")
        write_markdown_image(io, "Vista global de toda la red con Cairo", plot_paths[:full_network_cairo_png], "Vista general de la red completa renderizada con Cairo. El tamano del nodo refleja su grado, el color resume su nivel de insercion en el nucleo de la red y solo se etiquetan los 10 nodos mas populares para mantener legibilidad.")

        write_markdown_kv_table(io, "Patrones estructurales de la red", structural_indicator_rows(patterns))
        println(io, "## Patrones observados en la red social")
        println(io)
        for observation in observations
            println(io, "- ", observation)
        end
        println(io)
        println(io, "## Interpretacion desde la perspectiva de red social")
        println(io)
        for interpretation in social_interpretations
            println(io, "- ", interpretation)
        end
        println(io)
        println(io, "## Lectura a la luz de tendencias recientes")
        println(io)
        for trend in current_trends
            println(io, "- ", trend)
        end
        println(io)
        write_markdown_image(io, "Distribucion de grados", plot_paths[:degree_distribution_plot], "La forma de la distribucion ayuda a detectar hubs y desigualdad en el numero de conexiones.")
        gamma_val = round(-plot_paths[:loglog_slope]; digits=2)
        write_markdown_image(io, "Distribucion de grados (escala log-log)", plot_paths[:degree_distribution_loglog_plot], "La escala log-log permite verificar si la red sigue una ley de potencia P(k) ~ k^(-gamma). El exponente ajustado es gamma ~= $(gamma_val). Valores tipicos en redes sociales reales: 2 < gamma < 3. Una linea recta en log-log confirma estructura libre de escala (scale-free).")
        write_markdown_image(io, "Distribucion de k-core", plot_paths[:core_distribution_plot], "Resume que tan profundamente insertados estan los nodos dentro de nucleos densos de la red.")
        write_markdown_kv_table(io, "Subgrafo de los 10 nodos mas populares", top_popular_indicator_rows(plot_paths[:top_subgraph]))
        write_markdown_image(io, "Conexiones entre los 10 nodos mas populares", plot_paths[:top10_popular_plot], "Este subgrafo muestra solo los usuarios con mayor degree centrality y las conexiones que existen entre ellos. Permite ver si los hubs tambien estan conectados entre si o si concentran enlaces hacia la periferia.")
        write_markdown_image(io, "Mapa de calor de conexiones del top 10", plot_paths[:top10_popular_heatmap], "El mapa de calor resume la matriz de adyacencia del top 10. Las celdas con valor 1 indican conexion directa entre dos nodos populares y facilitan detectar bloques conectados sin la maraña visual del grafo completo.")

        write_markdown_table(io, "Top 10 por degree centrality", degree_top)
        write_markdown_table(io, "Top 10 por betweenness centrality", between_top)
        write_markdown_table(io, "Top 10 por closeness centrality", close_top)

        println(io, "## Conclusiones")
        println(io)
        println(io, "- Los nodos que se repiten en varios rankings suelen ser los actores mas influyentes de la red.")
        println(io, "- Degree centrality es util para detectar popularidad local.")
        println(io, "- Betweenness centrality es mas util para detectar intermediarios clave y posibles cuellos de botella.")
        println(io, "- Closeness centrality ayuda a encontrar nodos eficaces para difusion rapida de informacion.")
        println(io, "- Para visualizacion interactiva en Gephi, usa el archivo facebook_network.gexf generado por este script.")
    end
end

function write_html_report(path, graph, vertex_to_raw, degree_cent, between_cent, close_cent, patterns, plot_paths, community_data)
    degree_top = top_n_rows(degree_cent, vertex_to_raw)
    between_top = top_n_rows(between_cent, vertex_to_raw)
    close_top = top_n_rows(close_cent, vertex_to_raw)
    observations = pattern_observations(patterns)
    social_interpretations = social_network_interpretations(patterns)
    current_trends = current_trend_observations(patterns)
    community_rows = top_community_assignments(vertex_to_raw, community_data.communities_dict)

    open(path, "w") do io
        println(io, "<!DOCTYPE html>")
        println(io, "<html lang=\"es\">")
        println(io, "<head>")
        println(io, "<meta charset=\"utf-8\" />")
        println(io, "<title>Informe de centralidad en la red de Facebook</title>")
        println(io, "<style>")
        println(io, "body { font-family: Segoe UI, Arial, sans-serif; margin: 32px; color: #1f2937; }")
        println(io, "h1, h2, h3 { color: #0f172a; }")
        println(io, "table { border-collapse: collapse; width: 100%; margin: 12px 0 24px; }")
        println(io, "th, td { border: 1px solid #cbd5e1; padding: 8px 10px; text-align: left; }")
        println(io, "th { background: #e2e8f0; }")
        println(io, "img { max-width: 100%; display: block; margin: 12px 0; border: 1px solid #dbe4ee; }")
        println(io, ".caption { color: #475569; margin-top: 0; }")
        println(io, ".metric-grid { display: block; }")
        println(io, "@media print { body { margin: 18px; } h2, h3 { break-after: avoid; } img, table { break-inside: avoid; } }")
        println(io, "</style>")
        println(io, "</head>")
        println(io, "<body>")
        println(io, "<h1>Informe de centralidad en la red de Facebook</h1>")
        println(io, "<h2>Resumen de la red</h2>")
        println(io, "<ul>")
        println(io, "<li>Nodos: ", nv(graph), "</li>")
        println(io, "<li>Aristas: ", ne(graph), "</li>")
        println(io, "<li>Componentes conectados: ", patterns.component_count, "</li>")
        println(io, "<li>Grado promedio: ", round(patterns.average_degree; digits=4), "</li>")
        println(io, "<li>Densidad: ", round(patterns.density; digits=8), "</li>")
        println(io, "</ul>")
        println(io, "<h2>Interpretacion</h2>")
        println(io, "<ul>")
        println(io, "<li>Degree centrality destaca usuarios con muchas conexiones directas.</li>")
        println(io, "<li>Betweenness centrality resalta usuarios puente entre comunidades.</li>")
        println(io, "<li>Closeness centrality favorece usuarios con acceso rapido al resto de la red.</li>")
        println(io, "</ul>")
        println(io, "<h2>Comunidades detectadas con Louvain</h2>")
        println(io, "<ul>")
        println(io, "<li>Comunidades detectadas: ", community_data.community_count, "</li>")
        println(io, "<li>Modularidad (Louvain): ", round(community_data.modularity_score; digits=6), "</li>")
        println(io, "<li>Tamano de la comunidad mas grande: ", community_data.largest_community_size, "</li>")
        println(io, "</ul>")
        write_html_image(io, "Top comunidades por tamano", plot_paths[:community_sizes_top], "Las $(min(15, community_data.community_count)) comunidades mas grandes detectadas por el algoritmo Louvain, ordenadas por numero de nodos.")
        write_html_image(io, "Distribucion del tamano de comunidades", plot_paths[:community_size_distribution], "Histograma que muestra cuantas comunidades tienen cada rango de tamano. Una distribucion sesgada indica la presencia de unas pocas comunidades grandes y muchas pequeñas.")
        println(io, "<h3>Asignacion de comunidad por nodo (primeros 10 nodos)</h3>")
        println(io, "<table>")
        println(io, "<thead><tr><th>Vertice interno</th><th>Nodo original</th><th>Comunidad</th></tr></thead>")
        println(io, "<tbody>")
        for (vertex, raw_id, community_id) in community_rows
            println(io, "<tr><td>", vertex, "</td><td>", raw_id, "</td><td>", community_id, "</td></tr>")
        end
        println(io, "</tbody>")
        println(io, "</table>")
        println(io, "<h2>Graficos explicativos</h2>")
        write_html_image(io, "Top 10 por degree centrality", plot_paths[:degree_plot], "Muestra los usuarios con mayor numero de conexiones directas dentro de la red.")
        write_html_image(io, "Top 10 por betweenness centrality", plot_paths[:between_plot], "Destaca los nodos que actuan como puentes entre regiones de la red social.")
        write_html_image(io, "Top 10 por closeness centrality", plot_paths[:close_plot], "Resume los nodos con acceso mas rapido al resto de usuarios de la red.")
        write_html_image(io, "Relacion entre centralidades", plot_paths[:relation_plot], "Cada punto representa un usuario. El eje X usa degree centrality, el eje Y betweenness centrality y el color closeness centrality.")
        write_html_image(io, "Vista global de toda la red con Cairo", plot_paths[:full_network_cairo_png], "Vista general de la red completa renderizada con Cairo. El tamano del nodo refleja su grado, el color resume su nivel de insercion en el nucleo de la red y solo se etiquetan los 10 nodos mas populares para mantener legibilidad.")
        println(io, "<h2>Patrones estructurales de la red</h2>")
        write_html_kv_table(io, structural_indicator_rows(patterns))
        println(io, "<h2>Patrones observados en la red social</h2>")
        println(io, "<ul>")
        for observation in observations
            println(io, "<li>", observation, "</li>")
        end
        println(io, "</ul>")
        println(io, "<h2>Interpretacion desde la perspectiva de red social</h2>")
        println(io, "<ul>")
        for interpretation in social_interpretations
            println(io, "<li>", interpretation, "</li>")
        end
        println(io, "</ul>")
        println(io, "<h2>Lectura a la luz de tendencias recientes</h2>")
        println(io, "<ul>")
        for trend in current_trends
            println(io, "<li>", trend, "</li>")
        end
        println(io, "</ul>")
        write_html_image(io, "Distribucion de grados", plot_paths[:degree_distribution_plot], "La forma de la distribucion ayuda a detectar hubs y desigualdad en el numero de conexiones.")
        gamma_val_html = round(-plot_paths[:loglog_slope]; digits=2)
        write_html_image(io, "Distribucion de grados (escala log-log)", plot_paths[:degree_distribution_loglog_plot], "La escala log-log permite verificar si la red sigue una ley de potencia P(k) ~ k^(-gamma). El exponente ajustado es gamma ~= $(gamma_val_html). Valores tipicos en redes sociales reales: 2 &lt; gamma &lt; 3. Una linea recta en log-log confirma estructura libre de escala (scale-free).")
        write_html_image(io, "Distribucion de k-core", plot_paths[:core_distribution_plot], "Resume que tan profundamente insertados estan los nodos dentro de nucleos densos de la red.")
        println(io, "<h2>Subgrafo de los 10 nodos mas populares</h2>")
        write_html_kv_table(io, top_popular_indicator_rows(plot_paths[:top_subgraph]))
        write_html_image(io, "Conexiones entre los 10 nodos mas populares", plot_paths[:top10_popular_plot], "Este subgrafo muestra solo los usuarios con mayor degree centrality y las conexiones que existen entre ellos. Permite ver si los hubs tambien estan conectados entre si o si concentran enlaces hacia la periferia.")
        write_html_image(io, "Mapa de calor de conexiones del top 10", plot_paths[:top10_popular_heatmap], "El mapa de calor resume la matriz de adyacencia del top 10. Las celdas con valor 1 indican conexion directa entre dos nodos populares y facilitan detectar bloques conectados sin la maraña visual del grafo completo.")
        println(io, "<h2>Top 10 por degree centrality</h2>")
        write_html_table(io, degree_top)
        println(io, "<h2>Top 10 por betweenness centrality</h2>")
        write_html_table(io, between_top)
        println(io, "<h2>Top 10 por closeness centrality</h2>")
        write_html_table(io, close_top)
        println(io, "<h2>Conclusiones</h2>")
        println(io, "<ul>")
        println(io, "<li>Los nodos que se repiten en varios rankings suelen ser los actores mas influyentes de la red.</li>")
        println(io, "<li>Degree centrality es util para detectar popularidad local.</li>")
        println(io, "<li>Betweenness centrality es mas util para detectar intermediarios clave y posibles cuellos de botella.</li>")
        println(io, "<li>Closeness centrality ayuda a encontrar nodos eficaces para difusion rapida de informacion.</li>")
        println(io, "<li>Para visualizacion interactiva en Gephi, usa el archivo facebook_network.gexf generado por este script.</li>")
        println(io, "</ul>")
        println(io, "</body>")
        println(io, "</html>")
    end
end

function write_top_subgraph_gexf(path, top_subgraph)
    subgraph = top_subgraph.graph
    raw_ids = top_subgraph.raw_ids
    scores = top_subgraph.global_scores

    open(path, "w") do io
        println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        println(io, "<gexf xmlns=\"http://www.gexf.net/1.2draft\" version=\"1.2\">")
        println(io, "  <graph mode=\"static\" defaultedgetype=\"undirected\">")
        println(io, "    <attributes class=\"node\">")
        println(io, "      <attribute id=\"0\" title=\"raw_id\" type=\"integer\" />")
        println(io, "      <attribute id=\"1\" title=\"global_degree_centrality\" type=\"double\" />")
        println(io, "    </attributes>")
        println(io, "    <nodes>")
        for vertex in vertices(subgraph)
            raw_id = raw_ids[vertex]
            println(io, "      <node id=\"", raw_id, "\" label=\"", xml_escape(raw_id), "\">")
            println(io, "        <attvalues>")
            println(io, "          <attvalue for=\"0\" value=\"", raw_id, "\" />")
            println(io, "          <attvalue for=\"1\" value=\"", scores[vertex], "\" />")
            println(io, "        </attvalues>")
            println(io, "      </node>")
        end
        println(io, "    </nodes>")
        println(io, "    <edges>")
        for (edge_id, edge) in enumerate(edges(subgraph))
            println(io, "      <edge id=\"e", edge_id, "\" source=\"", raw_ids[src(edge)], "\" target=\"", raw_ids[dst(edge)], "\" />")
        end
        println(io, "    </edges>")
        println(io, "  </graph>")
        println(io, "</gexf>")
    end
end

function write_gexf(path, graph, vertex_to_raw, degree_cent, between_cent, close_cent)
    open(path, "w") do io
        println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        println(io, "<gexf xmlns=\"http://www.gexf.net/1.2draft\" version=\"1.2\">")
        println(io, "  <graph mode=\"static\" defaultedgetype=\"undirected\">")
        println(io, "    <attributes class=\"node\">")
        println(io, "      <attribute id=\"0\" title=\"raw_id\" type=\"integer\" />")
        println(io, "      <attribute id=\"1\" title=\"degree_centrality\" type=\"double\" />")
        println(io, "      <attribute id=\"2\" title=\"betweenness_centrality\" type=\"double\" />")
        println(io, "      <attribute id=\"3\" title=\"closeness_centrality\" type=\"double\" />")
        println(io, "    </attributes>")
        println(io, "    <nodes>")
        for vertex in vertices(graph)
            raw_id = vertex_to_raw[vertex]
            println(io, "      <node id=\"", raw_id, "\" label=\"", xml_escape(raw_id), "\">")
            println(io, "        <attvalues>")
            println(io, "          <attvalue for=\"0\" value=\"", raw_id, "\" />")
            println(io, "          <attvalue for=\"1\" value=\"", degree_cent[vertex], "\" />")
            println(io, "          <attvalue for=\"2\" value=\"", between_cent[vertex], "\" />")
            println(io, "          <attvalue for=\"3\" value=\"", close_cent[vertex], "\" />")
            println(io, "        </attvalues>")
            println(io, "      </node>")
        end
        println(io, "    </nodes>")
        println(io, "    <edges>")
        for (edge_id, edge) in enumerate(edges(graph))
            println(
                io,
                "      <edge id=\"e", edge_id,
                "\" source=\"", vertex_to_raw[src(edge)],
                "\" target=\"", vertex_to_raw[dst(edge)],
                "\" />",
            )
        end
        println(io, "    </edges>")
        println(io, "  </graph>")
        println(io, "</gexf>")
    end
end

graph, vertex_to_raw = load_facebook_graph(DATASET_PATH)
patterns = compute_network_patterns(graph)

println("Nodos cargados: ", nv(graph))
println("Aristas cargadas: ", ne(graph))
println("Calculando degree centrality...")
degree_cent = degree_centrality(graph)
println("Calculando betweenness centrality...")
between_cent = betweenness_centrality(graph)
println("Calculando closeness centrality...")
close_cent = closeness_centrality(graph)
println("Detectando comunidades con Louvain...")
community_data = compute_louvain_communities(graph)
println("Comunidades detectadas: ", community_data.community_count)
println("Modularidad (Louvain): ", round(community_data.modularity_score; digits=6))
println("Tamano de la comunidad mas grande: ", community_data.largest_community_size)

println("Generando graficos...")
plot_paths = generate_plots(graph, vertex_to_raw, degree_cent, between_cent, close_cent, patterns, community_data)

write_report(REPORT_PATH, graph, vertex_to_raw, degree_cent, between_cent, close_cent, patterns, plot_paths, community_data)
write_html_report(HTML_REPORT_PATH, graph, vertex_to_raw, degree_cent, between_cent, close_cent, patterns, plot_paths, community_data)
write_gexf(GEXF_PATH, graph, vertex_to_raw, degree_cent, between_cent, close_cent)
write_top_subgraph_gexf(TOP10_GEXF_PATH, plot_paths[:top_subgraph])

println("Informe generado en: ", REPORT_PATH)
println("Informe HTML generado en: ", HTML_REPORT_PATH)
println("Archivo GEXF generado en: ", GEXF_PATH)
println("Archivo GEXF del top 10 generado en: ", TOP10_GEXF_PATH)
println("PDF esperado en: ", PDF_REPORT_PATH)
