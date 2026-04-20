---
description: Dispara subagente executor-sprint para implementar sprint a partir de um spec aprovado
argument-hint: <path-do-spec-opcional>
---

Dispache o subagente `executor-sprint` (model: opus) para implementar a sprint conforme o spec.

Passos:

1. Detecte a raiz do repo: `git rev-parse --show-toplevel`. Se não estiver em repo, avise e pare.

2. Identifique o spec:
   - Se $ARGUMENTS fornecido: use esse path
   - Senão: último arquivo `.md` modificado em `~/.claude/plans/` ou `dev-journey/06-sprints/producao/` ou `docs/sprints/`
   - Leia o spec e confirme que entendeu (acceptance criteria + touches autorizados + checks)

3. Contexto a injetar no subagente:
   - Raiz do repo
   - Path do spec
   - Conteúdo do spec
   - VALIDATOR_BRIEF.md path (existe? sim/não)
   - CLAUDE.md global e local

4. Chame o Agent tool com:
   - subagent_type: executor-sprint
   - model: opus
   - prompt estruturado com o contexto acima + instrução "Execute protocolo completo conforme suas instruções. Estabeleça baseline, implemente dentro do escopo, rode checks, retorne proof-of-work estruturado."

5. Apresente o proof-of-work retornado ao usuário. Se houver achados colaterais, liste separadamente e sugira criar sprint nova. Se estiver pronto para validação, sugira "/validar-sprint <path-do-spec>".
