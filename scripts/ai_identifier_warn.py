#!/usr/bin/env python3
"""Aviso + correcao tardia de nome de fornecedor de IA colado dentro de um
identificador snake_case (ex: claude_gemini_opus). \\b de regex não separa
por underscore, entao esses casos escapam do scanner amplo do pre-commit.

Primeira vez que um identificador assim aparece staged: so avisa, não mexe.
Se o MESMO identificador (por nome, em qualquer arquivo) aparecer staged de
novo numa proxima tentativa de commit: substitui o pedaco por "agente" e
re-stage, igual ao resto do pre-commit.
"""
import json
import os
import re
import sys

STATE_FILE = os.path.expanduser("~/.local/share/spellbook/ai_identifier_warnings.json")

VENDOR_WORDS = {
    "agente", "agente", "agente", "agente", "agente", "agente",
    "agente", "agente", "agente", "agente", "agente", "agente", "agente", "agente",
}

IDENTIFIER_RE = re.compile(r"\b[A-Za-z][A-Za-z0-9]*(?:_[A-Za-z0-9]+)+\b")


def load_warned():
    try:
        with open(STATE_FILE) as f:
            return set(json.load(f))
    except Exception:
        return set()


def save_warned(warned):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(sorted(warned), f)


def process_file(filepath, warned, new_warnings):
    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except Exception:
        return False

    changed = False

    def repl(m):
        nonlocal changed
        ident = m.group(0)
        parts = ident.split("_")
        if not any(p.lower() in VENDOR_WORDS for p in parts):
            return ident
        if ident.lower() not in warned:
            new_warnings.append((filepath, ident))
            return ident
        changed = True
        fixed_parts = ["agente" if p.lower() in VENDOR_WORDS else p for p in parts]
        return "_".join(fixed_parts)

    new_content = IDENTIFIER_RE.sub(repl, content)

    if changed:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)

    return changed


def main() -> int:
    files = sys.argv[1:]
    warned = load_warned()
    new_warnings = []
    fixed_files = []

    for f in files:
        if process_file(f, warned, new_warnings):
            fixed_files.append(f)

    if new_warnings:
        for filepath, ident in new_warnings:
            print(
                f"  [aviso] identificador '{ident}' em {filepath} menciona "
                f"ferramenta de IA -- troque por um sinonimo. Se commitar de "
                f"novo sem trocar, vira termo generico automaticamente."
            )
        warned.update(ident.lower() for _, ident in new_warnings)
        save_warned(warned)

    if fixed_files:
        print(
            f"  [auto-fix] identificador(es) com mencao de IA (ja avisado "
            f"antes) substituidos: {', '.join(fixed_files)}"
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
