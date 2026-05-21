# Bootstrap — protocolo-ouroboros

> Cole o bloco abaixo da linha `---` na sessão Claude viva que revisou as sprints do ouroboros.
>
> Alternativa automatizada: `python3 ~/.config/zsh/scripts/bootstrap-rico-brief.py --projeto protocolo-ouroboros --saida /home/andrefarias/Desenvolvimento/protocolo-ouroboros/VALIDATOR_BRIEF.md`
>
> NOTA: pasta de memórias ainda vazia em `~/.claude/projects/-home-andrefarias-Desenvolvimento-protocolo-ouroboros/memory/`. O script gera BRIEF com seções CORE pré-preenchidas via template, mas sem import de memórias históricas.

---

Bootstrap VALIDATOR_BRIEF.md — protocolo-ouroboros

Escreva em `/home/andrefarias/Desenvolvimento/protocolo-ouroboros/VALIDATOR_BRIEF.md` seguindo o template em `~/.config/zsh/docs/claude/VALIDATOR_BRIEF_UNIVERSAL_TEMPLATE.md`.

## Contexto do projeto

Catalogador universal artesanal. Inbox recebe foto de cupom, DANFE PDF, XML NFe, HEIC, etc. Extração granular + grafo SQLite. Supervisor artesanal = o próprio Claude Code (sem API programática).

## Fases do protocolo

- **ALFA**: sprints 37-40 (retroativas)
- **BETA**: 41-43 (infra)
- **GAMA**: 44-47b (extratores)
- **DELTA**: 48-50 (linking / ER)
- **EPSILON**: 51-53 (UX)
- **ZETA**: finalização (em definição)

## Arquitetura essencial

- `src/` — código principal
- `data/` + `inbox/` — dados brutos a catalogar
- `mappings/` — grafo SQLite + schemas
- `docs/ROADMAP.md` — trilha de fases
- `docs/DIARIO_MELHORIAS.md` — log incremental de decisões
- `docs/adr/` — ADRs 13/14/15
- `contexto/` — contexto volátil por sessão
- `hooks/` — hooks do projeto

## Supervisor (Claude Code é o supervisor)

Comandos helpers:
- Consulta: `scripts/supervisor_contexto.sh <N>`
- Aprovar: `scripts/supervisor_aprovar.sh <ID>`
- Rejeitar: `scripts/supervisor_rejeitar.sh <ID>`
- Nova proposta: `scripts/supervisor_proposta_nova.sh`

## Contratos de runtime (preencher quando projeto estabilizar)

- Smoke: `<a preencher — provavelmente ./run.sh --smoke quando existir>`
- Acentuação: `python3 scripts/check_acentuacao.py`
- Gauntlet freshness: `python3 scripts/check_gauntlet_freshness.py`
- Finalizar sprint: `bash scripts/finish_sprint.sh`

## ADRs

- ADR-013, ADR-014, ADR-015 em `docs/adr/` — ler para entender decisões arquiteturais.

## Arquivos periféricos (acentuação)

- README.md
- Docstrings em `src/**/*.py`
- Citações filosóficas em docs/

## Regras de escrita

- Seja concreto: arquivo, função, linha quando lembrar.
- Não invente. Se não lembra, omita ou marque `<a preencher>`.
- PT-BR direto. Zero emojis. Acentuação correta obrigatória.
- Rodapé: `*Atualizado em <ISO timestamp> por bootstrap-rico (sessão protocolo-ouroboros)*`
