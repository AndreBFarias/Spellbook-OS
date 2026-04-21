<div align="center">

[![opensource](https://badges.frapsoft.com/os/v1/open-source.png?v=103)](#)
[![Licença](https://img.shields.io/badge/licença-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Zsh](https://img.shields.io/badge/shell-zsh-green.svg)](https://www.zsh.org/)
[![Oh My Zsh](https://img.shields.io/badge/Oh%20My%20Zsh-compatible-blue.svg)](https://ohmyz.sh/)
[![Estrelas](https://img.shields.io/github/stars/[REDACTED]/spellbook-OS.svg?style=social)](https://github.com/[REDACTED]/spellbook-OS/stargazers)

<img src="assets/spellbook_os.png" width="120" alt="Spellbook OS">

<h1>Spellbook OS</h1>

</div>

---

Configuração zsh modular e portável. 23 módulos de funções, 9 scripts Python, menu FZF interativo para projetos dbt/BigQuery, controle automático de identidade git e integração com Oh My Zsh. Instalável em qualquer máquina Linux com um único comando.

---

### Módulos

| Módulo | Descrição |
|--------|-----------|
| `functions/mec.zsh` | Menu FZF completo para projetos dbt/BigQuery (29 operações) |
| `functions/git-contexto.zsh` | Identidade git automática por diretório |
| `functions/conjurar.zsh` | Menu FZF global de ferramentas |
| `functions/diagnostico.zsh` | Dossiê completo de projeto — git, árvore, conteúdo, imagens, PDFs, planilhas com senha |
| `functions/sync.zsh` | Sincronização de repositórios com backup |
| `functions/controle-de-bordo.zsh` | Gestão de projetos e tarefas |
| `functions/projeto.zsh` | Criação e gestão de projetos |
| `functions/pulso.zsh` | Monitor de sistema em tempo real |
| `functions/limpeza.zsh` | Limpeza de ambiente e temporários |
| `functions/encoding.zsh` | Detecção e conversão de encoding (UTF-8, CRLF) |
| `functions/fontes.zsh` | Instalação e verificação de fontes de compatibilidade |
| `functions/restaurar.zsh` | Backup e restauração de sistema via manifesto |
| `functions/sistema.zsh` | Captura de manifesto e diagnóstico do sistema |
| `functions/_helpers.zsh` | Paleta Dracula + utilitários base |
| `kca/` | Wrapper CLI auxiliar |
| `scripts/` | Scripts Python auxiliares (dbt, migração, análise) |

---

### Instalação

#### Bootstrap completo (nova máquina)

```bash
git clone https://github.com/[REDACTED]/spellbook-OS ~/Desenvolvimento/spellbook-OS
bash ~/Desenvolvimento/spellbook-OS/install.sh
```

O `install.sh` instala dependências, Oh My Zsh com plugins, fontes de compatibilidade, ferramentas de encoding, sincroniza os arquivos para `~/.config/zsh/` e guia a configuração via TUI interativa com navegação Voltar entre etapas e detecção automática de valores existentes.

#### Atualizar (já instalado)

```bash
cd ~/Desenvolvimento/spellbook-OS && git pull && ./install.sh --update
```

O modo `--update` preserva `config.local.zsh` e `.zsh_secrets` existentes.

---

### Requisitos

**Sistema (instalados automaticamente pelo install.sh):**

```
zsh  git  fzf  jq  pv  rsync  tree  python3  pip3  whiptail
```

**Python (via requirements.txt):**

```
pandas >= 3.0
openpyxl >= 3.1
tabulate >= 0.9
pyarrow >= 14.0
pymupdf >= 1.23
msoffcrypto-tool >= 5.0
```

---

### Scripts Python

| Script | Uso |
|--------|-----|
| `mec-dbt-results.py` | Parser de `run_results.json` do dbt — exibe resultado colorido no terminal |
| `mec-migrar-censo.py` | Migração semi-automatizada de tabelas INEP no BigQuery (scan + apply) |
| `universal-sanitizer.py` | Sanitizador de rastros externos em arquivos staged antes do commit |
| `analisador-dados.py` | Analisa CSV, Excel, JSON, Parquet, PDF e imagens — gera markdown compatível com GitHub e Obsidian |

Uso: `python3 ~/.config/zsh/scripts/<script>.py --help`

---

### Configuração pós-instalação

Editar os arquivos gerados pelo installer:

| Arquivo | Conteúdo |
|---------|----------|
| `~/.config/zsh/config.local.zsh` | Caminhos locais, identidades git, `BQ_KEYFILE_PATH` |
| `~/.config/zsh/.zsh_secrets` | `GITHUB_TOKEN`, `GEMINI_API_KEY` |
| `~/.config/zsh/profiles.yml` | Configuração dbt BigQuery |

Os templates estão em `*.template` para referência.

---

### Estrutura

```
spellbook-OS/
├── install.sh                  # Instalador com TUI whiptail
├── requirements.txt            # Dependências Python
├── .zshrc                      # Entry point do zsh
├── env.zsh                     # Ambiente + Oh My Zsh
├── aliases.zsh                 # Aliases gerais
├── functions.zsh               # Loader de módulos
├── config.local.zsh.template   # Template: vars por máquina
├── .zsh_secrets.template       # Template: tokens e API keys
├── profiles.yml.template       # Template: dbt BigQuery
├── assets/
│   └── spellbook_os.png
├── functions/                  # 23 módulos zsh
│   ├── _helpers.zsh
│   ├── mec.zsh
│   ├── git-contexto.zsh
│   └── ...
└── scripts/                    # Scripts Python
    ├── mec-dbt-results.py
    ├── mec-migrar-censo.py
    └── universal-sanitizer.py
```

---

### Licença

GPLv3 — Veja [LICENSE](LICENSE) para detalhes.
