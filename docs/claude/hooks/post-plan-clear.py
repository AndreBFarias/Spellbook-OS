#!/usr/bin/env python3
"""
Hook UserPromptSubmit - sugere /clear apos aprovacao de plan mode.

Detecta triggers que indicam que o usuario acabou de aprovar um plan e esta
prestes a iniciar execucao. Em vez de forcar /clear (destruiria contexto
legitimo), injeta additionalContext sugerindo uso de subagent isolado OU
/clear manual.

Complementa o caso em que o menu nativo "Yes, clear context and auto-accept
edits" do Claude Code nao aparece (bugs conhecidos #45034, #38071, #39665).

Registrado em ~/.claude/settings.json:
  hooks.UserPromptSubmit[].matcher = "*"
  command = python3 /home/andrefarias/.claude/hooks/post-plan-clear.py
  timeout = 5

Filosofia: sutil, nao-forca. Claude le a dica e decide.
"""
from __future__ import annotations

import json
import re
import sys


TRIGGERS = [
    r"\baprov(o|ado|a)\b",
    r"\bpode\s+executar\b",
    r"\bexit\s+plan\s+mode\b",
    r"\bsegue\s+pra\s+frente\b",
    r"\bimplement(a|e|ar)\b",
    r"\bvai\s+la\b",
    r"\bmanda\s+ver\b",
]

DICA = (
    "DICA (automatica - pos plan approval detectado):\n"
    "Se o plano envolve implementacao de multiplos passos, prefira:\n"
    "  1. Dispatch executor-sprint via /sprint-ciclo ou /executar-sprint (subagent isolado, contexto fresco).\n"
    "  2. Ou `/clear` manual antes de iniciar se quer conversa principal enxuta.\n"
    "Subagents ja resolvem naturalmente a economia de contexto que o menu nativo oferecia.\n"
    "Esta dica nao e obrigatoria - ignore se nao aplicavel."
)


def _matches_trigger(prompt: str) -> bool:
    lower = prompt.lower()
    for pat in TRIGGERS:
        if re.search(pat, lower):
            return True
    return False


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0

    prompt = str(data.get("prompt") or "")
    if not prompt:
        return 0

    if not _matches_trigger(prompt):
        return 0

    output = {
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": DICA,
        }
    }
    print(json.dumps(output, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)

# "Sutileza > forca. Epicteto: 'nao instrua pela repreensao mas pela conducta.'"
