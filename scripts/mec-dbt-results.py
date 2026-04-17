#!/usr/bin/env python3

import json
import sys
from datetime import datetime
from pathlib import Path

RESET  = "\033[0m"
BOLD   = "\033[1m"
GREEN  = "\033[38;2;80;250;123m"
RED    = "\033[38;2;255;85;85m"
YELLOW = "\033[38;2;241;250;140m"
GRAY   = "\033[38;2;98;114;164m"
CYAN   = "\033[38;2;139;233;253m"
FG     = "\033[38;2;248;248;242m"


def _short_name(unique_id: str) -> str:
    parts = unique_id.split(".")
    return parts[-1] if parts else unique_id


def _format_elapsed(seconds: float) -> str:
    if seconds < 1.0:
        return f"{int(seconds * 1000)}ms"
    return f"{seconds:.1f}s"


def _calc_elapsed(timing: list) -> float:
    if not timing:
        return 0.0
    started = None
    completed = None
    for entry in timing:
        if entry.get("name") in ("execute", "compile", "execute_node"):
            s = entry.get("started_at", "")
            c = entry.get("completed_at", "")
            if s and c:
                try:
                    fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
                    dt_s = datetime.strptime(s, fmt)
                    dt_c = datetime.strptime(c, fmt)
                    return (dt_c - dt_s).total_seconds()
                except ValueError:
                    pass
    for entry in timing:
        s = entry.get("started_at", "")
        c = entry.get("completed_at", "")
        if s and c:
            try:
                fmt = "%Y-%m-%dT%H:%M:%S.%fZ"
                dt_s = datetime.strptime(s, fmt)
                dt_c = datetime.strptime(c, fmt)
                elapsed = (dt_c - dt_s).total_seconds()
                if elapsed > 0:
                    if started is None or dt_s < started:
                        started = dt_s
                    if completed is None or dt_c > completed:
                        completed = dt_c
            except ValueError:
                pass
    if started and completed:
        return (completed - started).total_seconds()
    return 0.0


def _status_color(status: str) -> str:
    s = status.lower()
    if s in ("success", "pass"):
        return GREEN
    if s in ("error", "fail", "runtime error"):
        return RED
    if s in ("warn",):
        return YELLOW
    if s in ("skip", "skipped"):
        return GRAY
    return FG


def _render_stdlib(rows: list, col_widths: tuple) -> None:
    w_model, w_status, w_time, w_msg = col_widths
    header = f"  {GRAY}{BOLD}{'MODELO':<{w_model}} {'STATUS':<{w_status}} {'TEMPO':<{w_time}} MENSAGEM{RESET}"
    sep = f"  {GRAY}{'─' * (w_model + w_status + w_time + 30)}{RESET}"
    print(header)
    print(sep)
    for model, status, elapsed, msg, color in rows:
        print(
            f"  {FG}{model:<{w_model}}{RESET} "
            f"{color}{status:<{w_status}}{RESET} "
            f"{CYAN}{elapsed:<{w_time}}{RESET} "
            f"{GRAY}{msg}{RESET}"
        )


def _render_tabulate(rows: list, col_widths: tuple) -> None:
    from tabulate import tabulate

    table_rows = []
    for model, status, elapsed, msg, color in rows:
        table_rows.append([
            f"{FG}{model}{RESET}",
            f"{color}{status}{RESET}",
            f"{CYAN}{elapsed}{RESET}",
            f"{GRAY}{msg}{RESET}",
        ])
    headers = [
        f"{GRAY}{BOLD}MODELO{RESET}",
        f"{GRAY}{BOLD}STATUS{RESET}",
        f"{GRAY}{BOLD}TEMPO{RESET}",
        f"{GRAY}{BOLD}MENSAGEM{RESET}",
    ]
    print()
    print(tabulate(table_rows, headers=headers, tablefmt="plain"))


def main() -> int:
    if len(sys.argv) < 2:
        print(
            "[ERRO] Uso: mec-dbt-results.py <run_results.json>",
            file=sys.stderr,
        )
        return 1

    results_path = Path(sys.argv[1])
    if not results_path.exists():
        print(
            f"[ERRO] Arquivo não encontrado: {results_path}",
            file=sys.stderr,
        )
        return 2

    with open(results_path, encoding="utf-8") as fh:
        data = json.load(fh)

    results = data.get("results", [])
    if not results:
        print(f"  {GRAY}Nenhum resultado encontrado em {results_path}{RESET}")
        return 0

    rows = []
    ok_count = 0
    err_count = 0
    warn_count = 0
    skip_count = 0

    for node in results:
        unique_id = node.get("unique_id", "?")
        status    = node.get("status", "?")
        timing    = node.get("timing", [])
        msg       = ""

        failures = node.get("failures") or []
        if isinstance(failures, list) and failures:
            msg = str(failures[0])[:60]
        else:
            adapter_resp = node.get("adapter_response", {}) or {}
            if isinstance(adapter_resp, dict):
                msg = adapter_resp.get("_message", "")[:60]

        elapsed   = _calc_elapsed(timing)
        model     = _short_name(unique_id)
        color     = _status_color(status)
        elapsed_s = _format_elapsed(elapsed)

        rows.append((model, status, elapsed_s, msg, color))

        s = status.lower()
        if s in ("success", "pass"):
            ok_count += 1
        elif s in ("error", "fail", "runtime error"):
            err_count += 1
        elif s in ("warn",):
            warn_count += 1
        elif s in ("skip", "skipped"):
            skip_count += 1

    max_model = max((len(r[0]) for r in rows), default=8)
    max_model = max(max_model, 8)
    col_widths = (max_model + 2, 10, 9, 0)

    print()
    try:
        _render_tabulate(rows, col_widths)
    except ImportError:
        _render_stdlib(rows, col_widths)

    total = len(rows)
    parts = []
    if ok_count:
        parts.append(f"{GREEN}{ok_count} ok{RESET}")
    if err_count:
        parts.append(f"{RED}{err_count} erro{RESET}")
    if warn_count:
        parts.append(f"{YELLOW}{warn_count} aviso{RESET}")
    if skip_count:
        parts.append(f"{GRAY}{skip_count} skip{RESET}")
    summary = "  ".join(parts)
    print(f"\n  {summary}  {GRAY}({total} total){RESET}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
