#!/usr/bin/env python3
"""
Hook PreToolUse (Write/Edit/MultiEdit) — bloqueia:
  1. Emojis em qualquer contexto (regra CLAUDE.md #3)
  2. Atribuicoes explicitas a IA (regra CLAUDE.md #2)

Executa ANTES da escrita/edicao. Se bloqueia, Claude ve a razao e ajusta.
"""
import json
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
    r"Windsurf|Codeium|Tabnine)"
)

AI_EMAIL = re.compile(r"noreply@anthropic", re.IGNORECASE)


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
        "/_lib.sh",
        "/emoji_guardian.py",
        "/sanitizar_ia.py",
        "/universal-sanitizer.py",
        "/CLAUDE.md",
        "/AI.md",
    ]
    return any(marker in file_path for marker in exempt_markers)


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
    if tool_name not in ("Write", "Edit", "MultiEdit"):
        sys.exit(0)

    tool_input = data.get("tool_input", {}) or {}
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
            f"Regra CLAUDE.md #3 (zero emojis em codigo, commits, docs, respostas)."
        )

    match = AI_ATTRIBUTION.search(content)
    if match:
        block(
            f"Atribuicao a IA detectada ({match.group(0)[:80]!r}) em "
            f"{file_path or 'conteudo'}. Regra CLAUDE.md #2 (anonimato absoluto: "
            f"zero mencoes a Claude/GPT/Anthropic/etc em codigo ou commits)."
        )

    match = AI_EMAIL.search(content)
    if match:
        block(
            f"Email de atribuicao IA detectado em {file_path or 'conteudo'}. "
            f"Regra CLAUDE.md #2 (anonimato absoluto)."
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
