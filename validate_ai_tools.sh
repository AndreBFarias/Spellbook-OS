#!/bin/bash

# ==============================================================================
# VALIDADOR DO SISTEMA AI TOOLS
# Verifica conformidade com protocolo AI.md
# ==============================================================================

set -e

ERRORS=0
WARNINGS=0

echo "=== VALIDACAO DO SISTEMA AI TOOLS ==="
echo ""

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Função de log
log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((ERRORS++))
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

# 1. Verificar estrutura de pastas
echo "[1/10] Verificando estrutura de pastas..."
for dir in claude gemini aider; do
    if [ -d "$HOME/.config/zsh/$dir" ]; then
        log_pass "Pasta $dir/ existe"
    else
        log_fail "Pasta $dir/ não encontrada"
    fi
done
echo ""

# 2. Verificar AI.md universal
echo "[2/10] Verificando AI.md universal..."
if [ -f "$HOME/.config/zsh/AI.md" ]; then
    log_pass "AI.md existe"
    for dir in claude gemini aider; do
        if [ -L "$HOME/.config/zsh/$dir/AI.md" ]; then
            log_pass "Symlink em $dir/AI.md OK"
        else
            log_fail "Symlink em $dir/AI.md faltando"
        fi
    done
else
    log_fail "AI.md não encontrado"
fi
echo ""

# 3. Verificar emojis em scripts
echo "[3/10] Verificando ausência de emojis em scripts..."
EMOJI_COUNT=$(grep -rn "\|\|\|\|\|🟡\|🟢\|\|\|\|" ~/.config/zsh/{claude,gemini,aider}/*.sh 2>/dev/null | wc -l)
if [ "$EMOJI_COUNT" -eq 0 ]; then
    log_pass "Nenhum emoji em scripts .sh"
else
    log_fail "$EMOJI_COUNT emojis encontrados em scripts"
fi
echo ""

# 4. Verificar permissões executáveis
echo "[4/10] Verificando permissões executáveis..."
for script in ~/.config/zsh/{claude,gemini,aider}/*.sh; do
    if [ -x "$script" ]; then
        log_pass "$(basename $script) executável"
    else
        log_warn "$(basename $script) não executável"
    fi
done
echo ""

# 5. Verificar symlink do Aider
echo "[5/10] Verificando symlink do Aider..."
if [ -L "$HOME/.aider.conf.yml" ]; then
    target=$(readlink "$HOME/.aider.conf.yml")
    if [[ "$target" == *"/.config/zsh/aider/.aider.conf.yml" ]]; then
        log_pass "Symlink .aider.conf.yml correto"
    else
        log_fail "Symlink .aider.conf.yml aponta para lugar errado"
    fi
else
    log_fail "Symlink .aider.conf.yml não existe"
fi
echo ""

# 6. Verificar documentação
echo "[6/10] Verificando documentação..."
for doc in AI.md INDEX.md AI_TOOLS_MASTER.md; do
    if [ -f "$HOME/.config/zsh/$doc" ]; then
        log_pass "$doc existe"
    else
        log_fail "$doc não encontrado"
    fi
done
echo ""

# 7. Verificar READMEs
echo "[7/10] Verificando READMEs..."
for dir in claude gemini aider; do
    if [ -f "$HOME/.config/zsh/$dir/README.md" ]; then
        log_pass "README.md em $dir/"
    else
        log_warn "README.md faltando em $dir/"
    fi
done
echo ""

# 8. Verificar aliases
echo "[8/10] Verificando aliases..."
if grep -q "aider/aliases_aider.zsh" "$HOME/.config/zsh/.zshrc" 2>/dev/null; then
    log_pass "Aliases do Aider carregados no .zshrc"
else
    log_warn "Aliases do Aider não estão no .zshrc"
fi

if grep -q "claude/aliases_claude.zsh" "$HOME/.config/zsh/.zshrc" 2>/dev/null; then
    log_pass "Aliases do Claude carregados no .zshrc"
else
    log_warn "Aliases do Claude não estão no .zshrc"
fi

if grep -q "gemini/aliases_gemini.zsh" "$HOME/.config/zsh/.zshrc" 2>/dev/null; then
    log_pass "Aliases do Gemini carregados no .zshrc"
else
    log_warn "Aliases do Gemini não estão no .zshrc"
fi
echo ""

# 9. Verificar quota managers
echo "[9/10] Verificando quota managers..."
if [ -x "$HOME/.config/zsh/claude/claude_quota_manager.sh" ]; then
    log_pass "Claude quota manager OK"
else
    log_fail "Claude quota manager inválido"
fi

if [ -x "$HOME/.config/zsh/gemini/gemini_quota_manager.sh" ]; then
    log_pass "Gemini quota manager OK"
else
    log_fail "Gemini quota manager inválido"
fi
echo ""

# 10. Verificar anonimato
echo "[10/10] Verificando anonimato..."
MENTIONS=$(grep -rni "Claude AI\|Anthropic\|OpenAI\|Google AI\|by AI\|AI-generated" ~/.config/zsh/{claude,gemini,aider}/*.sh 2>/dev/null | grep -v "api_key\|API_KEY\|provider\|model" | wc -l)
if [ "$MENTIONS" -eq 0 ]; then
    log_pass "Sem menções a IAs nos scripts"
else
    log_warn "$MENTIONS menções a IAs encontradas"
fi
echo ""

# Resumo final
echo "=== RESUMO ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}PERFEITO!${NC} Sistema 100% conforme."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}BOM${NC} com $WARNINGS avisos."
    exit 0
else
    echo -e "${RED}FALHAS${NC}: $ERRORS erros, $WARNINGS avisos."
    exit 1
fi
