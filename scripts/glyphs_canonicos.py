"""Allowlist canonica de glyphs de UI -- FONTE UNICA para os sanitizers.

Importado por:
- ~/.config/zsh/scripts/universal-sanitizer.py  (mesmo diretório)
- ~/Controle de Bordo/.sistema/scripts/emoji_guardian.py  (via sys.path, com fallback)

Motivo: antes cada sanitizer mantinha sua propria copia de ALLOWED_GLYPHS e
elas divergiram -- o emoji_guardian não tinha allowlist quando o universal ja
tinha, causando a recidiva de estripamento de glyphs legitimos (VECTOR-AUDIT-01
/ SPRINT 232). Centralizar aqui garante uma unica verdade.

Glyphs preservados: simbolos de UI legitimos usados por dashboards/TUI
(circle states, diamond/triangle, setas de tendencia/relacao). NAO sao emojis.
"""

from __future__ import annotations

ALLOWED_GLYPHS = frozenset({
    "○",  # U+25CB circle empty (cold/empty state)
    "◐",  # U+25D0 circle half left (warming/in progress)
    "●",  # U+25CF circle filled (warm/ok)
    "◆",  # U+25C6 diamond filled (header agente, multi-tool)
    "◇",  # U+25C7 diamond empty (glob)
    "▶",  # U+25B6 right triangle (collapsed)
    "▼",  # U+25BC down triangle (expanded)
    "▸",  # U+25B8 small right triangle (bash/execute)
    "◼",  # U+25FC small black square (todo done)
    "◻",  # U+25FB small white square (todo pending)
    "↗",  # U+2197 arrow upper right (web/network, tendencia de alta)
    "↘",  # U+2198 arrow lower right (tendencia de baixa -- be_medidas)
    "↔",  # U+2194 arrow left-right (relacao bidirecional A<->B)
})
