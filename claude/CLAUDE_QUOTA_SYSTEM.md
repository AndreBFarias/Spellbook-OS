# Sistema de Controle de Quota do Claude

## Problema

Claude Pro tem limite semanal de uso. Com o CLI do Claude Code, é fácil estorar esse limite rapidamente porque:

1. **Leituras de arquivos grandes** consomem muitos tokens
2. **Contexto acumulado** cresce a cada interação
3. **Respostas longas** também consomem da quota
4. **Sem feedback visual** de quanto foi usado

## Solução: Throttling Inteligente

### Arquitetura do Sistema

```
User → claude-safe → [Pre-Check] → [Guard] → Claude API → [Post-Track]
                          ↓            ↓                        ↓
                      Quota OK?    File OK?              Add tokens
                          ↓            ↓                        ↓
                      BLOCK/WARN   BLOCK/WARN            Update quota
```

### Componentes

#### 1. `claude_quota_manager.sh`
**Função:** Rastrear uso semanal de tokens

**Arquivo de estado:** `~/.config/zsh/.claude_quota`
```
week_start=2026-01-20
tokens_used=45000
requests_count=23
```

**Comandos:**
```bash
bash claude_quota_manager.sh init          # Inicializar
bash claude_quota_manager.sh check         # Ver status
bash claude_quota_manager.sh add 5000      # Adicionar 5000 tokens
bash claude_quota_manager.sh pre-check     # Verificar antes de request
bash claude_quota_manager.sh reset         # Resetar quota
```

**Limites:**
- `WEEKLY_LIMIT`: 500,000 tokens
- `WARNING_THRESHOLD`: 400,000 (80%)
- `CRITICAL_THRESHOLD`: 450,000 (90%)

#### 2. `claude_guard.sh`
**Função:** Bloquear requests perigosos ANTES de executar

**Arquivo de config:** `~/.config/zsh/.claude_guard_config`
```bash
MAX_FILE_SIZE_KB=100          # Bloqueio: arquivos > 100KB
MAX_CONTEXT_FILES=5           # Bloqueio: > 5 arquivos no contexto
MAX_LINE_COUNT=2000           # Bloqueio: arquivos > 2000 linhas
BLOCK_LARGE_READS=true        # Ativar bloqueio
SUGGEST_ALTERNATIVES=true     # Sugerir alternativas
```

**Comandos:**
```bash
bash claude_guard.sh init                    # Inicializar
bash claude_guard.sh check-file arquivo.py   # Verificar arquivo
bash claude_guard.sh check-context 10        # Verificar contexto
bash claude_guard.sh before                  # Check pre-request
bash claude_guard.sh after 5000              # Track post-request
bash claude_guard.sh analyze "cat file.py"   # Analisar comando
```

#### 3. `aliases_claude.zsh`
**Função:** Aliases user-friendly

**Comandos principais:**

```bash
# Uso diário
claude-safe <comando>          # Wrapper seguro (recomendado)
claude-quota                   # Ver uso semanal
claude-estimate arquivo.py     # Estimar custo ANTES de ler
claude-peek arquivo.py         # Preview (50 linhas início/fim)
claude-report                  # Relatório completo + dicas

# Avançado
claude-force <comando>         # Ignorar limites (emergência)
claude-quota-reset             # Resetar quota manualmente
```

**Alias automático:**
```bash
alias claude='claude-safe'     # Redireciona claude para wrapper
```

---

## Instalação

### 1. Adicionar ao `.zshrc`

```bash
# Adicionar no final de ~/.config/zsh/.zshrc
if [ -f "$ZDOTDIR/aliases_claude.zsh" ]; then
    source "$ZDOTDIR/aliases_claude.zsh"
fi
```

### 2. Tornar scripts executáveis

```bash
chmod +x ~/.config/zsh/claude_quota_manager.sh
chmod +x ~/.config/zsh/claude_guard.sh
```

### 3. Inicializar sistema

```bash
source ~/.config/zsh/.zshrc
claude-init
```

---

## Uso Diário

### Exemplo 1: Verificar quota antes de trabalhar

```bash
$ claude-quota
=== CLAUDE QUOTA STATUS ===
Tokens usados: 45000 / 500000 (9%)
Tokens restantes: 455000
Requests esta semana: 23
Week start: 2026-01-20

 Uso normal. Ainda tem 455000 tokens.
```

### Exemplo 2: Estimar custo de arquivo grande

```bash
$ claude-estimate Luna/src/soul/response_pipeline.py
  AVISO: Arquivo grande detectado
   Arquivo: Luna/src/soul/response_pipeline.py (87KB)
   Isso consumirá ~348 tokens estimados
   Continuar? (y/n)
```

### Exemplo 3: Preview sem consumir quota

```bash
$ claude-peek Luna/config.py
=== PREVIEW: Luna/config.py ===
Tamanho: 12K | Linhas: 350

--- INÍCIO (50 linhas) ---
import os
from pathlib import Path
...

--- FIM (50 linhas) ---
...
OLLAMA_KEEP_ALIVE = "5m"

[DICA] Use grep, sed ou awk para análises específicas sem consumir quota
```

### Exemplo 4: Arquivo bloqueado (muito grande)

```bash
$ claude-safe "read Luna/logs/luna_20260120.log"

 BLOQUEADO: Arquivo muito grande!
   Arquivo: Luna/logs/luna_20260120.log
   Tamanho: 250KB (limite: 100KB)
   Linhas: 5000 (limite: 2000)

ALTERNATIVAS:
1. Leia seções específicas: head -n 100 Luna/logs/luna_20260120.log
2. Busque padrões: grep 'ERROR' Luna/logs/luna_20260120.log
3. Resuma com: cat file | head -50 && echo '...' && tail -50
4. Force (não recomendado): CLAUDE_FORCE=1 claude ...
```

### Exemplo 5: Zona crítica (90% do limite)

```bash
$ claude-safe "help me debug this"

  ZONA CRITICA: 50000 tokens restantes
   Deseja continuar? (y/n)
n

[Request cancelado pelo usuário]
```

---

## Estratégias de Economia

### 1. Use ferramentas Unix ANTES de perguntar ao Claude

```bash
#  ERRADO (consome quota)
claude "what functions are in core.py?"

#  CORRETO (zero quota)
grep "^def " src/core.py
```

### 2. Leia arquivos em seções

```bash
#  ERRADO (arquivo inteiro, 2000 linhas)
claude "read entire_file.py and explain"

#  CORRETO (apenas função específica)
sed -n '100,150p' entire_file.py | claude "explain this function"
```

### 3. Use --skip-context quando possível

```bash
#  ERRADO (carrega todo histórico da sessão)
claude "quick question about syntax"

#  CORRETO (sem contexto desnecessário)
claude --skip-context "quick question about syntax"
```

### 4. Resuma contextos grandes com modelos locais

```bash
# Use Ollama (local, gratuito) para resumir ANTES de mandar pro Claude
ollama run llama3.2:3b "summarize this: $(cat large_file.py)" > summary.txt
claude "based on this summary: $(cat summary.txt), what should I do?"
```

### 5. Agrupe perguntas

```bash
#  ERRADO (3 requests separados)
claude "what is X?"
claude "what is Y?"
claude "what is Z?"

#  CORRETO (1 request)
claude "explain X, Y, and Z"
```

---

## Monitoramento

### Ver relatório semanal

```bash
$ claude-report
=== RELATÓRIO SEMANAL DE USO ===
Tokens usados: 345000 / 500000 (69%)
Tokens restantes: 155000
Requests esta semana: 87
Week start: 2026-01-20

  AVISO: 69% do limite usado!
    Cuidado com contextos grandes.

=== DICAS PARA ECONOMIZAR ===
1. Use grep/sed/awk para buscas rápidas
2. Leia arquivos em seções (head/tail)
3. Use --skip-context quando não precisar de histórico
4. Resuma contextos grandes antes de perguntar
5. Evite ler arquivos > 100KB diretamente
```

### Reset manual (nova semana)

```bash
$ claude-quota-reset
  Tem certeza que quer resetar a quota? (y/n)
y
Quota resetada.
```

**OBS:** O sistema reseta automaticamente toda segunda-feira.

---

## Configuração Avançada

### Ajustar limites

Edite: `~/.config/zsh/.claude_guard_config`

```bash
# Mais restritivo (economizar mais)
MAX_FILE_SIZE_KB=50
MAX_CONTEXT_FILES=3
MAX_LINE_COUNT=1000

# Menos restritivo (mais liberdade)
MAX_FILE_SIZE_KB=200
MAX_CONTEXT_FILES=10
MAX_LINE_COUNT=5000

# Desabilitar bloqueios (não recomendado)
BLOCK_LARGE_READS=false
BLOCK_MASSIVE_CONTEXT=false
```

### Ajustar quota semanal

Edite: `~/.config/zsh/claude_quota_manager.sh`

```bash
# Linha 3-5
WEEKLY_LIMIT=500000           # Total semanal
WARNING_THRESHOLD=400000      # 80% aviso
CRITICAL_THRESHOLD=450000     # 90% bloqueio condicional
```

---

## Troubleshooting

### Quota não atualiza

```bash
rm ~/.config/zsh/.claude_quota
claude-init
```

### Guard não bloqueia arquivos grandes

```bash
# Verifique se BLOCK_LARGE_READS está true
grep BLOCK_LARGE_READS ~/.config/zsh/.claude_guard_config

# Ou force reload
bash ~/.config/zsh/claude_guard.sh init
```

### Alias não funciona

```bash
# Verifique se foi carregado
type claude-safe

# Se não aparecer, recarregue .zshrc
source ~/.config/zsh/.zshrc
```

---

## Métricas Reais

### Custo aproximado por operação

| Operação | Tokens (estimado) |
|----------|-------------------|
| Read 10KB file | ~40 tokens |
| Read 100KB file | ~400 tokens |
| Read 1MB file | ~4000 tokens |
| Simple question | ~100-500 tokens |
| Complex explanation | ~1000-3000 tokens |
| Code generation (50 lines) | ~500-1000 tokens |
| Full conversation turn | ~1000-5000 tokens |

### Exemplo de consumo semanal

```
Dia 1: 50k tokens (setup projeto)
Dia 2: 80k tokens (debugging pesado)
Dia 3: 40k tokens (features simples)
Dia 4: 60k tokens (refatoração)
Dia 5: 70k tokens (documentação)
Dia 6: 50k tokens (testes)
Dia 7: 30k tokens (review)
---
TOTAL: 380k / 500k (76% usado)
```

Com o sistema de quota, você evita estourar e pode planejar melhor o uso.

---

## Roadmap Futuro

1. **Dashboard visual** - Web UI mostrando gráficos de uso
2. **Integração com Claude API** - Métricas reais em vez de estimadas
3. **Alertas proativos** - Notificações quando atingir thresholds
4. **Cache de respostas** - Evitar perguntas duplicadas
5. **Compression automática** - Resumir contextos grandes automaticamente

---

*"Quem controla seus recursos controla seu destino."*
*— Sistema criado em 2026-01-20*
