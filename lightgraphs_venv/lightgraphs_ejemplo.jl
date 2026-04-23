# Ejemplo con LightGraphs y SparseArrays
using LightGraphs, SparseArrays

# Crear grafo dirigido
g = SimpleDiGraph(5)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 4)
add_edge!(g, 3, 5)

println("Grafo dirigido")
# Obtener matriz de adyacencia
A = adjacency_matrix(g)
display(Matrix(A))

# Crear grafo no dirigido
h = SimpleGraph(5)
add_edge!(h, 1, 2)
add_edge!(h, 1, 3)
add_edge!(h, 2, 4)
add_edge!(h, 3, 5)

println("Grafo no dirigido")
# Obtener matriz de adyacencia
B = adjacency_matrix(h)
display(Matrix(B))

# Exportar grafo dirigido a formato Pajek NET
open(joinpath(@__DIR__, "grafo_dirigido.net"), "w") do io
    println(io, "*Vertices ", nv(g))
    for v in 1:nv(g)
        println(io, v, " \"", v, "\"")
    end
    println(io, "*Arcs")
    for e in edges(g)
        println(io, src(e), " ", dst(e))
    end
end

# Exportar grafo no dirigido a formato Pajek NET
open(joinpath(@__DIR__, "grafo_no_dirigido.net"), "w") do io
    println(io, "*Vertices ", nv(h))
    for v in 1:nv(h)
        println(io, v, " \"", v, "\"")
    end
    println(io, "*Edges")
    for e in edges(h)
        println(io, src(e), " ", dst(e))
    end
end