# GUIA RÁPIDO: Claude Quota System

## TL;DR - Uso Rápido

```bash
# Ver quanto você usou esta semana
cq

# Estimar antes de ler arquivo grande
claude-estimate arquivo.py

# Preview sem consumir quota (mostra 50 linhas início/fim)
claude-peek arquivo.py

# Relatório completo com dicas
claude-report
```

## O Problema

Você está estourando o limite semanal do Claude Pro em 3 dias porque:

1. **Leituras de arquivos grandes** - Um arquivo de 500KB consome ~2000 tokens
2. **Contexto acumulado** - Cada nova pergunta carrega todo o histórico
3. **Sem visibilidade** - Você não sabe quanto já usou

## A Solução

Sistema de **throttling inteligente** que:

-  **AVISA** quando arquivo é grande (> 50KB)
-  **BLOQUEIA** quando arquivo é enorme (> 100KB)
-  **RASTREIA** uso semanal automaticamente
-  **SUGERE** alternativas mais baratas

## Como Funciona

### Antes de cada request
```
User: claude "read big_file.py"
         ↓
    [PRE-CHECK]
         ↓
  Quota OK? (80% usado)
         ↓
  File OK? (150KB)  BLOQUEADO
         ↓
  SUGERE: grep, head, tail
```

### Alternativas sugeridas
```bash
# Em vez de:
claude "read entire_file.py"  # 2000 tokens

# Faça:
grep "def " entire_file.py    # 0 tokens
head -100 entire_file.py      # 0 tokens
claude-peek entire_file.py    # 0 tokens (50 linhas início/fim)
```

## Comandos Principais

### 1. Ver Status (`cq`)
```bash
$ cq
=== CLAUDE QUOTA STATUS ===
Tokens usados: 45000 / 500000 (9%)
Tokens restantes: 455000
Requests esta semana: 23
Week start: 2026-01-20

 Uso normal. Ainda tem 455000 tokens.
```

**Cores:**
- 🟢 Verde: 0-79% (normal)
- 🟡 Amarelo: 80-89% (atenção)
-  Vermelho: 90-100% (crítico)

### 2. Estimar Custo (`claude-estimate`)
```bash
$ claude-estimate logs/debug.log
  AVISO: Arquivo grande detectado
   Arquivo: logs/debug.log (87KB)
   Isso consumirá ~348 tokens estimados
   Continuar? (y/n)
```

**Decisão informada ANTES de consumir.**

### 3. Preview Grátis (`claude-peek`)
```bash
$ claude-peek config.py
=== PREVIEW: config.py ===
Tamanho: 12K | Linhas: 350

--- INÍCIO (50 linhas) ---
import os
from pathlib import Path
...

--- FIM (50 linhas) ---
...
OLLAMA_KEEP_ALIVE = "5m"

[DICA] Use grep, sed ou awk para análises específicas
```

**Zero tokens consumidos. Você vê começo e fim do arquivo.**

### 4. Relatório Completo (`claude-report`)
```bash
$ claude-report
=== RELATÓRIO SEMANAL DE USO ===
Tokens usados: 345000 / 500000 (69%)
...

=== DICAS PARA ECONOMIZAR ===
1. Use grep/sed/awk para buscas rápidas
2. Leia arquivos em seções (head/tail)
3. Use --skip-context quando possível
4. Resuma contextos grandes primeiro
5. Evite ler arquivos > 100KB
```

## Exemplos Práticos

### Cenário 1: Arquivo Bloqueado
```bash
$ claude "read Luna/logs/app.log"

 BLOQUEADO: Arquivo muito grande!
   Arquivo: Luna/logs/app.log
   Tamanho: 250KB (limite: 100KB)

ALTERNATIVAS:
1. grep 'ERROR' Luna/logs/app.log
2. tail -100 Luna/logs/app.log
3. head -50 && tail -50
```

**Você economizou ~1000 tokens.**

### Cenário 2: Zona Crítica (90%)
```bash
$ claude "help me debug"

  ZONA CRITICA: 50000 tokens restantes
   Deseja continuar? (y/n)
n
```

**Você evitou estorar o limite.**

### Cenário 3: Uso Inteligente
```bash
#  Consome ~500 tokens
claude "what are the functions in core.py?"

#  Consome 0 tokens
grep "^def " src/core.py
# Depois, pergunta específica (consome ~100 tokens)
claude "explain the parse_response function"
```

**Economia de 400 tokens (80%).**

## Estratégias de Economia

### 1. Ferramentas Unix Primeiro
```bash
# Buscar
grep -r "palavra" src/

# Contar
wc -l src/**/*.py

# Filtrar
find src/ -name "*.py" -type f

# Resumir
head -20 arquivo && echo "..." && tail -20 arquivo
```

**Use Claude só quando Unix não resolver.**

### 2. Perguntas Agrupadas
```bash
#  3 requests = ~300 tokens base
claude "what is X?"
claude "what is Y?"
claude "what is Z?"

#  1 request = ~100 tokens base
claude "explain X, Y, and Z"
```

### 3. Skip Context
```bash
#  Carrega todo histórico (pode ser 10k+ tokens)
claude "quick syntax question"

#  Sem histórico desnecessário
claude --skip-context "quick syntax question"
```

### 4. Modelos Locais para Pré-Processamento
```bash
# Resuma com Ollama (gratuito, local)
ollama run llama3.2:3b "summarize: $(cat large.py)" > summary.txt

# Então use Claude (pago, cloud)
claude "based on summary: $(cat summary.txt), what to do?"
```

## Configuração

### Ajustar Limites
Edite: `~/.config/zsh/.claude_guard_config`

```bash
# Mais restritivo (economizar mais)
MAX_FILE_SIZE_KB=50      # Bloqueia > 50KB
MAX_CONTEXT_FILES=3      # Max 3 arquivos contexto

# Mais permissivo (menos bloqueios)
MAX_FILE_SIZE_KB=200     # Bloqueia > 200KB
MAX_CONTEXT_FILES=10     # Max 10 arquivos contexto
```

### Status no Shell Prompt
Quando você abrir terminal, verá:
```
NVIDIA GPU Ativa: RTX 3050, 470.94, 45°C
VRAM: 16 MiB / 4096 MiB (0%)
Claude Quota: 45000 / 500000 tokens (9%) | Cmd: cq
```

**Visibilidade constante do seu uso.**

## Custos Reais Estimados

| Operação | Tokens |
|----------|--------|
| Pergunta simples | 100-500 |
| Ler 10KB | ~40 |
| Ler 100KB | ~400 |
| Ler 1MB | ~4000 |
| Explicação complexa | 1000-3000 |
| Gerar 50 linhas código | 500-1000 |
| Conversa completa | 1000-5000 |

**Objetivo:** Manter média < 70k tokens/dia (490k/semana).

## Troubleshooting

### Sistema não está bloqueando
```bash
# Verifique configuração
cat ~/.config/zsh/.claude_guard_config | grep BLOCK

# Deve mostrar:
# BLOCK_LARGE_READS=true

# Se false, edite:
nano ~/.config/zsh/.claude_guard_config
```

### Alias não funciona
```bash
# Recarregar shell
source ~/.config/zsh/.zshrc

# Testar
type claude-safe
# Deve mostrar: claude-safe is a shell function
```

### Quota incorreta
```bash
# Reset manual
bash ~/.config/zsh/claude_quota_manager.sh reset
```

## Próximos Passos

1. **Hoje:** Use `cq` antes e depois de sessões longas
2. **Esta semana:** Use `claude-estimate` antes de arquivos grandes
3. **Sempre:** Prefira grep/sed/awk quando possível

---

**Meta:** Nunca mais estoure o limite semanal.

**Resultado esperado:** Uso médio de 60-70% da quota semanal, com margem de segurança de 30% para emergências.
