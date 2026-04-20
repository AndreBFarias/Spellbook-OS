# Claude Code Setup — Spellbook-OS

Documentacao da integracao do Claude Code (CLI da Anthropic) com o ambiente Spellbook-OS. Cobre o sistema universal de validação de sprints, hooks, statusline, slash commands e aliases.

## Visao geral

Este setup transforma o Claude Code em um assistente de desenvolvimento estruturado ao redor do ciclo de sprint:

```
planejar -> executar -> validar
```

Cada etapa e um subagente Opus separado. A memoria do validador e persistida em `VALIDATOR_BRIEF.md` na raiz de cada projeto (versionado no repo), eliminando a dependencia de contexto volatil de sessão.

## Componentes

### 1. Agentes (em `~/.claude/agents/`)

| Agente | Função |
|---|---|
| `planejador-sprint` | Recebe ideia ou bug, explora codebase, redige spec de sprint com acceptance criteria |
| `executor-sprint` | Recebe spec aprovado, implementa dentro dos touches autorizados, retorna proof-of-work rigoroso |
| `validador-sprint` | Auto-inicializa `VALIDATOR_BRIEF.md` na primeira execução em qualquer projeto git; valida proof-of-work; enriquece BRIEF com padroes novos |

### 2. Slash Commands (em `~/.claude/commands/`)

| Command | Proposito |
|---|---|
| `/planejar-sprint <ideia>` | Dispatcha `planejador-sprint` |
| `/executar-sprint [spec]` | Dispatcha `executor-sprint` |
| `/validar-sprint [plano]` | Dispatcha `validador-sprint` com diff + proof-of-work |
| `/sprint-ciclo <ideia>` | Ciclo completo (plan -> exec -> val) com checkpoints de aprovacao |

### 3. Templates (em `~/.claude/templates/`)

Prompts para "bootstrap rico" em sessões vivas que acumularam expertise do projeto. Captura conhecimento tacito que o auto-bootstrap por exploracao não alcanca.

- `bootstrap-generico.md` — template universal para qualquer projeto novo
- `bootstrap-luna.md` — customizado para Luna
- `bootstrap-nyx-code.md` — customizado para Nyx-Code
- `bootstrap-ouroboros.md` — customizado para protocolo-ouroboros

### 4. Hook `guardian.py` (em `~/.claude/hooks/`)

Registrado como `PreToolUse` em `Write|Edit|MultiEdit`. Bloqueia:

- Emojis em qualquer conteudo editado (regra CLAUDE.md secao 3)
- Atribuicoes explicitas de autoria a ferramentas de IA (regra CLAUDE.md secao 2)

Paths exemptos: `guardian.py`, `_lib.sh`, `emoji_guardian.py`, `sanitizar_ia.py`, `universal-sanitizer.py`, `CLAUDE.md`, `AI.md` — arquivos onde regex de emoji ou de atribuicao sao legitimos por natureza.

### 5. Statusline (em `~/.claude/statusline.sh`)

Mostra na barra de status:

```
<projeto> | <branch> | <modelo> | $<custo> | brief:<N>L | cca:<N>req
```

Componentes:
- Nome do diretório (projeto)
- Branch git atual
- Modelo em uso (Opus 4.7, Sonnet 4.6, etc.)
- Custo acumulado da sessão em USD
- Status do `VALIDATOR_BRIEF.md` se existir (numero de linhas)
- Numero de requests na semana (do quota manager do cca)

### 6. Keybindings (em `~/.claude/keybindings.json`)

- `ctrl+k ctrl+t` -> toggle todos
- `ctrl+k ctrl+r` -> toggle transcript

Keybindings so mapeiam ações pre-definidas. Nao e possivel mapear atalho para slash command — use aliases shell para isso.

### 7. Integracao Shell

#### Função `sprint` (em `~/.config/zsh/functions/sprint.zsh`)

Wrapper unificado que chama `cca` (com quota guard) para os slash commands:

```bash
sprint plan <ideia>        # dispatcha /planejar-sprint
sprint exec [spec]         # dispatcha /executar-sprint
sprint val [plano]         # dispatcha /validar-sprint
sprint ciclo <ideia>       # dispatcha /sprint-ciclo

sprint brief               # status do VALIDATOR_BRIEF.md do projeto
sprint brief-edit          # abre BRIEF no editor
sprint bootstrap           # copia template bootstrap-rico pro clipboard

sprint doctor              # health check completo do setup
```

#### Aliases (em `~/.config/zsh/cca/aliases_sprint.zsh`)

Atalhos curtos para uso diario:

| Alias | Expande para |
|---|---|
| `splan` | `sprint plan` |
| `sexec` | `sprint exec` |
| `sval` | `sprint val` |
| `sciclo` | `sprint ciclo` |
| `sbrief` | `sprint brief` |
| `sbedit` | `sprint brief-edit` |
| `sboot` | `sprint bootstrap` |
| `sdoc` | `sprint doctor` |

#### Função `santuario` (em `~/.config/zsh/functions/projeto.zsh`)

Setup completo de projeto ja existente, agora estendido para:

1. Detectar `VALIDATOR_BRIEF.md` na raiz do repo e mostrar status (linhas + idade)
2. Ao final do fluxo, oferecer: "Abrir Claude Code pronto pra validar sprint?" — se aceitar, roda `cca "/validar-sprint"` (com quota guard)

#### `cca` wrapper (em `~/.config/zsh/cca/aliases_cca.zsh`)

Função existente que ja envolve a CLI do Claude Code com quota guard e accounting de tokens. Todas as funções do `sprint` usam `cca` em vez de invocar a CLI direto, para respeitar quota semanal.

## Settings

### `~/.claude/settings.json` (global, 12 plugins ativos)

Plugins habilitados:
- `commit-commands` — helpers de commit (`/commit`, `/commit-push-pr`)
- `learning-output-style` — modo educativo ativo
- `frontend-design` — UI production-grade
- `code-review` — review estruturado (`/code-review`)
- `playwright` — automacao de browser
- `superpowers` — skills de workflow (TDD, planning, debugging, etc.)
- `context7` — docs atualizadas de libs
- `feature-dev` — dev guiada de features
- `skill-creator` — criar skills customizadas
- `security-guidance` — hook de security em edits
- `hookify` — hooks custom via `.local.md`
- `claude-code-setup` — automation-recommender

Configs:
- `language`: Portugues Brasileiro
- `effortLevel`: high
- `defaultMode`: acceptEdits
- `statusLine`: script em `~/.claude/statusline.sh`
- `hooks.PreToolUse`: guardian.py em Write/Edit/MultiEdit

### `~/.claude/settings.local.json` (local, não-versionado)

Permissoes de uso diario: git operations (add, commit, push, log, rm, config), utilities (cp, rm, rsync, mkdir), Luna venvs (pip, python).

## Workflow tipico

### Projeto com expertise acumulada (Luna, Nyx-Code, ouroboros)

Primeira vez:
```bash
cd ~/Desenvolvimento/Nyx-Code
sprint bootstrap
# cole o conteudo copiado na sessão viva que acumulou expertise
# resultado: VALIDATOR_BRIEF.md rico ja na primeira leitura
```

### Projeto novo (qualquer repo git)

```bash
cd ~/Desenvolvimento/novo-projeto
sprint val
# primeira execução: subagente auto-explora e cria VALIDATOR_BRIEF.md
# subsequentes: valida e enriquece BRIEF
```

### Ciclo completo de sprint

```bash
cd ~/Desenvolvimento/Nyx-Code
sprint ciclo "adicionar suporte a novo tema"
# 1. planejador gera spec
# 2. voce aprova
# 3. executor implementa
# 4. voce confirma proof-of-work
# 5. validador verifica
# 6. se aprovado: sugere commit
```

### Validação sem ciclo

```bash
# depois de implementar uma sprint manualmente:
sprint val
# ou diretamente:
cca "/validar-sprint"
```

## Health check

```bash
sprint doctor
```

Verifica:
- 3 agentes em `~/.claude/agents/`
- 4 commands em `~/.claude/commands/`
- `guardian.py` e `emoji_guardian.py` ativos
- `cca` e `santuario` carregados
- `settings.json` valido (plugins, perms, hooks)
- Templates em `~/.claude/templates/`

## Arquivos de memoria

`~/.claude/projects/-home-andrefarias/memory/`:

- `MEMORY.md` — indice
- `user_santuario_function.md`
- `user_sistema.md`
- `feedback_acentuacao.md`
- `feedback_modelo_luna.md`
- `feedback_cca_wrapper.md`
- `project_icones_dracula_fix.md`
- `project_validador_universal.md`
- `reference_dracula_icones_tema.md`

## Docs adicionais

- `~/.claude/PLUGINS.md` — referencia dos 12 plugins
- `~/.claude/SETTINGS.md` — organizacao de `settings.json` vs local
- `~/.claude/plans/faz-assim-me-d-greedy-cerf.md` — plano original deste setup

## Manutencao

### Adicionar permissao apos prompt repetido

Editar `~/.claude/settings.local.json`, adicionar regra na lista `permissions.allow`.

### Desativar hook guardian temporariamente

Editar `~/.claude/settings.json`, remover o bloco `hooks`. Salvar e reabrir sessão.

### Instalar plugin novo

Usar o comando `/plugin install <nome>` na sessão ou adicionar em `~/.claude/settings.json` em `enabledPlugins`.

### Atualizar VALIDATOR_BRIEF.md manualmente

```bash
sprint brief-edit
```

Ou editar diretamente o arquivo na raiz do repo. Cada sessão `/validar-sprint` pode enriquecer o BRIEF automaticamente com padroes novos.

### Restaurar settings de backup

Backups em `~/.claude/settings.json.bak-YYYYMMDD` e `~/.claude/settings.local.json.bak-YYYYMMDD`. Para restaurar:

```bash
cp ~/.claude/settings.json.bak-20260420 ~/.claude/settings.json
```

---

*"Memoria em disco, não em contexto. Universal, não por-projeto. cca, não CLI direto."*
