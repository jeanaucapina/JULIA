"""
pcap_export.py — optional module to write a real .pcap from flows CSV.

Requirements:
    pip install scapy

Usage (called by run_pipeline.jl via Cmd):
    python pcap_export.py <flows_csv> <output_pcap>

Each flow row becomes N synthetic packets where N = packets column.
Packet sizes are distributed uniformly so total bytes match.
UDP used for flows with protocol=UDP, TCP SYN for TCP, ICMP echo for ICMP.
Timestamps are derived from the ts column (1 ts-unit = 1 ms).
"""

import sys
import csv
import math
from pathlib import Path

try:
    from scapy.all import (
        Ether, IP, TCP, UDP, ICMP,
        wrpcap, Raw
    )
except ImportError:
    print("ERROR: scapy not installed. Run: pip install scapy", file=sys.stderr)
    sys.exit(2)


def flows_to_packets(flows_csv: str, output_pcap: str) -> int:
    packets = []

    with open(flows_csv, newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            src_ip   = row["src_ip"]
            dst_ip   = row["dst_ip"]
            src_port = int(row.get("src_port", 1024))
            dst_port = int(row.get("dst_port", 80))
            proto    = row.get("protocol", "TCP").upper()
            n_pkts   = max(1, int(row["packets"]))
            total_b  = int(row["bytes"])
            ts_ms    = int(row.get("ts", 0))

            pkt_size = max(20, total_b // n_pkts)
            payload  = bytes(pkt_size - 20) if pkt_size > 20 else b""

            base_ts  = ts_ms / 1000.0  # seconds

            for i in range(n_pkts):
                ts = base_ts + i * 0.001  # 1 ms apart

                ip_layer = IP(src=src_ip, dst=dst_ip)

                if proto == "UDP":
                    transport = UDP(sport=src_port, dport=dst_port)
                elif proto == "ICMP":
                    transport = ICMP(type=8, code=0)
                else:  # default TCP
                    flags = "S" if i == 0 else "PA"
                    transport = TCP(sport=src_port, dport=dst_port, flags=flags)

                pkt = Ether() / ip_layer / transport / Raw(load=payload)
                pkt.time = ts
                packets.append(pkt)

    wrpcap(output_pcap, packets)
    return len(packets)


def main():
    if len(sys.argv) != 3:
        print(f"Usage: python {sys.argv[0]} <flows_csv> <output_pcap>")
        sys.exit(1)

    flows_csv   = sys.argv[1]
    output_pcap = sys.argv[2]

    if not Path(flows_csv).exists():
        print(f"ERROR: input file not found: {flows_csv}", file=sys.stderr)
        sys.exit(1)

    print(f"Reading flows from: {flows_csv}")
    n = flows_to_packets(flows_csv, output_pcap)
    print(f"Written {n} packets to: {output_pcap}")


if __name__ == "__main__":
    main()
