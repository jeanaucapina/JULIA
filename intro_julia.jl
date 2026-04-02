# ============================================================
#  Introducción a Julia - Script básico de aprendizaje
# ============================================================

# ── 1. Hola Mundo ───────────────────────────────────────────
println("¡Hola, Mundo!")

# ── 2. Variables y tipos de datos ───────────────────────────
entero   = 42
flotante = 3.14
texto    = "Julia es genial"
booleano = true

println("\n--- Variables ---")
println("Entero:   ", entero,   " (", typeof(entero),   ")")
println("Flotante: ", flotante, " (", typeof(flotante), ")")
println("Texto:    ", texto,    " (", typeof(texto),    ")")
println("Booleano: ", booleano, " (", typeof(booleano), ")")

# ── 3. Operaciones matemáticas ───────────────────────────────
println("\n--- Matemáticas ---")
println("Suma:        ", 10 + 3)
println("Resta:       ", 10 - 3)
println("Producto:    ", 10 * 3)
println("División:    ", 10 / 3)
println("Div. entera: ", 10 ÷ 3)   # operador Unicode ÷
println("Módulo:      ", 10 % 3)
println("Potencia:    ", 2 ^ 8)
println("Raíz cuad.:  ", sqrt(144))

# ── 4. Cadenas de texto ──────────────────────────────────────
nombre = "Mundo"
println("\n--- Cadenas ---")
# ERROR: "$nombre!" hacía que Julia buscara la variable `nombre!` (con el signo !
# incluido), ya que ! es un carácter válido en identificadores de Julia.
# CORRECCIÓN: usar $(nombre) para delimitar explícitamente el nombre de la variable.
println("Interpolación: Hola, $(nombre)!")
println("Concatenar:    " * "Hola" * ", " * nombre * "!")
println("Longitud:      ", length("Julia"))
println("Mayúsculas:    ", uppercase("julia"))
println("Subcadena:     ", "Programación"[1:7])

# ── 5. Colecciones ───────────────────────────────────────────
println("\n--- Arreglos (Array) ---")
numeros = [10, 20, 30, 40, 50]
println("Arreglo:      ", numeros)
println("Primer elem.: ", numeros[1])      # Índices empiezan en 1
println("Último elem.: ", numeros[end])
println("Slice:        ", numeros[2:4])
push!(numeros, 60)                         # agregar elemento
println("Tras push!:   ", numeros)

println("\n--- Diccionario ---")
persona = Dict("nombre" => "Ana", "edad" => 28, "ciudad" => "Madrid")
println("Nombre: ", persona["nombre"])
println("Edad:   ", persona["edad"])
persona["profesion"] = "Ingeniera"         # nueva clave
println("Claves: ", keys(persona))

# ── 6. Condicionales ─────────────────────────────────────────
println("\n--- Condicionales ---")
x = 15
if x > 10
    println("$x es mayor que 10")
elseif x == 10
    println("$x es igual a 10")
else
    println("$x es menor que 10")
end

# Operador ternario
paridad = iseven(x) ? "par" : "impar"
println("$x es $paridad")

# ── 7. Bucles ────────────────────────────────────────────────
println("\n--- Bucle for ---")
for i in 1:5
    print("$i  ")
end
println()

println("Cuadrados: ")
for n in [2, 4, 6, 8]
    # ERROR: "$n²" buscaba la variable `n²` porque ² (U+00B2, superíndice Unicode)
    # es un carácter válido en identificadores de Julia (permite notación como x²).
    # CORRECCIÓN: $(n) delimita la variable; ² queda como literal de texto.
    println("  $(n)² = $(n^2)")
end

println("\n--- Bucle while ---")
# ERROR: definir `contador` en scope global y modificarlo dentro del `while`
# provoca ambigüedad en Julia ≥1.5: el bucle crea un nuevo local `contador`
# en lugar de usar el global, dejando la condición `contador <= 5` sin valor.
# CORRECCIÓN: envolver en un bloque `let` para crear un scope local limpio.
let contador = 1
    while contador <= 5
        print("$contador  ")
        contador += 1
    end
end
println()

# ── 8. Funciones ─────────────────────────────────────────────
println("\n--- Funciones ---")

# Función estándar
function saludar(nombre::String)
    # ERROR: mismo problema que arriba — $nombre! buscaba la variable `nombre!`.
    # CORRECCIÓN: $(nombre) delimita correctamente la variable.
    return "Hola, $(nombre)!"
end

# Función compacta (una línea)
cuadrado(n) = n^2

# Función con valor por defecto
function potencia(base, exp=2)
    return base ^ exp
end

println(saludar("Julia"))
println("Cuadrado de 7: ", cuadrado(7))
println("2^10 = ", potencia(2, 10))
println("5^2  = ", potencia(5))       # usa exp=2 por defecto

# ── 9. Comprehensions (expresiones generadoras) ──────────────
println("\n--- Comprehensions ---")
cuadrados = [n^2 for n in 1:6]
println("Cuadrados 1-6: ", cuadrados)

pares = [n for n in 1:20 if iseven(n)]
println("Pares hasta 20: ", pares)

# ── 10. Manejo básico de errores ─────────────────────────────
println("\n--- Manejo de errores ---")
try
    resultado = 10 ÷ 0
    println("Resultado: ", resultado)
catch e
    println("Error capturado: ", e)
end

# ── 11. Funciones de orden superior ──────────────────────────
println("\n--- Funciones de orden superior ---")
nums = [3, 1, 4, 1, 5, 9, 2, 6]
println("Original:      ", nums)
println("map (x²):      ", map(x -> x^2, nums))
println("filter (>4):   ", filter(x -> x > 4, nums))
println("sort:          ", sort(nums))
println("reduce (suma): ", reduce(+, nums))

# ── 12. Álgebra lineal básica ────────────────────────────────
println("\n--- Álgebra lineal ---")
v1 = [1, 2, 3]
v2 = [4, 5, 6]
println("v1 + v2:       ", v1 .+ v2)          # operación element-wise
println("v1 · v2 (dot): ", sum(v1 .* v2))

A = [1 2; 3 4]
b = [5, 6]
println("Matriz A:\n", A)
println("A * b = ", A * b)

println("\n¡Script completado con éxito!")
