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
    # --- notacao tecnica, acrescentada em 31/07/2026 (Fase 7) --------------
    # Estes caem dentro das faixas 2600-26FF e 2700-27BF, que o sanitizer
    # apaga por serem "Miscellaneous Symbols" e "Dingbats". Mas nenhum deles
    # e emoji: sao a notacao com que documentacao, diagrama e tabela de
    # resultado dizem o que passou, o que falhou e o que exige atenção.
    # Apaga-los não limpa o texto, destroi o sentido dele.
    "→",  # U+2192 seta direita (fluxo, de-para, "vira")
    "←",  # U+2190 seta esquerda
    "↑",  # U+2191 seta acima
    "↓",  # U+2193 seta abaixo
    "✓",  # U+2713 marca de conferencia (passou)
    "✔",  # U+2714 marca de conferencia grossa
    "✗",  # U+2717 marca de falha (não passou)
    "✘",  # U+2718 marca de falha grossa
    "★",  # U+2605 estrela cheia (prioridade, destaque)
    "☆",  # U+2606 estrela vazia
    "⚠",  # U+26A0 sinal de atenção (aviso em documentacao)
    "☐",  # U+2610 caixa vazia (checklist em texto puro)
    "☑",  # U+2611 caixa marcada
    # --- controles de transporte, acrescentados em 21/09/2026 --------------
    # Caem na faixa 2300-23FF ("Miscellaneous Technical"), que o sanitizer
    # apaga junto com os emojis de relogio. Nenhum deles e emoji: sao o
    # vocabulario com que documentacao de player desenha a barra de controle.
    #
    # O CASO QUE OS TROUXE PARA CA. Em 21/09/2026 o pre-commit apagou nove
    # deles de src/applets/now-playing/LEIA.md do MeowSystem, nas linhas 49,
    # 50 e 76 -- linhas que ninguem tinha tocado. O mecanismo, medido: o
    # corretor de acentuacao roda primeiro e re-stageia o arquivo; com isso
    # aquelas linhas entram no diff staged; o sanitizer passa a ve-las como
    # linhas ACRESCENTADAS, e a guarda SANITIZER-STAGED-LINES-ONLY deixa de
    # proteger o que ja estava no arquivo.
    #
    # O estrago e o mesmo que o cabecalho deste arquivo ja descreve: uma frase
    # como "Controles na barra: ⏮ e ⏭, e ⏸ no meio" virou "Controles na
    # barra:  e , e  no meio". Apagar não limpou o texto, destruiu o sentido.
    "⏮",  # U+23EE faixa anterior
    "⏸",  # U+23F8 pausa
    "⏭",  # U+23ED proxima faixa
    "⏯",  # U+23EF tocar/pausar (o par dos dois acima)
    "⏹",  # U+23F9 parar
})
