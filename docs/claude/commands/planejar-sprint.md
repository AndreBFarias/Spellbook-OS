---
description: Dispara subagente planejador-sprint para redigir spec de sprint a partir de uma ideia/bug/requisito
argument-hint: <ideia-ou-contexto-da-sprint>
---

Dispache o subagente `planejador-sprint` (model: opus) para redigir o spec completo de uma sprint a partir do contexto fornecido.

Passos:

1. Detecte a raiz do repo: `git rev-parse --show-toplevel`. Se não estiver em repo, avise e pare.

2. Contexto a injetar no subagente:
   - Raiz do repo
   - VALIDATOR_BRIEF.md path (existe? sim/não)
   - CLAUDE.md global e local
   - Ideia/requisito/bug: $ARGUMENTS
   - Se $ARGUMENTS estiver vazio, peça ao usuário a ideia/requisito antes de dispatchar

3. Chame o Agent tool com:
   - subagent_type: planejador-sprint
   - model: opus
   - prompt estruturado com o contexto acima + instrução "Execute protocolo completo conforme suas instruções e retorne o path do spec criado."

4. Apresente o resultado:
   - Path do spec criado
   - Resumo em 3 linhas do que foi planejado
   - Próximo passo sugerido: "/executar-sprint <path>" quando aprovar
