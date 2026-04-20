# Settings Claude Code — organização

> Referência do que vai em cada arquivo de configuração.

## Arquivos

### `~/.claude/settings.json` (global, versionável)

**O que fica aqui:** configurações e permissões **transversais** que se aplicam a todos os projetos.

Chaves:
- `permissions.allow[]` — regras de Bash/Read/Write genéricas (`find`, `ls`, `grep`, `cat`, `chmod`, `timeout`, `python3`, `./install.sh`, gerenciamento do próprio Claude)
- `permissions.defaultMode` — `"acceptEdits"` (auto-aceita edições de arquivos)
- `enabledPlugins` — quais plugins estão ativos
- `language` — `"Português Brasileiro"`
- `effortLevel` — `"high"` (Opus default)
- `skipDangerousModePermissionPrompt` — `true`

### `~/.claude/settings.local.json` (local, não versionável)

**O que fica aqui:** permissões de ferramentas específicas do dia-a-dia, que podem variar entre máquinas ou evoluir rápido.

Chaves:
- `permissions.allow[]` — operações git comuns (`git add`, `git commit`, `git push`, `git log`, etc.), `rsync`, `cp`, `rm`, `mkdir`, utilities pontuais

### `~/.claude/CLAUDE.md` (symlink)

Symlink para `~/.config/zsh/AI.md`. Protocolo universal de instruções (PT-BR, anonimato, git, etc.). Carregado em toda sessão Claude.

## Regras de higiene

1. **Nunca colocar regras órfãs de scripts `/tmp/*`** em nenhum settings. Esses arquivos somem, a regra vira lixo.
2. **Nunca colocar regras com sintaxe quebrada** (`if [...]`, `then echo`, `else`, `fi` como regras separadas). Vieram de aprovações acidentais de blocos shell; não são regras válidas.
3. **Path absoluto só quando necessário** — prefira `Bash(python3:*)` a `Bash(/home/X/projeto/venv/bin/python:*)`, salvo quando o venv é chamado por Claude com frequência.
4. **Duplicatas entre os dois arquivos** → consolidar em `settings.local.json` (sempre ganha no merge).
5. **Ao adicionar regra nova temporária**, remover quando não precisar mais. Revisar semestralmente.

## Troubleshooting

- **Permissões demais são pedidas:** `settings.local.json` provavelmente foi limpo demais. Adicionar regra quando aparecer.
- **Permissão concedida mas prompt continua aparecendo:** conflito de sintaxe de matcher (`*` vs `...`). Ver docs do Claude Code.
- **Plugin desabilitado acidentalmente:** conferir `enabledPlugins` em `settings.json`.
