# Segmentacion de VLANs con K-means sobre trafico sintetico

Este modulo implementa un flujo reproducible para:

1. Generar un conjunto sintetico de hosts con direcciones IP privadas.
2. Simular trafico de red en formato tabular tipo PCAP (`src_ip`, `dst_ip`, `packets`, `bytes`, `ts`).
3. Extraer caracteristicas por host.
4. Aplicar K-means para inferir grupos de segmentacion tipo VLAN.
5. Exportar la tabla de VLANs y grafos en formato de aristas (global y por VLAN).

## Estructura

- `run_vlan_kmeans.jl`: Script principal del pipeline.
- `results/synthetic_pcap_like_flows.csv`: Flujos sinteticos (equivalente tabular a un PCAP).
- `results/tabla_vlans.csv`: Asignacion de IP a VLAN inferida.
- `results/flujos_con_vlan.csv`: Flujos con etiqueta de VLAN de origen y destino.
- `results/grafo_global_aristas.csv`: Grafo global agregado por aristas.
- `results/grafo_vlan_*_aristas.csv`: Subgrafos intra-VLAN por aristas.
- `results/grafo_inter_vlan_aristas.csv`: Aristas entre VLANs diferentes.

## Ejecucion

Desde esta carpeta:

```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
julia --project=. run_vlan_kmeans.jl
```

## Observaciones tecnicas

- El archivo `synthetic_pcap_like_flows.csv` es una representacion analitica del trafico; no es un archivo binario `.pcap`.
- Si se requiere un `.pcap` real para Wireshark o Zeek, se puede agregar un exportador adicional en Python (Scapy) o una etapa de conversion externa.
- La columna `latent_vlan_ref` en `tabla_vlans.csv` se incluye solo como referencia para validar la calidad del agrupamiento sintetico.
