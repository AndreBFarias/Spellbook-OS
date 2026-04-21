#!/usr/bin/env python3
import sys
import re
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _logging import setup_logger

_log = setup_logger("conjurar-helper", stderr=False)

DELIMITER = "\t"

D_CYAN = "\033[38;2;139;233;253m"
D_YELLOW = "\033[38;2;241;250;140m"
D_GREEN = "\033[38;2;80;250;123m"
D_PURPLE = "\033[38;2;189;147;249m"
D_ORANGE = "\033[38;2;255;184;108m"
D_COMMENT = "\033[38;2;98;114;164m"
D_FG = "\033[38;2;248;248;242m"
D_RESET = "\033[0m"

purpose_regex = re.compile(r"^\s*#\s*Prop[oó]sito:\s*(.*)", re.IGNORECASE)
usage_regex = re.compile(r"^\s*#\s*Uso:\s*(.*)", re.IGNORECASE)
alias_regex = re.compile(r"^\s*alias\s+([^=]+)='([^']*)'")
alias_regex_dq = re.compile(r'^\s*alias\s+([^=]+)="([^"]*)"')
func_start_regex = re.compile(
    r"^\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(\)\s*\{|^\s*function\s+([a-zA-Z][a-zA-Z0-9_]+)\s*\{"
)


def parse_zsh_file(file_path, items):
    current_purpose = ""
    current_usage = ""

    with open(file_path, "r", encoding="utf-8") as f:
        for line in f:
            line_strip = line.strip()
            if not line_strip:
                current_purpose, current_usage = "", ""
                continue

            purpose_match = purpose_regex.match(line_strip)
            if purpose_match:
                current_purpose = purpose_match.group(1).strip()
                continue

            usage_match = usage_regex.match(line_strip)
            if usage_match:
                current_usage = usage_match.group(1).strip()
                continue

            alias_match = alias_regex.match(line_strip) or alias_regex_dq.match(line_strip)
            if alias_match:
                name, code = alias_match.groups()
                name = name.strip()
                if not name.startswith("_"):
                    code = code.strip() if code else ""
                    items.append(
                        f"{name}{DELIMITER}alias{DELIMITER}{code}"
                        f"{DELIMITER}{current_purpose}{DELIMITER}{current_usage}"
                    )
                current_purpose, current_usage = "", ""
                continue

            func_match = func_start_regex.match(line_strip)
            if func_match:
                name = next(filter(None, func_match.groups()), None)
                if name and not name.startswith("_"):
                    items.append(
                        f"{name}{DELIMITER}func{DELIMITER}{name}"
                        f"{DELIMITER}{current_purpose}{DELIMITER}{current_usage}"
                    )
                current_purpose, current_usage = "", ""
                continue

            if not line_strip.startswith("#"):
                current_purpose, current_usage = "", ""


def parse_sources(*paths):
    items = []
    for p in paths:
        path = Path(p)
        if path.is_dir():
            for f in sorted(path.glob("*.zsh")):
                if f.name.startswith("_"):
                    continue
                parse_zsh_file(f, items)
        elif path.is_file():
            parse_zsh_file(path, items)
    return items


def format_preview(full_line):
    try:
        parts = full_line.split(DELIMITER)
        if len(parts) < 5:
            return

        name, kind, code, purpose, usage = parts[0], parts[1], parts[2], parts[3], parts[4]

        type_label = "ALIAS" if kind == "alias" else "Função"
        type_color = D_ORANGE if kind == "alias" else D_PURPLE

        print(f"{D_CYAN}{name}{D_RESET}  {type_color}{type_label}{D_RESET}")
        print(f"{D_COMMENT}{'─' * 40}{D_RESET}")

        if purpose:
            print(f"\n{D_YELLOW}Propósito:{D_RESET}")
            print(f"{D_FG}{purpose}{D_RESET}")
        else:
            print(f"\n{D_COMMENT}(sem descrição){D_RESET}")

        if usage:
            print(f"\n{D_GREEN}Uso:{D_RESET}")
            print(f"{D_FG}{usage}{D_RESET}")

        if kind == "alias" and code:
            print(f"\n{D_PURPLE}Comando:{D_RESET}")
            print(f"{D_FG}{code}{D_RESET}")

    except Exception as e:
        _log.error("Erro no preview: %s", e)
        print(f"{D_YELLOW}Erro no preview: {e}{D_RESET}", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--preview":
        if len(sys.argv) > 2:
            format_preview(sys.argv[2])
        sys.exit(0)

    if len(sys.argv) >= 2:
        parsed = parse_sources(*sys.argv[1:])
        for item in sorted(parsed):
            print(item)
    else:
        _log.error("Uso: conjurar-helper.py <arquivo_ou_diretório> [...]")
        print("Uso: conjurar-helper.py <arquivo_ou_diretório> [...]", file=sys.stderr)
        sys.exit(1)
