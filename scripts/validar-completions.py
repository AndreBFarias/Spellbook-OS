#!/usr/bin/env python3
"""validar-completions.py — Detecta completions órfãs (sem função/alias correspondente).

Cruza completions/_* com funções definidas em functions/*.zsh e aliases em
aliases.zsh, cca/aliases_cca.zsh, cca/aliases_sprint.zsh.

Saída:
  - lista de completions sem owner (uma por linha, prefixadas com 'STALE: ')
  - exit code 0 sempre (relatório informacional, não bloqueia CI)

Uso:
  python3 scripts/validar-completions.py
  python3 scripts/validar-completions.py --strict   # exit 1 se houver órfãs
"""
import re
import sys
from pathlib import Path

ZSH_ROOT = Path(__file__).resolve().parent.parent
FUNCTIONS_DIR = ZSH_ROOT / "functions"
COMPLETIONS_DIR = ZSH_ROOT / "completions"
ALIAS_FILES = [
    ZSH_ROOT / "aliases.zsh",
    ZSH_ROOT / "cca" / "aliases_cca.zsh",
    ZSH_ROOT / "cca" / "aliases_sprint.zsh",
]

# Padrões zsh de definição:
#   foo() { ... }
#   function foo { ... }
#   alias foo='...'
FUNC_RE = re.compile(r"^(?:function\s+)?([A-Za-z_][A-Za-z0-9_-]*)\s*\(\)", re.MULTILINE)
FUNC_RE_2 = re.compile(r"^function\s+([A-Za-z_][A-Za-z0-9_-]*)\s*\{", re.MULTILINE)
ALIAS_RE = re.compile(r"^alias\s+([A-Za-z_][A-Za-z0-9_-]*)=", re.MULTILINE)


def gather_defined_names() -> set[str]:
    names: set[str] = set()
    # Funções em functions/*.zsh
    for f in FUNCTIONS_DIR.glob("*.zsh"):
        content = f.read_text(encoding="utf-8", errors="replace")
        names.update(FUNC_RE.findall(content))
        names.update(FUNC_RE_2.findall(content))
    # Aliases
    for f in ALIAS_FILES:
        if not f.exists():
            continue
        content = f.read_text(encoding="utf-8", errors="replace")
        names.update(ALIAS_RE.findall(content))
    return names


def gather_completion_names() -> list[str]:
    names = []
    for c in COMPLETIONS_DIR.glob("_*"):
        if c.name == "_helpers.zsh" or not c.is_file():
            continue
        # `_foo` é completion para `foo`. `_foo_bar` pode ser para `foo bar`
        # (subcomando) ou `foo_bar` (função). Tratamos como `foo_bar` primeiro,
        # depois fallback para primeira-palavra.
        names.append(c.name[1:])  # tira o '_' inicial
    return sorted(names)


def main() -> int:
    strict = "--strict" in sys.argv

    defined = gather_defined_names()
    completions = gather_completion_names()

    stale = []
    for c in completions:
        # Match direto: completion `_foo` -> função `foo` existe
        if c in defined:
            continue
        # Match fallback: completion `_foo_bar` poderia ser subcomando de `foo`
        first_word = c.split("_")[0]
        if first_word in defined:
            continue
        stale.append(c)

    print(f"[validar-completions] {len(completions)} completions, {len(stale)} órfã(s)")
    for s in stale:
        print(f"STALE: completions/_{s}")

    return 1 if (strict and stale) else 0


if __name__ == "__main__":
    sys.exit(main())
