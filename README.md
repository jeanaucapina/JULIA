# Entornos Julia en este repositorio

Este repositorio usa un entorno por carpeta de proyecto. Cada carpeta como `ejemplo_basico_venv`, `intro_julia_venv`, `lightgraphs_venv` o `weightedgraph_venv` debe tratarse como un proyecto Julia independiente con su propio `Project.toml` y, cuando corresponda, su propio `Manifest.toml`.

## Idea principal

En Julia, el equivalente pr\u00e1ctico a un "venv" de Python es un entorno de proyecto.

Cada entorno vive en una carpeta y se identifica por:

- `Project.toml`: declara dependencias del proyecto.
- `Manifest.toml`: fija versiones exactas instaladas.

La regla m\u00e1s importante es esta:

**antes de ejecutar un script, activa el entorno correcto de su carpeta.**

## Usar un proyecto existente

Ejemplo con `weightedgraph_venv`:

```powershell
cd .\weightedgraph_venv
julia --project=.
```

Ya dentro del REPL de Julia:

```julia
using Pkg
Pkg.instantiate()
include("weightedgraph_ejemplo.jl")
```

Notas:

- `Pkg.instantiate()` instala lo que falte seg\u00fan `Project.toml` y `Manifest.toml`.
- Si ya instalaste todo antes, igual se puede ejecutar sin problema.
- Si abres Julia desde otra carpeta y no activas el proyecto, probablemente cargar\u00e1s paquetes del entorno equivocado.

## Crear un proyecto nuevo sin romper el entorno

### Opcion recomendada: crear todo desde cero con Pkg

En PowerShell:

```powershell
mkdir .\mi_proyecto_venv
cd .\mi_proyecto_venv
julia --project=.
```

En Julia:

```julia
using Pkg
Pkg.activate(".")
Pkg.add("Graphs")
Pkg.add("SimpleWeightedGraphs")
Pkg.status()
```

Luego crea tu script, por ejemplo `mi_proyecto.jl`:

```julia
using Graphs
using SimpleWeightedGraphs

g = SimpleWeightedGraph(3)
add_edge!(g, 1, 2, 1.5)
add_edge!(g, 2, 3, 2.0)

display(Matrix(weights(g)))
```

Para ejecutarlo:

```julia
include("mi_proyecto.jl")
```

## Estructura recomendada para cada proyecto

```text
mi_proyecto_venv/
  Project.toml
  Manifest.toml
  README.md
  mi_proyecto.jl
```

Si el proyecto genera archivos, d\u00e9jalos dentro de la misma carpeta y usa `joinpath(@__DIR__, ...)` para que las rutas no dependan del directorio actual.

## Flujo corto para el d\u00eda a d\u00eda

Para trabajar en un proyecto existente:

```powershell
cd .\mi_proyecto_venv
julia --project=.
```

```julia
using Pkg
Pkg.instantiate()
include("mi_proyecto.jl")
```

Para agregar una dependencia nueva:

```julia
using Pkg
Pkg.add("NombreDelPaquete")
```

## Errores comunes que conviene evitar

### 1. Editar `Project.toml` a mano

No es la forma recomendada para agregar paquetes.

Usa siempre:

```julia
using Pkg
Pkg.add("NombreDelPaquete")
```

Motivo: `Pkg.add(...)` escribe el nombre correcto, el UUID correcto y resuelve compatibilidades. Editarlo a mano suele romper el entorno.

### 2. Ejecutar Julia desde la carpeta equivocada

Si corres Julia desde la ra\u00edz del repo o desde otra carpeta, puede usar otro `Project.toml`.

Usa siempre una de estas dos opciones:

```powershell
cd .\mi_proyecto_venv
julia --project=.
```

o bien:

```powershell
julia --project=.\mi_proyecto_venv
```

### 3. Mezclar `LightGraphs` y `Graphs`

En este repo hay ejemplos viejos con `LightGraphs` y otros nuevos con `Graphs`.

Regla pr\u00e1ctica:

- Si el paquete moderno funciona sobre `Graphs.jl`, usa `Graphs`.
- No mezcles `using LightGraphs, SimpleWeightedGraphs` en proyectos nuevos.

`SimpleWeightedGraphs` actual trabaja con `Graphs.jl`.

### 4. No instanciar despu\u00e9s de clonar o mover el proyecto

Siempre ejecuta:

```julia
using Pkg
Pkg.instantiate()
```

### 5. Rutas relativas fr\u00e1giles

Para escribir archivos desde un script, evita depender del directorio actual. Usa:

```julia
open(joinpath(@__DIR__, "salida.txt"), "w") do io
    write(io, "ok")
end
```

## Comandos \u00fatiles de diagn\u00f3stico

Dentro de Julia:

```julia
using Pkg
Pkg.status()
Pkg.project()
Pkg.instantiate()
Pkg.resolve()
```

Si sospechas problemas de registros:

```julia
using Pkg
Pkg.Registry.update()
```

## Plantilla de README para nuevos subproyectos

Puedes copiar esto dentro de cada carpeta nueva:

```md
# Nombre del proyecto

## Uso

1. Abre una terminal en esta carpeta.
2. Ejecuta `julia --project=.`
3. En Julia, corre `using Pkg; Pkg.instantiate()`
4. Ejecuta `include("nombre_script.jl")`

## Dependencias

- Agrega paquetes con `Pkg.add("Paquete")`
- No edites `Project.toml` manualmente
```

## Recomendaci\u00f3n pr\u00e1ctica para este repo

Si vas a crear ejemplos nuevos, usa este patr\u00f3n:

- un directorio por ejemplo
- `julia --project=.` desde esa carpeta
- dependencias instaladas con `Pkg.add(...)`
- `README.md` corto en cada subcarpeta
- `Graphs.jl` para ejemplos nuevos, salvo que quieras mantener compatibilidad con un ejemplo viejo de `LightGraphs`

## Resumen corto

Si quieres evitar casi todos los problemas, usa siempre esta secuencia:

```powershell
cd .\mi_proyecto_venv
julia --project=.
```

```julia
using Pkg
Pkg.instantiate()
include("mi_script.jl")
```

Y para agregar paquetes:

```julia
using Pkg
Pkg.add("NombreDelPaquete")
```