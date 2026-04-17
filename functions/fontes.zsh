#!/bin/zsh

# ---------------------------------------------------------------------------
# Helpers privados
# ---------------------------------------------------------------------------

__fontes_dir_windows() {
    echo "${HOME}/.local/share/fonts/windows-compat"
}

__fontes_dir_macos() {
    echo "${HOME}/.local/share/fonts/macos-compat"
}

__fontes_pacotes_instalados() {
    dpkg -l 2>/dev/null | awk '/^ii/ {print $2}'
}

__fontes_pacote_disponivel() {
    apt-cache show "$1" &>/dev/null
}

__fontes_instalar_pacotes() {
    local descricao="$1"; shift
    local pacotes=("$@")
    local faltantes=()

    local instalados=$(__fontes_pacotes_instalados)

    for pkg in "${pacotes[@]}"; do
        if ! echo "$instalados" | grep -q "^${pkg}$"; then
            if __fontes_pacote_disponivel "$pkg"; then
                faltantes+=("$pkg")
            else
                __warn "Pacote indisponível nos repositórios: $pkg"
            fi
        fi
    done

    if [[ ${#faltantes[@]} -eq 0 ]]; then
        __ok "$descricao — já instalado"
        return 0
    fi

    echo -e "  ${D_COMMENT}Instalando ${descricao}...${D_RESET}"
    if sudo apt install -y -qq "${faltantes[@]}" 2>/dev/null; then
        __ok "$descricao — instalado com sucesso"
    else
        __err "Falha ao instalar ${descricao}"
        return 1
    fi
}

__fontes_detectar_windows() {
    local caminho="$1"

    if [[ -n "$caminho" ]]; then
        if [[ -d "${caminho}/Windows/Fonts" ]]; then
            echo "${caminho}/Windows/Fonts"
            return 0
        fi
        return 1
    fi

    local candidatos=(
        "/mnt/windows"
        "/mnt/Windows"
    )

    for dir in /media/*/Windows /media/*/*/Windows /mnt/*/Windows; do
        [[ -d "$dir" ]] && candidatos+=("${dir%/Windows}")
    done

    for base in "${candidatos[@]}"; do
        if [[ -d "${base}/Windows/Fonts" ]]; then
            echo "${base}/Windows/Fonts"
            return 0
        fi
    done

    return 1
}

__fontes_gerar_fontconfig() {
    local conf_dir="${HOME}/.config/fontconfig"
    local conf_file="${conf_dir}/fonts.conf"
    local win_dir=$(__fontes_dir_windows)
    local tem_windows=false

    [[ -d "$win_dir" ]] && [[ -n "$(ls -A "$win_dir" 2>/dev/null)" ]] && tem_windows=true

    mkdir -p "$conf_dir"

    cat > "$conf_file" << 'FONTCONFIG_EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>

  <!-- Arial -->
  <alias>
    <family>Arial</family>
    <prefer>
      <family>Arial</family>
      <family>Liberation Sans</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <!-- Times New Roman -->
  <alias>
    <family>Times New Roman</family>
    <prefer>
      <family>Times New Roman</family>
      <family>Liberation Serif</family>
      <family>Noto Serif</family>
    </prefer>
  </alias>

  <!-- Courier New -->
  <alias>
    <family>Courier New</family>
    <prefer>
      <family>Courier New</family>
      <family>Liberation Mono</family>
      <family>Noto Sans Mono</family>
    </prefer>
  </alias>

  <!-- Calibri -->
  <alias>
    <family>Calibri</family>
    <prefer>
      <family>Calibri</family>
      <family>Carlito</family>
      <family>Liberation Sans</family>
    </prefer>
  </alias>

  <!-- Cambria -->
  <alias>
    <family>Cambria</family>
    <prefer>
      <family>Cambria</family>
      <family>Caladea</family>
      <family>Liberation Serif</family>
    </prefer>
  </alias>

  <!-- Consolas -->
  <alias>
    <family>Consolas</family>
    <prefer>
      <family>Consolas</family>
      <family>FiraCode Nerd Font</family>
      <family>Liberation Mono</family>
    </prefer>
  </alias>

  <!-- Segoe UI -->
  <alias>
    <family>Segoe UI</family>
    <prefer>
      <family>Segoe UI</family>
      <family>Liberation Sans</family>
      <family>Inter</family>
    </prefer>
  </alias>

  <!-- Tahoma -->
  <alias>
    <family>Tahoma</family>
    <prefer>
      <family>Tahoma</family>
      <family>Liberation Sans</family>
    </prefer>
  </alias>

  <!-- Helvetica -->
  <alias>
    <family>Helvetica</family>
    <prefer>
      <family>TeX Gyre Heros</family>
      <family>Liberation Sans</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <!-- Helvetica Neue -->
  <alias>
    <family>Helvetica Neue</family>
    <prefer>
      <family>TeX Gyre Heros</family>
      <family>Inter</family>
      <family>Liberation Sans</family>
    </prefer>
  </alias>

  <!-- San Francisco -->
  <alias>
    <family>San Francisco</family>
    <prefer>
      <family>Inter</family>
      <family>Liberation Sans</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <!-- Palatino -->
  <alias>
    <family>Palatino</family>
    <prefer>
      <family>TeX Gyre Pagella</family>
      <family>Liberation Serif</family>
    </prefer>
  </alias>

  <!-- Palatino Linotype -->
  <alias>
    <family>Palatino Linotype</family>
    <prefer>
      <family>TeX Gyre Pagella</family>
      <family>Liberation Serif</family>
    </prefer>
  </alias>

  <!-- Candara -->
  <alias>
    <family>Candara</family>
    <prefer>
      <family>Candara</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <!-- Corbel -->
  <alias>
    <family>Corbel</family>
    <prefer>
      <family>Corbel</family>
      <family>Noto Sans</family>
    </prefer>
  </alias>

  <!-- Constantia -->
  <alias>
    <family>Constantia</family>
    <prefer>
      <family>Constantia</family>
      <family>Noto Serif</family>
    </prefer>
  </alias>

</fontconfig>
FONTCONFIG_EOF

    __ok "Fontconfig gerado em ${conf_file}"
}

# ---------------------------------------------------------------------------
# Funções públicas
# ---------------------------------------------------------------------------

# Propósito: Instalar fontes de compatibilidade Win/Mac (MS Core, Liberation, Noto, Inter)
# Uso: fontes_instalar
fontes_instalar() {
    __verificar_dependencias "fc-cache" "wget" || return 1

    __header "INSTALAÇÃO DE FONTES" "$D_CYAN"
    echo -e "  ${D_COMMENT}Compatibilidade com Windows e macOS${D_RESET}"
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}[1/7]${D_RESET} ${D_FG}MS Core Fonts${D_RESET}"
    echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | \
        sudo debconf-set-selections 2>/dev/null
    __fontes_instalar_pacotes "MS Core Fonts" \
        "ttf-mscorefonts-installer"

    echo -e "  ${D_PURPLE}${D_BOLD}[2/7]${D_RESET} ${D_FG}Liberation Fonts (substitutos métricos)${D_RESET}"
    __fontes_instalar_pacotes "Liberation Fonts" \
        "fonts-liberation2"

    echo -e "  ${D_PURPLE}${D_BOLD}[3/7]${D_RESET} ${D_FG}CrOS Extra (Carlito=Calibri, Caladea=Cambria)${D_RESET}"
    __fontes_instalar_pacotes "CrOS Extra" \
        "fonts-crosextra-carlito" "fonts-crosextra-caladea"

    echo -e "  ${D_PURPLE}${D_BOLD}[4/7]${D_RESET} ${D_FG}Google Noto (cobertura Unicode universal)${D_RESET}"
    __fontes_instalar_pacotes "Google Noto" \
        "fonts-noto-core" "fonts-noto-extra" "fonts-noto-color-emoji"

    echo -e "  ${D_PURPLE}${D_BOLD}[5/7]${D_RESET} ${D_FG}Fontes Windows via partição${D_RESET}"
    local win_fonts
    win_fonts=$(__fontes_detectar_windows)
    if [[ $? -eq 0 ]]; then
        fontes_importar_windows
    else
        __warn "Partição Windows não detectada — use 'fontes_importar_windows /caminho' para importar manualmente"
    fi

    echo -e "  ${D_PURPLE}${D_BOLD}[6/7]${D_RESET} ${D_FG}Equivalentes macOS (Inter, TeX Gyre)${D_RESET}"
    __fontes_instalar_pacotes "Equivalentes macOS" \
        "fonts-inter" "fonts-texgyre"

    echo -e "  ${D_PURPLE}${D_BOLD}[7/7]${D_RESET} ${D_FG}Fontconfig (regras de fallback)${D_RESET}"
    __fontes_gerar_fontconfig

    echo ""
    echo -e "  ${D_COMMENT}Atualizando cache de fontes...${D_RESET}"
    fc-cache -f 2>/dev/null
    __ok "Cache de fontes atualizado"

    echo ""
    __ok "Instalação de fontes concluída"
    echo -e "  ${D_COMMENT}Execute 'fontes_verificar' para ver o estado completo${D_RESET}"
    echo ""
}

# Propósito: Copiar fontes proprietárias da partição Windows para ~/.local/share/fonts
# Uso: fontes_importar_windows [raiz_windows]
# Completa:
#   [raiz_windows]=_path_files -/
fontes_importar_windows() {
    local raiz_windows="$1"
    local win_fonts

    win_fonts=$(__fontes_detectar_windows "$raiz_windows")
    if [[ $? -ne 0 ]]; then
        __warn "Partição Windows não encontrada"
        echo -e "  ${D_COMMENT}Monte a partição e tente novamente:${D_RESET}"
        echo -e "  ${D_FG}  sudo mount /dev/sdXN /mnt/windows -o ro${D_RESET}"
        echo -e "  ${D_FG}  fontes_importar_windows /mnt/windows${D_RESET}"
        return 1
    fi

    local destino=$(__fontes_dir_windows)
    mkdir -p "$destino"

    __header "IMPORTAR FONTES WINDOWS" "$D_CYAN"
    echo -e "  ${D_COMMENT}Origem: ${D_FG}${win_fonts}${D_RESET}"
    echo -e "  ${D_COMMENT}Destino: ${D_FG}${destino}${D_RESET}"
    echo ""

    local alvos=(
        "calibri*.ttf" "cambria*.ttc" "consola*.ttf"
        "candara*.ttf" "corbel*.ttf" "constan*.ttf"
        "segoeui*.ttf" "tahoma*.ttf" "wingding*.ttf"
        "symbol.ttf"
    )

    local copiadas=0
    for padrao in "${alvos[@]}"; do
        local encontrados=("${win_fonts}"/${~padrao}(N))
        for arquivo in "${encontrados[@]}"; do
            [[ -f "$arquivo" ]] || continue
            cp "$arquivo" "$destino/" 2>/dev/null && ((copiadas++))
        done
    done

    if [[ $copiadas -eq 0 ]]; then
        __warn "Nenhuma fonte encontrada em ${win_fonts}"
    else
        __ok "${copiadas} fonte(s) importada(s) para ${destino}"
        fc-cache -f 2>/dev/null
    fi
    echo ""
}

# Propósito: Verificar cobertura de fontes instaladas e fallback
# Uso: fontes_verificar
fontes_verificar() {
    __header "VERIFICAÇÃO DE FONTES" "$D_CYAN"

    local total=0 instaladas=0

    __fontes_verificar_pacote() {
        local nome="$1"
        local pacote="$2"
        ((total++))

        local instalados=$(__fontes_pacotes_instalados)
        if echo "$instalados" | grep -q "^${pacote}$"; then
            __item "$nome" "instalado" "$D_COMMENT" "$D_GREEN"
            ((instaladas++))
        else
            __item "$nome" "ausente" "$D_COMMENT" "$D_RED"
        fi
    }

    __fontes_verificar_arquivo() {
        local nome="$1"
        local diretorio="$2"
        ((total++))

        if [[ -d "$diretorio" ]] && [[ -n "$(ls -A "$diretorio" 2>/dev/null)" ]]; then
            local contagem=$(find "$diretorio" -type f \( -name "*.ttf" -o -name "*.ttc" -o -name "*.otf" \) 2>/dev/null | wc -l)
            __item "$nome" "${contagem} arquivo(s)" "$D_COMMENT" "$D_GREEN"
            ((instaladas++))
        else
            __item "$nome" "ausente" "$D_COMMENT" "$D_YELLOW"
        fi
    }

    echo -e "  ${D_PURPLE}${D_BOLD}Pacotes APT${D_RESET}"
    __fontes_verificar_pacote "MS Core"       "ttf-mscorefonts-installer"
    __fontes_verificar_pacote "Liberation"    "fonts-liberation2"
    __fontes_verificar_pacote "Carlito"       "fonts-crosextra-carlito"
    __fontes_verificar_pacote "Caladea"       "fonts-crosextra-caladea"
    __fontes_verificar_pacote "Noto Core"     "fonts-noto-core"
    __fontes_verificar_pacote "Noto Extra"    "fonts-noto-extra"
    __fontes_verificar_pacote "Noto Emoji"    "fonts-noto-color-emoji"
    __fontes_verificar_pacote "Inter"         "fonts-inter"
    __fontes_verificar_pacote "TeX Gyre"      "fonts-texgyre"
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}Fontes importadas${D_RESET}"
    __fontes_verificar_arquivo "Windows" "$(__fontes_dir_windows)"
    __fontes_verificar_arquivo "macOS"   "$(__fontes_dir_macos)"
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}Fontconfig${D_RESET}"
    local conf_file="${HOME}/.config/fontconfig/fonts.conf"
    ((total++))
    if [[ -f "$conf_file" ]]; then
        __item "fonts.conf" "presente" "$D_COMMENT" "$D_GREEN"
        ((instaladas++))
    else
        __item "fonts.conf" "ausente" "$D_COMMENT" "$D_RED"
    fi
    echo ""

    echo -e "  ${D_PURPLE}${D_BOLD}Testes de fallback${D_RESET}"
    local -A testes_fallback=(
        [Calibri]="Carlito"
        [Cambria]="Caladea"
        [Arial]="Liberation Sans"
        [Helvetica]="TeX Gyre Heros"
        [Helvetica Neue]="TeX Gyre Heros"
        [San Francisco]="Inter"
    )

    for fonte esperado in "${(@kv)testes_fallback}"; do
        local resultado=$(fc-match "$fonte" 2>/dev/null | sed 's/:.*//')
        if [[ -n "$resultado" ]]; then
            __item "$fonte" "$resultado" "$D_COMMENT" "$D_FG"
        else
            __item "$fonte" "sem fallback" "$D_COMMENT" "$D_RED"
        fi
    done
    echo ""

    local percentual=0
    (( total > 0 )) && percentual=$((instaladas * 100 / total))

    if [[ $percentual -eq 100 ]]; then
        __ok "Cobertura: ${percentual}% (${instaladas}/${total})"
    elif [[ $percentual -ge 70 ]]; then
        __warn "Cobertura: ${percentual}% (${instaladas}/${total})"
    else
        __err "Cobertura: ${percentual}% (${instaladas}/${total})"
    fi
    echo ""

    unfunction __fontes_verificar_pacote 2>/dev/null
    unfunction __fontes_verificar_arquivo 2>/dev/null
}

# Propósito: Exibir mapeamento Win/Mac -> substituto Linux -> fallback
# Uso: fontes_mapa
fontes_mapa() {
    __header "MAPEAMENTO DE FONTES" "$D_CYAN"
    echo -e "  ${D_COMMENT}Windows/macOS -> Substituto Linux -> Fallback${D_RESET}"
    echo ""

    printf "  ${D_PURPLE}%-20s${D_RESET} ${D_FG}%-22s${D_RESET} ${D_COMMENT}%s${D_RESET}\n" \
        "ORIGINAL" "SUBSTITUTO" "FALLBACK"
    printf "  ${D_COMMENT}%s${D_RESET}\n" "$(printf '%.0s─' {1..60})"

    local -a linhas=(
        "Arial|Liberation Sans|Noto Sans"
        "Times New Roman|Liberation Serif|Noto Serif"
        "Courier New|Liberation Mono|Noto Sans Mono"
        "Calibri|Carlito|Liberation Sans"
        "Cambria|Caladea|Liberation Serif"
        "Consolas|FiraCode NF|Liberation Mono"
        "Segoe UI|Liberation Sans|Inter"
        "Tahoma|Liberation Sans|Noto Sans"
        "Helvetica|TeX Gyre Heros|Liberation Sans"
        "Helvetica Neue|TeX Gyre Heros|Inter"
        "San Francisco|Inter|Liberation Sans"
        "Palatino|TeX Gyre Pagella|Liberation Serif"
    )

    for linha in "${linhas[@]}"; do
        local original="${linha%%|*}"
        local resto="${linha#*|}"
        local substituto="${resto%%|*}"
        local fallback="${resto#*|}"
        printf "  ${D_FG}%-20s${D_RESET} ${D_GREEN}%-22s${D_RESET} ${D_COMMENT}%s${D_RESET}\n" \
            "$original" "$substituto" "$fallback"
    done
    echo ""
}

# Propósito: Listar todas as famílias de fontes instaladas no sistema
# Uso: fontes_listar
fontes_listar() {
    __header "FONTES INSTALADAS" "$D_CYAN"

    local -A categorias=(
        [serif]="Serif (serifadas)"
        [sans-serif]="Sans-Serif (sem serifa)"
        [monospace]="Monospace (largura fixa)"
    )

    for cat desc in "${(@kv)categorias}"; do
        echo -e "  ${D_PURPLE}${D_BOLD}${desc}${D_RESET}"
        fc-list ":spacing=100" family 2>/dev/null | sort -u | head -30 | while IFS= read -r familia; do
            [[ -z "$familia" ]] && continue
            echo -e "    ${D_FG}${familia}${D_RESET}"
        done 2>/dev/null
        echo ""
    done

    local total_fontes=$(fc-list 2>/dev/null | wc -l)
    __ok "Total de fontes no sistema: ${total_fontes}"

    local custom_win=$(__fontes_dir_windows)
    local custom_mac=$(__fontes_dir_macos)
    local custom=0
    [[ -d "$custom_win" ]] && custom=$((custom + $(find "$custom_win" -type f 2>/dev/null | wc -l)))
    [[ -d "$custom_mac" ]] && custom=$((custom + $(find "$custom_mac" -type f 2>/dev/null | wc -l)))
    echo -e "  ${D_COMMENT}Fontes importadas (custom): ${custom}${D_RESET}"
    echo ""
}

# "A tipografia é a voz visual do pensamento." — Robert Bringhurst
