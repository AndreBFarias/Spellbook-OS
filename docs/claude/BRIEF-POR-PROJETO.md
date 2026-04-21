# docs/claude/BRIEF-POR-PROJETO.md — Catálogo de VALIDATOR_BRIEF.md ativos

Tabela atualizada pelo validador-sprint conforme BRIEFs são criados ou enriquecidos.

## Projetos conhecidos (SPECIAL_PROJECTS)

| Projeto | Path | BRIEF presente? | Linhas | Última atualização | Tipo | Notas |
|---|---|---|---|---|---|---|
| Luna | `/home/andrefarias/Desenvolvimento/Luna/VALIDATOR_BRIEF.md` | Não (ainda) | — | — | tui | Será gerado em MODO BOOTSTRAP_RICO ao 1º santuario pós-v2 (65 memórias) |
| Nyx-Code | `/home/andrefarias/Desenvolvimento/Nyx-Code/VALIDATOR_BRIEF.md` | Não (ainda) | — | — | cli | Idem (13 memórias) |
| protocolo-ouroboros | `/home/andrefarias/Desenvolvimento/protocolo-ouroboros/VALIDATOR_BRIEF.md` | Não (ainda) | — | — | cli | Idem (memória vazia — MODO BOOTSTRAP genérico via exploração) |

## Projetos genéricos

Qualquer outro repo git que você abrir com `santuario + cca` terá BRIEF criado automaticamente via MODO BOOTSTRAP (exploração exaustiva do codebase). A entrada será adicionada aqui quando o validador atualizar este catálogo.

## Como é atualizado

Ao criar ou atualizar um BRIEF:
1. Validador-sprint (ou bootstrap-rico-brief.py) grava `VALIDATOR_BRIEF.md` no repo-alvo.
2. Adiciona linha aqui com: path, linhas, data, tipo.
3. Commit no Spellbook-OS via autosync.

## Leitura rápida

Para inspecionar um BRIEF:
```bash
cd ~/Desenvolvimento/<Projeto>
sprint brief
# ou:
cat VALIDATOR_BRIEF.md | head -50
```

Editar manualmente:
```bash
sprint brief-edit
```

## Integração com validador

Ao invocar `/validar-sprint`:
1. Se BRIEF ausente -> dispatch MODO BOOTSTRAP (ou BOOTSTRAP_RICO se projeto conhecido com memórias).
2. Se BRIEF presente -> dispatch MODO VALIDATE usando BRIEF como memória.
3. Validador pode atualizar BRIEF se detecta padrão novo recorrente.
