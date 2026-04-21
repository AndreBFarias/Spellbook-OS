#!/usr/bin/env python3
"""
Gera FUNCOES.md a partir dos metadados das funções em functions/*.zsh.  # noqa-acento

Consome os mesmos blocos `# Propósito:` / `# Uso:` / `# Flags:` que
scripts/gerar-completions.py usa, e produz uma tabela organizada por domínio
(arquivo de origem).

Uso:
    gerar-readme-funcoes.py [--out CAMINHO]
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path

CONFIG_ROOT = Path(__file__).resolve().parent.parent
FUNCTIONS_DIR = CONFIG_ROOT / "functions"

RE_PURPOSE = re.compile(r"^\s*#\s*Prop[oó]sito:\s*(.*)$", re.IGNORECASE)
RE_USAGE = re.compile(r"^\s*#\s*Uso:\s*(.*)$", re.IGNORECASE)
RE_FLAGS_HEAD = re.compile(r"^\s*#\s*Flags:\s*(.*)$", re.IGNORECASE)
RE_CONT = re.compile(r"^\s*#\s+(\S.*)$")
RE_FUNC_DEF = re.compile(
    r"^\s*([a-zA-Z][a-zA-Z0-9_]*)\s*\(\)\s*\{"
    r"|^\s*function\s+([a-zA-Z][a-zA-Z0-9_]+)\s*\{"
)


# Mapeamento arquivo -> domínio humano
DOMAIN_LABELS = {
    "árvore.zsh": "Navegação e exploração",
    "auditoria.zsh": "Navegação e exploração",
    "busca.zsh": "Navegação e exploração",
    "navegacao.zsh": "Navegação e exploração",
    "diagnostico.zsh": "Navegação e exploração",
    "controle-de-bordo.zsh": "Vault Obsidian (Controle de Bordo)",
    "sync.zsh": "Vault Obsidian (Controle de Bordo)",
    "projeto.zsh": "Setup de projeto",
    "git-add.zsh": "Git",
    "git-contexto.zsh": "Git",
    "git-recovery.zsh": "Git",
    "encoding.zsh": "Encoding e normalização",
    "fontes.zsh": "Fontes",
    "sistema.zsh": "Sistema (Pop!_OS)",
    "restaurar.zsh": "Sistema (Pop!_OS)",
    "hooks.zsh": "Hooks e aplicações",
    "remoto.zsh": "Hooks e aplicações",
    "spellbook-sync.zsh": "Spellbook Sync",
    "spicetify.zsh": "Spicetify",
    "mec.zsh": "MEC",
    "conjurar.zsh": "Meta (descoberta)",
    "completions.zsh": "Meta (descoberta)",
    "pulso.zsh": "Observabilidade",
    "extrair.zsh": "Utilidades",
    "limpeza.zsh": "Utilidades",
    "fontes.zsh": "Fontes",
}


def parse_file(path: Path):
    result = []
    purpose = usage = ""
    flags = []
    mode = None

    with path.open(encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip("\n")
            stripped = line.strip()

            if not stripped:
                purpose, usage, flags, mode = "", "", [], None
                continue

            m = RE_PURPOSE.match(line)
            if m:
                purpose = m.group(1).strip()
                mode = None
                continue
            m = RE_USAGE.match(line)
            if m:
                usage = m.group(1).strip()
                mode = None
                continue
            m = RE_FLAGS_HEAD.match(line)
            if m:
                first = m.group(1).strip()
                if first and "=" in first:
                    flags.append(first)
                mode = "flags"
                continue

            m = RE_CONT.match(line)
            if m and mode == "flags":
                if "=" in m.group(1):
                    flags.append(m.group(1).strip())
                continue

            if stripped.startswith("#"):
                continue

            m = RE_FUNC_DEF.match(line)
            if m:
                name = next(filter(None, m.groups()), None)
                if name and not name.startswith("_"):
                    result.append({
                        "name": name,
                        "purpose": purpose,
                        "usage": usage,
                        "flags": list(flags),
                    })
                purpose, usage, flags, mode = "", "", [], None
                continue

            purpose, usage, flags, mode = "", "", [], None

    return result


def render_markdown(by_domain: dict) -> str:
    lines = []
    lines.append("# Funções do Spellbook-OS")
    lines.append("")
    lines.append("Gerado automaticamente por `scripts/gerar-readme-funcoes.py` a partir")
    lines.append("dos metadados `# Propósito:` / `# Uso:` / `# Flags:` em `functions/*.zsh`.")
    lines.append("")
    lines.append("## Índice")
    lines.append("")
    for dominio in sorted(by_domain.keys()):
        slug = dominio.lower().replace(" ", "-").replace("(", "").replace(")", "")
        lines.append(f"- [{dominio}](#{slug}) — {len(by_domain[dominio])} função(ões)")
    lines.append("")

    for dominio in sorted(by_domain.keys()):
        funcs = sorted(by_domain[dominio], key=lambda f: f["name"])
        lines.append(f"## {dominio}")
        lines.append("")
        lines.append("| Função | Propósito | Uso |")
        lines.append("|---|---|---|")
        for f in funcs:
            uso = f["usage"].replace("|", "\\|") if f["usage"] else "—"
            propósito = f["purpose"].replace("|", "\\|") if f["purpose"] else "*(sem descrição)*"
            lines.append(f"| `{f['name']}` | {propósito} | `{uso}` |")
        lines.append("")
        # Flags agrupadas por função
        flagged = [f for f in funcs if f["flags"]]
        if flagged:
            lines.append("### Flags detalhadas")
            lines.append("")
            for f in flagged:
                lines.append(f"**`{f['name']}`**")
                lines.append("")
                for flag_entry in f["flags"]:
                    if "=" in flag_entry:
                        nome, desc = flag_entry.split("=", 1)
                        lines.append(f"- `{nome.strip()}` — {desc.strip()}")
                lines.append("")

    lines.append("---")
    lines.append("")
    lines.append("*Para regenerar: `python3 scripts/gerar-readme-funcoes.py`*")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=CONFIG_ROOT / "FUNCOES.md")  # noqa-acento
    args = parser.parse_args()

    by_domain = defaultdict(list)
    for zsh_file in sorted(FUNCTIONS_DIR.glob("*.zsh")):
        if zsh_file.name.startswith("_"):
            continue
        funcs = parse_file(zsh_file)
        domain = DOMAIN_LABELS.get(zsh_file.name, zsh_file.stem.title())
        for f in funcs:
            f["source"] = zsh_file.name
            by_domain[domain].append(f)

    markdown = render_markdown(by_domain)
    args.out.write_text(markdown, encoding="utf-8")

    total = sum(len(v) for v in by_domain.values())
    print(f"FUNCOES.md gerado: {total} funções em {len(by_domain)} domínios -> {args.out}")  # noqa-acento
    return 0


if __name__ == "__main__":
    sys.exit(main())
