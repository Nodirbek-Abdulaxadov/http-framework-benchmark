#!/usr/bin/env python3
"""Render the README tables for one results dir: ranking, per-endpoint detail, p99."""
import json, sys, os
R = sys.argv[1]
EP = [("ping","`/ping` — Plain Text (500 connections)"),
      ("json-small","`/json-small` — Tiny JSON Object (500 connections)"),
      ("json-large","`/json-large` — 1000-item JSON Array (200 connections, ~42 KB body)"),
      ("cpu","`/cpu` — CPU-Bound Workload (32 connections)"),
      ("async-delay","`/async-delay` — 10 ms `await sleep` (1000 connections)"),
      ("db","`/db` — Single Random Row (64 connections)"),
      ("queries","`/queries` — 20 Random Rows per Request (64 connections)"),
      ("updates","`/updates` — 20 Read+Write Rows per Request (64 connections)")]
SERVERS = ["dotnet-minimal","go-fiber","node-fastify","python-fastapi","rust-axum","jwc-app","liteapi-rust","liteapi-managed"]
SHORT = {"dotnet-minimal":"dotnet","node-fastify":"node","python-fastapi":"python"}
def load(s, e):
    p = os.path.join(R, s, e + ".json")
    if not os.path.exists(p): return None
    r = json.load(open(p))["result"]
    t = r["timeTakenSeconds"]; ok = r["req2xx"]
    non = r["req1xx"] + r["req3xx"] + r["req4xx"] + r["req5xx"]
    pc = r["latency"]["percentiles"]
    return dict(ok=ok, oks=ok/t, rps=r["rps"]["mean"], p50=pc["50"]/1000, p90=pc["90"]/1000, p99=pc["99"]/1000, non=non, err=r["others"])
data = {s: {e: load(s, e) for e, _ in EP} for s in SERVERS}
n = lambda x: f"{x:,.0f}"
out = []
out.append("| Endpoint | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th |\n|---|---|---|---|---|---|---|---|---|")
for e, _ in EP:
    rows = sorted(((data[s][e]["oks"], s) for s in SERVERS if data[s][e]), reverse=True)
    out.append(f"| `/{e}` | " + " | ".join(f"{SHORT.get(s,s)} **{n(v)}**" for v, s in rows) + " |")
out.append("")
for e, title in EP:
    out.append(f"#### {title}\n\n| Server | 2xx/s | RPS mean* | p50 (ms) | p90 (ms) | p99 (ms) | 2xx | non-2xx | client errors |\n|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for _, s in sorted(((data[s][e]["oks"], s) for s in SERVERS if data[s][e]), reverse=True):
        d = data[s][e]
        out.append(f"| **{s}** | **{n(d['oks'])}** | {n(d['rps'])} | {d['p50']:.2f} | {d['p90']:.2f} | {d['p99']:.2f} | {n(d['ok'])} | {n(d['non'])} | {n(d['err'])} |")
    out.append("")
out.append("| Server | " + " | ".join(f"`/{e}`" for e, _ in EP) + " |\n|---|" + "---:|"*len(EP))
best = {e: min(data[s][e]["p99"] for s in SERVERS if data[s][e]) for e, _ in EP}
for s in SERVERS:
    cells = []
    for e, _ in EP:
        d = data[s][e]
        if not d: cells.append("—"); continue
        v = f"{d['p99']:,.2f}"
        cells.append(f"**{v}**" if d["p99"] == best[e] else v)
    out.append(f"| **{s}** | " + " | ".join(cells) + " |")
print("\n".join(out))
