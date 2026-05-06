UCUENCA
FACULTADDEINGENIERÍA-DEET
MAESTRÍAENCIENCIASDELAINGENIERÍAELÉCTRICA
PROYECTO
Detección de
Anomalías en Redes
Métricas de Centralidad en Grafos
Análisis de Redes Complejas
RedesComplejas
Cuenca—Ecuador Abril2026


|  |
|  |
| UCUENCA
FACULTADDEINGENIERÍA-DEET
MAESTRÍAENCIENCIASDELAINGENIERÍAELÉCTRICA
PROYECTO
Detección de
Anomalías en Redes
Métricas de Centralidad en Grafos
Análisis de Redes Complejas
RedesComplejas
Cuenca—Ecuador Abril2026 |
|  |
|  |

Índice
1 Introducción 2
1.1 Objetivos de Aprendizaje . . . . . . . . . . . . . . . . . . . . . . . . . . . 2
1.2 Marco Teórico . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 2
1.2.1 Representación de Redes como Grafos . . . . . . . . . . . . . . 2
1.2.2 Métricas de Centralidad . . . . . . . . . . . . . . . . . . . . . . . . 3
1.2.3 Detección de Anomalías con Z-Score . . . . . . . . . . . . . . . . 3
1.2.4 Modelo SIR de Propagación de Malware . . . . . . . . . . . . . . 3
1.2.5 Nodos de Articulación y Puentes . . . . . . . . . . . . . . . . . . 4
1.2.6 Dataset de Trabajo: IoT-23 . . . . . . . . . . . . . . . . . . . . . . 4
1.2.7 Datasets Alternativos para Análisis de Grafos . . . . . . . . . . 4
2 Parte1:ConstruccióndelGrafodeRed 7
3 Parte2:CálculodeMétricasdeCentralidad 9
4 Parte3:DeteccióndeAnomalíasEstadísticas 10
5 Parte4:SimulacióndePropagacióndeMalware(ModeloSIR) 12
6 Parte5:Resiliencia—NodosdeArticulaciónyPuentes 14
7 DesafíoExtra:DeteccióndeBotnet 16
7.1 Rúbrica de Evaluación . . . . . . . . . . . . . . . . . . . . . . . . . . . . . 17
A Referencias 19
1

Capítulo 1
Introducción
1.1 Objetivos de Aprendizaje
Al finalizar esta práctica, el estudiante será capaz de:
OA-1. Modelar una red corporativa como grafo G = (V,E) e implementarla
con NetworkX.
OA-2. Calcular métricas de centralidad: Degree, Betweenness, Closeness y
PageRank.
OA-3. Detectar nodos anómalos aplicando z-score sobre las métricas de
centralidad.
OA-4. Simularlapropagacióndemalwaremedianteelmodeloepidemiológico
SIR.
OA-5. Identificar nodos de articulación y puentes como activos críticos de
infraestructura.
OA-6. Proponerestrategiasdehardeningyredundanciabasadasenelanálisis
de grafos.
(cid:193) Advertencia
ConexiónconloscontenidosdelcursoEstaprácticaintegralosconceptosdelos
módulos de RedesComplejas (grafos, centralidad, detección de comunidades)
con aplicaciones directas en Ciberseguridad: análisis de botnets, modelado
de ataques, propagación de malware en redes Scale-Free y resiliencia de
infraestructura crítica.
1.2 Marco Teórico
1.2.1 RepresentacióndeRedescomoGrafos
Una red de computadoras se modela como un grafo G = (V,E) donde:
• V es el conjunto de vértices (hosts, routers, servidores, firewalls)
• E ⊆ V ×V es el conjunto de aristas (enlaces de red)
• Cada arista (u,v,w) tiene un peso w que puede representar ancho de banda,
latencia o confianza.
2


| (cid:193) Advertencia |
| ConexiónconloscontenidosdelcursoEstaprácticaintegralosconceptosdelos
módulos de RedesComplejas (grafos, centralidad, detección de comunidades)
con aplicaciones directas en Ciberseguridad: análisis de botnets, modelado
de ataques, propagación de malware en redes Scale-Free y resiliencia de
infraestructura crítica. |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
1.2.2 MétricasdeCentralidad
Las métricas de centralidad cuantifican la importancia de cada nodo dentro de la
topología de red. Su uso en ciberseguridad permite identificar activos críticos y
nodos comprometidos.
Cuadro 1: Métricas de centralidad y su aplicación en ciberseguridad
Métrica Fórmula AplicaciónenSeguridad
**Degree Centrality:**

$$
C_d(v) = \frac{deg(v)}{n-1}
$$
Detectar hosts con conexiones inusualmente altas (posibles bots).

**Betweenness Centrality:**

$$
C_b(v) = \sum_{s \neq v \neq t} \frac{\sigma(s, t | v)}{\sigma(s, t)}
$$
Identificar routers críticos y objetivos Man-in-the-Middle.

**Closeness Centrality:**

$$
C_c(v) = \frac{n-1}{\sum_u d(v, u)}
$$
Evaluar la velocidad de propagación de malware desde un nodo.

**PageRank:**

$$
PR(v) = \frac{1-d}{n} + d \sum_{u \in N(v)} \frac{PR(u)}{deg(u)}
$$
Priorizar activos de alto valor informacional para proteger.
1.2.3 DeteccióndeAnomalíasconZ-Score
Para detectar nodos estadísticamente atípicos se computa un score compuesto y
se normaliza:

Score compuesto:
$$
score(v) = 0.5 \cdot C_b(v) + 0.3 \cdot C_d(v) + 0.2 \cdot PR(v)
$$

Normalización (z-score):
$$
z(v) = \frac{score(v) - \mu}{\sigma}
$$
Un nodo con $z > 1.5$ se clasifica como anómalo y requiere investigación adicional.
1.2.4 ModeloSIRdePropagacióndeMalware
El modelo epidemiológico SIR discreto sobre el grafo G simula la propagación de
malware:

Modelo SIR discreto sobre el grafo $G$:
$$
S(t+1) = S(t) - \beta \cdot k_i \cdot S(t) \cdot I(t)
$$
$$
I(t+1) = I(t) + \beta \cdot k_i \cdot S(t) \cdot I(t) - \gamma \cdot I(t)
$$
$$
R(t+1) = R(t) + \gamma \cdot I(t)
$$
donde $\beta$ es la tasa de infección por contacto, $\gamma$ la tasa de recuperación, y $k_i$ el grado del nodo infectado. El número reproductivo básico es $R_0 = \beta/\gamma$.


| Métrica | Fórmula | AplicaciónenSeguridad |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
(cid:174) Nota
Condición de epidemia Si R > 1, la infección se propaga por la red. En
0
redes Scale-Free, el umbral epidémico tiende a cero (β → 0) debido a la
c
heterogeneidad en la distribución de grados.
1.2.5 NodosdeArticulaciónyPuentes
• Nodo de articulación (cut vertex): nodo cuya eliminación divide el grafo en
componentes desconectados. Su compromiso o fallo aísla segmentos de red.
• Puente(bridge):aristacuyaeliminaciónaumentaelnúmerodecomponentes
conexos. Representa un Single Point of Failure (SPOF) en la infraestructura.
1.2.6 DatasetsdeTrabajoRecomendados
Paravalidarlastécnicasestudiadassobretráficoreal,elestudiantedebeseleccionar
unadelassiguientesdoscapturas,ambaspublicadasporelStratosphereLaboratory
delaUniversidadTécnicaChecadePraga(CTU)[7].Lasdosopcionessonequivalentes
en términos de complejidad y permiten cumplir todos los objetivos de la práctica;
difieren en la familia de malware analizada y en el tipo de canal C&C.
(cid:601) Recomendación
Opción A — CTU-13: Escenario 10 u 11 (Rbot, C&C IRC)
• Familia: Rbot — botnet clásica con ComandoyControlvíaIRC.
• Capturassugeridas:CTU-Malware-Capture-Botnet-51(escenario10)o
CTU-Malware-Capture-Botnet-52 (escenario 11).
• Formato:flujosbidireccionalesArgus(*.binetflow)concamposSrcAddr,
DstAddr, Sport, Dport, Label.
• URL: https://www.stratosphereips.org/datasets-ctu13
• PorquéRbot: la topología en estrella alrededor del servidor IRC produce un
nodo C&C con Betweenness y Degree extremos — caso ideal para validar la
detección por z-score.
(cid:601) Recomendación
Opción B — IoT-23: capture-1-1 (Mirai)
• Familia: Mirai — botnet IoT que propaga vía escaneo Telnet/SSH y realiza
DDoS coordinado.
• Captura sugerida: CTU-IoT-Malware-Capture-1-1 (Mirai infectando
una Philips HUE).
• Formato: conn.log.labeled de Zeek con etiquetas Malicious + sub-
categoría (PartOfAHorizontalPortScan, C&C, DDoS, Okiru, etc.).
• URL: https://www.stratosphereips.org/datasets-iot23
• Por qué Mirai: el patrón de escaneo horizontal masivo genera nodos con
4


| (cid:174) Nota |
| Condición de epidemia Si R > 1, la infección se propaga por la red. En
0
redes Scale-Free, el umbral epidémico tiende a cero (β → 0) debido a la
c
heterogeneidad en la distribución de grados. |


| (cid:601) Recomendación |
| Opción A — CTU-13: Escenario 10 u 11 (Rbot, C&C IRC)
• Familia: Rbot — botnet clásica con ComandoyControlvíaIRC.
• Capturassugeridas:CTU-Malware-Capture-Botnet-51(escenario10)o
CTU-Malware-Capture-Botnet-52 (escenario 11).
• Formato:flujosbidireccionalesArgus(*.binetflow)concamposSrcAddr,
DstAddr, Sport, Dport, Label.
• URL: https://www.stratosphereips.org/datasets-ctu13
• PorquéRbot: la topología en estrella alrededor del servidor IRC produce un
nodo C&C con Betweenness y Degree extremos — caso ideal para validar la
detección por z-score. |


| (cid:601) Recomendación |
| Opción B — IoT-23: capture-1-1 (Mirai)
• Familia: Mirai — botnet IoT que propaga vía escaneo Telnet/SSH y realiza
DDoS coordinado.
• Captura sugerida: CTU-IoT-Malware-Capture-1-1 (Mirai infectando
una Philips HUE).
• Formato: conn.log.labeled de Zeek con etiquetas Malicious + sub-
categoría (PartOfAHorizontalPortScan, C&C, DDoS, Okiru, etc.).
• URL: https://www.stratosphereips.org/datasets-iot23
• Por qué Mirai: el patrón de escaneo horizontal masivo genera nodos con |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
Degree Centrality anómala y comunidades de bots claramente detectables
por Louvain.
(cid:174) Nota
Construcción del grafo desde la captura Independientemente de la opción
elegida, el grafo G = (V,E) se construye de la misma manera: cada IP única
(SrcAddr o id.orig_h, DstAddr o id.resp_h) se convierte en un nodo, y
cada par origen–destino observado al menos una vez en los flujos forma una
arista.Elpesodelaaristapuedeserelnúmerodeflujos,losbytesacumulados
o la duración total.
1.2.7 DatasetsAlternativosparaAnálisisdeGrafos
Aunque IoT-23 es el dataset principal de la práctica, existen otras fuentes públicas
ampliamenteutilizadasenlaliteraturadedeteccióndebotnetsyanomalíasdered.
Se clasifican en dos niveles según el grado de preprocesamiento requerido para
construir el grafo G = (V,E).
Tier1—Listosparaconstruirgrafos(NetFlow/BidirectionalFlows)
Estos datasets ya proveen flujos con campos SrcAddr/DstAddr, lo que permite
generar el grafo de comunicaciones directamente con un groupby en pandas o
Spark.
Cuadro 2: Datasets Tier 1: NetFlow / flujos bidireccionales etiquetados
Dataset Origen Tamaño/Contenido Ventaja para la
práctica
CTU-13 CTU Praga 13 escenarios reales: Cada flujo ya tiene
→
(Stratosphere Neris, Rbot, Virut, SrcAddr DstAddr
Lab) Menti, Sogou, Murlo, — se convierte directo
≈
NSIS-ay. 1.5GB de a grafo con groupby.
Argus binetflow.
IoT-23 Stratosphere 23 capturas de IoT Ideal para esta
(Aposemat) Lab, 2020 infectadas (Mirai, Torii, práctica: incluye
Hide-and-Seek, Hakai, los IoT-Device del
Okiru, etc.). modelo. Labels por
flujo.
CIC-IDS2017 Canadian ARES botnet + Zeus El CSV ya tiene
/ CSE-CIC- Inst. for + Ares. CSV de 80 Source IP /
IDS2018 Cybersecurity features. Destination IP
(UNB) / Flow Duration
— conversión a grafo
trivial.
5


| (cid:174) Nota |
| Construcción del grafo desde la captura Independientemente de la opción
elegida, el grafo G = (V,E) se construye de la misma manera: cada IP única
(SrcAddr o id.orig_h, DstAddr o id.resp_h) se convierte en un nodo, y
cada par origen–destino observado al menos una vez en los flujos forma una
arista.Elpesodelaaristapuedeserelnúmerodeflujos,losbytesacumulados
o la duración total. |


| Dataset | Origen | Tamaño/Contenido | Ventaja para la
práctica |


| IoT-23
(Aposemat) | Stratosphere
Lab, 2020 | 23 capturas de IoT
infectadas (Mirai, Torii,
Hide-and-Seek, Hakai,
Okiru, etc.). | Ideal para esta
práctica: incluye
los IoT-Device del
modelo. Labels por
flujo. |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
Continuación de tabla 2
Dataset Origen Tamaño/Contenido Ventaja para la
práctica
Bot-IoT UNSW 72M flujos: DDoS, DoS, Etiquetado fino:
(UNSW) Canberra, recon, theft vía Mirai ataque/normal
2018 en testbed con 5 + categoría +
dispositivos IoT. subcategoría.
Tier2—PCAPscrudos(requierenpreprocesarconZeek/Argus)
Estosdatasetscontienencapturas.pcapsinagregar;esnecesarioprocesarlascon
Zeek (antes Bro) o Argus para producir flujos antes de construir el grafo.
Cuadro 3: Datasets Tier 2: PCAPs crudos
Dataset Uso
MCFP — Malware Cientos de capturas de malware real con C&C activo.
Capture Facility Contiene la suite original de CTU.
Project
N-BaIoT Mirai + BASHLITE en 9 IoTs reales (cámaras, monitores de
bebé). Features ya extraídas, no requiere Wireshark.
ISOT Botnet Mezcla Storm + Waledac + tráfico legítimo, formato pcap.
(cid:174) Nota
Enlaces oficiales
→
• CTU-13 https://www.stratosphereips.org/datasets-ctu13
→
• IoT-23 https://www.stratosphereips.org/datasets-iot23
→
• CIC-IDS2017 https://www.unb.ca/cic/datasets/ids-2017.ht
ml
→
• CIC-IDS2018 https://www.unb.ca/cic/datasets/ids-2018.ht
ml
→
• Bot-IoTUNSW https://research.unsw.edu.au/projects/bot-i
ot-dataset
→
• N-BaIoT https://archive.ics.uci.edu/ml/datasets/detect
ion_of_IoT_botnet_attacks_N_BaIoT
→
• MCFPcapturas https://www.stratosphereips.org/datasets-m
alware
6


| Dataset | Origen | Tamaño/Contenido | Ventaja para la
práctica |


| Bot-IoT
(UNSW) | UNSW
Canberra,
2018 | 72M flujos: DDoS, DoS,
recon, theft vía Mirai
en testbed con 5
dispositivos IoT. | Etiquetado fino:
ataque/normal
+ categoría +
subcategoría. |


| Dataset | Uso |


| N-BaIoT | Mirai + BASHLITE en 9 IoTs reales (cámaras, monitores de
bebé). Features ya extraídas, no requiere Wireshark. |


| (cid:174) Nota |
| Enlaces oficiales
→
• CTU-13 https://www.stratosphereips.org/datasets-ctu13
→
• IoT-23 https://www.stratosphereips.org/datasets-iot23
→
• CIC-IDS2017 https://www.unb.ca/cic/datasets/ids-2017.ht
ml
→
• CIC-IDS2018 https://www.unb.ca/cic/datasets/ids-2018.ht
ml
→
• Bot-IoTUNSW https://research.unsw.edu.au/projects/bot-i
ot-dataset
→
• N-BaIoT https://archive.ics.uci.edu/ml/datasets/detect
ion_of_IoT_botnet_attacks_N_BaIoT
→
• MCFPcapturas https://www.stratosphereips.org/datasets-m
alware |

Capítulo 2
Parte 1: Construcción del Grafo de Red
(cid:174) Nota
EscenarioSemodelaunaredcorporativacon20nodosdecuatrotipos: ,
firewall
, , . La red incluye zonas DMZ, LAN interna y un servidor SIEM
router server host/IoT
para monitoreo.
import networkx as nx
1
import numpy as np
2
import matplotlib.pyplot as plt
3
import random
4
5
random.seed(42)
6
np.random.seed(42)
7
8
G = nx.Graph()
9
10
# Definicion de nodos: {id: (tipo, nombre)}
11
nodos = {
12
0: (”firewall”, ”FW-Perimetral”),
13
1: (”router”, ”Router-Core”),
14
2: (”router”, ”Router-DMZ”),
15
3: (”server”, ”Web-Server”),
16
4: (”server”, ”DB-Server”),
17
5: (”server”, ”Mail-Server”),
18
6: (”router”, ”Router-LAN-A”),
19
7: (”router”, ”Router-LAN-B”),
20
8: (”host”, ”PC-Admin”),
21
9: (”host”, ”PC-User1”),
22
10: (”host”, ”PC-User2”),
23
11: (”host”, ”PC-User3”),
24
12: (”host”, ”PC-User4”),
25
13: (”host”, ”PC-User5”),
26
14: (”host”, ”Impresora”),
27
15: (”host”, ”IoT-Device1”),
28
16: (”host”, ”IoT-Device2”),
29
17: (”server”, ”SIEM-Server”),
30
18: (”host”, ”PC-User6”),
31
19: (”host”, ”PC-User7”),
32
}
33
34
for nid, (tipo, nombre) in nodos.items():
35
G.add_node(nid, tipo=tipo, nombre=nombre)
36
37
7


| import networkx as nx |
| import numpy as np |
| import matplotlib.pyplot as plt |
| import random |
|  |
| random.seed(42) |
| np.random.seed(42) |
|  |
| G = nx.Graph() |
|  |
| # Definicion de nodos: {id: (tipo, nombre)} |
| nodos = { |
| 0: (”firewall”, ”FW-Perimetral”), |
| 1: (”router”, ”Router-Core”), |
| 2: (”router”, ”Router-DMZ”), |
| 3: (”server”, ”Web-Server”), |
| 4: (”server”, ”DB-Server”), |
| 5: (”server”, ”Mail-Server”), |
| 6: (”router”, ”Router-LAN-A”), |
| 7: (”router”, ”Router-LAN-B”), |
| 8: (”host”, ”PC-Admin”), |
| 9: (”host”, ”PC-User1”), |
| 10: (”host”, ”PC-User2”), |
| 11: (”host”, ”PC-User3”), |
| 12: (”host”, ”PC-User4”), |
| 13: (”host”, ”PC-User5”), |
| 14: (”host”, ”Impresora”), |
| 15: (”host”, ”IoT-Device1”), |
| 16: (”host”, ”IoT-Device2”), |
| 17: (”server”, ”SIEM-Server”), |
| 18: (”host”, ”PC-User6”), |
| 19: (”host”, ”PC-User7”), |
| } |
|  |
| for nid, (tipo, nombre) in nodos.items(): |
| G.add_node(nid, tipo=tipo, nombre=nombre) |
|  |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
# Aristas: (origen, destino, peso_Mbps)
38
aristas = [
39
(0, 1, 1000), (1, 2, 500), (1, 6, 500), (1, 7, 500),
40
(1, 17, 1000),(2, 3, 100), (2, 5, 100), (6, 4, 100),
41
(6, 8, 100), (6, 9, 100), (6, 10, 100), (6, 14, 10),
42
(7, 11, 100), (7, 12, 100), (7, 13, 100), (7, 15, 10),
43
(7, 16, 10), (7, 18, 100), (7, 19, 100), (8, 4, 100),
44
(3, 5, 100), (17, 3, 100), (17, 5, 100),
45
]
46
47
for u, v, w in aristas:
48
G.add_edge(u, v, weight=w)
49
50
print(f”Nodos: {G.number_of_nodes()}, Aristas: {G.number_of_edges()
51
}”)
print(f”Densidad: {nx.density(G):.4f}, Conectado: {nx.is_connected(
52
G)}”)
Listing 2.1: Construcción del grafo de red corporativa
Nodos: 20, Aristas: 23
1
Densidad: 0.1211, Conectado: True
2
Listing 2.2: Salida esperada
(cid:173) PreguntasdeAnálisis
P1. ¿Qué representa la densidad del grafo en términos de la infraestructura
de red? ¿Qué implicaciones tiene para la resiliencia ante ataques?
P2. Modifique el código para que el grafo sea dirigido (DiGraph). ¿Cómo
cambia la interpretación de las métricas de centralidad?
8


| # Aristas: (origen, destino, peso_Mbps) |
| aristas = [ |
| (0, 1, 1000), (1, 2, 500), (1, 6, 500), (1, 7, 500), |
| (1, 17, 1000),(2, 3, 100), (2, 5, 100), (6, 4, 100), |
| (6, 8, 100), (6, 9, 100), (6, 10, 100), (6, 14, 10), |
| (7, 11, 100), (7, 12, 100), (7, 13, 100), (7, 15, 10), |
| (7, 16, 10), (7, 18, 100), (7, 19, 100), (8, 4, 100), |
| (3, 5, 100), (17, 3, 100), (17, 5, 100), |
| ] |
|  |
| for u, v, w in aristas: |
| G.add_edge(u, v, weight=w) |
|  |
| print(f”Nodos: {G.number_of_nodes()}, Aristas: {G.number_of_edges() |
| }”) |
| print(f”Densidad: {nx.density(G):.4f}, Conectado: {nx.is_connected( |
| G)}”) |


| Nodos: 20, Aristas: 23 |
| Densidad: 0.1211, Conectado: True |

Capítulo 3
Parte 2: Cálculo de Métricas de Centralidad
degree_c = nx.degree_centrality(G)
1
betweenness_c = nx.betweenness_centrality(G)
2
closeness_c = nx.closeness_centrality(G)
3
pagerank = nx.pagerank(G, alpha=0.85)
4
5
# Mostrar top-5 por Betweenness (mas relevante en seguridad)
6
print(f”\n{’Nodo’:>4} {’Nombre’:<20} {’Tipo’:<10} ”
7
f”{’Degree’:>8} {’Betw.’:>8} {’Close.’:>8} {’PR’:>8}”)
8
print(”-” * 70)
9
10
top5 = sorted(betweenness_c.items(), key=lambda x: x[1], reverse=
11
True)[:5]
for nid, _ in top5:
12
tipo, nm = nodos[nid]
13
print(f”{nid:>4} {nm:<20} {tipo:<10} ”
14
f”{degree_c[nid]:>8.4f} {betweenness_c[nid]:>8.4f} ”
15
f”{closeness_c[nid]:>8.4f} {pagerank[nid]:>8.4f}”)
16
Listing 3.1: Cálculo de las cuatro métricas de centralidad
Nodo Nombre Tipo Degree Betw. Close. PR
1
----------------------------------------------------------------------
2
1 Router-Core router 0.2632 0.7154 0.5758 0.2722
3
7 Router-LAN-B router 0.4211 0.6140 0.5135 0.1348
4
6 Router-LAN-A router 0.3158 0.4620 0.4634 0.1018
5
2 Router-DMZ router 0.1579 0.0936 0.4043 0.0341
6
17 SIEM-Server server 0.1579 0.0936 0.4043 0.0900
7
Listing 3.2: Top-5 nodos por Betweenness Centrality
(cid:173) PreguntasdeAnálisis
P3. ¿Por qué el Router-Core (ID=1) tiene el mayor Betweenness aunque
no es el nodo más conectado? ¿Qué tipo de ataque lo hace un objetivo
prioritario?
P4. Compare los valores de Degree Centrality vs. Betweenness Centrality.
¿Siempre coincide el nodo más conectado con el más “intermediario”?
P5. Compute el coeficiente de clustering global y local. ¿Qué segmentos de
la red forman cliques?
9


| degree_c = nx.degree_centrality(G) |
| betweenness_c = nx.betweenness_centrality(G) |
| closeness_c = nx.closeness_centrality(G) |
| pagerank = nx.pagerank(G, alpha=0.85) |
|  |
| # Mostrar top-5 por Betweenness (mas relevante en seguridad) |
| print(f”\n{’Nodo’:>4} {’Nombre’:<20} {’Tipo’:<10} ” |
| f”{’Degree’:>8} {’Betw.’:>8} {’Close.’:>8} {’PR’:>8}”) |
| print(”-” * 70) |
|  |
| top5 = sorted(betweenness_c.items(), key=lambda x: x[1], reverse= |
| True)[:5] |
| for nid, _ in top5: |
| tipo, nm = nodos[nid] |
| print(f”{nid:>4} {nm:<20} {tipo:<10} ” |
| f”{degree_c[nid]:>8.4f} {betweenness_c[nid]:>8.4f} ” |
| f”{closeness_c[nid]:>8.4f} {pagerank[nid]:>8.4f}”) |


| Nodo Nombre Tipo Degree Betw. Close. PR |
| ------------------------------------------------------------------- |
|  |
| 1 Router-Core router 0.2632 0.7154 0.5758 0.2722 |
| 7 Router-LAN-B router 0.4211 0.6140 0.5135 0.1348 |
| 6 Router-LAN-A router 0.3158 0.4620 0.4634 0.1018 |
| 2 Router-DMZ router 0.1579 0.0936 0.4043 0.0341 |
| 17 SIEM-Server server 0.1579 0.0936 0.4043 0.0900 |

Capítulo 4
Parte 3: Detección de Anomalías Estadísticas
# Score compuesto ponderado
1
scores = {}
2
for n in G.nodes():
3
scores[n] = (betweenness_c[n] * 0.5 +
4
degree_c[n] * 0.3 +
5
pagerank[n] * 0.2)
6
7
vals = np.array(list(scores.values()))
8
media = np.mean(vals)
9
std = np.std(vals)
10
umbral_z = 1.5
11
12
print(f”Score: mu={media:.4f}, sigma={std:.4f}”)
13
print(f”Umbral anomalia: z > {umbral_z} ”
14
f”=> score > {media + umbral_z * std:.4f}\n”)
15
16
anomalos = {}
17
for n in G.nodes():
18
z = (scores[n] - media) / std if std > 0 else 0
19
if z > umbral_z:
20
tipo, nm = nodos[n]
21
anomalos[n] = z
22
print(f”[ANOMALO] ID={n:>2} | {nm:<20} | {tipo:<10} | z={z:.2
23
f}”)
Listing 4.1: Score compuesto y detección por z-score
Score: mu=0.0959, sigma=0.1459
1
Umbral anomalia: z > 1.5 => score > 0.3148
2
3
[ANOMALO] ID= 1 | Router-Core | router | z=2.71
4
[ANOMALO] ID= 7 | Router-LAN-B | router | z=2.50
5
[ANOMALO] ID= 6 | Router-LAN-A | router | z=1.71
6
Listing 4.2: Nodos anómalos detectados
(cid:102) Hallazgo
Nodos críticos detectados Los tres routers de agregación dominan el tráfico
de la red. En un entorno real, estos nodos serían objetivos prioritarios para
hardening, microsegmentación y monitoreo intensivo en el SIEM.
10


| # Score compuesto ponderado |
| scores = {} |
| for n in G.nodes(): |
| scores[n] = (betweenness_c[n] * 0.5 + |
| degree_c[n] * 0.3 + |
| pagerank[n] * 0.2) |
|  |
| vals = np.array(list(scores.values())) |
| media = np.mean(vals) |
| std = np.std(vals) |
| umbral_z = 1.5 |
|  |
| print(f”Score: mu={media:.4f}, sigma={std:.4f}”) |
| print(f”Umbral anomalia: z > {umbral_z} ” |
| f”=> score > {media + umbral_z * std:.4f}\n”) |
|  |
| anomalos = {} |
| for n in G.nodes(): |
| z = (scores[n] - media) / std if std > 0 else 0 |
| if z > umbral_z: |
| tipo, nm = nodos[n] |
| anomalos[n] = z |
| print(f”[ANOMALO] ID={n:>2} | {nm:<20} | {tipo:<10} | z={z:.2 |
| f}”) |


| Score: mu=0.0959, sigma=0.1459 |
| Umbral anomalia: z > 1.5 => score > 0.3148 |
|  |
| [ANOMALO] ID= 1 | Router-Core | router | z=2.71 |
| [ANOMALO] ID= 7 | Router-LAN-B | router | z=2.50 |
| [ANOMALO] ID= 6 | Router-LAN-A | router | z=1.71 |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
(cid:173) PreguntasdeAnálisis
P6. Modifiqueelumbralaz > 2.0.¿Cuántosnodossedetectanahora?¿Cómo
balancearía el umbral en un entorno de producción (SIEM)?
P7. Añada Closeness Centrality al score compuesto con peso 0.1
(redistribuyendo los demás pesos). ¿Cambian los nodos detectados?
11


| (cid:173) PreguntasdeAnálisis |
| P6. Modifiqueelumbralaz > 2.0.¿Cuántosnodossedetectanahora?¿Cómo
balancearía el umbral en un entorno de producción (SIEM)?
P7. Añada Closeness Centrality al score compuesto con peso 0.1
(redistribuyendo los demás pesos). ¿Cambian los nodos detectados? |

Capítulo 5
Parte 4: Simulación de Propagación de Malware (Modelo
SIR)
(cid:174) Nota
Parámetros de simulación
• Nodoinicial: IoT-Device1 (ID=15)
• Pasos: 20
• β: 0.3 (tasa de infección)
• γ: 0.1 (tasa de recuperación)
R = β/γ = 3 ⇒ Condición de epidemia (R > 1).
0 0
def simular_sir(G, nodo_inicial, beta=0.3, gamma=0.1, pasos=20):
1
”””Modelo SIR discreto sobre grafo. Retorna historiales S, I, R.
2
”””
estado = {n: ’S’ for n in G.nodes()}
3
estado[nodo_inicial] = ’I’
4
hS, hI, hR = [], [], []
5
6
for paso in range(pasos):
7
nuevo_estado = estado.copy()
8
for nodo in G.nodes():
9
if estado[nodo] == ’I’:
10
# Intentar infectar vecinos susceptibles
11
for vecino in G.neighbors(nodo):
12
if estado[vecino] == ’S’ and random.random() < beta:
13
nuevo_estado[vecino] = ’I’
14
# Recuperacion espontanea
15
if random.random() < gamma:
16
nuevo_estado[nodo] = ’R’
17
estado = nuevo_estado
18
s = sum(v == ’S’ for v in estado.values())
19
i = sum(v == ’I’ for v in estado.values())
20
r = sum(v == ’R’ for v in estado.values())
21
hS.append(s); hI.append(i); hR.append(r)
22
23
return hS, hI, hR, estado
24
25
# Ejecutar simulacion desde IoT-Device1
26
hS, hI, hR, estado_final = simular_sir(G, nodo_inicial=15)
27
28
12


| def simular_sir(G, nodo_inicial, beta=0.3, gamma=0.1, pasos=20): |
| ”””Modelo SIR discreto sobre grafo. Retorna historiales S, I, R. |
| ””” |
| estado = {n: ’S’ for n in G.nodes()} |
| estado[nodo_inicial] = ’I’ |
| hS, hI, hR = [], [], [] |
|  |
| for paso in range(pasos): |
| nuevo_estado = estado.copy() |
| for nodo in G.nodes(): |
| if estado[nodo] == ’I’: |
| # Intentar infectar vecinos susceptibles |
| for vecino in G.neighbors(nodo): |
| if estado[vecino] == ’S’ and random.random() < beta: |
| nuevo_estado[vecino] = ’I’ |
| # Recuperacion espontanea |
| if random.random() < gamma: |
| nuevo_estado[nodo] = ’R’ |
| estado = nuevo_estado |
| s = sum(v == ’S’ for v in estado.values()) |
| i = sum(v == ’I’ for v in estado.values()) |
| r = sum(v == ’R’ for v in estado.values()) |
| hS.append(s); hI.append(i); hR.append(r) |
|  |
| return hS, hI, hR, estado |
|  |
| # Ejecutar simulacion desde IoT-Device1 |
| hS, hI, hR, estado_final = simular_sir(G, nodo_inicial=15) |
|  |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
# Visualizar curvas SIR
29
fig, ax = plt.subplots(figsize=(8, 4))
30
pasos = range(1, len(hS) + 1)
31
ax.plot(pasos, hS, color=’#2196F3’, lw=2, label=’Susceptibles (S)’)
32
ax.plot(pasos, hI, color=’#A51008’, lw=2, label=’Infectados (I)’)
33
ax.plot(pasos, hR, color=’#4CAF50’, lw=2, label=’Recuperados (R)’)
34
ax.fill_between(pasos, hI, alpha=0.15, color=’#A51008’)
35
ax.set_xlabel(’Paso de tiempo’); ax.set_ylabel(’Nodos’)
36
ax.set_title(’Propagacion de Malware - Modelo SIR (origen: IoT-
37
Device1)’)
ax.legend(); ax.grid(alpha=0.3)
38
plt.tight_layout()
39
plt.savefig(’sir_propagacion.png’, dpi=150)
40
Listing 5.1: Implementación del modelo SIR sobre el grafo
(cid:173) PreguntasdeAnálisis
P8. Ejecute la simulación cambiando el nodo inicial a Router-Core (ID=1).
Compare la tasa de ataque final
|R|/n
con la simulación desde IoT-
Device1. ¿Por qué difieren?
P9. Experimente con β ∈ {0.1,0.2,0.3,0.5} manteniendo γ = 0.1. ¿Para qué
valor de β se tiene R < 1 y la infección se extingue?
0
P10. Implemente una estrategia de cuarentena: después del paso 5, elimine
las aristas del nodo más infectado. ¿Cómo cambian las curvas SIR?
13


| # Visualizar curvas SIR |
| fig, ax = plt.subplots(figsize=(8, 4)) |
| pasos = range(1, len(hS) + 1) |
| ax.plot(pasos, hS, color=’#2196F3’, lw=2, label=’Susceptibles (S)’) |
| ax.plot(pasos, hI, color=’#A51008’, lw=2, label=’Infectados (I)’) |
| ax.plot(pasos, hR, color=’#4CAF50’, lw=2, label=’Recuperados (R)’) |
| ax.fill_between(pasos, hI, alpha=0.15, color=’#A51008’) |
| ax.set_xlabel(’Paso de tiempo’); ax.set_ylabel(’Nodos’) |
| ax.set_title(’Propagacion de Malware - Modelo SIR (origen: IoT- |
| Device1)’) |
| ax.legend(); ax.grid(alpha=0.3) |
| plt.tight_layout() |
| plt.savefig(’sir_propagacion.png’, dpi=150) |

Capítulo 6
Parte 5: Resiliencia — Nodos de Articulación y Puentes
# Nodos de articulacion (cut vertices)
1
articulation_pts = list(nx.articulation_points(G))
2
print(f”Nodos de articulacion ({len(articulation_pts)} encontrados)
3
:”)
for n in articulation_pts:
4
tipo, nm = nodos[n]
5
print(f” ID={n:>2} | {nm:<20} | Grado={G.degree(n)}”)
6
7
# Puentes (Single Points of Failure)
8
bridges = list(nx.bridges(G))
9
print(f”\nPuentes criticos ({len(bridges)} encontrados):”)
10
for u, v in bridges:
11
print(f” {nodos[u][1]} <--> {nodos[v][1]}”)
12
13
# Analisis de impacto: eliminar Router-Core
14
G_test = G.copy()
15
G_test.remove_node(1) # Eliminar Router-Core
16
componentes = list(nx.connected_components(G_test))
17
print(f”\nSin Router-Core: {len(componentes)} componentes”)
18
print(f”Tamanos: {sorted([len(c) for c in componentes], reverse=
19
True)}”)
Listing 6.1: Identificación de activos críticos de infraestructura
Nodos de articulacion (3 encontrados):
1
ID= 1 | Router-Core | Grado=4
2
ID= 6 | Router-LAN-A | Grado=6
3
ID= 7 | Router-LAN-B | Grado=8
4
5
Puentes criticos (13 encontrados):
6
FW-Perimetral <--> Router-Core
7
Router-Core <--> Router-LAN-A
8
Router-Core <--> Router-LAN-B
9
... (10 puentes adicionales a hosts/IoT)
10
11
Sin Router-Core: 3 componentes
12
Tamanos: [9, 7, 2]
13
Listing 6.2: Resultados de resiliencia
(cid:173) PreguntasdeAnálisis
P11. La eliminación de Router-Core divide la red en 3 componentes. ¿Qué
hosts quedan aislados? ¿Cómo afecta esto a la operación del negocio?
14


| # Nodos de articulacion (cut vertices) |
| articulation_pts = list(nx.articulation_points(G)) |
| print(f”Nodos de articulacion ({len(articulation_pts)} encontrados) |
| :”) |
| for n in articulation_pts: |
| tipo, nm = nodos[n] |
| print(f” ID={n:>2} | {nm:<20} | Grado={G.degree(n)}”) |
|  |
| # Puentes (Single Points of Failure) |
| bridges = list(nx.bridges(G)) |
| print(f”\nPuentes criticos ({len(bridges)} encontrados):”) |
| for u, v in bridges: |
| print(f” {nodos[u][1]} <--> {nodos[v][1]}”) |
|  |
| # Analisis de impacto: eliminar Router-Core |
| G_test = G.copy() |
| G_test.remove_node(1) # Eliminar Router-Core |
| componentes = list(nx.connected_components(G_test)) |
| print(f”\nSin Router-Core: {len(componentes)} componentes”) |
| print(f”Tamanos: {sorted([len(c) for c in componentes], reverse= |
| True)}”) |


| Nodos de articulacion (3 encontrados): |
| ID= 1 | Router-Core | Grado=4 |
| ID= 6 | Router-LAN-A | Grado=6 |
| ID= 7 | Router-LAN-B | Grado=8 |
|  |
| Puentes criticos (13 encontrados): |
| FW-Perimetral <--> Router-Core |
| Router-Core <--> Router-LAN-A |
| Router-Core <--> Router-LAN-B |
| ... (10 puentes adicionales a hosts/IoT) |
|  |
| Sin Router-Core: 3 componentes |
| Tamanos: [9, 7, 2] |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
P12. Proponga las aristasmínimas a añadir para eliminar todos los puentes y
garantizar 2-conectividad en la red. Implemente los cambios y verifique
con nx.is_2_edge_connected(G).
15

Capítulo 7
Desafío Extra: Detección de Botnet
(cid:193) Advertencia
Escenario avanzado Una botnet se caracteriza por un conjunto de nodos que
secomunicandensamenteentresí(comandoycontrolC&C)perotienenpocas
conexiones hacia el resto de la red. En grafos, esto genera una comunidad con
altamodularidadinternaybajacentralidaddeintermediaciónhaciaelexterior.
# Agregar nodos botnet al grafo existente
1
G_botnet = G.copy()
2
bot_ids = list(range(20, 25)) # 5 nodos bot
3
4
for bid in bot_ids:
5
G_botnet.add_node(bid, tipo=’bot’, nombre=f’Bot-{bid-19}’)
6
7
# Conexiones internas densas (C&C)
8
for i in bot_ids:
9
for j in bot_ids:
10
if i < j:
11
G_botnet.add_edge(i, j, weight=100)
12
13
# Pocas conexiones externas (canal de exfiltracion)
14
G_botnet.add_edge(bot_ids[0], 9, weight=1) # Bot maestro -> PC-
15
User1
G_botnet.add_edge(bot_ids[0], 12, weight=1) # Bot maestro -> PC-
16
User4
17
# Recalcular metricas
18
bc_botnet = nx.betweenness_centrality(G_botnet)
19
cc_botnet = nx.average_clustering(G_botnet, nodes=bot_ids)
20
print(f”Clustering interno botnet: {cc_botnet:.4f}”) # Cercano a
21
1.0
print(f”Clustering red normal: ”
22
f”{nx.average_clustering(G_botnet, nodes=list(range(20))):.4f}
23
”)
24
# Deteccion por algoritmo Louvain (comunidades)
25
try:
26
from networkx.algorithms.community import louvain_communities
27
comunidades = louvain_communities(G_botnet, seed=42)
28
for i, com in enumerate(comunidades):
29
bots_en_com = com & set(bot_ids)
30
if bots_en_com:
31
print(f”Comunidad {i}: contiene bots {bots_en_com}”)
32
16


| # Agregar nodos botnet al grafo existente |
| G_botnet = G.copy() |
| bot_ids = list(range(20, 25)) # 5 nodos bot |
|  |
| for bid in bot_ids: |
| G_botnet.add_node(bid, tipo=’bot’, nombre=f’Bot-{bid-19}’) |
|  |
| # Conexiones internas densas (C&C) |
| for i in bot_ids: |
| for j in bot_ids: |
| if i < j: |
| G_botnet.add_edge(i, j, weight=100) |
|  |
| # Pocas conexiones externas (canal de exfiltracion) |
| G_botnet.add_edge(bot_ids[0], 9, weight=1) # Bot maestro -> PC- |
| User1 |
| G_botnet.add_edge(bot_ids[0], 12, weight=1) # Bot maestro -> PC- |
| User4 |
|  |
| # Recalcular metricas |
| bc_botnet = nx.betweenness_centrality(G_botnet) |
| cc_botnet = nx.average_clustering(G_botnet, nodes=bot_ids) |
| print(f”Clustering interno botnet: {cc_botnet:.4f}”) # Cercano a |
| 1.0 |
| print(f”Clustering red normal: ” |
| f”{nx.average_clustering(G_botnet, nodes=list(range(20))):.4f} |
| ”) |
|  |
| # Deteccion por algoritmo Louvain (comunidades) |
| try: |
| from networkx.algorithms.community import louvain_communities |
| comunidades = louvain_communities(G_botnet, seed=42) |
| for i, com in enumerate(comunidades): |
| bots_en_com = com & set(bot_ids) |
| if bots_en_com: |
| print(f”Comunidad {i}: contiene bots {bots_en_com}”) |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
except ImportError:
33
print(”Instalar: pip install networkx[default]”)
34
Listing 7.1: Simulación e identificación de una botnet
(cid:173) PreguntasdeAnálisis
P13. ¿Qué métrica distingue mejor a los nodos bot del resto? ¿Degree
Centrality, Betweenness o Clustering Coefficient? Justifique.
P14. ElalgoritmodeLouvaindetectacomunidadesconaltamodularidad.¿Por
qué los nodos bot forman una comunidad separada?
P15. Diseñe un sistema de alertas que combine tres umbrales (clustering
> 0.8, betweenness externo < 0.01, degree externo < 2) para detectar
botnets automáticamente.
7.1 Rúbrica de Evaluación
Cuadro 4: Rúbrica de evaluación de la práctica
Criterio Excelente(10) Satisfactorio Mínimo(5) Peso
(7)
Construcción del G correcto G correcto sin G incompleto 15%
grafo con todos los atributos
atributos y
visualización
Métricas de 4 métricas 3 métricas 2 métricas 20%
centralidad + análisis correctas
comparativo
completo
Detección de Z-score + Z-score Identifica 20%
anomalías justificación correcto anomalías
del umbral
Simulación SIR Código + Código Intento de 20%
análisis de β + funcional simulación
gráficas
Resiliencia Articulación + Identifica Lista parcial 15%
propuesta de correctamente
mejoras
Respuestas escritas Todas las 8 de 13 5 de 13 10%
preguntas preguntas preguntas
+ reflexión
crítica
17


| except ImportError: |
| print(”Instalar: pip install networkx[default]”) |


| Excelente(10) | Satisfactorio
(7) | Mínimo(5) |


| 4 métricas
+ análisis
comparativo
completo | 3 métricas
correctas | 2 métricas |


| Código +
análisis de β +
gráficas | Código
funcional | Intento de
simulación |


| Todas las
preguntas
+ reflexión
crítica | 8 de 13
preguntas | 5 de 13
preguntas |

DETECCIÓNDEANOMALÍASENREDES UNIVERSIDADDECUENCA
FormatodeEntrega
1. ArchivoPython:practica_redes_[apellido].pyconcódigocompletamente
comentado.
2. ReportePDF:Documentoconrespuestasjustificadasalas13preguntas(mínimo
3 párrafos por pregunta).
3. Visualizaciones:Capturasdepantallaofigurasexportadasdelosseispaneles
generados por matplotlib.
4. Plazo: Una semana desde la sesión de laboratorio.
18

Capítulo A
Referencias
[1] Barabási, A.-L. (2016). Network Science. Cambridge University Press. http://
networksciencebook.com
[2] Newman, M. E. J. (2010). Networks: An Introduction. Oxford University Press.
[3] Hagberg,A.,Swart,P.,&Schult,D.(2008).Exploringnetworkstructure,dynamics,
andfunctionusingNetworkX.Proc.7thPythoninScienceConference(SciPy2008),
11–15.
[4] Chakrabarti, D., Wang, Y., Wang, C., Leskovic, J., & Faloutsos, C. (2008). Epidemic
thresholds in real networks. ACM TISSEC, 10(4), 1–26.
[5] Strogatz, S. H. (2001). Exploring complex networks. Nature, 410, 268–276.
[6] Boccaletti,S.,etal.(2006).Complexnetworks:Structureanddynamics.Physics
Reports, 424(4–5), 175–308.
[7] García, S., Parmisano, A., & Erquiaga, M. J. (2020). IoT-23: A labeled dataset with
maliciousandbenignIoTnetworktraffic(Version1.0.0)[Dataset].Stratosphere
Laboratory, CTU University, Prague. https://www.stratosphereips.or
g/datasets-iot23
UCUENCA | FacultaddeIngeniería | MaestríaenCienciasdelaIngenieríaEléctrica | #UCuenca
#LaUQueVive #SeguridadDeRedes
19

