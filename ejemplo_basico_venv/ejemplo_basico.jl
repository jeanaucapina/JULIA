# Copia de ejemplo_basico.jl para su venv dedicado
import Cairo, Fontconfig
using Graphs, GraphPlot

g = SimpleGraph(5)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 4)
add_edge!(g, 3, 5)

plt = gplot(g)
display(plt)
