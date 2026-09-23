#!/usr/bin/env python3
"""
Hook PreToolUse (Write/Edit/MultiEdit) — bloqueia:
  1. Emojis em qualquer contexto (regra GUIDE.md #3)
  2. Atribuicoes explicitas a IA (regra GUIDE.md #2)

Executa ANTES da escrita/edicao. Se bloqueia, Claude ve a razao e ajusta.
"""
import json
import pathlib
import re
import sys

EMOJI_PATTERN = re.compile(
    "["
    "\U0001F600-\U0001F64F"
    "\U0001F300-\U0001F5FF"
    "\U0001F680-\U0001F6FF"
    "\U00002600-\U000026FF"
    "\U00002700-\U000027BF"
    "\U0001F900-\U0001F9FF"
    "\U0001FA00-\U0001FA6F"
    "\U0001FA70-\U0001FAFF"
    "]"
)

AI_ATTRIBUTION = re.compile(
    r"(?i)(Co[- ]Authored[- ]By|Generated\s+(by|with)|Created\s+by|Written\s+by|"
    r"Paired[- ]With|Assisted[- ]By)[:\s.]*"
    r"(Claude|GPT|Copilot|Anthropic|OpenAI|Gemini|ChatGPT|DeepSeek|Cursor|"
    r"Windsurf|Codeium|Tabnine|Opus|Sonnet|Haiku|Fable)"
)

AI_EMAIL = re.compile(r"noreply@anthropic", re.IGNORECASE)

# Commit curado por path: bloqueia stage em massa (git add -A / --all / git add .).
# Forca listar os arquivos explicitamente (regra anti-debito do sprint-ciclo). NAO pega
# `git add -p` nem `-u` (atualizacao seletiva de tracked), nem `git add ./caminho`.
GIT_ADD_ALL = re.compile(r"\bgit\s+add\s+(?:-A\b|--all\b|\.(?:\s|$))")


def get_content(tool_input: dict, tool_name: str) -> str:
    texts = []
    if tool_name == "Write":
        texts.append(tool_input.get("content", ""))
    elif tool_name == "Edit":
        texts.append(tool_input.get("new_string", ""))
    elif tool_name == "MultiEdit":
        for edit in tool_input.get("edits", []) or []:
            texts.append(edit.get("new_string", ""))
    return "\n".join(t for t in texts if t)


def get_file_path(tool_input: dict) -> str:
    return tool_input.get("file_path") or tool_input.get("notebook_path") or ""


def is_exempt_path(file_path: str) -> bool:
    """Arquivos onde regex de emoji ou mencao a IA sao legitimos por natureza."""
    if not file_path:
        return False
    exempt_markers = [
        "/.claude/hooks/guardian.py",
        "/zsh/docs/claude/hooks/guardian.py",
        "/_lib.sh",
        "/emoji_guardian.py",
        "/sanitizar_ia.py",
        "/universal-sanitizer.py",
        "/scripts/auditoria-repos.sh",
        "/GUIDE.md",
        "/CLAUDE.md",
        "/AI.md",
    ]
    return any(marker in file_path for marker in exempt_markers)


SEGAPE_MODELOS_PAINEL = pathlib.Path.home() / (
    "Desenvolvimento/Projetos_segape/pipelines/queries/models/projeto_painel_ministro"
)
SEGAPE_FERRAMENTA = re.compile(r"\b(bq|dbt|gcloud|gsutil)\b|bigquery", re.IGNORECASE)
SEGAPE_PROIBIDO = [
    (re.compile(r"br-mec-segape(?![-\w])"), "produção (br-mec-segape)"),
    (re.compile(r"br-mec-segape-sandbox"), "sandbox (br-mec-segape-sandbox)"),
    (re.compile(r"(?:--target[=\s]+|\s-t\s+)prod\b"), "target prod do dbt"),
    (re.compile(r"andre_teste"), "dataset andre_teste"),
]
SEGAPE_ESCRITA_SQL = re.compile(
    r"(?i)\b(?:create(?:\s+or\s+replace)?(?:\s+temp(?:orary)?)?\s+(?:table|view)"
    r"|insert\s+into|(?<!git\s)merge(?:\s+into)?|(?<![-\w])update|delete\s+from|drop\s+(?:table|view)"
    r"|truncate\s+table|alter\s+table)\s+`?([\w.-]+)"
)
SEGAPE_BQ_ESCRITA = re.compile(r"\bbq\s+(?:mk|rm|load|cp|insert|update)\b[^;&|]*?\s([\w-]+[:.][\w.-]+)")
SEGAPE_DBT_ESCRITA = re.compile(r"\bdbt\s+(run|build|seed|snapshot)\b([^;&|]*)")


def _segape_selecao_valida(args: str) -> str | None:
    m = re.search(r"(?:--select|-s|-m|--models)[=\s]+((?:[^\s-][^\s]*\s*)+)", args)
    if not m:
        return "dbt de escrita sem --select roda o projeto inteiro"
    for sel in m.group(1).split():
        if any(c in sel for c in "+@*"):
            return f"seletor com operador de grafo ({sel}) alcança modelos fora do painel"
        if sel.startswith("path:"):
            if "models/projeto_painel_ministro" not in sel:
                return f"seletor fora de projeto_painel_ministro ({sel})"
            continue
        if not (SEGAPE_MODELOS_PAINEL / f"{sel.split('.')[-1]}.sql").is_file():
            return f"modelo {sel} não está em projeto_painel_ministro"
    return None


def segape_violacao(cmd: str, cwd: str) -> str | None:
    """Acesso permitido nos repos SEGAPE: escrita só em br-mec-segape-dev.projeto_painel_ministro."""
    if not SEGAPE_FERRAMENTA.search(cmd):
        return None
    for padrao, alvo in SEGAPE_PROIBIDO:
        if padrao.search(cmd):
            return f"acesso a {alvo}"
    for m in SEGAPE_ESCRITA_SQL.finditer(cmd):
        if "projeto_painel_ministro" not in m.group(1):
            return f"escrita SQL em {m.group(1)}"
    for m in SEGAPE_BQ_ESCRITA.finditer(cmd):
        if "projeto_painel_ministro" not in m.group(1):
            return f"bq escrevendo em {m.group(1)}"
    if "/Projetos_segape" in cwd:
        for m in SEGAPE_DBT_ESCRITA.finditer(cmd):
            motivo = _segape_selecao_valida(m.group(2))
            if motivo:
                return motivo
    return None


def block(reason: str) -> None:
    """Bloqueia via JSON output."""
    print(json.dumps({"decision": "block", "reason": reason}))
    sys.exit(0)


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except Exception:
        sys.exit(0)

    tool_name = data.get("tool_name", "")
    if tool_name not in ("Write", "Edit", "MultiEdit", "Bash"):
        sys.exit(0)

    tool_input = data.get("tool_input", {}) or {}

    if tool_name == "Bash":
        cmd = tool_input.get("command", "") or ""
        if not cmd:
            sys.exit(0)
        bypass_pat = re.compile(
            r"(?:^|[\s;&|])"
            r"(?:--no-verify|--no-gpg-sign|-c\s+commit\.gpgsign\s*=\s*false"
            r"|core\.hookspath[\s=]+(?!" + re.escape("/home/andrefarias/.config/git/hooks") + r"))",
            re.IGNORECASE,
        )
        m = bypass_pat.search(cmd)
        if m:
            block(
                f"Comando tenta contornar defesas anti-IA ({m.group(0)!r}). "
                "Politica: --no-verify, --no-gpg-sign e override de core.hookspath "
                "estao bloqueados. Use o caminho correto: corrija a causa, não bypass."
            )
        m = GIT_ADD_ALL.search(cmd)
        if m:
            block(
                f"Stage em massa bloqueado ({m.group(0)!r}). Commit curado por path: "
                "liste os arquivos explicitamente (git add caminho1 caminho2). "
                "Regra anti-debito do sprint-ciclo (nunca git add -A / --all / git add .)."
            )
        motivo = segape_violacao(cmd, data.get("cwd", "") or "")
        if motivo:
            block(
                f"SEGAPE: {motivo}. So existe escrita em br-mec-segape-dev.projeto_painel_ministro; "
                "producao, sandbox e andre_teste estao fora do acesso. "
                "Regras em ~/Desenvolvimento/Projetos_segape/CLAUDE.md."
            )
        if AI_ATTRIBUTION.search(cmd) or AI_EMAIL.search(cmd):
            block(
                "Comando contem atribuicao a IA (provavel git commit/tag com "
                "Co-Authored-By ou email de provedor). Regra GUIDE.md #2."
            )
        sys.exit(0)

    file_path = get_file_path(tool_input)

    if is_exempt_path(file_path):
        sys.exit(0)

    content = get_content(tool_input, tool_name)
    if not content:
        sys.exit(0)

    match = EMOJI_PATTERN.search(content)
    if match:
        start = max(0, match.start() - 30)
        end = min(len(content), match.end() + 30)
        snippet = content[start:end].replace("\n", " ")
        block(
            f"Emoji detectado ({match.group(0)!r}) em {file_path or 'conteudo'}. "
            f"Contexto: ...{snippet}... "
            f"Regra GUIDE.md #3 (zero emojis em codigo, commits, docs, respostas)."
        )

    match = AI_ATTRIBUTION.search(content)
    if match:
        block(
            f"Atribuicao a IA detectada ({match.group(0)[:80]!r}) em "
            f"{file_path or 'conteudo'}. Regra GUIDE.md #2 (anonimato absoluto: "
            f"zero mencoes a Claude/GPT/Anthropic/etc em codigo ou commits)."
        )

    match = AI_EMAIL.search(content)
    if match:
        block(
            f"Email de atribuicao IA detectado em {file_path or 'conteudo'}. "
            f"Regra GUIDE.md #2 (anonimato absoluto)."
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
