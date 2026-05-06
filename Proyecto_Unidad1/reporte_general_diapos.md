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
header-includes:
  - \usepackage{booktabs}
  - \usepackage{array}
  - \setbeamertemplate{navigation symbols}{}
---

## Contexto y objetivo

### Universidad de Cuenca, DEET, Maestria en Ciencias de la Ingenieria Electrica

Este proyecto aplica teoria de grafos a un problema de ciberseguridad: detectar nodos criticos, modelar propagacion de malware y evaluar resiliencia topologica.

### Objetivo general

- Modelar la red como grafo.
- Calcular metricas de centralidad.
- Detectar anomalias mediante score compuesto y z-score.
- Simular propagacion de malware con SIR.
- Evaluar resiliencia con nodos de articulacion y puentes.
- Validar la metodologia con trafico real del dataset IoT-23.

## Enunciado del problema (escenario)

### Problema a resolver

Se requiere un procedimiento reproducible para detectar nodos y comportamientos anómalos en una red de datos, priorizar activos críticos y evaluar capacidad de respuesta ante propagación de malware.

### Escenario de trabajo

- Escenario 1 (controlado): red corporativa modelada como grafo ponderado.
- Escenario 2 (real): capturas IoT-23 con etiquetas de trafico benigno/malicioso.
- Resultado esperado: identificar nodos/IPs de alto riesgo con criterio cuantitativo e interpretable.

## Procedimiento de implementacion (paso a paso)

1. Construir el grafo de la red (nodos, aristas, pesos).
2. Calcular metricas topologicas por nodo (DC, BC, CC, PR).
3. Integrar metricas en un score compuesto y estandarizar con z-score.
4. Definir umbral y marcar nodos anómalos.
5. Simular propagacion con SIR para distintos nodos iniciales.
6. Evaluar resiliencia con articulaciones, puentes y $\kappa$.
7. Repetir la deteccion en IoT-23 a nivel IP y validar contra `label`.
8. Priorizar acciones de hardening con base en evidencia numerica.

## Metodologia general

### Como se hizo

1. Se construyo un grafo corporativo sintetico y ponderado.
2. Se calcularon metricas topologicas para cada nodo.
3. Se combino la informacion en un score estadistico para detectar anomalias.
4. Se simulo la propagacion de malware sobre la topologia real del grafo.
5. Se evaluo el impacto estructural ante fallos dirigidos.
6. Se replico el enfoque sobre capturas reales de IoT-23.

### Logica del metodo (resumen rapido)

- Parte 1: modelado del sistema como grafo para representar conectividad real.
- Parte 2: uso de centralidades para cuantificar importancia topologica por nodo.
- Parte 3: combinacion de metricas en un score + z-score para separar outliers.
- Parte 4: simulacion SIR para medir propagacion segun nodo inicial y parametros.
- Parte 5: analisis de conectividad (articulaciones, puentes, $\kappa$) para estimar robustez.
- Bonus IoT-23: deteccion de botnets mediante score por IP y validacion contra etiquetas reales.

## Modelos matematicos y variables

### Modelo 1: score de anomalia topologica

$$
score(v)=0.5\,BC(v)+0.3\,DC(v)+0.2\,PR(v)
$$

Variables:

- $v$: nodo evaluado.
- $BC(v)$: betweenness centrality del nodo $v$.
- $DC(v)$: degree centrality del nodo $v$.
- $PR(v)$: PageRank del nodo $v$.
- 0.5, 0.3, 0.2: pesos relativos de cada metrica en el score.

### Modelo 2: estandarizacion estadistica (z-score)

$$
z(v)=\frac{score(v)-\mu}{\sigma}
$$

Variables:

- $z(v)$: distancia estandarizada del nodo respecto al promedio.
- $\mu$: media de scores en todos los nodos.
- $\sigma$: desviacion estandar de scores.
- Regla usada: nodo anómalo si $z(v)>1.5$.

### Modelo 3: dinamica SIR sobre grafo

Transiciones por paso temporal:

$$
S \rightarrow I \text{ con probabilidad } \beta, \quad I \rightarrow R \text{ con probabilidad } \gamma
$$

$$
R_0=\frac{\beta}{\gamma}
$$

Variables:

- $S$: nodos susceptibles.
- $I$: nodos infectados.
- $R$: nodos recuperados.
- $\beta$: tasa de contagio.
- $\gamma$: tasa de recuperacion.
- $R_0$: potencial de propagacion del brote.

### Modelo 4: score de deteccion botnet en IoT-23

$$
score_{botnet}(v)=0.35\,%Mal+0.25\,DC+0.20\,BC+0.20\,Ports_{norm}
$$

Variables:

- $%Mal$: proporcion de flujos etiquetados como maliciosos para la IP.
- $DC$: centralidad de grado de la IP en el grafo dirigido.
- $BC$: intermediacion de la IP en rutas de comunicacion.
- $Ports_{norm}$: diversidad de puertos normalizada.
- $score_{botnet}(v)$: puntaje final de riesgo botnet por IP.
- Decision: IP candidata si su z-score supera el umbral definido.

### Implementacion

- Lenguaje: Julia.
- Script principal: `practica_redes_aucapina.jl`.
- Entorno reproducible con `Project.toml` y `Manifest.toml`.
- Salida: tablas, graficos y reportes en Markdown/PDF.

```bash
julia --project=Proyecto_Unidad1 Proyecto_Unidad1/practica_redes_aucapina.jl
```

## Parte 1: construccion del grafo

### Modelo de red corporativa

- Grafo no dirigido ponderado $G=(V,E,w)$.
- 20 nodos y 23 aristas.
- Pesos interpretados como capacidad de enlace.
- Topologia jerarquica con firewall, routers, servidores, hosts e IoT.

### Metodo aplicado: modelado del grafo

- Se definio un grafo no dirigido porque la infraestructura interna se analizo como enlaces bidireccionales.
- Se asignaron pesos para reflejar capacidad relativa de cada enlace y no tratar todas las conexiones como equivalentes.
- Se verifico conectividad global y densidad para obtener una linea base antes del analisis de riesgo.

### Resultado clave

- Densidad = 0.1211.
- Red conectada, pero dispersa.
- Existen pocos caminos alternativos entre segmentos.

### Lectura tecnica

Una densidad baja anticipa fragilidad frente a fallos dirigidos sobre nodos estructurales.

![Grafo base de la red corporativa](grafo_red.png){width=68%}

## Parte 2: metricas de centralidad

### Metricas calculadas

- Degree Centrality.
- Betweenness Centrality.
- Closeness Centrality.
- PageRank.

### Metodo aplicado: centralidades

- Degree Centrality (DC): mide alcance local inmediato.
- Betweenness Centrality (BC): mide control de rutas minimas entre pares de nodos.
- Closeness Centrality (CC): mide rapidez promedio para alcanzar el resto de la red.
- PageRank (PR): mide relevancia por estructura global y no solo por cantidad de enlaces.
- Se compararon las cuatro metricas para evitar decisiones basadas en un unico indicador.

### Hallazgo principal

- Router-LAN-B obtuvo la mayor intermediacion.
- Router-Core quedo segundo, con rol de hub intersegmento.
- FW-Perimetral tuvo relevancia operativa, pero no topologica.

### Interpretacion del riesgo

No basta contar conexiones directas; tambien importa cuantos caminos criticos dependen del nodo.

![Grafo resaltando betweenness centrality](grafo_centralidad_bc.png){width=56%}

![Comparacion de centralidades en barras](centralidad_barras.png){width=56%}

### Como interpretar estas graficas

- En el grafo de betweenness, los nodos de mayor tamano o mayor realce visual concentran rutas minimas entre segmentos.
- Si un nodo aparece dominante en esta vista, su degradacion puede aumentar latencia o desconectar subredes.
- En la grafica de barras, la consistencia de un nodo en varias metricas (DC, BC, CC, PR) indica criticidad transversal y no solo local.

## Parte 3: deteccion de anomalias

### Criterio estadistico

$$
score(v)=0.5\,BC(v)+0.3\,DC(v)+0.2\,PR(v)
$$

$$
z(v)=\frac{score(v)-\mu}{\sigma}
$$

### Metodo aplicado: deteccion estadistica

- Se normalizaron metricas y se construyo un score lineal ponderado para capturar riesgo operativo y estructural.
- Se transformo el score a z-score para comparar nodos en la misma escala estadistica.
- Regla de decision: outlier si $z>1.5$, priorizando sensibilidad sin sobredetectar nodos comunes.

### Umbral de decision

- Nodo anomalo si $z > 1.5$.

### Nodos detectados

- Router-LAN-B: $z=2.631$
- Router-Core: $z=2.528$
- Router-LAN-A: $z=1.791$

El score compuesto redujo falsos positivos al combinar conectividad, intermediacion y relevancia estructural.

![Grafo con nodos anomalos destacados](grafo_anomalias.png){width=52%}

![Barras de z-score por nodo](zscore_barras.png){width=52%}

### Como interpretar la deteccion

- En el grafo, los nodos marcados como anomalos no son necesariamente los de mayor grado, sino los de mayor riesgo estructural compuesto.
- En la grafica de z-score, el criterio operativo es la distancia al umbral ($z=1.5$): a mayor separacion, mayor confianza de deteccion.
- Una brecha amplia entre los primeros nodos y el resto sugiere priorizacion clara para contencion y hardening.

## Parte 4: propagacion de malware con SIR

### Modelo utilizado

- Estados: Susceptible, Infectado y Recuperado.
- Parametros: $\beta=0.3$, $\gamma=0.1$.
- Numero reproductivo base: $R_0=3$.

### Comparacion de escenarios

- Inicio en IoT-Device1: tasa de ataque 5%.
- Inicio en Router-Core: tasa de ataque 50%.

### Interpretacion estructural

La posicion topologica del nodo inicial condiciona mas el impacto de la propagacion que el valor global de $R_0$.

### Metodo aplicado: simulacion SIR

- Se utilizo el modelo SIR discreto sobre el grafo: cada paso actualiza transiciones S->I con probabilidad $\beta$ e I->R con probabilidad $\gamma$.
- Se ejecutaron escenarios con distintos nodos semilla para aislar el efecto de la posicion topologica inicial.
- Se compararon curvas temporales y estado final para medir alcance del brote en cada escenario.

![Comparacion de curvas SIR](sir_comparacion.png){width=62%}

![Estado final de la simulacion SIR](sir_estado_final.png){width=44%}

## Parte 4: sensibilidad y contencion

### Barrido de $\beta$ desde un nodo periferico

- Con origen en IoT-Device1, no hubo epidemia para $\beta=0.1$, $0.2$ y $0.3$.
- Solo con $\beta=0.5$ el brote logro escapar de la periferia.

### Lectura operativa

La topologia actua como barrera natural cuando el compromiso inicial ocurre en un nodo hoja.

### Metodo aplicado: sensibilidad y cuarentena

- Se hizo un barrido paramétrico de $\beta$ para evaluar sensibilidad del brote bajo el mismo origen periferico.
- Se agrego un experimento de cuarentena removiendo de forma temprana un nodo central para medir reduccion de alcance.
- El resultado permite traducir simulacion en controles operativos concretos (aislamiento y segmentacion).

![Barrido de beta en la simulacion SIR](sir_betas.png){width=62%}

### Efecto de cuarentena

- Aislar temprano un nodo central reduce nodos alcanzables.
- La medida interrumpe corredores topologicos de propagacion.

![Impacto de una cuarentena temprana](sir_cuarentena.png){width=52%}

## Parte 5: resiliencia de la red

### Metricas estructurales

- 3 nodos de articulacion.
- 13 puentes.
- $\kappa = 1$.

### Interpretacion

- La red no es 2-conexa.
- Existen multiples enlaces sin redundancia.
- Hay puntos unicos de fallo en el backbone y la distribucion.

### Metodo aplicado: resiliencia topologica

- Nodos de articulacion: se identificaron removiendo un nodo y verificando si aumenta el numero de componentes conexas.
- Puentes: se identificaron removiendo una arista y verificando si la red se fragmenta.
- Conectividad por nodos ($\kappa$): se calculo como el minimo numero de nodos cuya remocion desconecta la red.
- Esta combinacion permite medir robustez desde nivel local (enlace) hasta nivel global (topologia completa).

### Nodo mas critico

Router-Core: su falla fragmenta la red en varias componentes y aisla segmentos completos.

![Grafo con articulaciones y puentes](resiliencia_grafo.png){width=52%}

![Impacto por eliminacion de nodos criticos](resiliencia_impacto.png){width=52%}

## Hardening propuesto

### Recomendaciones priorizadas

| Prioridad | Medida | Efecto esperado |
| --- | --- | --- |
| 1 | Agregar un Router-Core redundante | Elevar $\kappa$ de 1 a 2 |
| 2 | Crear enlace directo LAN-A a LAN-B | Reducir puentes criticos |
| 3 | Agregar segunda conexion al firewall | Eliminar un SPOF perimetral |
| 4 | Enlace SIEM-Server a Router-LAN-A | Mejorar resiliencia de monitoreo |

### Idea central

El objetivo no es agregar enlaces indiscriminadamente, sino incorporar rutas alternativas donde hoy existe dependencia de un unico nodo o arista.

## Desafio extra: validacion con IoT-23

### Datos analizados

- Capture-1-1: Mirai, 150001 lineas.
- Capture-3-1: Mirai variante, 150001 lineas.
- Capture-42-1: C\&C FileDownload, 4001 lineas.

### Metodologia

- Construccion de grafo dirigido IP $\rightarrow$ IP.
- Score botnet por IP activa.
- Umbral por z-score.
- Comparacion con ground truth del campo `label`.

### Metodo usado para detectar botnets

1. Extraccion de flujos desde `conn.log.labeled` y limpieza de registros inconsistentes.
2. Agregacion por IP origen para obtener comportamiento por emisor (frecuencia, destinos y puertos).
3. Construccion de un grafo dirigido donde cada arista representa comunicacion observada.
4. Calculo de variables por IP: porcentaje de trafico malicioso, DC, BC y diversidad de puertos normalizada.
5. Calculo de $score_{botnet}(v)$ como combinacion ponderada de esas variables.
6. Estandarizacion con z-score y marcacion de candidatas cuando superan el umbral.
7. Validacion con etiquetas reales (`label`) y medicion con matriz de confusion y F1.

$$
score_{botnet}(v)=0.35\,%Mal+0.25\,DC+0.20\,BC+0.20\,Ports_{norm}
$$

![Comparacion entre capturas IoT-23](botnet_comparacion.png){width=64%}

### Como interpretar la comparacion IoT-23

- Esta grafica compara severidad y separacion estadistica entre capturas; no solo cuenta eventos, sino cuan distinguible es el patron malicioso frente al trafico benigno.
- Capture-1-1 y Capture-3-1 muestran mayor separacion porque Mirai produce escaneo horizontal, alta actividad por puertos y concentracion de conexiones salientes.
- Capture-42-1 presenta menor contraste relativo, por lo que su deteccion depende mas del contexto de etiqueta y volumen disponible.

## Resultados del desafio extra

### IPs detectadas correctamente

- 192.168.100.103 en Capture-1-1.
- 192.168.2.5 en Capture-3-1.

### Desempeno

- F1 = 1.000 en las dos capturas de Mirai.
- La separacion estadistica fue extrema: $z > 8$.

### Variable mas discriminante

La combinacion de porcentaje malicioso y diversidad de puertos contactados identifico con claridad el comportamiento botnet.

### Que significa esto en terminos simples

- Una IP botnet tipicamente habla con muchos destinos y prueba multiples puertos en poco tiempo.
- Ese patron produce simultaneamente alto porcentaje malicioso y alta diversidad de puertos.
- Cuando ambas variables suben juntas, la separacion frente a trafico normal se vuelve marcada.

![Z-score de deteccion para Mirai](botnet_Capture11_Miraiscan_zscore.png){width=50%}

![Matriz de confusion multicaputra](botnet_confusion_multi.png){width=50%}

### Como interpretar las graficas finales del desafio

- Z-score por IP (Mirai):
  - Eje X: IPs evaluadas.
  - Eje Y: distancia estandarizada del score botnet respecto a la media.
  - Lectura: una IP con $z \gg 1.5$ es un outlier operacional; en este caso, la IP infectada se separa de forma extrema ($z>8$), lo que reduce ambiguedad.
- Matriz de confusion multicaptura:
  - Filas: clase real (`label`).
  - Columnas: clase predicha por el modelo.
  - Diagonal principal: aciertos; celdas fuera de la diagonal: errores.
  - Lectura del resultado: la concentracion en la diagonal para capturas Mirai explica el F1=1.0 reportado.
- Implicacion practica: cuando ambas graficas coinciden (outlier extremo + matriz limpia), la deteccion no solo es correcta, sino tambien interpretable para toma de decisiones en SOC.

## Integracion de resultados

### Convergencia entre metodos

- Los nodos anomalos de la Parte 3 coincidieron con los nodos de articulacion de la Parte 5.
- Router-Core fue tambien el mejor punto de inicio para una propagacion severa en la Parte 4.
- La metodologia detecto tanto criticidad estructural como riesgo operativo.

### Lectura final

El score compuesto de centralidad funciona como predictor robusto de criticidad, y su extension a trafico real permite detectar comportamientos botnet con alta precision.

## Conclusiones y cierre

### Conclusiones principales

1. La red corporativa modelada es funcional, pero fragil ante fallos dirigidos.
2. La centralidad permite identificar activos cuya perdida rompe la conectividad.
3. La propagacion de malware depende fuertemente de la posicion del nodo inicial.
4. La resiliencia mejora cuando se eliminan SPOF y se incrementa la redundancia.
5. La metodologia se valido en IoT-23 con resultados solidos para Mirai.

### Mensaje final

La integracion entre teoria de grafos, simulacion epidemiologica y analisis estadistico ofrece un marco coherente para priorizar defensa, deteccion y hardening en redes reales.
