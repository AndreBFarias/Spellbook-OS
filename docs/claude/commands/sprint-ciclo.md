---
description: Fluxo completo de sprint (planejar → aprovar → executar → validar) com checkpoints manuais entre cada etapa
argument-hint: <ideia-da-sprint>
---

Execute o ciclo completo de uma sprint com checkpoints de aprovação do usuário entre etapas.

**Etapa 1 — Planejamento**
1. Dispatche `planejador-sprint` (model: opus) com a ideia: $ARGUMENTS
2. Receba o spec gerado
3. Apresente ao usuário e aguarde aprovação explícita. Não avance sem "aprovado" ou equivalente.

**Etapa 2 — Execução**
1. Só após aprovação, dispatche `executor-sprint` (model: opus) com o spec aprovado.
2. Receba o proof-of-work.
3. Apresente ao usuário. Se houver achados colaterais, deixe claro e aguarde decisão (criar sprint nova? continuar?).

**Etapa 3 — Validação**
1. Só após confirmação da etapa 2, dispatche `validador-sprint` (model: opus) com o spec + diff + proof-of-work.
2. Apresente o veredicto.
3. Se APROVADO: sugira commit. Se REPROVADO: apresente achados e aguarde decisão de correção.

**Regras do ciclo:**
- Nunca pule checkpoints. Usuário aprova entre cada etapa.
- Se qualquer subagente reportar bloqueio/dúvida, pause e peça clarificação ao usuário.
- Protocolo anti-débito em vigor: achados colaterais viram sprints novas, nunca fixados inline.
- Todos os subagentes usam o VALIDATOR_BRIEF.md do projeto atual como memória compartilhada.
