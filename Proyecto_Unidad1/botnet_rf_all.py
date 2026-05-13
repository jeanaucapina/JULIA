"""
Entrena Random Forest sobre TODAS las capturas IoT-23.
Features por nodo (IP) extraídas de conexiones bidireccionales.
Split estratificado 70/30 por nodo.
Genera gráfica de red con nodos predichos como botnet.
"""

import os, math, random
from collections import defaultdict
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches

from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import StratifiedShuffleSplit

BASE = Path(r"C:\Users\jeanj\Documents\GitHub\JULIA\Proyecto_Unidad1\iot_23_datasets_small\opt\Malware-Project\BigDataset\IoTScenarios")
OUT  = Path(r"C:\Users\jeanj\Documents\GitHub\JULIA\Proyecto_Unidad1")

# ── helpers ──────────────────────────────────────────────────────────────────

def parse_label(raw: str) -> str:
    r = raw.lower()
    if "malicious" in r: return "malicious"
    if "benign"    in r: return "benign"
    return "other"

def parse_conn(path: Path):
    """Lee conn.log.labeled, devuelve lista de dicts por conexión."""
    rows = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith('#'): continue
            cols = line.rstrip('\n').split('\t')
            if len(cols) < 21: continue
            try:
                src   = cols[2]
                dst   = cols[4]
                dport = int(cols[5])   if cols[5].isdigit() else None
                proto = cols[6]
                obytes= float(cols[9])  if cols[9]  not in ('-','') else 0.0
                rbytes= float(cols[10]) if cols[10] not in ('-','') else 0.0
                label = parse_label(cols[20])
                rows.append((src, dst, dport, proto, obytes, rbytes, label))
            except Exception:
                continue
    return rows

def extract_features(rows):
    """
    Devuelve (ips, X, y_gt) donde:
      ips  : lista de IPs (strings)
      X    : ndarray (n_ips, 8) float32
      y_gt : lista de strings ('malicious'/'benign'/'other')
    """
    out_total  = defaultdict(int)
    in_total   = defaultdict(int)
    out_mal    = defaultdict(int)
    in_mal     = defaultdict(int)
    out_dports = defaultdict(set)
    in_dports  = defaultdict(set)
    out_bytes  = defaultdict(float)
    in_bytes   = defaultdict(float)
    out_protos = defaultdict(set)
    votes      = defaultdict(lambda: defaultdict(int))
    edge_freq  = defaultdict(int)
    all_ips    = set()

    for src, dst, dport, proto, ob, rb, label in rows:
        all_ips.add(src); all_ips.add(dst)

        out_total[src] += 1
        in_total[dst]  += 1
        if label == "malicious":
            out_mal[src] += 1
            in_mal[dst]  += 1
        if dport is not None:
            out_dports[src].add(dport)
            in_dports[dst].add(dport)
        out_bytes[src] += ob
        in_bytes[dst]  += rb
        out_protos[src].add(proto)
        votes[src][label] += 1
        edge_freq[(src, dst)] += 1

    ips = sorted(all_ips)
    idx = {ip: i for i, ip in enumerate(ips)}

    # Grado no dirigido
    adj = defaultdict(set)
    for (s, d) in edge_freq:
        if s != d:
            adj[s].add(d); adj[d].add(s)
    deg = {ip: len(nb) for ip, nb in adj.items()}
    max_deg = max(deg.values(), default=1)

    # Features
    feats = []
    for ip in ips:
        ot  = out_total[ip]
        it  = in_total[ip]
        f1  = out_mal[ip] / ot if ot > 0 else 0.0          # tasa out malicious
        f2  = in_mal[ip]  / it if it > 0 else 0.0          # tasa in  malicious
        f3  = deg.get(ip, 0) / max_deg                      # grado norm
        f4  = len(out_dports[ip]) / max(ot, 1)             # out port diversity
        f5  = len(in_dports[ip])  / max(it, 1)             # in  port diversity
        f6  = math.log1p(out_bytes[ip]) / math.log1p(in_bytes[ip] + 1)  # byte ratio
        f6  = min(f6, 10.0) / 10.0                          # clamped & norm
        f7  = len(out_protos[ip]) / 5.0                     # diversidad protocolos
        f8  = math.log1p(ot + it)                           # volumen total (log)
        feats.append([f1, f2, f3, f4, f5, f6, f7, f8])

    X = np.array(feats, dtype=np.float32)

    # Ground truth
    y_gt = []
    for ip in ips:
        v = votes[ip]
        if v["malicious"] > v["benign"]:
            y_gt.append("malicious")
        elif v["benign"] > v["malicious"]:
            y_gt.append("benign")
        else:
            y_gt.append("other")

    return ips, X, y_gt, edge_freq

# ── cargar todas las capturas ─────────────────────────────────────────────────

print("Cargando capturas...")
all_ips_list = []
all_X        = []
all_y        = []
capture_of   = []   # qué captura pertenece cada nodo

for cap_dir in sorted(BASE.iterdir()):
    conn_file = cap_dir / "bro" / "conn.log.labeled"
    if not conn_file.exists():
        print(f"  [skip] {cap_dir.name} — sin conn.log.labeled")
        continue
    print(f"  Leyendo {cap_dir.name}...", end=" ", flush=True)
    rows = parse_conn(conn_file)
    if not rows:
        print("vacío")
        continue
    ips, X, y_gt, _ = extract_features(rows)
    n_mal = y_gt.count("malicious")
    print(f"{len(ips)} IPs, {n_mal} malicious")
    for ip, x, y in zip(ips, X, y_gt):
        all_ips_list.append(f"{cap_dir.name}::{ip}")
        all_X.append(x)
        all_y.append(y)
        capture_of.append(cap_dir.name)

all_X = np.array(all_X, dtype=np.float32)
all_y = np.array(all_y)
print(f"\nTotal nodos: {len(all_y)}")
print(f"  malicious : {(all_y=='malicious').sum()}")
print(f"  benign    : {(all_y=='benign').sum()}")
print(f"  other     : {(all_y=='other').sum()}")

# ── split estratificado 70/30 sobre nodos conocidos ──────────────────────────

known_mask = all_y != "other"
known_idx  = np.where(known_mask)[0]
X_k = all_X[known_idx]
y_k = all_y[known_idx]

sss = StratifiedShuffleSplit(n_splits=1, test_size=0.30, random_state=42)
train_rel, test_rel = next(sss.split(X_k, y_k))
train_idx = known_idx[train_rel]
test_idx  = known_idx[test_rel]

print(f"\nTrain: {len(train_idx)} nodos  (malicious={( all_y[train_idx]=='malicious').sum()})")
print(f"Test:  {len(test_idx)}  nodos  (malicious={( all_y[test_idx] =='malicious').sum()})")

# ── entrenar Random Forest ────────────────────────────────────────────────────

print("\nEntrenando Random Forest...")
clf = RandomForestClassifier(
    n_estimators=200,
    max_depth=12,
    class_weight="balanced",   # maneja desbalance automáticamente
    n_jobs=-1,
    random_state=42,
)
clf.fit(all_X[train_idx], all_y[train_idx])

y_pred_test = clf.predict(all_X[test_idx])

print("\n=== Reporte de clasificación (test 30%) ===")
print(classification_report(all_y[test_idx], y_pred_test, digits=4))
print("Matriz de confusión:")
labels_order = ["malicious", "benign"]
cm = confusion_matrix(all_y[test_idx], y_pred_test, labels=labels_order)
print(f"             pred_mal  pred_ben")
for i, lab in enumerate(labels_order):
    print(f"  real_{lab[:3]:3s}   {cm[i,0]:8d}  {cm[i,1]:8d}")

# Feature importance
feat_names = ["out_mal_rate","in_mal_rate","degree","out_port_div","in_port_div","byte_ratio","proto_div","log_volume"]
print("\nImportancia de features:")
for name, imp in sorted(zip(feat_names, clf.feature_importances_), key=lambda x: -x[1]):
    print(f"  {name:20s}  {imp:.4f}")

# ── predecir todo el dataset ──────────────────────────────────────────────────

y_all = clf.predict(all_X)
print(f"\nNodos predichos botnet (global): {(y_all=='malicious').sum()}")

# ── gráfica: una captura por subplot ─────────────────────────────────────────

captures = sorted(set(capture_of))
n_caps   = len(captures)
ncols    = 4
nrows    = math.ceil(n_caps / ncols)

fig, axes = plt.subplots(nrows, ncols, figsize=(ncols*5, nrows*4.5))
axes = axes.flatten()

# Recargar edge_freq por captura para dibujar aristas
print("\nGenerando gráfica por capturas...")
for ax_i, cap_name in enumerate(captures):
    ax = axes[ax_i]
    ax.set_aspect('equal'); ax.axis('off')
    ax.set_title(cap_name.replace("CTU-","").replace("IoT-Malware-","").replace("Honeypot-","H-"),
                 fontsize=7, pad=3)

    # Índices globales de esta captura
    cap_mask  = np.array(capture_of) == cap_name
    cap_gidx  = np.where(cap_mask)[0]
    if len(cap_gidx) == 0: continue

    cap_ips_full = [all_ips_list[i] for i in cap_gidx]  # "capname::ip"
    cap_ips      = [s.split("::",1)[1] for s in cap_ips_full]
    cap_pred     = y_all[cap_gidx]
    cap_gt       = all_y[cap_gidx]

    # Filtrar: solo nodos botnet predichos + vecinos directos (max 200 nodos)
    # Reconstruir aristas desde archivo
    conn_file = BASE / cap_name / "bro" / "conn.log.labeled"
    rows = parse_conn(conn_file)
    _, _, _, edge_freq = extract_features(rows)

    ip_set  = set(cap_ips)
    ip_local_idx = {ip: j for j, ip in enumerate(cap_ips)}
    pred_bot_ips = {cap_ips[j] for j, p in enumerate(cap_pred) if p == "malicious"}

    # Vecinos de nodos botnet
    neighbors = set(pred_bot_ips)
    for (s, d) in edge_freq:
        if s in pred_bot_ips and d in ip_set: neighbors.add(d)
        if d in pred_bot_ips and s in ip_set: neighbors.add(s)
    vis_ips = sorted(neighbors)[:200]
    if len(vis_ips) == 0:
        vis_ips = sorted(pred_bot_ips)[:10] if pred_bot_ips else cap_ips[:50]

    nv = len(vis_ips)
    if nv == 0: continue
    vis_set = set(vis_ips)
    ang = np.linspace(0, 2*np.pi, nv, endpoint=False)
    xc  = np.cos(ang); yc = np.sin(ang)
    vpos = {ip: (xc[j], yc[j]) for j, ip in enumerate(vis_ips)}

    # Aristas (sin hub dominante)
    adj_vis = defaultdict(int)
    for (s, d), freq in edge_freq.items():
        if s in vis_set and d in vis_set and s != d:
            adj_vis[s] += 1; adj_vis[d] += 1
    hub = max(adj_vis, key=adj_vis.get) if adj_vis else None
    hub_deg = adj_vis[hub] if hub else 0
    total_e = sum(adj_vis.values()) / 2
    suppress_hub = hub and (hub_deg / max(total_e, 1) > 0.3)

    for (s, d) in edge_freq:
        if s not in vis_set or d not in vis_set or s == d: continue
        if suppress_hub and (s == hub or d == hub): continue
        ax.plot([vpos[s][0], vpos[d][0]], [vpos[s][1], vpos[d][1]],
                color='#aaaaaa', lw=0.3, alpha=0.4, zorder=1)

    # Nodos
    for ip in vis_ips:
        x0, y0 = vpos[ip]
        j_local = ip_local_idx.get(ip)
        pred = cap_pred[j_local] if j_local is not None else "other"
        gt   = cap_gt[j_local]   if j_local is not None else "other"
        if gt == "malicious":
            color, marker, size, zorder = 'limegreen', '*', 120, 4
        elif pred == "malicious":
            color, marker, size, zorder = 'crimson',   '*', 100, 4
        else:
            color, marker, size, zorder = 'steelblue', 'o', 20,  2
        ax.scatter(x0, y0, c=color, marker=marker, s=size, zorder=zorder,
                   linewidths=0, alpha=0.9)

    n_pred = sum(1 for ip in vis_ips if ip_local_idx.get(ip) is not None and cap_pred[ip_local_idx[ip]] == "malicious")
    n_gt   = sum(1 for ip in vis_ips if ip_local_idx.get(ip) is not None and cap_gt[ip_local_idx[ip]]   == "malicious")
    ax.text(0, -1.18, f"pred={n_pred} gt={n_gt}", ha='center', fontsize=6)

# Apagar ejes sobrantes
for ax_i in range(n_caps, len(axes)):
    axes[ax_i].axis('off')

legend_handles = [
    mpatches.Patch(color='crimson',   label='Pred botnet'),
    mpatches.Patch(color='limegreen', label='GT botnet'),
    mpatches.Patch(color='steelblue', label='Resto'),
]
fig.legend(handles=legend_handles, loc='lower right', fontsize=9, ncol=3)
fig.suptitle("IoT-23 — Detección Botnet (Random Forest, todas las capturas)\n70% train / 30% test estratificado", fontsize=11)
plt.tight_layout(rect=[0, 0.03, 1, 0.97])

out_png = OUT / "botnet_all_captures_rf.png"
fig.savefig(out_png, dpi=130, bbox_inches='tight')
print(f"\nFigura guardada: {out_png}")
plt.close()
