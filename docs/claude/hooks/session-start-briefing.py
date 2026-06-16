#!/usr/bin/env python3
"""
Hook SessionStart — coracao do "boot capacitado".

Le variaveis de ambiente exportadas pelo wrapper `cca` + arquivos leves
(BRIEF, SPECIAL_PROJECTS.json) e emite JSON com `additionalContext` no stdout.

Objetivo: Claude iniciar cada sessão ja sabendo:
  - qual e o projeto ativo (nome, path, kind)
  - status do VALIDATOR_BRIEF.md
  - capacidades visuais disponiveis (CLI X11, claude-in-chrome, playwright)
  - regras especiais se projeto conhecido (Luna / Nyx-Code / ouroboros)
  - acao automática pra criar BRIEF se ausente

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
        return False, "native-host ausente ou não-executavel"
    if not CHROME_EXTENSION_DIR.is_dir():
        return False, "extensao Chrome não instalada"
    versions = list(CHROME_EXTENSION_DIR.glob("*/manifest.json"))
    if not versions:
        return False, "extensao Chrome sem versao instalada"
    return True, "OK"


def _check_playwright_cache() -> tuple[bool, str]:
    if not PLAYWRIGHT_CACHE_GLOB.is_dir():
        return False, "~/.npm/_npx/ não existe"
    for d in PLAYWRIGHT_CACHE_GLOB.iterdir():
        if (d / "node_modules/@playwright/mcp").is_dir():
            return True, "cache aquecido"
    return False, "cache frio (cold start 20s na 1a chamada)"


# -- Blocos do additionalContext -------------------------------------------


def _block_santuario_ready(root: str, project_name: str, kind: str, brief_path: str, brief_status: str) -> str:
    if not root:
        return "[SANTUARIO READY] Sessão iniciada fora de repo git. Sem contexto de projeto ativo."
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
        f"Smoke canônico: {info.get('smoke_cmd', '<a preencher>')}",
        f"Gauntlet canônico: {info.get('gauntlet_cmd', '<a preencher>')}",
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
        "Skill canonica: validação-visual (auto-invocada pelo validador-sprint quando diff toca UI).",
    ]
    return "\n".join(lines)


def _block_sprint_ciclo(retries_max: str) -> str:
    return "\n".join([
        "[SPRINT CICLO]",
        f"Ciclo automático via /sprint-ciclo <ideia>: plan -> exec -> val em cadeia, ate {retries_max} iteracoes.",
        "- Ambiguidade no spec: pausa e pede clarificacao.",
        "- REPROVADO: auto-dispatch executor com patch-brief (ate max retries).",
        "- APROVADO/APROVADO_COM_RESSALVAS: auto-commit + auto-push + auto-PR (via /commit-push-pr).",
        "Modo manual (opt-in) disponivel via /sprint-ciclo-manual.",
        "Zero follow-up: cada achado vira Edit-pronto OU sprint-ID nova. Nunca 'issue depois'.",
    ])


def _block_acao_automatica(brief_status: str, kind: str, has_mem: bool, brief_path: str, kind_canonical: str) -> str:
    if brief_status == "exists":
        return "[AÇÃO AUTOMÁTICA] BRIEF ativo. Use-o como memoria acumulada ao iniciar qualquer sprint."
    if kind != "generic" and has_mem:
        return "\n".join([
            "[AÇÃO AUTOMÁTICA]",
            "Projeto conhecido sem BRIEF e com memorias historicas disponiveis.",
            "ANTES de qualquer outra tarefa, auto-disparar:",
            f"  python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto {kind_canonical} --saida {brief_path}",
            "OU dispatch validador-sprint em MODO BOOTSTRAP_RICO.",
            "Não peca confirmacao ao usuário. O BRIEF e pre-requisito do ciclo de sprint.",
        ])
    if brief_status == "missing":
        return "\n".join([
            "[AÇÃO AUTOMÁTICA]",
            "Projeto sem BRIEF. ANTES da proxima tarefa, auto-disparar:",
            "  dispatch validador-sprint em MODO BOOTSTRAP (exploracao read-only exaustiva).",
            "BRIEF sera criado em VALIDATOR_BRIEF.md na raiz do repo.",
        ])
    return ""


# -- Guarda anti-vazamento OSC 9 (preferredNotifChannel x terminal real) ----


def _block_aviso_terminal_osc() -> str:
    """Detecta mismatch entre preferredNotifChannel=ghostty (ou agentPushNotif
    ativo) e terminal atual sem suporte a OSC 9.

    Causa-raiz documentada em ~/.claude/plans/ultimamente-fomos-rodar-as-cozy-cosmos.md
    e VALIDATOR_BRIEF.md §armadilhas: gnome-terminal/VTE não consome OSC 9 nem
    OSC 777 — sequências vazam como `]9;` / `^[]777;` e quebram raw-mode do TTY.

    Retorna bloco de aviso ou string vazia (sem ruído quando ok).
    """
    settings_path = pathlib.Path.home() / ".claude/settings.json"
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
    except Exception:
        return ""

    pref_channel = settings.get("preferredNotifChannel")
    push_enabled = settings.get("agentPushNotifEnabled")

    # Sem risco se canal não é ghostty E push notif desativado
    if pref_channel != "ghostty" and not push_enabled:
        return ""

    # Terminal compatível? (Ghostty/Kitty/iTerm/WezTerm via $TERM_PROGRAM ou envs específicas)
    term_prog = _env("TERM_PROGRAM").lower()
    if term_prog in {"ghostty", "kitty", "iterm.app", "wezterm"}:
        return ""
    for env_name in ("GHOSTTY_RESOURCES_DIR", "GHOSTTY_BIN_DIR",
                     "KITTY_PID", "KITTY_WINDOW_ID",
                     "WEZTERM_PANE", "ITERM_SESSION_ID"):
        if _env(env_name):
            return ""

    # Mismatch confirmado
    lines = [
        "[AVISO TERMINAL]",
        "preferredNotifChannel=ghostty (ou agentPushNotifEnabled=true) ativo,",
        "mas terminal atual não é Ghostty/Kitty/iTerm/WezTerm.",
        f"  TERM_PROGRAM={_env('TERM_PROGRAM') or '<vazio>'} TERM={_env('TERM') or '<vazio>'}",
        "Risco: OSC 9 / OSC 9;4 vazam como `]9;` ou `^[]777;` no TTY ao despachar agente,",
        "quebrando raw-mode (teclas viram continuação de escape, sessão fecha).",
        "",
        "Ação recomendada:",
        "  - Rode 'cca' (relança em Ghostty se instalado) OU 'cca-here' (força in-place).",
        "  - Se Ghostty não instalado: bash ~/.config/zsh/install.sh --update",
        "  - Quick-fix: editar ~/.claude/settings.json setando",
        '      "preferredNotifChannel": "system", "agentPushNotifEnabled": false',
    ]
    return "\n".join(lines)


def _block_a_porta(root: str) -> str:
    """[A PORTA] -- injeta a entrada única da sessão (dev-journey/NEXT_SPRINT.md, MAESTRO-M01).

    Lê o cabeçalho + o FOCO curado da porta e emite a cadência + os top invariantes do BRIEF.
    Read-only: a porta é produzida por M01; este bloco só a consome. Graceful: porta
    ausente -> string vazia (filtrada no join), a sessão abre sem erro.
    """
    if not root:
        return ""
    try:
        porta = pathlib.Path(root) / "dev-journey" / "NEXT_SPRINT.md"
        if not porta.is_file():
            return ""
        linhas = porta.read_text(encoding="utf-8").splitlines()
    except Exception:
        return ""

    titulo = next((ln for ln in linhas if ln.startswith("# ")), "# NEXT_SPRINT -- A Porta")

    # Extrai a seção "## FOCO ATUAL" (o próximo chunk curado), até o próximo "## ".
    foco: list[str] = []
    capturando = False
    for ln in linhas:
        if ln.startswith("## FOCO ATUAL"):
            capturando = True
            continue
        if capturando:
            if ln.startswith("## "):
                break
            foco.append(ln)
    foco_txt = "\n".join(foco).strip()
    if len(foco_txt) > 900:
        foco_txt = foco_txt[:900].rstrip() + " [...]"

    partes = [
        "[A PORTA] (dev-journey/NEXT_SPRINT.md -- leia ela primeiro, é a entrada única da sessão)",
        titulo.lstrip("# ").strip(),
    ]
    if foco_txt:
        partes += ["", "FOCO ATUAL (o próximo chunk curado):", foco_txt]
    partes += [
        "",
        "CADÊNCIA (siga em ordem, sempre):",
        "  1. ABRIR -- leia esta porta + VALIDATOR_BRIEF.md + abra ./acompanhar.sh (o medidor vivo)",
        "  2. PEGAR UM PEDAÇO -- um chunk por vez, do FOCO acima",
        "  3. INTEGRAR + VALIDAR -- cirúrgico (integra, não cria solto); proof-of-work runtime-real + ADR-22 se toca UI; nunca diga 'funciona' sem rodar",
        "  4. FECHAR -- commit curado por path (nunca git add -A); dashboard verde; regenere a porta (python scripts/gen_porta.py) + a memória",
        "",
        "INVARIANTES (VALIDATOR_BRIEF.md):",
        "  - GPU EXCLUSIVA (ADR-14): 1 dono por vez (TTS > Vision > Code > SLM)",
        "  - think:true APENAS para qwen3 (nunca qwen2.5)",
        "  - Commit curado por PATH, nunca git add -A",
        "  - Integração obrigatória: nada solto (registry/command/service)",
        "  - Zero follow-up: cada achado vira Edit-pronto OU sprint-ID nova",
    ]
    return "\n".join(partes)


def _block_gsd(root: str) -> str:
    """[GSD] -- injeta o GSD.md (Get Shit Done) da raiz do repo em TODA sessão.

    O GSD.md concentra as regras invioláveis, armadilhas críticas e estado de sprints do
    projeto. Antes só era lido pelo validador-sprint em modo BOOTSTRAP (quando faltava
    VALIDATOR_BRIEF.md); agora entra no boot de qualquer sessão cca, independente do BRIEF.
    Graceful: GSD.md ausente -> dica curta se for repo git, senão string vazia (filtrada no
    join). A sessão sempre abre sem erro.
    """
    if not root:
        return ""
    gsd = pathlib.Path(root) / "GSD.md"
    if not gsd.is_file():
        if (pathlib.Path(root) / ".git").exists():
            return (
                "[GSD] Projeto sem GSD.md na raiz. Considere criar um (regras invioláveis + "
                "armadilhas + estado de sprints) -- o boot passa a carregá-lo automaticamente."
            )
        return ""
    try:
        texto = gsd.read_text(encoding="utf-8").strip()
    except Exception:
        return ""
    if not texto:
        return ""

    cap = 8000
    if len(texto) > cap:
        texto = texto[:cap].rstrip() + "\n\n[...] (GSD.md truncado no boot -- leia o arquivo completo na raiz)"

    return "\n".join([
        "[GSD] (GSD.md da raiz -- regras invioláveis e armadilhas do projeto, sempre ativas)",
        "",
        texto,
    ])


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
        _block_gsd(root),
        _block_a_porta(root),
        _block_projeto_especial(kind_canonical, spec, has_mem),
        _block_aviso_terminal_osc(),
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

# "Boot capacitado: Claude inicia sabendo o que pode fazer. Epicteto: 'não e o que nos acontece que nos afeta, mas como respondemos.'"
