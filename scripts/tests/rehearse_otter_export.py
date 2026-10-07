#!/usr/bin/env python3
"""Offline end-to-end rehearsal of the Otter export (no network, no creds).

Drives cmd_export with a stubbed MCP transport and a stubbed token provider,
then runs the real acceptance checker over the artifacts it produced. Proves
the whole pipeline is wired without contacting Otter.
"""
import io
import os
import sys
import json
import tempfile
import contextlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts import export_otter_mcp as ex
from scripts import acceptance_otter_export as acc
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_otter_mcp import FakeTransport, make_meeting, make_transcript, wrap_twice

# Three months of conversations; month 2 repeats one from month 1 and the
# query sweep repeats two more, so dedupe has real work to do.
BY_MONTH = {
    "2026/01/01": [make_meeting(1, "2026-01-05 09:00:00"),
                   make_meeting(2, "2026-01-19 14:00:00")],
    "2026/02/01": [make_meeting(2, "2026-01-19 14:00:00"),
                   make_meeting(3, "2026-02-10 11:00:00")],
    "2026/03/01": [make_meeting(4, "2026-03-02 16:00:00")],
}
ALL = {m["id"]: m for rows in BY_MONTH.values() for m in rows}


def search(args):
    if args.get("query"):
        return wrap_twice({"results": list(ALL.values())})
    return wrap_twice({"results": BY_MONTH.get(args.get("created_after"), [])})


def fetch(args):
    meeting = ALL[args["id"]]
    return wrap_twice(make_transcript(meeting))


def main():
    transport = FakeTransport({"search": search, "fetch": fetch})
    real_client = ex.OtterMcpClient
    ex.OtterMcpClient = lambda provider, **kw: real_client(
        lambda: "stub-token", transport=transport)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "otter_rehearsal"
            rc = ex.cmd_export(out, "2026-01-01", "2026-03-31",
                               queries=["roadmap"], split_months=True)
            print(f"\ncmd_export rc={rc}")

            files = sorted(p.name for p in out.glob("*.json"))
            print(f"artifacts: {files}")
            summary = json.loads(
                (out / "export_summary.json").read_text(encoding="utf-8"))
            print("export_summary.json:")
            print(json.dumps(summary, indent=2))
            manifest = json.loads(
                (out / "otter_export_manifest.json").read_text(encoding="utf-8"))
            print(f"dedupe: unique={manifest['conversations_unique']} "
                  f"duplicates={manifest['sweep_stats']['duplicates']} "
                  f"rows_seen={manifest['sweep_stats']['rows_seen']} "
                  f"mcp_calls={manifest['mcp_calls']}")

            print("\n--- acceptance checker on the rehearsal artifacts ---")
            arc = acc.main(["acceptance_otter_export.py", str(out)])
            print(f"acceptance rc={arc}")

            blob = "\n".join(p.read_text(encoding="utf-8")
                             for p in out.glob("*.json"))
            leaked = [m for m in ("stub-token", "Bearer", "access_token",
                                  "refresh_token", "Mcp-Session-Id")
                      if m in blob]
            print(f"leaked markers in artifacts: {leaked or 'NONE'}")
            return 0 if (rc == 0 and arc == 0 and not leaked) else 1
    finally:
        ex.OtterMcpClient = real_client


if __name__ == "__main__":
    sys.exit(main())
