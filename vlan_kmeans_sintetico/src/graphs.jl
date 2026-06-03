using DataFrames, CSV

"""
Build aggregated edge table with VLAN annotations.
Returns DataFrame: src_ip, dst_ip, src_vlan, dst_vlan, bytes_sum, n_flujos, is_inter
"""
function build_edge_table(flows::DataFrame, vlan_assignments::Vector{Int})::DataFrame
    edge_rows = DataFrame(
        src_ip   = String[],
        dst_ip   = String[],
        src_vlan = Int[],
        dst_vlan = Int[],
        bytes    = Int[]
    )
    for r in eachrow(flows)
        push!(edge_rows, (
            r.src_ip,
            r.dst_ip,
            vlan_assignments[r.src_id],
            vlan_assignments[r.dst_id],
            r.bytes
        ))
    end

    agg = combine(
        groupby(edge_rows, [:src_ip, :dst_ip, :src_vlan, :dst_vlan]),
        :bytes => sum => :bytes_sum,
        nrow   => :n_flujos
    )
    agg.is_inter = agg.src_vlan .!= agg.dst_vlan
    return agg
end

"""
Export all graph CSV files to output_dir/graphs/:
  - grafo_global_aristas.csv
  - grafo_vlan_N_aristas.csv  (one per VLAN)
  - grafo_inter_vlan_aristas.csv
"""
function export_graph_csvs(edge_tbl::DataFrame, output_dir::String)
    graphs_dir = joinpath(output_dir, "graphs")
    mkpath(graphs_dir)

    CSV.write(joinpath(graphs_dir, "grafo_global_aristas.csv"), edge_tbl)

    for v in sort(unique(edge_tbl.src_vlan))
        intra = filter(r -> r.src_vlan == v && r.dst_vlan == v, edge_tbl)
        CSV.write(joinpath(graphs_dir, "grafo_vlan_$(v)_aristas.csv"), intra)
    end

    inter = filter(r -> r.is_inter, edge_tbl)
    CSV.write(joinpath(graphs_dir, "grafo_inter_vlan_aristas.csv"), inter)
end

"""
Export Graphviz DOT files for each VLAN and the inter-VLAN graph.
These can be rendered with: dot -Tpng grafo_vlan_1.dot -o grafo_vlan_1.png
No Julia graphics backend required — works on any OS.
"""
function export_dot_files(edge_tbl::DataFrame, output_dir::String)
    plots_dir = joinpath(output_dir, "plots")
    mkpath(plots_dir)

    vlans = sort(unique(vcat(edge_tbl.src_vlan, edge_tbl.dst_vlan)))

    # per-VLAN intra graphs
    for v in vlans
        intra = filter(r -> r.src_vlan == v && r.dst_vlan == v, edge_tbl)
        isempty(intra) && continue
        path = joinpath(plots_dir, "grafo_vlan_$(v).dot")
        open(path, "w") do io
            println(io, "digraph VLAN_$(v) {")
            println(io, "  graph [label=\"VLAN $(v)\", fontsize=14];")
            println(io, "  node  [shape=ellipse, style=filled, fillcolor=lightblue];")
            for r in eachrow(intra)
                label = "$(r.n_flujos)f/$(r.bytes_sum)B"
                println(io, "  \"$(r.src_ip)\" -> \"$(r.dst_ip)\" [label=\"$label\"];")
            end
            println(io, "}")
        end
    end

    # inter-VLAN graph
    inter = filter(r -> r.is_inter, edge_tbl)
    if !isempty(inter)
        path = joinpath(plots_dir, "grafo_inter_vlan.dot")
        open(path, "w") do io
            println(io, "digraph InterVLAN {")
            println(io, "  graph [label=\"Inter-VLAN Traffic\", fontsize=14];")
            println(io, "  node  [shape=box, style=filled, fillcolor=lightyellow];")
            for r in eachrow(inter)
                color = "red"
                println(io, "  \"$(r.src_ip)\\nV$(r.src_vlan)\" -> \"$(r.dst_ip)\\nV$(r.dst_vlan)\" [color=$color, label=\"$(r.n_flujos)f\"];")
            end
            println(io, "}")
        end
    end

    # global graph (node = VLAN, edge = aggregated inter-VLAN traffic)
    inter_agg = combine(
        groupby(inter, [:src_vlan, :dst_vlan]),
        :bytes_sum => sum => :total_bytes,
        :n_flujos  => sum => :total_flujos
    )
    path = joinpath(plots_dir, "grafo_vlan_summary.dot")
    open(path, "w") do io
        println(io, "digraph VLANSummary {")
        println(io, "  graph [label=\"VLAN Topology Summary\", fontsize=14];")
        println(io, "  node  [shape=box, style=filled, fillcolor=lightgreen];")
        for v in vlans
            println(io, "  VLAN_$(v) [label=\"VLAN $(v)\"];")
        end
        for r in eachrow(inter_agg)
            bw = round(r.total_bytes / 1024, digits=1)
            println(io, "  VLAN_$(r.src_vlan) -> VLAN_$(r.dst_vlan) [label=\"$(r.total_flujos)f / $(bw)KB\"];")
        end
        println(io, "}")
    end
end

"""
Export GEXF files for Gephi (alternative to DOT).
One file per VLAN + one global file.
"""
function export_gexf(edge_tbl::DataFrame, output_dir::String)
    plots_dir = joinpath(output_dir, "plots")
    mkpath(plots_dir)

    vlans = sort(unique(edge_tbl.src_vlan))

    for v in vlans
        intra = filter(r -> r.src_vlan == v && r.dst_vlan == v, edge_tbl)
        isempty(intra) && continue

        nodes = unique(vcat(intra.src_ip, intra.dst_ip))
        path  = joinpath(plots_dir, "grafo_vlan_$(v).gexf")

        open(path, "w") do io
            println(io, """<?xml version="1.0" encoding="UTF-8"?>
<gexf xmlns="http://gexf.net/1.3">
  <graph defaultedgetype="directed">
    <nodes>""")
            for (i, ip) in enumerate(nodes)
                println(io, "      <node id=\"$i\" label=\"$ip\" />")
            end
            node_idx = Dict(ip => i for (i, ip) in enumerate(nodes))
            println(io, "    </nodes>\n    <edges>")
            for (i, r) in enumerate(eachrow(intra))
                s = node_idx[r.src_ip]
                d = node_idx[r.dst_ip]
                println(io, "      <edge id=\"$i\" source=\"$s\" target=\"$d\" weight=\"$(r.n_flujos)\" />")
            end
            println(io, "    </edges>\n  </graph>\n</gexf>")
        end
    end
end
