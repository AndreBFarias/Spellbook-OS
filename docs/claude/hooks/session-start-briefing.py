#!/usr/bin/env python3
"""
Hook SessionStart — coracao do "boot capacitado".

Le variaveis de ambiente exportadas pelo wrapper `cca` + arquivos leves
(BRIEF, SPECIAL_PROJECTS.json) e emite JSON com `additionalContext` no stdout.

Objetivo: Claude iniciar cada sessao ja sabendo:
  - qual e o projeto ativo (nome, path, kind)
  - status do VALIDATOR_BRIEF.md
  - capacidades visuais disponiveis (CLI X11, claude-in-chrome, playwright)
  - regras especiais se projeto conhecido (Luna / Nyx-Code / ouroboros)
  - acao automatica pra criar BRIEF se ausente

Registrado em ~/.claude/settings.json:
  hooks.SessionStart[].matcher = "*"
  command = python3 /home/andrefarias/.claude/hooks/session-start-briefing.py
  timeout = 10

Filosofia: sempre exit 0. Qualquer erro vira string informativa no additionalContext.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time

# -- Constantes --------------------------------------------------------------

SPECIAL_PROJECTS_JSON = pathlib.Path.home() / ".config/zsh/docs/claude/SPECIAL_PROJECTS.json"
TEMPLATES_DIR = pathlib.Path.home() / ".claude/templates"
CHROME_NATIVE_HOST = pathlib.Path.home() / ".claude/chrome/chrome-native-host"
CHROME_EXTENSION_DIR = pathlib.Path.home() / ".config/google-chrome/Default/Extensions/fcoeoabgfenejglbffodgkkbkcdhcgfn"
PLAYWRIGHT_CACHE_GLOB = pathlib.Path.home() / ".npm/_npx"

# -- Helpers ----------------------------------------------------------------


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def _file_lines(path: pathlib.Path) -> int:
    try:
        with path.open("rb") as fh:
            return sum(1 for _ in fh)
    except Exception:
        return 0


def _file_age_days(path: pathlib.Path) -> int:
    try:
        mtime = path.stat().st_mtime
        return int((time.time() - mtime) / 86400)
    except Exception:
        return -1


def _load_special_projects() -> dict:
    try:
        with SPECIAL_PROJECTS_JSON.open(encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return {"projects": {}, "aliases": {}}


def _resolve_kind(project_name: str, spec: dict) -> str:
    if not project_name:
        return "generic"
    aliases = spec.get("aliases", {})
    return aliases.get(project_name, aliases.get(project_name.lower(), "generic"))


def _has_memories(project_name_canonical: str, spec: dict) -> bool:
    info = spec.get("projects", {}).get(project_name_canonical)
    if not info:
        return False
    mem_dir = pathlib.Path.home() / ".claude/projects" / info["dir_memoria"] / "memory"
    if not mem_dir.is_dir():
        return False
    return any(mem_dir.glob("*.md"))


def _check_chrome_pairing() -> tuple[bool, str]:
    if not CHROME_NATIVE_HOST.exists() or not os.access(CHROME_NATIVE_HOST, os.X_OK):
        return False, "native-host ausente ou nao-executavel"
    if not CHROME_EXTENSION_DIR.is_dir():
        return False, "extensao Chrome nao instalada"
    versions = list(CHROME_EXTENSION_DIR.glob("*/manifest.json"))
    if not versions:
        return False, "extensao Chrome sem versao instalada"
    return True, "OK"


def _check_playwright_cache() -> tuple[bool, str]:
    if not PLAYWRIGHT_CACHE_GLOB.is_dir():
        return False, "~/.npm/_npx/ nao existe"
    for d in PLAYWRIGHT_CACHE_GLOB.iterdir():
        if (d / "node_modules/@playwright/mcp").is_dir():
            return True, "cache aquecido"
    return False, "cache frio (cold start 20s na 1a chamada)"


# -- Blocos do additionalContext -------------------------------------------


def _block_santuario_ready(root: str, project_name: str, kind: str, brief_path: str, brief_status: str) -> str:
    if not root:
        return "[SANTUARIO READY] Sessao iniciada fora de repo git. Sem contexto de projeto ativo."
    lines = [
        "[SANTUARIO READY]",
        f"Projeto: {project_name}",
        f"Raiz: {root}",
        f"Tipo: {kind}",
    ]
    if brief_status == "exists":
        p = pathlib.Path(brief_path)
        lines.append(f"VALIDATOR_BRIEF.md: ativo ({_file_lines(p)} linhas, atualizado ha {_file_age_days(p)}d)")
    else:
        lines.append(f"VALIDATOR_BRIEF.md: ausente (sera criado automaticamente na 1a tarefa)")
    return "\n".join(lines)


def _block_projeto_especial(kind: str, spec: dict, has_mem: bool) -> str:
    if kind == "generic":
        return ""
    info = spec.get("projects", {}).get(kind, {})
    lines = [
        "[PROJETO ESPECIAL]",
        f"Kind: {kind}",
        f"Memorias em ~/.claude/projects/{info.get('dir_memoria', '<?>')}/memory/: {'existem' if has_mem else 'vazio'}",
        f"Template bootstrap: ~/.claude/templates/{info.get('template', '<?>')}",
        f"Smoke canonico: {info.get('smoke_cmd', '<a preencher>')}",
        f"Gauntlet canonico: {info.get('gauntlet_cmd', '<a preencher>')}",
    ]
    regras = info.get("regras_especiais", [])
    if regras:
        lines.append("Regras especiais:")
        for r in regras:
            lines.append(f"  - {r}")
    return "\n".join(lines)


def _block_capacidades_visuais() -> str:
    chrome_ok, chrome_msg = _check_chrome_pairing()
    pw_ok, pw_msg = _check_playwright_cache()
    lines = [
        "[CAPACIDADES VISUAIS]",
        "Pipeline 3-tentativas para qualquer UI/TUI/Web (nunca diga 'impossivel' sem tentar 3):",
        "",
        "Tentativa 1 - CLI X11 (pre-autorizado em settings.json):",
        "  scrot, import, xdotool, wmctrl, ffmpeg, xclip, sha256sum",
        "  Ex TUI: import -window $(xdotool search --name '<app>' | head -1) /tmp/<proj>_<area>_<ts>.png",
        "",
        "Tentativa 2 - claude-in-chrome MCP (carregar via ToolSearch):",
        "  ToolSearch select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__navigate",
        f"  Status pairing: {'OK' if chrome_ok else 'FALHA - ' + chrome_msg}",
        "",
        "Tentativa 3 - playwright MCP (carregar via ToolSearch):",
        "  ToolSearch select:mcp__plugin_playwright_playwright__browser_navigate,mcp__plugin_playwright_playwright__browser_take_screenshot,mcp__plugin_playwright_playwright__browser_snapshot",
        f"  Status cache: {pw_msg}",
        "",
        "Skill canonica: validacao-visual (auto-invocada pelo validador-sprint quando diff toca UI).",
    ]
    return "\n".join(lines)


def _block_sprint_ciclo(retries_max: str) -> str:
    return "\n".join([
        "[SPRINT CICLO]",
        f"Ciclo automatico via /sprint-ciclo <ideia>: plan -> exec -> val em cadeia, ate {retries_max} iteracoes.",
        "- Ambiguidade no spec: pausa e pede clarificacao.",
        "- REPROVADO: auto-dispatch executor com patch-brief (ate max retries).",
        "- APROVADO/APROVADO_COM_RESSALVAS: auto-commit + auto-push + auto-PR (via /commit-push-pr).",
        "Modo manual (opt-in) disponivel via /sprint-ciclo-manual.",
        "Zero follow-up: cada achado vira Edit-pronto OU sprint-ID nova. Nunca 'issue depois'.",
    ])


def _block_acao_automatica(brief_status: str, kind: str, has_mem: bool, brief_path: str, kind_canonical: str) -> str:
    if brief_status == "exists":
        return "[ACAO AUTOMATICA] BRIEF ativo. Use-o como memoria acumulada ao iniciar qualquer sprint."
    if kind != "generic" and has_mem:
        return "\n".join([
            "[ACAO AUTOMATICA]",
            "Projeto conhecido sem BRIEF e com memorias historicas disponiveis.",
            "ANTES de qualquer outra tarefa, auto-disparar:",
            f"  python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto {kind_canonical} --saida {brief_path}",
            "OU dispatch validador-sprint em MODO BOOTSTRAP_RICO.",
            "Nao peca confirmacao ao usuario. O BRIEF e pre-requisito do ciclo de sprint.",
        ])
    if brief_status == "missing":
        return "\n".join([
            "[ACAO AUTOMATICA]",
            "Projeto sem BRIEF. ANTES da proxima tarefa, auto-disparar:",
            "  dispatch validador-sprint em MODO BOOTSTRAP (exploracao read-only exaustiva).",
            "BRIEF sera criado em VALIDATOR_BRIEF.md na raiz do repo.",
        ])
    return ""


# -- Main -------------------------------------------------------------------


def main() -> int:
    root = _env("CLAUDE_PROJECT_ROOT")
    name = _env("CLAUDE_PROJECT_NAME")
    brief_path = _env("CLAUDE_BRIEF_PATH")
    brief_status = _env("CLAUDE_BRIEF_STATUS", "missing")
    kind_env = _env("CLAUDE_PROJECT_KIND", "generic")
    retries_max = _env("CLAUDE_SPRINT_CICLO_MAX_RETRIES", "3")

    spec = _load_special_projects()
    kind_canonical = _resolve_kind(name, spec) if kind_env == "generic" else kind_env
    has_mem = _has_memories(kind_canonical, spec)

    blocks = [
        _block_santuario_ready(root, name, kind_canonical, brief_path, brief_status),
        _block_projeto_especial(kind_canonical, spec, has_mem),
        _block_capacidades_visuais(),
        _block_sprint_ciclo(retries_max),
        _block_acao_automatica(brief_status, kind_canonical, has_mem, brief_path, kind_canonical),
    ]
    additional_context = "\n\n".join(b for b in blocks if b)

    output = {
        "hookSpecificOutput": {
            "hookEventName": "SessionStart",
            "additionalContext": additional_context,
        }
    }
    print(json.dumps(output, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        fallback = {
            "hookSpecificOutput": {
                "hookEventName": "SessionStart",
                "additionalContext": f"[SANTUARIO READY] erro no hook: {type(exc).__name__}: {exc}",
            }
        }
        print(json.dumps(fallback, ensure_ascii=False))
        sys.exit(0)

# "Boot capacitado: Claude inicia sabendo o que pode fazer. Epicteto: 'nao e o que nos acontece que nos afeta, mas como respondemos.'"
