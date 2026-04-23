# Ejemplo de grafo ponderado no dirigido
using Graphs, SimpleWeightedGraphs

function xml_escape(value)
    text = string(value)
    text = replace(text, "&" => "&amp;")
    text = replace(text, "<" => "&lt;")
    text = replace(text, ">" => "&gt;")
    text = replace(text, '"' => "&quot;")
    return replace(text, "'" => "&apos;")
end

# Crear grafo ponderado no dirigido
g = SimpleWeightedGraph(5)

# Añadir aristas con pesos
add_edge!(g, 1, 2, 3.5)    # Conexión entre nodos 1-2 con peso 3.5
add_edge!(g, 1, 3, 2.0)    # Conexión entre nodos 1-3 con peso 2.0
add_edge!(g, 2, 4, 1.5)    # Conexión entre nodos 2-4 con peso 1.5
add_edge!(g, 3, 5, 4.2)    # Conexión entre nodos 3-5 con peso 4.2

# Obtener matriz de adyacencia ponderada
A = weights(g)
display(Matrix(A))

# Exportar grafo ponderado a formato Pajek NET
open(joinpath(@__DIR__, "grafo_ponderado.net"), "w") do io
    println(io, "*Vertices ", nv(g))
    for v in 1:nv(g)
        println(io, v, " \"", v, "\"")
    end
    println(io, "*Edges")
    for e in edges(g)
        println(io, src(e), " ", dst(e), " ", get_weight(g, src(e), dst(e)))
    end
end

# Exportar grafo ponderado a GEXF para Gephi con etiquetas visibles en aristas
open(joinpath(@__DIR__, "grafo_ponderado.gexf"), "w") do io
    println(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
    println(io, "<gexf xmlns=\"http://www.gexf.net/1.2draft\" version=\"1.2\">")
    println(io, "  <graph mode=\"static\" defaultedgetype=\"undirected\">")
    println(io, "    <nodes>")
    for v in 1:nv(g)
        println(io, "      <node id=\"", v, "\" label=\"", xml_escape(v), "\" />")
    end
    println(io, "    </nodes>")
    println(io, "    <edges>")
    for (edge_id, e) in enumerate(edges(g))
        edge_weight = get_weight(g, src(e), dst(e))
        weight_label = xml_escape(edge_weight)
        println(
            io,
            "      <edge id=\"e", edge_id,
            "\" source=\"", src(e),
            "\" target=\"", dst(e),
            "\" weight=\"", edge_weight,
            "\" label=\"", weight_label,
            "\" />",
        )
    end
    println(io, "    </edges>")
    println(io, "  </graph>")
    println(io, "</gexf>")
end
