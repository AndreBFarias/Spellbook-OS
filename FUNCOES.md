# Funções do Spellbook-OS

Gerado automaticamente por `scripts/gerar-readme-funcoes.py` a partir
dos metadados `# Propósito:` / `# Uso:` / `# Flags:` em `functions/*.zsh`.

## Índice

- [Encoding e normalização](#encoding-e-normalização) — 6 função(ões)
- [Fontes](#fontes) — 5 função(ões)
- [Git](#git) — 7 função(ões)
- [Hooks e aplicações](#hooks-e-aplicações) — 3 função(ões)
- [MEC](#mec) — 1 função(ões)
- [Meta (descoberta)](#meta-descoberta) — 3 função(ões)
- [Navegação e exploração](#navegação-e-exploração) — 6 função(ões)
- [Observabilidade](#observabilidade) — 3 função(ões)
- [Prompt-Hint](#prompt-hint) — 1 função(ões)
- [Setup de projeto](#setup-de-projeto) — 2 função(ões)
- [Sistema (Pop!_OS)](#sistema-pop!_os) — 15 função(ões)
- [Spellbook Sync](#spellbook-sync) — 4 função(ões)
- [Spicetify](#spicetify) — 3 função(ões)
- [Utilidades](#utilidades) — 3 função(ões)
- [Vault Obsidian (Controle de Bordo)](#vault-obsidian-controle-de-bordo) — 12 função(ões)

## Encoding e normalização

| Função | Propósito | Uso |
|---|---|---|
| `enc_converter` | Converter encoding de arquivo (auto-detecta origem se omitida) | `enc_converter <arquivo> [destino] [origem] [--no-backup]` |
| `enc_detectar` | Detectar encoding, BOM e line ending de arquivo/diretório | `enc_detectar <alvo>` |
| `enc_fixar_bom` | Remover BOM de arquivos UTF-8 | `enc_fixar_bom <alvo> [--no-backup]` |
| `enc_fixar_crlf` | Converter line endings (CRLF<->LF) | `enc_fixar_crlf <alvo> [--para-windows] [--no-backup]` |
| `enc_fixar_python` | Normalizar scripts Python (shebang, coding, BOM, CRLF, chmod) | `enc_fixar_python <alvo> [--no-backup]` |
| `enc_lote` | Conversão em lote (encoding + BOM + CRLF + scripts Python) | `enc_lote <diretório> [--perfil windows-para-linux\|linux-para-windows] [--dry-run] [--no-backup]` |

### Flags detalhadas

**`enc_converter`**

- `--no-backup` — Não cria cópia .bak antes de converter
- `<arquivo>` — _files
- `[destino]` — __enc_encodings
- `[origem]` — __enc_encodings

**`enc_fixar_bom`**

- `--no-backup` — Não cria .bak antes de remover BOM
- `<alvo>` — _files

**`enc_fixar_crlf`**

- `--para-windows` — Converte LF->CRLF (padrão é CRLF->LF)
- `--no-backup` — Não cria .bak antes de converter
- `<alvo>` — _files

**`enc_fixar_python`**

- `--no-backup` — Não cria .bak antes de editar
- `<alvo>` — _files

**`enc_lote`**

- `--perfil` — Perfil de conversão (default: windows-para-linux)
- `--dry-run` — Apenas lista, não altera nada
- `--no-backup` — Não cria .bak antes de converter
- `<diretório>` — _path_files -/

## Fontes

| Função | Propósito | Uso |
|---|---|---|
| `fontes_importar_windows` | Copiar fontes proprietárias da partição Windows para ~/.local/share/fonts | `fontes_importar_windows [raiz_windows]` |
| `fontes_instalar` | Instalar fontes de compatibilidade Win/Mac (MS Core, Liberation, Noto, Inter) | `fontes_instalar` |
| `fontes_listar` | Listar todas as famílias de fontes instaladas no sistema | `fontes_listar` |
| `fontes_mapa` | Exibir mapeamento Win/Mac -> substituto Linux -> fallback | `fontes_mapa` |
| `fontes_verificar` | Verificar cobertura de fontes instaladas e fallback | `fontes_verificar` |

## Git

| Função | Propósito | Uso |
|---|---|---|
| `ga` | Git add com sanitizer automático e ruff (lint + format) para Python | `ga [arquivos]` |
| `git_info` | Exibir identidade git do repositorio atual (nome, email, branch, remote) | `git_info` |
| `grecuperar` | Investigar branch ou commit para recuperacao (log, diff, sugestoes) | `grecuperar [branch_ou_commit]` |
| `grestore` | Reset hard para um ponto do reflog (com confirmacao e preview) | `grestore <ref>` |
| `gsos` | Painel de emergencia git (status, branches, reflog, stashes) | `gsos` |
| `sincronizar_repositorio` | Sincronizar repositorios selecionados via FZF (com backup de alteracoes) | `sincronizar_repositorio` |
| `sincronizar_todos_os_repositorios` | Sincronizar TODOS os repositorios com o remoto (com backup) | `sincronizar_todos_os_repositorios` |

## Hooks e aplicações

| Função | Propósito | Uso |
|---|---|---|
| `aplicar_hooks_globais` | Copiar hooks git (pre-commit + commit-msg + pre-push + _lib.sh) para todos os repos | `aplicar_hooks_globais [diretorio_base]` |
| `conectar_andre` | Sincronizar Beholder com o Nitro5 via rsync | `conectar_andre` |
| `conectar_maria` | Sincronizar Beholder com a máquina da Maria via rsync | `conectar_maria` |

## MEC

| Função | Propósito | Uso |
|---|---|---|
| `conjurar_mec` | Interface CLI completa para o projeto MEC (dbt, git, push, ambiente) | `conjurar_mec` |

## Meta (descoberta)

| Função | Propósito | Uso |
|---|---|---|
| `conjurar` | Menu FZF interativo de aliases e funções do Spellbook | `conjurar [--help] [--list] [--search <termo>] [--recent]` |
| `recompilar_completions` | Regera arquivos _<função> em completions/ a partir dos metadados | `recompilar_completions [--verbose] [--func NOME]` |
| `validar_completions` | Lista funções sem metadados de completion (# Propósito + # Uso) | `validar_completions` |

### Flags detalhadas

**`conjurar`**

- `--help` — Exibe ajuda
- `--list` — Listagem sem FZF
- `--search` — Abre menu com filtro inicial
- `--recent` — Últimos 5 comandos executados

**`recompilar_completions`**

- `--verbose` — Mostra progresso detalhado
- `--func` — Regera apenas uma função específica

## Navegação e exploração

| Função | Propósito | Uso |
|---|---|---|
| `auditar_repos` | Escanear todos os repos por violacoes de anonimato (co-autoria, IA, emojis) | `auditar_repos [diretorio_base]` |
| `buscar` | Buscar arquivos por padrao de nome em um diretório | `buscar <padrao> <pasta>` |
| `diagnostico_projeto` | Gerar dossiê completo de um projeto (ambiente, git, árvore, conteúdo) | `diagnostico_projeto <profundidade> [--max-linhas N]` |
| `ir` | Navegacao rapida entre projetos com FZF (preview de git log e ls) | `ir` |
| `reconstruir_diagnostico` | Reconstruir arquivos a partir de um diagnostico .md | `reconstruir_diagnostico <arquivo.md>` |
| `tree` | Arvore de diretórios com filtros e exportacao para arquivo | `tree <profundidade> [diretório]` |

## Observabilidade

| Função | Propósito | Uso |
|---|---|---|
| `pulso` | Saude rapida do sistema (CPU, RAM, Disco, GPU, Uptime) | `pulso` |
| `purgar` | Limpar caches do sistema (pip, npm, apt, journalctl, pycache) | `purgar` |
| `repos` | Status git de todos os repositorios (branch, alteracoes, sync) | `repos` |

## Prompt-Hint

| Função | Propósito | Uso |
|---|---|---|
| `prompt_hint_refresh` | Recarrega cache de hints da RPROMPT (útil após editar uma função) | `prompt_hint_refresh` |

## Setup de projeto

| Função | Propósito | Uso |
|---|---|---|
| `levitar` | Abrir diretório no Antigravity (file manager) | `levitar [caminho]` |
| `santuario` | Setup completo de projeto (cd, branch, venv, deps, git context) | `santuario <Projeto> [Branch] [--sync] [--vit]` |

### Flags detalhadas

**`santuario`**

- `--sync` — Sincroniza dependências via pip install -r
- `--vit` — Usa subdiretório VitoriaMariaDB/
- `<Projeto>` — __santuario_pastas_dev
- `[Branch]` — __santuario_branches_git

## Sistema (Pop!_OS)

| Função | Propósito | Uso |
|---|---|---|
| `arquivos_pacote` | Listar todos os arquivos de um pacote instalado | `arquivos_pacote <pacote>` |
| `diagnostico_pop` | Gerar diagnostico completo do Pop!_OS (kernel, disco, processos, erros) | `diagnostico_pop <profundidade>` |
| `prompt_context` | Exibir contexto de usuário no prompt (SSH e usuários não-padrão) | `prompt_context` |
| `quem_instalou` | Descobrir qual pacote instalou um arquivo | `quem_instalou <caminho>` |
| `rebuild_dracula_theme` | Reconstruir Dracula_OS-Theme do zero (build + install --user) | `rebuild_dracula_theme [--activate]` |
| `reinstalar` | Reinstalar um pacote via apt | `reinstalar <pacote>` |
| `reparo_pop` | Reparo automático do sistema (deps, pacotes, limpeza, atualização) | `reparo_pop` |
| `servico_iniciar` | Iniciar um servico systemd | `servico_iniciar <servico>` |
| `servico_parar` | Parar um servico systemd | `servico_parar <servico>` |
| `servico_reiniciar` | Reiniciar um servico systemd | `servico_reiniciar <servico>` |
| `servico_status` | Status de um servico systemd | `servico_status <servico>` |
| `sistema_capturar` | Capturar manifesto completo do sistema (APT, Flatpak, SSH, VSCode, git, temas) | `sistema_capturar [--saida <arquivo>]` |
| `sistema_diff` | Comparar manifesto salvo com estado atual do sistema | `sistema_diff [manifesto.json]` |
| `sistema_manifesto` | Gerenciar manifestos salvos (exibir ou listar) | `sistema_manifesto [--listar]` |
| `sistema_restaurar` | Restaurar sistema a partir de manifesto salvo por sistema_capturar | `sistema_restaurar <manifesto.json> [categorias] [--dry-run]` |

### Flags detalhadas

**`sistema_capturar`**

- `--saida` — Caminho do manifesto de saída (default: $HOME/.sistema/manifestos/AAAA-MM-DD.json)

**`sistema_manifesto`**

- `--listar` — Lista todos os manifestos ao invés do último

**`sistema_restaurar`**

- `--dry-run` — Não altera nada, apenas lista o que seria feito
- `<manifesto.json>` — _files -g "*.json"

## Spellbook Sync

| Função | Propósito | Uso |
|---|---|---|
| `spellbook_sync_force` | Forçar sync do Spellbook-OS sobrescrevendo local ou remoto | `spellbook_sync_force [--local\|--remote]` |
| `spellbook_sync_pull` | Pull sincronizado do Spellbook-OS (commit local + fetch + merge com tratamento de conflito) | `spellbook_sync_pull` |
| `spellbook_sync_push` | Push em background do Spellbook-OS (auto-commit local + push não-bloqueante) | `spellbook_sync_push` |
| `spellbook_sync_status` | Exibir status do sync do Spellbook-OS (branch, ahead/behind, pendentes) | `spellbook_sync_status` |

### Flags detalhadas

**`spellbook_sync_force`**

- `--local` — Push força (sobrescreve remoto com local)
- `--remote` — Pull força (sobrescreve local com remoto)

## Spicetify

| Função | Propósito | Uso |
|---|---|---|
| `spicetify_instalar` | Instalar Spicetify via script de setup | `spicetify_instalar` |
| `spicetify_reparar` | Reparar Spicetify (re-aplicar tema, extensions, custom apps, sidebar) | `spicetify_reparar` |
| `spicetify_status` | Exibir status do Spicetify (tema, esquema, extensions, custom apps) | `spicetify_status` |

## Utilidades

| Função | Propósito | Uso |
|---|---|---|
| `extrair` | Extrair arquivos compactados (tar, zip, rar, 7z, gz, xz, zst) | `extrair <arquivo>` |
| `limpar_pastas_vazias` | Remover pastas vazias dos projetos (--dry-run para preview) | `limpar_pastas_vazias [--dry-run]` |
| `limpeza_interativa` | Limpeza interativa do Controle de Bordo com FZF | `limpeza_interativa` |

## Vault Obsidian (Controle de Bordo)

| Função | Propósito | Uso |
|---|---|---|
| `cdb` | Navegar para o diretório raiz do vault Obsidian | `cdb` |
| `sincronizar_controle_de_bordo` | Sincronizar documentação dos repos em $DEV_DIR para o vault Obsidian | `sincronizar_controle_de_bordo [--auto] [--dry-run] [--stats] [--cleanup] [--check-size]` |
| `vault_buscar` | Buscar notas no vault por título e conteúdo | `vault_buscar <termo>` |
| `vbackups` | Listar backups disponíveis do vault | `vbackups [filtro]` |
| `vhelp` | Exibir ajuda do Controle de Bordo (comandos e aliases) | `vhelp` |
| `vinbox` | Listar e processar arquivos do Inbox do vault | `vinbox` |
| `vnova` | Criar nova nota no vault a partir de template por tipo | `vnova <tipo> [nome]` |
| `vopen` | Abrir o vault Obsidian pelo URI | `vopen` |
| `vrestore` | Restaurar arquivo do vault a partir de backup | `vrestore <caminho>` |
| `vsize` | Exibir tamanho do vault por pasta | `vsize` |
| `vstats` | Estatísticas do vault (notas, tamanho, hubs, responsáveis) | `vstats` |
| `vtask` | Criar/editar nota quinzenal de tarefas para um cliente | `vtask <cliente> [quinzena]` |

### Flags detalhadas

**`sincronizar_controle_de_bordo`**

- `--auto` — Executa sem pedir confirmação
- `--dry-run` — Lista mudanças sem copiar
- `--stats` — Exibe estatísticas do rsync
- `--cleanup` — Remove caches Python antes do sync
- `--check-size` — Aborta se vault > 1GB

---

*Para regenerar: `python3 scripts/gerar-readme-funcoes.py`*
