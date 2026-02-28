#!/bin/bash

echo "=== INSTALANDO CLAUDE QUOTA SYSTEM ==="
echo ""

ZDOTDIR="$HOME/.config/zsh/claude"

echo "[1/5] Verificando arquivos necessários..."
if [ ! -f "$ZDOTDIR/claude_quota_manager.sh" ]; then
    echo "[ERRO] claude_quota_manager.sh não encontrado"
    exit 1
fi
if [ ! -f "$ZDOTDIR/claude_guard.sh" ]; then
    echo "[ERRO] claude_guard.sh não encontrado"
    exit 1
fi
if [ ! -f "$ZDOTDIR/aliases_claude.zsh" ]; then
    echo "[ERRO] aliases_claude.zsh não encontrado"
    exit 1
fi
echo "[OK] Todos os arquivos encontrados"
echo ""

echo "[2/5] Tornando scripts executáveis..."
chmod +x "$ZDOTDIR/claude_quota_manager.sh"
chmod +x "$ZDOTDIR/claude_guard.sh"
echo "[OK] Permissões configuradas"
echo ""

echo "[3/5] Verificando integração no .zshrc..."
if ! grep -q "aliases_claude.zsh" "$ZDOTDIR/.zshrc"; then
    echo "[INFO] Adicionando linha ao .zshrc..."
    echo "" >> "$ZDOTDIR/.zshrc"
    echo "# Claude Quota System" >> "$ZDOTDIR/.zshrc"
    echo "[ -f \"\$ZDOTDIR/aliases_claude.zsh\" ] && source \"\$ZDOTDIR/aliases_claude.zsh\"" >> "$ZDOTDIR/.zshrc"
    echo "[OK] Integração adicionada"
else
    echo "[OK] Integração já existe"
fi
echo ""

echo "[4/5] Inicializando sistema de quota..."
bash "$ZDOTDIR/claude_quota_manager.sh" init
bash "$ZDOTDIR/claude_guard.sh" init
echo "[OK] Sistema inicializado"
echo ""

echo "[5/5] Criando symlinks do CLAUDE.md universal..."
PROJECTS=(
    "$HOME/Desenvolvimento/Luna"
    "$HOME/Desenvolvimento/Neurosonancy"
    "$HOME/Desenvolvimento/Detector-de-Doppelganger"
    "$HOME/Desenvolvimento/dbt-date-harvester"
    "$HOME/Desenvolvimento/FogStripper-Removedor-Background"
    "$HOME/Desenvolvimento/Conversor-Video-Para-ASCII"
)

for project in "${PROJECTS[@]}"; do
    if [ -d "$project" ]; then
        if [ -L "$project/CLAUDE.md" ]; then
            rm "$project/CLAUDE.md"
        elif [ -f "$project/CLAUDE.md" ]; then
            mv "$project/CLAUDE.md" "$project/CLAUDE.md.backup"
            echo "  [INFO] Backup criado: $project/CLAUDE.md.backup"
        fi
        ln -s "$ZDOTDIR/CLAUDE.md" "$project/CLAUDE.md"
        echo "  [OK] Symlink criado: $project/CLAUDE.md"
    fi
done
echo ""

echo "=== INSTALAÇÃO COMPLETA ==="
echo ""
echo "Para ativar agora, rode:"
echo "  source ~/.config/zsh/.zshrc"
echo ""
echo "Comandos disponíveis:"
echo "  claude-quota       - Ver uso semanal"
echo "  claude-estimate    - Estimar custo de arquivo"
echo "  claude-peek        - Preview sem consumir quota"
echo "  claude-report      - Relatório completo"
echo "  cq                 - Atalho para claude-quota"
echo ""
echo "Documentação completa:"
echo "  cat $ZDOTDIR/CLAUDE_QUOTA_SYSTEM.md"
echo ""
echo "Agora 'claude' usa wrapper seguro automaticamente!"
