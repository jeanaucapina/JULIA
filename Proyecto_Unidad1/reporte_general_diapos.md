---
title: "Deteccion de Anomalias en Redes"
subtitle: "Resumen Ejecutivo del Proyecto"
author: "Grupo de trabajo"
date: "Abril 2026"
lang: "es"
documentclass: beamer
classoption:
  - aspectratio=169
theme: Madrid
colortheme: dolphin
fontsize: 10pt
slide-level: 3
header-includes:
  - \usepackage{booktabs}
  - \usepackage{array}
  - \setbeamertemplate{navigation symbols}{}
---

## Contexto y objetivo

### Universidad de Cuenca, DEET, Maestria en Ciencias de la Ingenieria Electrica

Este proyecto aplica teoria de grafos a ciberseguridad: detectar nodos criticos, modelar propagacion de malware y evaluar resiliencia topologica.

### Objetivo general

- Modelar la red como grafo.
- Calcular metricas de centralidad.
- Detectar anomalias con score compuesto y z-score.
- Simular propagacion de malware con SIR.
- Evaluar resiliencia con articulaciones y puentes.
- Validar con trafico real del dataset IoT-23.

## Enunciado del problema

### Problema a resolver

Procedimiento reproducible para detectar nodos anomalos, priorizar activos criticos y evaluar respuesta ante propagacion de malware.

### Escenario de trabajo

- **Escenario 1** (controlado): red corporativa como grafo ponderado.
- **Escenario 2** (real): capturas IoT-23 con etiquetas benigno/malicioso.
- **Resultado esperado**: identificar nodos/IPs de alto riesgo con criterio cuantitativo.

## Procedimiento (paso a paso)

### Flujo de implementacion

1. Construir el grafo (nodos, aristas, pesos).
2. Calcular metricas topologicas por nodo (DC, BC, CC, PR).
3. Integrar metricas en score compuesto + z-score.
4. Definir umbral y marcar nodos anomalos.
5. Simular propagacion SIR con distintos nodos iniciales.
6. Evaluar resiliencia: articulaciones, puentes y $\kappa$.
7. Repetir deteccion en IoT-23 y validar contra `label`.
8. Priorizar hardening con base en evidencia numerica.

## Metodologia general

### Como se hizo

1. Grafo corporativo sintetico y ponderado.
2. Metricas topologicas por nodo.
3. Score estadistico para deteccion de anomalias.
4. Simulacion de propagacion de malware.
5. Impacto estructural ante fallos dirigidos.
6. Replicacion sobre capturas reales IoT-23.

### Logica del metodo

- **Parte 1**: modelado como grafo — conectividad real.
- **Parte 2**: centralidades — importancia topologica por nodo.
- **Parte 3**: score + z-score — separacion de outliers.
- **Parte 4**: SIR — propagacion segun nodo inicial.
- **Parte 5**: articulaciones, puentes, $\kappa$ — robustez.
- **Bonus**: deteccion botnet en IoT-23 con validacion real.

## Modelos matematicos

### Modelo 1: score de anomalia topologica

$$
score(v)=0.5\,BC(v)+0.3\,DC(v)+0.2\,PR(v)
$$

- $BC(v)$: betweenness centrality.
- $DC(v)$: degree centrality.
- $PR(v)$: PageRank.
- Pesos: 0.5, 0.3, 0.2 segun relevancia estructural.

### Modelo 2: estandarizacion con z-score

$$
z(v)=\frac{score(v)-\mu}{\sigma}
$$

- $\mu$: media de scores en todos los nodos.
- $\sigma$: desviacion estandar.
- Regla: nodo anomalo si $z(v)>1.5$.

## Modelos matematicos (cont.)

### Modelo 3: dinamica SIR sobre grafo

$$
S \rightarrow I \text{ con prob. } \beta, \quad I \rightarrow R \text{ con prob. } \gamma
$$

$$
R_0=\frac{\beta}{\gamma}
$$

- $S$: susceptibles, $I$: infectados, $R$: recuperados.
- $\beta$: contagio, $\gamma$: recuperacion, $R_0$: potencial del brote.

### Modelo 4: score botnet IoT-23

$$
score_{botnet}(v)=0.35\,pMal+0.25\,DC+0.20\,BC+0.20\,Ports_{norm}
$$

- $pMal$: proporcion de flujos maliciosos de la IP.
- $Ports_{norm}$: diversidad de puertos normalizada.
- Decision: IP candidata si su z-score supera el umbral.

## Implementacion

### Entorno de ejecucion

- Lenguaje: Julia.
- Script: `practica_redes_aucapina.jl`.
- Entorno reproducible: `Project.toml` y `Manifest.toml`.
- Salida: tablas, graficos y reportes en Markdown/PDF.

```bash
julia --project=Proyecto_Unidad1 \
      Proyecto_Unidad1/practica_redes_aucapina.jl
```

## Parte 1: construccion del grafo

### Modelo de red corporativa

- Grafo no dirigido ponderado $G=(V,E,w)$.
- 20 nodos, 23 aristas.
- Pesos = capacidad relativa del enlace.
- Topologia jerarquica: firewall, routers, servidores, hosts, IoT.

### Resultado clave

- Densidad = 0.1211 — red conectada pero dispersa.
- Pocos caminos alternativos entre segmentos.
- Densidad baja anticipa fragilidad ante fallos dirigidos.

### Grafo base

![Grafo base de la red corporativa](grafo_red.png){width=75%}

## Parte 2: metricas de centralidad

### Metricas calculadas

| Metrica | Mide |
|---|---|
| Degree Centrality (DC) | Alcance local inmediato |
| Betweenness Centrality (BC) | Control de rutas minimas |
| Closeness Centrality (CC) | Rapidez para alcanzar la red |
| PageRank (PR) | Relevancia por estructura global |

### Hallazgo principal

- **Router-LAN-B**: mayor intermediacion.
- **Router-Core**: hub intersegmento (segundo lugar).
- **FW-Perimetral**: relevancia operativa, baja topologica.

No basta contar conexiones — importa cuantos caminos criticos dependen del nodo.

## Parte 2: grafo de betweenness

### Betweenness centrality

![Grafo resaltando betweenness centrality](grafo_centralidad_bc.png){width=85%}

## Parte 2: comparacion de centralidades

### Barras por metrica

![Comparacion de centralidades en barras](centralidad_barras.png){width=85%}

## Parte 3: deteccion de anomalias

### Criterio estadistico

$$score(v)=0.5\,BC(v)+0.3\,DC(v)+0.2\,PR(v) \quad z(v)=\frac{score(v)-\mu}{\sigma}$$

- Normalizar metricas, construir score ponderado, transformar a z-score.
- **Umbral**: nodo anomalo si $z > 1.5$.

### Nodos detectados

| Nodo | z-score |
|---|---|
| Router-LAN-B | 2.631 |
| Router-Core | 2.528 |
| Router-LAN-A | 1.791 |

Score compuesto reduce falsos positivos al combinar BC, DC y PR.

## Parte 3: grafo de anomalias

### Nodos anomalos destacados

![Grafo con nodos anomalos destacados](grafo_anomalias.png){width=85%}

## Parte 3: z-score por nodo

### Distribucion de z-scores

![Barras de z-score por nodo](zscore_barras.png){width=85%}

## Parte 4: propagacion SIR

### Parametros y escenarios

- Estados: Susceptible, Infectado, Recuperado.
- $\beta=0.3$, $\gamma=0.1$, $R_0=3$.
- IoT-Device1 (periferia): tasa de ataque 5%.
- Router-Core (hub): tasa de ataque 50%.

La posicion topologica condiciona mas el impacto que $R_0$.

## Parte 4: curvas SIR

### Comparacion de curvas

![Comparacion de curvas SIR](sir_comparacion.png){width=85%}

## Parte 4: sensibilidad

### Barrido de $\beta$ desde nodo periferico

- $\beta=0.1, 0.2, 0.3$: sin epidemia desde IoT-Device1.
- $\beta=0.5$: brote escapa de la periferia.
- Topologia actua como barrera natural en nodos hoja.

## Parte 4: barrido de $\beta$

### Resultado del barrido

![Barrido de beta en la simulacion SIR](sir_betas.png){width=85%}

## Parte 4: cuarentena

### Efecto de aislamiento temprano

- Aislar nodo central reduce nodos alcanzables.
- Interrumpe corredores topologicos de propagacion.

## Parte 4: impacto de cuarentena

### Resultado

![Impacto de una cuarentena temprana](sir_cuarentena.png){width=85%}

## Parte 5: resiliencia de la red

### Metricas estructurales

| Metrica | Valor |
|---|---|
| Nodos de articulacion | 3 |
| Puentes | 13 |
| Conectividad $\kappa$ | 1 |

- Red no 2-conexa.
- Multiples enlaces sin redundancia.
- Puntos unicos de fallo en backbone y distribucion.

### Nodo mas critico

**Router-Core**: su falla fragmenta la red y aisla segmentos completos.

## Parte 5: articulaciones y puentes

### Grafo de resiliencia

![Grafo con articulaciones y puentes](resiliencia_grafo.png){width=85%}

## Parte 5: impacto por eliminacion

### Degradacion ante fallos dirigidos

![Impacto por eliminacion de nodos criticos](resiliencia_impacto.png){width=85%}

## Hardening propuesto

### Recomendaciones priorizadas

| Prioridad | Medida | Efecto |
|---|---|---|
| 1 | Router-Core redundante | $\kappa$: 1 $\to$ 2 |
| 2 | Enlace directo LAN-A $\leftrightarrow$ LAN-B | Menos puentes criticos |
| 3 | Segunda conexion al firewall | Eliminar SPOF perimetral |
| 4 | Enlace SIEM-Server a Router-LAN-A | Resiliencia de monitoreo |

### Idea central

No agregar enlaces indiscriminadamente — incorporar rutas alternativas donde hoy existe dependencia de un unico nodo o arista.

## Desafio extra: IoT-23

### Datos analizados

| Captura | Tipo | Lineas |
|---|---|---|
| Capture-1-1 | Mirai | 150 001 |
| Capture-3-1 | Mirai variante | 150 001 |
| Capture-42-1 | C\&C FileDownload | 4 001 |

### Metodologia

1. Grafo dirigido IP $\rightarrow$ IP desde `conn.log.labeled`.
2. Score botnet por IP: $pMal$, DC, BC, $Ports_{norm}$.
3. Marcacion por z-score y validacion contra `label`.

$$score_{botnet}(v)=0.35\,pMal+0.25\,DC+0.20\,BC+0.20\,Ports_{norm}$$

## Desafio extra: resultados

### IPs detectadas y desempeno

- **192.168.100.103** en Capture-1-1 — F1=1.000, $z>8$.
- **192.168.2.5** en Capture-3-1 — F1=1.000, $z>8$.
- Variable clave: $pMal$ + $Ports_{norm}$ juntos.

## Desafio extra: comparacion de capturas

### Severidad por captura

![Comparacion entre capturas IoT-23](botnet_comparacion.png){width=85%}

## Desafio extra: z-score Mirai

### Deteccion por IP

![Z-score de deteccion para Mirai](botnet_Capture11_Miraiscan_zscore.png){width=85%}

## Desafio extra: matriz de confusion

### Validacion multicaptura

![Matriz de confusion multicaptura](botnet_confusion_multi.png){width=85%}

## Integracion de resultados

### Convergencia entre metodos

- Nodos anomalos (Parte 3) coinciden con articulaciones (Parte 5).
- Router-Core: mayor anomalia, mejor punto de inicio para brote severo (Parte 4).
- Metodologia detecta criticidad estructural y riesgo operativo simultaneamente.

### Lectura final

Score compuesto de centralidad = predictor robusto de criticidad. Su extension a trafico real detecta botnets con alta precision.

## Conclusiones

### Conclusiones principales

1. Red corporativa funcional, pero fragil ante fallos dirigidos.
2. Centralidad identifica activos cuya perdida rompe conectividad.
3. Propagacion depende fuertemente de posicion del nodo inicial.
4. Resiliencia mejora eliminando SPOF e incrementando redundancia.
5. Metodologia validada en IoT-23 con F1=1.0 para Mirai.

### Mensaje final

La integracion de teoria de grafos, simulacion epidemiologica y analisis estadistico ofrece un marco coherente para priorizar defensa, deteccion y hardening en redes reales.
