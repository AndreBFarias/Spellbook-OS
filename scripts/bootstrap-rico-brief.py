#!/usr/bin/env python3
"""
bootstrap-rico-brief.py — gera VALIDATOR_BRIEF.md pré-populado a partir de memórias históricas.

Lê:
- ~/.claude/projects/-home-andrefarias-Desenvolvimento-<Dir>/memory/*.md (memórias do projeto)
- ~/.config/zsh/docs/claude/templates/bootstrap-<kind>.md (template específico do projeto)
- ~/.config/zsh/docs/claude/VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md (template base)
- ~/.config/zsh/docs/claude/SPECIAL_PROJECTS.json (mapa canônico)

Grava o BRIEF no caminho de saída especificado.

Uso:
    python3 bootstrap-rico-brief.py --projeto luna --saida /home/andrefarias/Desenvolvimento/Luna/VALIDATOR_BRIEF.md
    python3 bootstrap-rico-brief.py --projeto nyx-code --saida /path/VALIDATOR_BRIEF.md
    python3 bootstrap-rico-brief.py --projeto protocolo-ouroboros --saida /path/VALIDATOR_BRIEF.md
    python3 bootstrap-rico-brief.py --projeto <qualquer> --saida <path> --dry-run

Invocação automática:
- Hook session-start-briefing.py instrui Claude a rodar este script quando projeto conhecido + BRIEF ausente.
- Subagent validador-sprint em MODO BOOTSTRAP_RICO invoca explicitamente.
- Manual: `sprint bootstrap --rich` (alias `sbr`).
"""
from __future__ import annotations

import argparse
import datetime as _dt
import hashlib
import json
import pathlib
import re
import sys
from typing import Any


ROOT_ZSH = pathlib.Path.home() / ".config/zsh"
SPECIAL_PROJECTS_JSON = ROOT_ZSH / "docs/claude/SPECIAL_PROJECTS.json"
TEMPLATE_UNIVERSAL = ROOT_ZSH / "docs/claude/VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md"
TEMPLATES_DIR = ROOT_ZSH / "docs/claude/templates"


def _load_special_projects() -> dict[str, Any]:
    try:
        with SPECIAL_PROJECTS_JSON.open(encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        print(f"[erro] não consegui carregar SPECIAL_PROJECTS.json: {exc}", file=sys.stderr)
        return {"projects": {}, "aliases": {}}


def _resolve_kind(projeto: str, spec: dict[str, Any]) -> str | None:
    aliases = spec.get("aliases", {})
    canonical = aliases.get(projeto) or aliases.get(projeto.lower())
    if canonical:
        return canonical
    if projeto in spec.get("projects", {}):
        return projeto
    return None


def _ler_memorias(dir_memoria: str) -> list[dict[str, str]]:
    base = pathlib.Path.home() / ".claude/projects" / dir_memoria / "memory"
    if not base.is_dir():
        return []
    out: list[dict[str, str]] = []
    for f in sorted(base.glob("*.md")):
        try:
            texto = f.read_text(encoding="utf-8")
        except Exception:
            continue
        fm = re.match(r"---\n(.*?)\n---", texto, re.DOTALL)
        name = ""
        desc = ""
        tipo = ""
        corpo = texto
        if fm:
            fm_body = fm.group(1)
            m_name = re.search(r"^name:\s*(.+)$", fm_body, re.MULTILINE)
            m_desc = re.search(r"^description:\s*(.+)$", fm_body, re.MULTILINE)
            m_type = re.search(r"^type:\s*(.+)$", fm_body, re.MULTILINE)
            if m_name:
                name = m_name.group(1).strip()
            if m_desc:
                desc = m_desc.group(1).strip()
            if m_type:
                tipo = m_type.group(1).strip()
            corpo = texto[fm.end():].strip()
        out.append({
            "arquivo": f.name,
            "nome": name or f.stem,
            "desc": desc,
            "tipo": tipo,
            "corpo": corpo,
            "hash": hashlib.sha256(texto.encode()).hexdigest()[:12],
        })
    return out


def _ler_template_projeto(template_filename: str) -> str:
    p = TEMPLATES_DIR / template_filename
    try:
        return p.read_text(encoding="utf-8")
    except Exception:
        return ""


def _ler_template_universal() -> str:
    try:
        return TEMPLATE_UNIVERSAL.read_text(encoding="utf-8")
    except Exception:
        return ""


def _substituir_placeholders(template: str, valores: dict[str, str]) -> str:
    # Placeholders no formato {{CHAVE}}
    for chave, valor in valores.items():
        template = template.replace("{{" + chave + "}}", valor)
    return template


def _seccao_memorias(memorias: list[dict[str, str]]) -> str:
    if not memorias:
        return ""
    linhas = [
        "## [OPCIONAL] Memória histórica (importada de `~/.claude/projects/.../memory/`)",
        "",
        f"{len(memorias)} arquivos de memória encontrados. Resumo por tipo:",
        "",
    ]
    por_tipo: dict[str, list[dict[str, str]]] = {}
    for m in memorias:
        tipo = m["tipo"] or "misc"
        por_tipo.setdefault(tipo, []).append(m)

    for tipo in sorted(por_tipo):
        linhas.append(f"### Tipo: {tipo}")
        linhas.append("")
        for m in por_tipo[tipo]:
            desc_short = (m["desc"][:120] + "...") if len(m["desc"]) > 120 else m["desc"]
            linhas.append(f"- **{m['nome']}** (`{m['arquivo']}`): {desc_short}")
        linhas.append("")
    return "\n".join(linhas)


def _compor_brief(kind: str, info: dict[str, Any], memorias: list[dict[str, str]], template_projeto: str) -> str:
    now_iso = _dt.datetime.now().isoformat(timespec="seconds")

    # Chaves em ASCII para casar com placeholders {{CHAVE}} no template universal.
    # Os VALORES podem ter acentos PT-BR; as chaves não.
    valores: dict[str, str] = {
        "NOME_PROJETO": kind,
        "LINGUAGEM": "<a preencher — inferir do projeto>",
        "FRAMEWORK": "<a preencher — inferir do projeto>",
        "PROPOSITO": "<a preencher — 1 linha>",
        "TIPO": info.get("tipo_projeto", "<a preencher>"),
        "TIPO_VISUAL": info.get("tipo_projeto", "<a preencher>"),
        "STACK_VISUAL": "<a preencher>",
        "CAPTURE_CMD": "bash scripts/tui_tests/capture.sh" if info.get("tipo_projeto") == "tui" else "<a preencher>",
        "FALLBACK_TOOL": "scrot + claude-in-chrome MCP + playwright MCP",
        "CRITERIA_PATH": "<a preencher ou omitir>",
        "SMOKE_CMD": info.get("smoke_cmd", "<a preencher>"),
        "UNIT_CMD": "<a preencher — ver manifesto do projeto>",
        "INTEGRACAO_CMD": info.get("gauntlet_cmd", "<a preencher>"),
        "GAUNTLET_CMD": info.get("gauntlet_cmd", "<a preencher>"),
        "LINT_CMD": "<a preencher>",
        "RUN_CMD": "<a preencher>",
        "LIMITE_LINHAS": "800",
        "EXCECOES": "config/, testes/, registries/",
        "SIM_NAO": "sim",
        "ISO_TIMESTAMP": now_iso,
        "AUTOR": "bootstrap-rico-brief.py",
        "MODO": "bootstrap_rico",
    }

    universal = _ler_template_universal()
    if not universal:
        return (
            f"# VALIDATOR_BRIEF — {kind}\n\n"
            "Template universal não encontrado. Rodar exploração manual.\n"
        )

    brief = _substituir_placeholders(universal, valores)

    # Seção adicional com memórias importadas
    seccao = _seccao_memorias(memorias)
    if seccao:
        brief = brief.rstrip() + "\n\n" + seccao + "\n"

    # Regras específicas do projeto
    regras = info.get("regras_especiais", [])
    if regras:
        linhas_regras = ["## [OPCIONAL] Regras especiais deste projeto", ""]
        for r in regras:
            linhas_regras.append(f"- {r}")
        brief = brief.rstrip() + "\n\n" + "\n".join(linhas_regras) + "\n"

    # Referência ao template específico
    if template_projeto:
        linhas_tpl = [
            "## [OPCIONAL] Template de bootstrap específico",
            "",
            f"Template do projeto em `~/.claude/templates/{info.get('template')}`.",
            "Contém estrutura recomendada + padrões conhecidos. Leia para enriquecimento manual.",
            "",
        ]
        brief = brief.rstrip() + "\n\n" + "\n".join(linhas_tpl) + "\n"

    # Rodapé personalizado
    brief = brief.rstrip()
    if not brief.endswith("*"):
        brief = re.sub(
            r"\*Atualizado em .+ por .+ \(modo .+\)\*",
            f"*Atualizado em {now_iso} por bootstrap-rico-brief.py (modo bootstrap_rico, {len(memorias)} memórias lidas)*",
            brief,
        )
    return brief + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description="Gera VALIDATOR_BRIEF.md rico a partir de memórias históricas")
    ap.add_argument("--projeto", required=True, help="Nome do projeto (luna, nyx-code, protocolo-ouroboros, ou alias)")
    ap.add_argument("--saida", required=True, help="Path absoluto do VALIDATOR_BRIEF.md a gravar")
    ap.add_argument("--dry-run", action="store_true", help="Imprime no stdout sem escrever arquivo")
    args = ap.parse_args()

    spec = _load_special_projects()
    kind = _resolve_kind(args.projeto, spec)
    if not kind:
        print(f"[erro] projeto '{args.projeto}' não reconhecido. Disponíveis: {list(spec.get('projects', {}).keys())}", file=sys.stderr)
        return 2

    info = spec.get("projects", {}).get(kind, {})
    memorias = _ler_memorias(info.get("dir_memoria", ""))
    template_projeto = _ler_template_projeto(info.get("template", ""))
    brief = _compor_brief(kind, info, memorias, template_projeto)

    if args.dry_run:
        sys.stdout.write(brief)
        return 0

    out_path = pathlib.Path(args.saida).expanduser()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(brief, encoding="utf-8")
    linhas = brief.count("\n")
    print(f"[ok] BRIEF gravado: {out_path} ({linhas} linhas, {len(memorias)} memórias incorporadas)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)

# "Memória acumulada em disco vale mais do que contexto volátil em sessão." — Epicteto, em parafraseio livre.
