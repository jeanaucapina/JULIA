# Actividad: Analisis de Centralidad en Red Social

Este entorno contiene el dataset `facebook_combined.txt` y un script para analizar centralidad con `Graphs.jl` y generar un informe con graficos explicativos.

## Archivos

- `facebook_combined.txt`: dataset de conexiones de Facebook.
- `facebook_centralidad_analisis.jl`: carga el grafo, calcula centralidades y genera salidas.
- `plots/`: imagenes PNG con graficos de centralidad.
- `informe_centralidad.md`: informe generado automaticamente.
- `informe_centralidad.html`: version HTML del informe.
- `informe_centralidad.pdf`: version PDF del informe.
- `facebook_network.gexf`: exportacion para abrir la red en Gephi.

## Uso

En PowerShell:

```powershell
cd .\facebook_centralidad_venv
julia --project=. .\facebook_centralidad_analisis.jl
```

## Salidas esperadas

- Graficos explicativos en PNG.
- Top 10 de nodos por degree centrality.
- Top 10 de nodos por betweenness centrality.
- Top 10 de nodos por closeness centrality.
- Informe en Markdown.
- Informe en HTML.
- Informe en PDF.
- Red exportada a GEXF para visualizacion interactiva.

## Nota

`Graphs.jl` no incluye `load_edgelist`, por eso este proyecto carga el archivo manualmente desde el `.txt`.