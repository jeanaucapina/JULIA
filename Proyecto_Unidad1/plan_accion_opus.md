# Plan de Acción para Proyecto de Detección de Anomalías en Redes (Opus)

## Objetivo General
Resolver todas las partes del proyecto y el desafío extra, generando reportes claros con visualizaciones, explicaciones y avances documentados en Markdown.

---

## 1. Estructura del Plan

### 1.1. Fases del Proyecto
- **Parte 1:** Construcción del grafo de red
- **Parte 2:** Cálculo de métricas de centralidad
- **Parte 3:** Detección de anomalías estadísticas
- **Parte 4:** Simulación de propagación de malware (modelo SIR)
- **Parte 5:** Resiliencia — nodos de articulación y puentes
- **Desafío Extra:** Detección de botnet y comunidades

### 1.2. Metodología de Trabajo
- Cada parte se implementará y documentará por separado.
- Tras la aprobación de cada parte, se continuará con la siguiente (para optimizar recursos y tokens).
- Se generará un reporte Markdown (`reporte_avances.md`) con explicaciones, resultados, imágenes y visualizaciones.
- Los grafos se representarán con colores, tamaños y leyendas adecuadas. Si el grafo es muy grande, se buscarán técnicas de reducción o visualización por comunidades para evitar puntos sobremontados.

---

## 2. Consideraciones sobre los Datos
- El dataset IoT-23 (ubicado en `C:/Users/jeanj/Documents/GitHub/JULIA/Proyecto_Unidad1/iot_23_datasets_small`) debe procesarse completamente para el análisis.
- No se recomienda procesar todo el dataset usando Claude, para evitar un gasto excesivo de tokens. Automatiza el procesamiento con scripts y solo utiliza Claude para documentar la exploración, estructura y selección de variables.
- Documentar el proceso de exploración y selección de datos en el reporte.

---

## 3. Requerimientos de Reporte
- El reporte debe incluir:
  - Explicaciones claras de cada paso y resultado.
  - Imágenes de los grafos y resultados relevantes (pueden ser capturas o generadas con matplotlib/networkx).
  - Análisis y justificación de decisiones tomadas.
  - Un resumen de las partes ya realizadas (checklist Markdown).

### Ejemplo de Checklist Markdown

```markdown
## Avance del Proyecto
- [x] Parte 1: Construcción del grafo de red
- [ ] Parte 2: Cálculo de métricas de centralidad
- [ ] Parte 3: Detección de anomalías estadísticas
- [ ] Parte 4: Simulación de propagación de malware (modelo SIR)
- [ ] Parte 5: Resiliencia — nodos de articulación y puentes
- [ ] Desafío Extra: Detección de botnet y comunidades
```

---

## 4. Visualización de Grafos
- Usar colores y tamaños para distinguir tipos de nodos, métricas o comunidades.
- Si el grafo es muy grande, aplicar:
  - Filtros por subredes o comunidades
  - Algoritmos de reducción de dimensionalidad
  - Visualizaciones interactivas o por capas
- Documentar en el reporte la estrategia de visualización utilizada.

---

## 5. Siguiente Paso
- **Iniciar con la Parte 1:**
  - Explorar el dataset
  - Construir el grafo base
  - Documentar el proceso y resultados
- Esperar aprobación antes de continuar a la Parte 2.

---

## 6. Referencias
- [IoT-23 Dataset](https://www.stratosphereips.org/datasets-iot23)
- Documentación de NetworkX, matplotlib, pandas

---

> **Nota:** Este plan busca asegurar un avance ordenado, eficiente y bien documentado, facilitando la revisión y aprobación en cada etapa.
