# ─────────────────────────────────────────────────────────────────────────────
# md_to_pdf_ucuenca.ps1
# Convierte un archivo .md a PDF usando el template visual de UCuenca.
#
# Uso:
#   .\md_to_pdf_ucuenca.ps1 -Archivo informe_centralidad.md
#   .\md_to_pdf_ucuenca.ps1 -Archivo informe_centralidad.md -ConTOC
#
# Requisitos:
#   - Pandoc instalado (winget install JohnMacFarlane.Pandoc)
#   - MiKTeX instalado con pdflatex en el PATH
# ─────────────────────────────────────────────────────────────────────────────

param(
    [Parameter(Mandatory=$true)]
    [string]$Archivo,

    [switch]$ConTOC
)

$template = Join-Path $PSScriptRoot "ucuenca_template.tex"
$salida   = [System.IO.Path]::ChangeExtension($Archivo, ".pdf")

if (-not (Test-Path $Archivo)) {
    Write-Error "No se encontro el archivo: $Archivo"
    exit 1
}

if (-not (Test-Path $template)) {
    Write-Error "No se encontro el template: $template"
    exit 1
}

$args_pandoc = @(
    $Archivo,
    "--output", $salida,
    "--template", $template,
    "--pdf-engine", "pdflatex",
    "--variable", "lang=spanish"
)

if ($ConTOC) {
    $args_pandoc += "--toc"
}

Write-Host "Convirtiendo: $Archivo -> $salida" -ForegroundColor Cyan
pandoc @args_pandoc

if ($LASTEXITCODE -eq 0) {
    Write-Host "PDF generado correctamente: $salida" -ForegroundColor Green
} else {
    Write-Host "Error al generar el PDF." -ForegroundColor Red
}
