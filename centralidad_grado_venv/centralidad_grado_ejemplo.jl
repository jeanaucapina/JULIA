using Graphs, GraphPlot

# Crear un grafo simple
g = SimpleGraph(6)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 1, 4)
add_edge!(g, 2, 3)
add_edge!(g, 4, 5)
add_edge!(g, 4, 6)

# Calcular centralidad de grado
cent = degree_centrality(g)
println("Centralidad de grado: $cent")
