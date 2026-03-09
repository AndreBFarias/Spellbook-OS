# Claude Quota System

Sistema de controle de uso do Claude CLI com quota semanal e guard fiscal.

##  Estrutura

```
claude/
├── .claude_guard_config        # Configuração de limites
├── .claude_quota               # Estado atual da quota
├── aliases_claude.zsh          # Aliases (claude-safe, cq, etc)
├── claude_guard.sh             # Guard fiscal
├── claude_quota_manager.sh     # Gerenciador de quota
├── CLAUDE.md                   # Contexto para IA
├── CLAUDE_QUOTA_SYSTEM.md      # Documentação do sistema
├── GUIA_RAPIDO_QUOTA.md        # Guia rápido
├── INSTALL_QUOTA_SYSTEM.sh     # Script de instalação
└── README_QUOTA.txt            # README original
```

##  Comandos

```bash
cca "pergunta"           # Claude CLI com quota tracking
claude-quota  ou  cq     #  Ver quota semanal
claude-estimate arquivo  # Estimar custo de arquivo
claude-peek arquivo      # Preview sem consumir quota
claude-report            # Relatório semanal
claude-init              # Inicializar sistema
claude-force "..."       # Forçar (ignora limites)
```

##  Configuração

### Limites de Quota (`claude_quota_manager.sh`)
```bash
WEEKLY_LIMIT=500000        # 500k tokens/semana
WARNING_THRESHOLD=400000   # Aviso em 80%
CRITICAL_THRESHOLD=450000  # Crítico em 90%
```

### Limites de Arquivo (`.claude_guard_config`)
```bash
MAX_FILE_SIZE_KB=100       # Bloqueia arquivos > 100KB
WARN_FILE_SIZE_KB=50       # Avisa arquivos > 50KB
MAX_CONTEXT_FILES=5        # Max arquivos no contexto
MAX_LINE_COUNT=2000        # Max linhas por arquivo
```

##  Personalização

### Alterar Quota Semanal
```bash
# Editar claude_quota_manager.sh
WEEKLY_LIMIT=1000000  # 1M tokens
```

### Alterar Limites de Arquivo
```bash
# Editar .claude_guard_config
MAX_FILE_SIZE_KB=200  # Permite até 200KB
```

### API Key
```bash
# Em ~/.config/zsh/.zsh_secrets
export ANTHROPIC_API_KEY="sk-ant-..."
```

##  Como Funciona

1. **Before Request:** `claude_guard.sh` verifica quota e tamanho de arquivos
2. **Execute:** Roda o Claude CLI
3. **After Request:** Registra tokens usados (estimativa baseada em tempo)
4. **Weekly Reset:** Auto-reseta após 7 dias

##  Instalação

```bash
# Já instalado! Mas para reinstalar:
bash INSTALL_QUOTA_SYSTEM.sh
```

##  Troubleshooting

### Quota não reseta
```bash
claude-quota-reset
```

### Guard muito restritivo
```bash
# Usa CLAUDE_FORCE=1 para bypass
CLAUDE_FORCE=1 claude "sua pergunta"
# Ou
claude-force "sua pergunta"
```

### Ver estado da quota
```bash
cat .claude_quota
```

##  Docs Relacionadas

- **Master:** `~/.config/zsh/AI_TOOLS_MASTER.md`
- **Aider:** `~/.config/zsh/aider/README.md`
- **Gemini:** `~/.config/zsh/gemini/README.md`
