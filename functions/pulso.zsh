#!/bin/zsh

# Propósito: Saúde rápida do sistema (CPU, RAM, Disco, GPU, Uptime)
# Uso: pulso
pulso() {
    __header "PULSO DO SISTEMA" "$D_CYAN"

    printf "  ${D_COMMENT}%-10s${D_RESET} " "CPU"
    local cpu_idle=$(top -bn1 | awk '/^%Cpu/ {print $8}')
    local cpu_usage=$(printf "%.0f" $(echo "100 - $cpu_idle" | bc))
    local cpu_color="$D_GREEN"
    [ "$cpu_usage" -ge 50 ] && cpu_color="$D_YELLOW"
    [ "$cpu_usage" -ge 80 ] && cpu_color="$D_RED"
    echo -e "${cpu_color}${cpu_usage}%${D_RESET}"

    printf "  ${D_COMMENT}%-10s${D_RESET} " "RAM"
    local mem_used=$(free -h | awk '/^Mem/ {print $3}')
    local mem_total=$(free -h | awk '/^Mem/ {print $2}')
    local mem_pct=$(free | awk '/^Mem/ {printf "%.0f", $3/$2*100}')
    local mem_color="$D_GREEN"
    [ "$mem_pct" -ge 60 ] && mem_color="$D_YELLOW"
    [ "$mem_pct" -ge 85 ] && mem_color="$D_RED"
    echo -e "${mem_color}${mem_used}${D_RESET} ${D_COMMENT}/${D_RESET} ${mem_total} ${D_DIM}(${mem_pct}%)${D_RESET}"

    printf "  ${D_COMMENT}%-10s${D_RESET} " "Disco"
    local disk_used=$(df -h / | awk 'NR==2 {print $3}')
    local disk_total=$(df -h / | awk 'NR==2 {print $2}')
    local disk_pct=$(df / | awk 'NR==2 {sub(/%/,""); print $5}')
    local disk_color="$D_GREEN"
    [ "$disk_pct" -ge 70 ] && disk_color="$D_YELLOW"
    [ "$disk_pct" -ge 90 ] && disk_color="$D_RED"
    echo -e "${disk_color}${disk_used}${D_RESET} ${D_COMMENT}/${D_RESET} ${disk_total} ${D_DIM}(${disk_pct}%)${D_RESET}"

    if command -v nvidia-smi &> /dev/null; then
        printf "  ${D_COMMENT}%-10s${D_RESET} " "GPU"
        local gpu_info=$(nvidia-smi --query-gpu=name,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null)
        if [ -n "$gpu_info" ]; then
            local gpu_name=$(echo "$gpu_info" | cut -d',' -f1 | xargs)
            local gpu_temp=$(echo "$gpu_info" | cut -d',' -f2 | xargs)
            local gpu_used=$(echo "$gpu_info" | cut -d',' -f3 | xargs)
            local gpu_total=$(echo "$gpu_info" | cut -d',' -f4 | xargs)
            local gpu_pct=$(( (gpu_used * 100) / gpu_total ))
            local gpu_color="$D_GREEN"
            [ "$gpu_pct" -ge 50 ] && gpu_color="$D_YELLOW"
            [ "$gpu_pct" -ge 80 ] && gpu_color="$D_RED"
            local temp_color="$D_GREEN"
            [ "$gpu_temp" -ge 60 ] && temp_color="$D_YELLOW"
            [ "$gpu_temp" -ge 80 ] && temp_color="$D_RED"
            echo -e "${D_FG}${gpu_name}${D_RESET} ${temp_color}${gpu_temp}C${D_RESET} ${D_COMMENT}|${D_RESET} VRAM: ${gpu_color}${gpu_used}${D_RESET}${D_COMMENT}/${D_RESET}${gpu_total} MiB"
        fi
    fi

    printf "  ${D_COMMENT}%-10s${D_RESET} " "Uptime"
    echo -e "${D_FG}$(uptime -p | sed 's/up //')${D_RESET}"

    echo ""
}

# Propósito: Status git de todos os repositórios (branch, alterações, sync)
# Uso: repos
repos() {
    if [ ! -d "$DEV_DIR" ]; then
        __err "Diretório '$DEV_DIR' não encontrado."
        return 1
    fi

    __header "REPOSITÓRIOS" "$D_PURPLE"

    local repos=$(find "$DEV_DIR" -maxdepth 3 -name ".git" -type d -prune 2>/dev/null | sed 's/\/\.git//' | sort)

    if [ -z "$repos" ]; then
        __warn "Nenhum repositório encontrado."
        return 0
    fi

    printf "  ${D_COMMENT}%-28s %-14s %-18s %s${D_RESET}\n" "PROJETO" "BRANCH" "STATUS" "SYNC"
    echo -e "  ${D_COMMENT}$(printf '%.0s─' {1..70})${D_RESET}"

    while read -r repo_path; do
        local repo_name=$(basename "$repo_path")
        local branch=$(git -C "$repo_path" branch --show-current 2>/dev/null)
        local status=$(git -C "$repo_path" status --porcelain 2>/dev/null)
        local ahead=$(git -C "$repo_path" rev-list --count @{u}..HEAD 2>/dev/null)
        local behind=$(git -C "$repo_path" rev-list --count HEAD..@{u} 2>/dev/null)

        local estado_str="" estado_cor="$D_GREEN"
        if [ -n "$status" ]; then
            local mod_count=$(echo "$status" | wc -l | xargs)
            estado_str="${mod_count} modificados"
            estado_cor="$D_ORANGE"
        else
            estado_str="limpo"
        fi

        local sync_str=""
        if [ -n "$ahead" ] && [ "$ahead" -gt 0 ] 2>/dev/null; then
            sync_str="+${ahead}"
        fi
        if [ -n "$behind" ] && [ "$behind" -gt 0 ] 2>/dev/null; then
            [ -n "$sync_str" ] && sync_str="${sync_str} "
            sync_str="${sync_str}-${behind}"
        fi

        printf "  ${D_FG}%-28s${D_RESET} ${D_CYAN}%-14s${D_RESET} ${estado_cor}%-18s${D_RESET} ${D_YELLOW}%s${D_RESET}\n" \
            "${repo_name:0:27}" "${branch:0:13}" "$estado_str" "$sync_str"
    done <<< "$repos"

    echo ""
}

# Propósito: Limpar caches do sistema (pip, npm, apt, journalctl, pycache)
# Uso: purgar
purgar() {
    __header "LIMPEZA DE CACHES" "$D_PINK"

    if command -v pip &> /dev/null; then
        printf "  ${D_COMMENT}pip cache...${D_RESET}"
        pip cache purge 2>/dev/null && echo -e " ${D_GREEN}ok${D_RESET}" || echo -e " ${D_DIM}skip${D_RESET}"
    fi

    if command -v npm &> /dev/null; then
        printf "  ${D_COMMENT}npm cache...${D_RESET}"
        npm cache clean --force 2>/dev/null && echo -e " ${D_GREEN}ok${D_RESET}" || echo -e " ${D_DIM}skip${D_RESET}"
    fi

    printf "  ${D_COMMENT}apt cache...${D_RESET}"
    sudo apt clean 2>/dev/null && echo -e " ${D_GREEN}ok${D_RESET}" || echo -e " ${D_DIM}skip${D_RESET}"

    printf "  ${D_COMMENT}journalctl...${D_RESET}"
    sudo journalctl --vacuum-size=100M 2>/dev/null && echo -e " ${D_GREEN}ok${D_RESET}" || echo -e " ${D_DIM}skip${D_RESET}"

    printf "  ${D_COMMENT}__pycache__...${D_RESET}"
    find "$DEV_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null
    find "$DEV_DIR" -name "*.pyc" -delete 2>/dev/null
    echo -e " ${D_GREEN}ok${D_RESET}"

    echo ""
    __ok "Limpeza concluída."
    echo ""
}
