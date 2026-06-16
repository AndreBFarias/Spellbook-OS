#!/bin/bash
# Statusline Claude Code — projeto, branch, modelo, custo, BRIEF, quota cca, RAM do slice
# Input: JSON via stdin com contexto da sessão
# Output: linha unica a ser exibida
# Canônico: docs/claude/hooks/statusline.sh -> symlink em ~/.claude/statusline.sh (install.sh)

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "?"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0' | LC_NUMERIC=C awk '{printf "%.2f", $1}')

project=$(basename "$cwd")
[ -z "$project" ] && project="?"

branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch="detached"
fi

brief_info=""
if [ -f "$cwd/VALIDATOR_BRIEF.md" ]; then
    brief_lines=$(wc -l < "$cwd/VALIDATOR_BRIEF.md" 2>/dev/null)
    brief_info="brief:${brief_lines}L"
fi

quota_info=""
quota_file="$HOME/.config/zsh/cca/.cca_quota"
if [ -f "$quota_file" ]; then
    tokens_used=$(grep "^tokens_used=" "$quota_file" 2>/dev/null | cut -d'=' -f2)
    if [ -n "$tokens_used" ] && [ "$tokens_used" -gt 0 ]; then
        requests=$(grep "^requests_count=" "$quota_file" 2>/dev/null | cut -d'=' -f2)
        quota_info="cca:${requests:-0}req"
    fi
fi

# Memoria do claude.slice (early-warning de OOM): a sessão cca roda dentro do slice via
# systemd-run --scope, entao MemoryCurrent reflete o uso desta sessão. Teto = MemoryMax (12G).
# Cor: verde <70%, amarelo 70-89%, vermelho >=90%. Vazio se a sessão não esta no slice.
mem_info=""
mem_bytes=$(systemctl --user show claude.slice -p MemoryCurrent --value 2>/dev/null)
if [ -n "$mem_bytes" ] && [ "$mem_bytes" -gt 0 ] 2>/dev/null; then
    mem_max=12884901888
    mem_gb=$(LC_NUMERIC=C awk -v b="$mem_bytes" 'BEGIN{printf "%.1f", b/1073741824}')
    pct=$(( mem_bytes * 100 / mem_max ))
    if   [ "$pct" -ge 90 ]; then col=$'\033[31m'   # vermelho
    elif [ "$pct" -ge 70 ]; then col=$'\033[33m'   # amarelo
    else                        col=$'\033[32m'    # verde
    fi
    mem_info="${col}mem:${mem_gb}/12G${col:+$'\033[0m'}"
fi

parts=("${project}")
[ -n "$branch" ] && parts+=("${branch}")
parts+=("${model}")
parts+=("\$${cost}")
[ -n "$brief_info" ] && parts+=("${brief_info}")
[ -n "$quota_info" ] && parts+=("${quota_info}")
[ -n "$mem_info" ] && parts+=("${mem_info}")

# Join com " | " manualmente (IFS multi-char não funciona com ${array[*]})
out=""
for p in "${parts[@]}"; do
    if [ -z "$out" ]; then
        out="$p"
    else
        out="${out} | ${p}"
    fi
done
echo "$out"
