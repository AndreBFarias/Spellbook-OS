# Projetos SEGAPE (MEC)

Vale para tudo abaixo de `~/Desenvolvimento/Projetos_segape/`. O `install.sh` cria este arquivo
aqui como link simbólico para `~/.config/zsh/docs/claude/segape/regras-segape.md`. Ele fica fora de
qualquer repositório e nunca entra em commit.

## Quem

André Farias, da **equipe do Painel** (`projeto_painel_ministro`). Não é da equipe de Analytics.
Conta GitHub: `andrefariasmec`. Se o `gh` ativo for a conta pessoal, use
`GH_TOKEN=$(gh auth token -u andrefariasmec) gh ...`.

## Leitura obrigatória

Antes de qualquer tarefa, conheça as duas pastas de referência:

1. `onboarding-painel-estrategico/`: o README e os guias 04, 05 e 10 estão importados abaixo.
   Leia os outros guias quando o assunto aparecer.
2. `pipelines/`: antes de mexer num modelo, leia o SQL dele, o bloco dele em
   `queries/models/projeto_painel_ministro/schema.yml` e dois ou três modelos vizinhos do mesmo
   programa. Copie o jeito deles, não um padrão genérico.

@~/Desenvolvimento/Projetos_segape/onboarding-painel-estrategico/README.md
@~/Desenvolvimento/Projetos_segape/onboarding-painel-estrategico/04-padroes-codigo.md
@~/Desenvolvimento/Projetos_segape/onboarding-painel-estrategico/05-armadilhas.md
@~/Desenvolvimento/Projetos_segape/onboarding-painel-estrategico/10-commit-e-pull-request.md

## Acesso ao BigQuery

| Projeto | Leitura | Escrita |
|---|---|---|
| `br-mec-segape-dev` | Sim | Só no schema `projeto_painel_ministro` |
| `br-mec-segape-dev.andre_teste` | Não | Não. O target existe em `dev/profiles.yml`, mas não se usa |
| `br-mec-segape` (prod) | Não | Não. A comparação com prod é do revisor |
| `br-mec-segape-sandbox` | Não | Não. Depois de `gcloud auth login` pelo navegador a conta passa a conseguir criar tabela lá, mas a regra continua a mesma |

- dbt sempre de dentro de `queries/`, com `--profiles-dir ../dev` e `--select` apontando só para
  modelos de `projeto_painel_ministro`, sem `+` nem `@`. O `queries/profiles.yml` versionado
  aponta para prod.
- O hook `guardian.py` barra comando de `bq`/`dbt`/`gcloud` que fure essa tabela. Se ele
  barrar, o comando está errado. Não procure contorno.

## Escrever como o Vinicius Jacinto

Ele é a referência de escrita do repositório. Medido em 2026-09-23:

- **Commit**: uma linha, minúscula, sem ponto, de 2 a 5 palavras. `ajuste schema`,
  `remove filtro df`, `inclusao coluna ano`, `adiciona coluna`. Rituais: `pre-commit`,
  `checkpoint`, `ajustes da revisão`. Sem `feat:`/`fix:`.
- **Título da PR**: `[PAINEL] <PROGRAMA> - <Verbo no presente> <objeto>`, com maiúscula e
  acento, de 45 a 75 caracteres. Outro consumidor entra depois: `[PAINEL] [BRIEFING]`. Nunca
  `[ANALYTICS]`, que é a tag da outra equipe.
- **Corpo da PR**: vazio, ou uma frase que começa pelo verbo e cita `schema.tabela` entre
  crases. Quando houver mais, use `## Resumo`, uma tabela ou lista das colunas,
  `## Alterações` e `## Fora deste PR`. Não use `## Como testar`, checklist nem
  "Padrões cumpridos".
- **SQL**: quase sem comentário (4 comentários em 2.336 linhas dele). Se um for inevitável,
  use `{# #}` numa linha, com a regra de negócio e não com o raciocínio.

## Sem rastro de IA

- Nada verborrágico. Commit curto, título no molde, corpo curto ou vazio.
- Nenhum comentário, título ou commit que narre o problema ("corrige bug que duplicava",
  "antes X, agora Y", "isso resolve"). Diga o que muda, não a história do defeito.
  `Claude`, IA ou assistente.
- Fora do diff, sempre: `CLAUDE.md`, `VALIDATOR_BRIEF.md`, `.claude/`, arquivos de plano ou de
  spec.
- Commit, push e PR só quando o André pedir. Sem sprint-ciclo, sem validador-sprint e sem
  subagentes aqui.

## schema.yml

Toda mudança de coluna ou de modelo do Painel entra no arquivo existente
`queries/models/projeto_painel_ministro/schema.yml`. Mantenha o schema atual e só acrescente:

- Coluna nova vai no bloco do modelo, depois da última coluna, com uma linha em branco entre
  colunas, como as vizinhas.
- Modelo novo vai num bloco próprio, com o cabeçalho `#nome_do_modelo` que os outros usam e a
  description no formato `... // Frequência de atualização: ... // Partição: ... // Nível da
  observação: ... // Fonte: ... // Gestora dos dados: ... // Tratamento dos dados: SEGAPE`.
- Não reordene, não reindente, não reformate e não mexa em description de outro modelo. O diff
  do `schema.yml` tem de mostrar só linhas `+`, como na PR #1656.

## Fora de todo commit

`dev/run.py` com execução ativa, `prefect.yaml` com deployment descomentado, `dev/profiles.yml`,
credenciais, `queries/target/`, `queries/dbt_packages/`, `queries/dbt_internal_packages/`,
`.github/`, `.gitattributes`, `queries/profiles.yml`. `git add` arquivo por arquivo.
