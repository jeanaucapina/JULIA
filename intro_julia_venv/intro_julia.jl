# Copia de intro_julia.jl para su venv dedicado
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

# ── 3. Operaciones matemáticas ──────────────────────────────
println("\n--- Matemáticas ---")
println("Suma:        ", 10 + 3)
println("Resta:       ", 10 - 3)
println("Producto:    ", 10 * 3)
println("División:    ", 10 / 3)
println("Div. entera: ", 10 ÷ 3)   # operador Unicode ÷
println("Módulo:      ", 10 % 3)
println("Potencia:    ", 2 ^ 8)
println("Raíz cuad.:  ", sqrt(144))

# ── 4. Cadenas de texto ────────────────────────────────────
nombre = "Mundo"
println("\n--- Cadenas ---")
# ERROR: "$nombre!" hacía que Julia buscara la variable `nombre!` (con el signo !
# incluido), ya que ! es un carácter válido en identificadores de Julia.
# CORRECCIÓN: usar $(nombre) para delimitar explícitamente el nombre de la variable.
println("Interpolación: Hola, $(nombre)!")
println("Concatenar:    " * "Hola" * ", " * nombre * "!")
println("Longitud:      ", length("Julia"))
println("Mayúsculas:    ", uppercase("julia"))
