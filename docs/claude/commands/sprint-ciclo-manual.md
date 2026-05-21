---
description: Ciclo de sprint com checkpoints manuais (opt-in). Usuário aprova entre planejar → executar → validar. Versão conservadora do /sprint-ciclo para revisar passo a passo.
argument-hint: <ideia-da-sprint>
---

Execute o ciclo completo de uma sprint **com checkpoints de aprovação** entre etapas. Use quando quiser revisar o spec antes de executar, ou inspecionar o proof-of-work antes de validar.

Para ciclo automático (sem checkpoints), use `/sprint-ciclo`.

**Etapa 1 — Planejamento**

1. Dispatche `planejador-sprint` (subagent, model: opus) com `$ARGUMENTS`.
2. Capture o spec gerado.
3. Apresente ao usuário: path do spec + resumo em 3-5 linhas (escopo, touches, acceptance).
4. Aguarde aprovação explícita. Palavras-gatilho: "aprovo", "aprovado", "pode executar", "segue". Se ambíguo, peça confirmação explícita.
5. Se usuário rejeita ou pede ajustes, retorne ao planejador com o feedback e itere.

**Etapa 2 — Execução**

1. Só após aprovação, dispatche `executor-sprint` (subagent, model: opus) com o spec path.
2. Executor aplica o protocolo v2 (passos PRÉ-0, 0.3, 0.4, 1-7).
3. Apresente ao usuário o proof-of-work retornado:
   - Diff final
   - Runtime-real (smoke + gauntlet + unit)
   - Validação visual (se aplicável — PNG + hash + descrição)
   - Acentuação periférica
   - Achados colaterais (se houver)
4. Se houver achados colaterais, liste-os explicitamente e peça decisão: criar sprint nova automaticamente? Continuar sem criar?
5. Aguarde confirmação do usuário para seguir para validação.

**Etapa 3 — Validação**

1. Só após confirmação da etapa 2, dispatche `validador-sprint` (subagent, model: opus) com spec + diff + proof-of-work.
2. Apresente o veredicto completo:
   - Status: APROVADO / APROVADO_COM_RESSALVAS / REPROVADO
   - Achados por severidade (CRÍTICO / PONTO-CEGO / IMPORTANTE / MINÚCIA)
   - Evidência visual
   - Tabela de checks universais
   - Próximo passo sugerido
3. Se APROVADO ou APROVADO_COM_RESSALVAS: sugira commit manualmente via `/commit-push-pr` — não execute automaticamente (esta é a versão manual).
4. Se REPROVADO: apresente achados com Edit-prontos. Aguarde decisão do usuário:
   - Aplicar correções inline agora?
   - Dispatch executor novamente com patch-brief?
   - Abandonar e revisar spec?

## Regras do ciclo manual

- **Checkpoints obrigatórios** entre cada etapa. Nunca pule.
- Se qualquer subagente reporta bloqueio/dúvida, pause e peça clarificação.
- Protocolo anti-débito em vigor: achados colaterais viram sprints novas (auto-dispatch disponível).
- Todos os subagentes usam o `VALIDATOR_BRIEF.md` do projeto como memória compartilhada.
- Sem auto-commit/push/PR — usuário executa manualmente após APROVADO.
