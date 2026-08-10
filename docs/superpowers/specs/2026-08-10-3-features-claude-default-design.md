# Design: 3 features do Claude Code como padrão (hallmark, i-have-adhd, code-review-graph)

- **Data:** 2026-08-10
- **Repo:** `~/.config/zsh` (Spellbook-OS)
- **Status:** design aprovado, pendente plano de implementação

## Objetivo

Instalar três ferramentas de terceiros e torná-las padrão nesta máquina, com
propagação automática para as demais via autosync, respeitando a idempotência
do `install.sh`.

| Ferramenta | Natureza real | Papel pretendido |
| --- | --- | --- |
| [hallmark](https://github.com/nutlope/hallmark) | Skill do Claude Code | Direção de design, com prioridade em `/design` |
| [i-have-adhd](https://github.com/ayghri/i-have-adhd) | Plugin com hook `SessionStart` | Formato de saída padrão em toda sessão `cca` |
| [code-review-graph](https://github.com/tirth8205/code-review-graph) | MCP server + CLI Python | Contexto de código sob demanda, por repositório |

## Verificações feitas (2026-08-10)

Registradas porque contradizem os READMEs em pontos que mudam a implementação.

1. `code-review-graph` está no PyPI, v2.3.7, `requires_python >=3.10`. Local:
   `pipx 1.0.0`, `python3 3.12.1`, `uv 0.12.1` presentes.
2. `hallmark` **não** é plugin nem tem `.claude-plugin/`. É uma árvore de skill
   em `skills/hallmark/`: `SKILL.md` (67 KB) + `references/` com 113 arquivos.
   Total 114 entradas, 674 KB.
3. `i-have-adhd` é plugin completo (`.claude-plugin/marketplace.json` +
   `plugin.json`) e seu `hooks/always-on.mjs` **não é always-on por si**: só
   injeta o ruleset se existir o arquivo-flag
   `$CLAUDE_CONFIG_DIR/.i-have-adhd-always` (default `~/.claude`). Sai com 0 em
   qualquer falha, nunca bloqueia o início da sessão.
4. `i-have-adhd/skills/i-have-adhd/SKILL.md` declara
   `disable-model-invocation: true`. O modelo não pode invocá-la. O arquivo-flag
   é o único caminho para comportamento padrão.
5. A `description` do hallmark dispara em "build a new app or landing page,
   redesign, audit/study, ou Hallmark pelo nome". **Não menciona `/design`.**
6. `code-review-graph` grava o grafo em `.code-review-graph/` na raiz do repo.
   Config MCP publicada no README:
   `command: code-review-graph`, `args: ["serve", "--tools", "query_graph_tool,semantic_search_nodes_tool,detect_changes_tool,get_review_context_tool"]`.
7. `install.sh` já symlinka `$DOCS/skills/*/` para `$CLAUDE/skills/` em
   `_sync_claude_symlinks` (linhas 51-56). É o mecanismo que serve a
   `validacao-visual`. `DOCS="${SCRIPT_DIR}/docs/claude"` e
   `CLAUDE="${HOME}/.claude"` (linhas 28-29).
8. `~/.claude/CLAUDE.md` é symlink para `GUIDE.md` deste repo.
9. Nenhum passo exige `sudo`: `pipx` instala em `~/.local`, plugins e skills do
   Claude ficam em `$HOME`.

## Decisões

### D1 — i-have-adhd convive com o output style `learning`

O ADHD dita a **forma**, o `learning` dita o **conteúdo**. Regra de precedência
escrita no `GUIDE.md`: estrutura ADHD (ação primeiro, passos numerados, sem
preâmbulo, máximo 5 itens por lista) e o insight educacional reduzido a **no
máximo um bloco curto ao final**, nunca espalhado pelo texto.

Justificativa: o ruleset do ADHD chega por hook de `SessionStart` e o `learning`
por output style. Nenhum dos dois conhece o outro. `CLAUDE.md` está num nível
acima de ambos e serve de árbitro.

Alternativas descartadas: aposentar o `learning` (perde valor didático);
deixar o ADHD opt-in (contraria o pedido de "por default").

### D2 — code-review-graph sobe só onde tem grafo

MCP ligado por autodetecção: se existir `.code-review-graph/` no diretório
atual, `cca` injeta `--mcp-config`. Caso contrário, zero RAM.

Justificativa: em 2026-06-16 o context7 foi desligado por default porque cada
MCP custa ~168 MB por instância e cada subagente sobe o próprio par (~1,1 GB
medidos com 5 sessões). Um MCP always-on reverteria essa decisão. Além disso,
sem `code-review-graph build` no repo o servidor não tem o que responder — em
repositório sem grafo ele só ocuparia memória.

Escape hatch simétrico ao context7: `CCA_CRG=0` desliga, `CCA_CRG=1` força.

### D3 — hallmark tem precedência sobre frontend-design

Ambos ficam instalados. Regra no `GUIDE.md`: em trabalho visual e em `/design`,
hallmark primeiro; o plugin oficial `frontend-design` só no que o hallmark não
cobrir.

Esta regra é o que efetivamente liga o hallmark ao `/design`, já que a
`description` da skill não cita esse modo (verificação 5) e sem a regra o modelo
provavelmente não a acionaria ali.

### D4 — três comandos explícitos, disponíveis nos dois ambientes

Cada ação ganha um par: função de shell e comando de barra.

| Ação | Shell | Sessão |
| --- | --- | --- |
| Construir o grafo do repo atual | `fazer_grafos` | `/fazer-grafos` |
| Ligar e desligar o modo TDAH | `ativar_tdah`, `desativar_tdah` | `/tdah` |
| Trabalhar com direção de design | `design_humano` | `/design-humano` |

Justificativa: regra em arquivo de instrução diz *o quê*; comando explícito dá o
*gatilho*. Como a `description` do hallmark não cobre `/design`, o comando é o
que garante acionamento sem depender do julgamento do modelo.

Assimetria a respeitar na implementação: o hook do TDAH roda em `SessionStart`,
então a função de shell só faz efeito na sessão seguinte. O comando de barra
deve fazer as duas coisas — injetar o conjunto de regras na hora **e** criar o
arquivo-flag para persistir.

`design_humano` no shell abre `cca` já com a skill hallmark acionada.

### D5 — specs técnicos saem do filtro do pre-commit

`docs/superpowers/*` entra no `case` de exclusão de `filter_files()`, com
comentário datado no padrão dos três precedentes já autorizados pelo dono.

Justificativa e custo aceito estão detalhados na seção "Armadilha conhecida"
adiante, que também registra o mapeamento medido do comportamento do hook.

## Arquitetura

### C1 — hallmark vendorizado

Árvore `skills/hallmark/` do upstream copiada para
`docs/claude/skills/hallmark/` neste repo. `_sync_claude_symlinks` cria
`$CLAUDE/skills/hallmark` automaticamente.

Ganhos: idempotente pelo mecanismo que já existe; versionado; propagado pelo
autosync para as demais máquinas sem passo extra.

Descartado `npx skills add nutlope/hallmark`: baixa da rede em cada máquina, sem
pin de versão, fora do controle de idempotência do projeto.

Registrar a versão de origem (`version: 1.1.0` do frontmatter) e o commit
upstream num `PROVENANCE.md` ao lado, para saber o que atualizar depois.

### C2 — i-have-adhd como plugin + arquivo-flag

```
claude plugin marketplace add ayghri/i-have-adhd
claude plugin install i-have-adhd@i-have-adhd
touch "$CLAUDE/.i-have-adhd-always"
```

Reversão: `rm "$CLAUDE/.i-have-adhd-always"` desliga sem tocar em
`settings.json`.

O plugin aparece em `enabledPlugins` do `~/.claude/settings.json`, que **não é
versionado** — daí o passo idempotente no `install.sh` cobrir máquina nova.

### C3 — code-review-graph com MCP condicional

1. `pipx install code-review-graph`
2. `cca/mcp-code-review-graph.json` no mesmo padrão de `cca/mcp-context7.json`
3. Em `__cca_run`: se `-d .code-review-graph` no diretório atual e `CCA_CRG` não
   for `0`, acrescenta `--mcp-config`; `CCA_CRG=1` força mesmo sem grafo

### C4 — regras no GUIDE.md

Duas seções novas, curtas, no arquivo que já é o `CLAUDE.md` global:
precedência de forma (D1) e precedência de design (D3).

### C5 — comandos: um par por ação

Comandos de barra em `docs/claude/commands/*.md`, que `_sync_claude_symlinks` já
liga a `$CLAUDE/commands/` (mesmo mecanismo de `/executar-sprint` e afins).

Funções de shell em `functions/cca_features.zsh`, seguindo o padrão dos demais
arquivos de `functions/` e usando os auxiliares de `_helpers.zsh`
(`__header`, `__item`, `__ok`, `__warn`, `__err`) e a paleta Dracula.

Comportamento esperado:

- `fazer_grafos` — roda o build no repositório atual, informa o tamanho do
  índice gerado e confirma que a próxima sessão vai detectá-lo
- `ativar_tdah` / `desativar_tdah` — cria e remove o arquivo-flag, avisando de
  forma explícita que só vale a partir da sessão seguinte
- `design_humano` — abre `cca` com a skill de design já acionada
- `/tdah` — injeta o conjunto de regras na sessão corrente **e** cria o
  arquivo-flag
- `/fazer-grafos` e `/design-humano` — equivalentes de sessão

### C6 — três passos idempotentes no install.sh

Seguindo o padrão existente (`_step_*`, `_run`, `_info/_ok/_warn`, respeito a
`--dry-run`):

| Passo | Guarda de idempotência |
| --- | --- |
| `_step_claude_skill_hallmark` | symlink já aponta para o destino certo |
| `_step_claude_plugin_adhd` | `jq` em `enabledPlugins` + existência da flag |
| `_step_code_review_graph` | `pipx list` já contém o pacote |

Os comandos de C5 não precisam de passo próprio: os de barra vêm de
`_sync_claude_symlinks` e as funções de shell são carregadas pelo mesmo
mecanismo que já lê `functions/*.zsh`.

## Armadilha conhecida: pre-commit corrompe menções soltas

O `pre-commit` troca `\b[Cc]laude\b` por "agente" nas linhas novas do diff.
Mapeamento exato do comportamento, medido no hook em 2026-08-10:

- `_PERL_KEEP_TOKEN='(\S*/\S*)'` preserva qualquer token que contenha barra.
  Portanto `~/.claude/skills/hallmark` e `docs/claude/skills/` **sobrevivem**.
- Menções soltas **não** sobrevivem: nomes de produto e arquivos sem barra
  viram "agente", quebrando prosa técnica e linhas de comando.
- `_PERL_SKIP_LINE='!/ia-artifact:manter/'` é a válvula de escape por linha.
- O `case` de `filter_files()` (linha 156) é a válvula por caminho, com três
  precedentes autorizados pelo dono.

Decisão (D5): adicionar `docs/superpowers/*` ao `case` de exclusão, com
comentário datado no mesmo padrão dos precedentes. Specs técnicos passam a citar
nomes de ferramenta sem corromper.

Para o código, a mitigação continua sendo usar as variáveis `$CLAUDE` e `$DOCS`
já definidas no `install.sh` (verificação 7), nunca o caminho literal.

Nota operacional: `.git/config` define `hooksPath = .githooks`, logo `.githooks/`
é o hook efetivo e os arquivos em `.git/hooks/` são resíduo. Confirmar na
prática antes de confiar nisso.

Verificação obrigatória: reler os arquivos **depois** do commit, não antes.

## Proof-of-work

Nada é considerado pronto sem execução real:

1. `code-review-graph build` neste repo, confirmando criação de
   `.code-review-graph/` — e a entrada correspondente no `.gitignore`.
2. `cca` aberto neste repo listando a ferramenta MCP; aberto em repo sem grafo
   **não** listando.
3. `ls -l "$CLAUDE/skills/hallmark"` resolvendo para `docs/claude/skills/hallmark/`.
4. Sessão nova exibindo o ruleset do ADHD injetado; após `rm` da flag, não mais.
5. `bash install.sh --dry-run` limpo, e segunda execução real sem efeito
   colateral (idempotência).
6. `grep -rn 'agente' docs/superpowers/ GUIDE.md functions/cca_features.zsh`
   sem ocorrência espúria após o commit, confirmando a exceção de D5.
7. Cada uma das seis entradas de C5 executada de fato: as três funções no shell
   e os três comandos de barra numa sessão real.

## Fora de escopo

**Andromeda (`maria` / MeowSystem).** Diagnóstico feito nesta sessão: rede
íntegra (mesma /24, mDNS resolve, ping 0% de perda, porta 22 aberta), SSH por
chave funcionando, mount sshfs ativo. Não é cabo versus Wi-Fi. O que falta é o
próprio Claude Code: `~/.claude/` existe e está populado, mas os binários
`claude` e `npm` sumiram — restou apenas `node` de `/usr/bin/node` e `uv`.

Reinstalação é viável por SSH, mas fica para decisão posterior do dono.
