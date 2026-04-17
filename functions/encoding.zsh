#!/bin/zsh

# ---------------------------------------------------------------------------
# Helpers privados
# ---------------------------------------------------------------------------

__enc_dirs_ignorados() {
    echo ".git|node_modules|venv|.venv|__pycache__|.tox|.nox|.eggs"
}

__enc_extensoes_texto() {
    echo "py|txt|csv|json|yml|yaml|md|cfg|ini|toml|sh|zsh|bash|js|ts|jsx|tsx|html|css|scss|xml|sql|r|R|rst|tex|conf"
}

__enc_eh_binario() {
    local arquivo="$1"
    local tipo
    tipo=$(file -bi "$arquivo" 2>/dev/null)
    [[ "$tipo" != *"text"* && "$tipo" != *"empty"* ]]
}

__enc_em_dir_ignorado() {
    local caminho="$1"
    local ignorados=$(__enc_dirs_ignorados)
    local IFS='|'
    for dir in $ignorados; do
        [[ "$caminho" == *"/${dir}/"* ]] && return 0
    done
    return 1
}

__enc_detectar_encoding() {
    local arquivo="$1"
    local charset
    charset=$(file -bi "$arquivo" 2>/dev/null | sed -n 's/.*charset=\([^ ;]*\).*/\1/p')

    if [[ -z "$charset" || "$charset" == "binary" ]]; then
        if command -v chardet &>/dev/null; then
            charset=$(chardet "$arquivo" 2>/dev/null | sed -n 's/.*: \([^ ]*\) .*/\1/p')
        elif command -v python3 &>/dev/null; then
            charset=$(python3 -c "
import sys
try:
    from chardet import detect
    with open(sys.argv[1], 'rb') as f:
        result = detect(f.read())
    print(result.get('encoding', 'unknown') or 'unknown')
except Exception:
    print('unknown')
" "$arquivo" 2>/dev/null)
        fi
    fi

    echo "${charset:-unknown}"
}

__enc_detectar_bom() {
    local arquivo="$1"
    local header
    header=$(head -c 3 "$arquivo" 2>/dev/null | xxd -p 2>/dev/null)

    case "$header" in
        efbbbf*) echo "UTF-8-BOM" ;;
        fffe*)   echo "UTF-16LE-BOM" ;;
        feff*)   echo "UTF-16BE-BOM" ;;
        *)       echo "nenhum" ;;
    esac
}

__enc_detectar_line_ending() {
    local arquivo="$1"

    if head -c 8192 "$arquivo" 2>/dev/null | grep -qP '\r\n'; then
        echo "CRLF"
    elif head -c 8192 "$arquivo" 2>/dev/null | grep -qP '\r[^\n]'; then
        echo "CR"
    else
        echo "LF"
    fi
}

__enc_backup() {
    local arquivo="$1"
    local no_backup="$2"
    [[ "$no_backup" == "true" ]] && return 0
    cp "$arquivo" "${arquivo}.bak" 2>/dev/null
}

__enc_remover_bom() {
    local arquivo="$1"
    local bom=$(__enc_detectar_bom "$arquivo")

    if [[ "$bom" == "UTF-8-BOM" ]]; then
        sed -i '1s/^\xEF\xBB\xBF//' "$arquivo" 2>/dev/null
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Funções públicas
# ---------------------------------------------------------------------------

# Propósito: Detectar encoding, BOM e line ending de arquivo/diretório
# Uso: enc_detectar <alvo>
# Completa:
#   <alvo>=_files
enc_detectar() {
    local alvo="$1"

    if [[ -z "$alvo" ]]; then
        __err "Uso: enc_detectar <arquivo|diretório>"
        return 1
    fi

    if [[ ! -e "$alvo" ]]; then
        __err "Não encontrado: $alvo"
        return 1
    fi

    __header "DETECÇÃO DE ENCODING" "$D_ORANGE"

    echo -e "  ${D_COMMENT}Mapa de referência:${D_RESET}"
    echo -e "  ${D_FG}  CP1252     = \"ANSI\" do Windows (português, caracteres 0x80-0x9F)${D_RESET}"
    echo -e "  ${D_FG}  ISO-8859-1 = Latin-1 (similar ao CP1252, sem 0x80-0x9F)${D_RESET}"
    echo -e "  ${D_FG}  UTF-8      = Padrão Linux (suporta todo Unicode)${D_RESET}"
    echo -e "  ${D_FG}  UTF-8-BOM  = UTF-8 com 3 bytes iniciais EF BB BF${D_RESET}"
    echo -e "  ${D_FG}  UTF-16LE   = Arquivos de sistema Windows (.reg, PowerShell)${D_RESET}"
    echo -e "  ${D_FG}  ASCII      = 7-bit puro (sem acentos)${D_RESET}"
    echo ""

    __enc_analisar_arquivo() {
        local arquivo="$1"
        local nome_exibicao="${2:-$arquivo}"

        if __enc_eh_binario "$arquivo"; then
            return 0
        fi

        local encoding=$(__enc_detectar_encoding "$arquivo")
        local bom=$(__enc_detectar_bom "$arquivo")
        local line_ending=$(__enc_detectar_line_ending "$arquivo")

        local cor_enc="$D_GREEN"
        [[ "$encoding" != "utf-8" && "$encoding" != "us-ascii" && "$encoding" != "ascii" ]] && cor_enc="$D_YELLOW"

        local cor_bom="$D_GREEN"
        [[ "$bom" != "nenhum" ]] && cor_bom="$D_YELLOW"

        local cor_le="$D_GREEN"
        [[ "$line_ending" != "LF" ]] && cor_le="$D_YELLOW"

        printf "  ${D_FG}%-40s${D_RESET} " "${nome_exibicao:0:40}"
        printf "${cor_enc}%-12s${D_RESET} " "$encoding"
        printf "${cor_bom}%-12s${D_RESET} " "$bom"
        printf "${cor_le}%-4s${D_RESET}\n" "$line_ending"
    }

    printf "  ${D_PURPLE}%-40s %-12s %-12s %-4s${D_RESET}\n" "ARQUIVO" "ENCODING" "BOM" "EOL"
    printf "  ${D_COMMENT}%s${D_RESET}\n" "$(printf '%.0s─' {1..70})"

    if [[ -f "$alvo" ]]; then
        __enc_analisar_arquivo "$alvo" "$(basename "$alvo")"
    elif [[ -d "$alvo" ]]; then
        local contagem=0
        local problemas=0

        while IFS= read -r arquivo; do
            __enc_em_dir_ignorado "$arquivo" && continue
            __enc_eh_binario "$arquivo" && continue

            local ext="${arquivo##*.}"
            local exts_validas=$(__enc_extensoes_texto)
            [[ ! "$ext" =~ ^(${exts_validas})$ ]] && continue

            local relativo="${arquivo#$alvo/}"
            __enc_analisar_arquivo "$arquivo" "$relativo"
            ((contagem++))

            local enc=$(__enc_detectar_encoding "$arquivo")
            local bom=$(__enc_detectar_bom "$arquivo")
            local le=$(__enc_detectar_line_ending "$arquivo")
            [[ "$enc" != "utf-8" && "$enc" != "us-ascii" && "$enc" != "ascii" ]] && ((problemas++))
            [[ "$bom" != "nenhum" ]] && ((problemas++))
            [[ "$le" != "LF" ]] && ((problemas++))
        done < <(find "$alvo" -type f | sort)

        echo ""
        __ok "${contagem} arquivo(s) analisado(s)"
    fi

    echo ""
    unfunction __enc_analisar_arquivo 2>/dev/null
}

# Propósito: Converter encoding de arquivo (auto-detecta origem se omitida)
# Uso: enc_converter <arquivo> [destino] [origem] [--no-backup]
# Flags: --no-backup=Não cria cópia .bak antes de converter
# Completa:
#   <arquivo>=_files
#   [destino]=__enc_encodings
#   [origem]=__enc_encodings
enc_converter() {
    local arquivo="$1"
    local destino="${2:-utf-8}"
    local origem="$3"
    local no_backup=false

    for arg in "$@"; do
        [[ "$arg" == "--no-backup" ]] && no_backup=true
    done

    if [[ -z "$arquivo" || ! -f "$arquivo" ]]; then
        __err "Uso: enc_converter <arquivo> [destino] [origem]"
        return 1
    fi

    if __enc_eh_binario "$arquivo"; then
        __err "Arquivo binário, conversão ignorada: $arquivo"
        return 1
    fi

    if [[ -z "$origem" ]]; then
        origem=$(__enc_detectar_encoding "$arquivo")
    fi

    if [[ "$origem" == "unknown" ]]; then
        __err "Encoding de origem não detectado para: $arquivo"
        return 1
    fi

    local origem_upper="${origem:u}"
    local destino_upper="${destino:u}"

    if [[ "$origem_upper" == "$destino_upper" || "$origem_upper" == "UTF-8" && "$destino_upper" == "UTF-8" ]]; then
        __ok "Arquivo já está em ${destino_upper}: $arquivo"
        return 0
    fi

    __enc_backup "$arquivo" "$no_backup"

    local temp_file=$(mktemp)
    if iconv -f "$origem" -t "${destino_upper}//TRANSLIT" "$arquivo" > "$temp_file" 2>/dev/null; then
        mv "$temp_file" "$arquivo"
        __ok "Convertido ${origem_upper} -> ${destino_upper}: $(basename "$arquivo")"
    else
        rm -f "$temp_file"
        __err "Falha na conversão de $(basename "$arquivo")"
        return 1
    fi
}

# Propósito: Remover BOM de arquivos UTF-8
# Uso: enc_fixar_bom <alvo> [--no-backup]
# Flags: --no-backup=Não cria .bak antes de remover BOM
# Completa:
#   <alvo>=_files
enc_fixar_bom() {
    local alvo="$1"
    local no_backup=false

    for arg in "$@"; do
        [[ "$arg" == "--no-backup" ]] && no_backup=true
    done

    if [[ -z "$alvo" ]]; then
        __err "Uso: enc_fixar_bom <arquivo|diretório>"
        return 1
    fi

    __header "REMOVER BOM" "$D_ORANGE"

    local removidos=0

    __enc_processar_bom() {
        local arquivo="$1"
        __enc_eh_binario "$arquivo" && return
        __enc_em_dir_ignorado "$arquivo" && return

        local bom=$(__enc_detectar_bom "$arquivo")
        if [[ "$bom" != "nenhum" ]]; then
            __enc_backup "$arquivo" "$no_backup"
            __enc_remover_bom "$arquivo"
            __ok "BOM removido: $(basename "$arquivo")"
            ((removidos++))
        fi
    }

    if [[ -f "$alvo" ]]; then
        __enc_processar_bom "$alvo"
    elif [[ -d "$alvo" ]]; then
        while IFS= read -r arquivo; do
            __enc_em_dir_ignorado "$arquivo" && continue
            __enc_processar_bom "$arquivo"
        done < <(find "$alvo" -type f)
    fi

    if [[ $removidos -eq 0 ]]; then
        __ok "Nenhum BOM encontrado"
    else
        __ok "${removidos} arquivo(s) corrigido(s)"
    fi
    echo ""

    unfunction __enc_processar_bom 2>/dev/null
}

# Propósito: Converter line endings (CRLF<->LF)
# Uso: enc_fixar_crlf <alvo> [--para-windows] [--no-backup]
# Flags: --para-windows=Converte LF->CRLF (padrão é CRLF->LF)
#        --no-backup=Não cria .bak antes de converter
# Completa:
#   <alvo>=_files
enc_fixar_crlf() {
    local alvo="$1"
    local para_windows=false
    local no_backup=false

    for arg in "$@"; do
        case "$arg" in
            --para-windows) para_windows=true ;;
            --no-backup) no_backup=true ;;
        esac
    done

    if [[ -z "$alvo" ]]; then
        __err "Uso: enc_fixar_crlf <arquivo|diretório> [--para-windows] [--no-backup]"
        return 1
    fi

    local direcao="CRLF -> LF"
    [[ "$para_windows" == true ]] && direcao="LF -> CRLF"

    __header "CONVERTER LINE ENDINGS ($direcao)" "$D_ORANGE"

    local convertidos=0

    __enc_processar_crlf() {
        local arquivo="$1"
        __enc_eh_binario "$arquivo" && return
        __enc_em_dir_ignorado "$arquivo" && return

        local le=$(__enc_detectar_line_ending "$arquivo")

        if [[ "$para_windows" == true && "$le" == "LF" ]]; then
            __enc_backup "$arquivo" "$no_backup"
            if command -v unix2dos &>/dev/null; then
                unix2dos -q "$arquivo" 2>/dev/null
            else
                sed -i 's/$/\r/' "$arquivo" 2>/dev/null
            fi
            __ok "LF -> CRLF: $(basename "$arquivo")"
            ((convertidos++))
        elif [[ "$para_windows" == false && "$le" == "CRLF" ]]; then
            __enc_backup "$arquivo" "$no_backup"
            if command -v dos2unix &>/dev/null; then
                dos2unix -q "$arquivo" 2>/dev/null
            else
                sed -i 's/\r$//' "$arquivo" 2>/dev/null
            fi
            __ok "CRLF -> LF: $(basename "$arquivo")"
            ((convertidos++))
        fi
    }

    if [[ -f "$alvo" ]]; then
        __enc_processar_crlf "$alvo"
    elif [[ -d "$alvo" ]]; then
        while IFS= read -r arquivo; do
            __enc_em_dir_ignorado "$arquivo" && continue
            __enc_processar_crlf "$arquivo"
        done < <(find "$alvo" -type f)
    fi

    if [[ $convertidos -eq 0 ]]; then
        __ok "Nenhuma conversão necessária"
    else
        __ok "${convertidos} arquivo(s) convertido(s)"
    fi
    echo ""

    unfunction __enc_processar_crlf 2>/dev/null
}

# Propósito: Normalizar scripts Python (shebang, coding, BOM, CRLF, chmod)
# Uso: enc_fixar_python <alvo> [--no-backup]
# Flags: --no-backup=Não cria .bak antes de editar
# Completa:
#   <alvo>=_files
enc_fixar_python() {
    local alvo="$1"
    local no_backup=false

    for arg in "$@"; do
        [[ "$arg" == "--no-backup" ]] && no_backup=true
    done

    if [[ -z "$alvo" ]]; then
        __err "Uso: enc_fixar_python <arquivo|diretório> [--no-backup]"
        return 1
    fi

    __header "CORRIGIR SCRIPTS PYTHON" "$D_ORANGE"
    echo -e "  ${D_COMMENT}Operações: remover BOM, CRLF->LF, shebang, coding, chmod${D_RESET}"
    echo ""

    local corrigidos=0
    local avisos=0

    __enc_fixar_py_arquivo() {
        local arquivo="$1"
        local nome=$(basename "$arquivo")
        local alterado=false

        __enc_eh_binario "$arquivo" && return
        __enc_em_dir_ignorado "$arquivo" && return
        [[ "${arquivo##*.}" != "py" ]] && return

        __enc_backup "$arquivo" "$no_backup"

        local bom=$(__enc_detectar_bom "$arquivo")
        if [[ "$bom" == "UTF-8-BOM" ]]; then
            __enc_remover_bom "$arquivo"
            echo -e "    ${D_GREEN}BOM removido${D_RESET}: $nome"
            alterado=true
        fi

        local le=$(__enc_detectar_line_ending "$arquivo")
        if [[ "$le" == "CRLF" ]]; then
            if command -v dos2unix &>/dev/null; then
                dos2unix -q "$arquivo" 2>/dev/null
            else
                sed -i 's/\r$//' "$arquivo" 2>/dev/null
            fi
            echo -e "    ${D_GREEN}CRLF -> LF${D_RESET}: $nome"
            alterado=true
        fi

        local linha1
        linha1=$(head -1 "$arquivo" 2>/dev/null)
        if [[ "$linha1" != "#!/usr/bin/env python3" && "$linha1" != "#!"* ]]; then
            sed -i '1i#!/usr/bin/env python3' "$arquivo" 2>/dev/null
            echo -e "    ${D_GREEN}Shebang adicionado${D_RESET}: $nome"
            alterado=true
        elif [[ "$linha1" == "#!"*"python3"* && "$linha1" != "#!/usr/bin/env python3" ]]; then
            sed -i "1s|.*|#!/usr/bin/env python3|" "$arquivo" 2>/dev/null
            echo -e "    ${D_GREEN}Shebang corrigido${D_RESET}: $nome"
            alterado=true
        fi

        if grep -qP '[^\x00-\x7F]' "$arquivo" 2>/dev/null; then
            if ! head -3 "$arquivo" | grep -q 'coding' 2>/dev/null; then
                local shebang_line
                shebang_line=$(head -1 "$arquivo")
                if [[ "$shebang_line" == "#!"* ]]; then
                    sed -i '1a# -*- coding: utf-8 -*-' "$arquivo" 2>/dev/null
                else
                    sed -i '1i# -*- coding: utf-8 -*-' "$arquivo" 2>/dev/null
                fi
                echo -e "    ${D_GREEN}Coding header adicionado${D_RESET}: $nome"
                alterado=true
            fi
        fi

        if [[ ! -x "$arquivo" ]]; then
            chmod +x "$arquivo" 2>/dev/null
            echo -e "    ${D_GREEN}Permissão +x${D_RESET}: $nome"
            alterado=true
        fi

        local open_sem_encoding
        open_sem_encoding=$(grep -nP 'open\s*\(' "$arquivo" 2>/dev/null | grep -v 'encoding' | grep -v '#.*open' | head -5)
        if [[ -n "$open_sem_encoding" ]]; then
            echo -e "    ${D_YELLOW}Aviso: open() sem encoding=${D_RESET}: $nome"
            echo "$open_sem_encoding" | while IFS= read -r linha; do
                echo -e "      ${D_COMMENT}${linha}${D_RESET}"
            done
            ((avisos++))
        fi

        [[ "$alterado" == true ]] && ((corrigidos++))
    }

    if [[ -f "$alvo" ]]; then
        __enc_fixar_py_arquivo "$alvo"
    elif [[ -d "$alvo" ]]; then
        while IFS= read -r arquivo; do
            __enc_em_dir_ignorado "$arquivo" && continue
            __enc_fixar_py_arquivo "$arquivo"
        done < <(find "$alvo" -name "*.py" -type f | sort)
    fi

    echo ""
    if [[ $corrigidos -eq 0 && $avisos -eq 0 ]]; then
        __ok "Todos os scripts Python estão em ordem"
    else
        [[ $corrigidos -gt 0 ]] && __ok "${corrigidos} script(s) corrigido(s)"
        [[ $avisos -gt 0 ]] && __warn "${avisos} script(s) com open() sem encoding (verifique manualmente)"
    fi
    echo ""

    unfunction __enc_fixar_py_arquivo 2>/dev/null
}

# Propósito: Conversão em lote (encoding + BOM + CRLF + scripts Python)
# Uso: enc_lote <diretorio> [--perfil windows-para-linux|linux-para-windows] [--dry-run] [--no-backup]
# Flags: --perfil=Perfil de conversão (default: windows-para-linux)
#        --dry-run=Apenas lista, não altera nada
#        --no-backup=Não cria .bak antes de converter
# Completa:
#   <diretorio>=_path_files -/
enc_lote() {
    local dir="$1"
    local perfil="windows-para-linux"
    local dry_run=false
    local no_backup=false

    for arg in "$@"; do
        case "$arg" in
            --perfil) ;;
            windows-para-linux|linux-para-windows) perfil="$arg" ;;
            --dry-run) dry_run=true ;;
            --no-backup) no_backup=true ;;
        esac
    done

    if [[ -z "$dir" || ! -d "$dir" ]]; then
        __err "Uso: enc_lote <diretório> [--perfil windows-para-linux|linux-para-windows] [--dry-run]"
        return 1
    fi

    __header "CONVERSÃO EM LOTE" "$D_ORANGE"
    echo -e "  ${D_COMMENT}Diretório: ${D_FG}${dir}${D_RESET}"
    echo -e "  ${D_COMMENT}Perfil:    ${D_FG}${perfil}${D_RESET}"
    [[ "$dry_run" == true ]] && echo -e "  ${D_YELLOW}Modo dry-run — nenhum arquivo será alterado${D_RESET}"
    echo ""

    local extensoes=$(__enc_extensoes_texto)
    local total=0 problemas=0

    if [[ "$perfil" == "windows-para-linux" ]]; then
        echo -e "  ${D_PURPLE}${D_BOLD}Operações:${D_RESET}"
        echo -e "    ${D_FG}1. Converter CP1252/Latin-1 -> UTF-8${D_RESET}"
        echo -e "    ${D_FG}2. Remover BOM${D_RESET}"
        echo -e "    ${D_FG}3. Converter CRLF -> LF${D_RESET}"
        echo -e "    ${D_FG}4. Corrigir scripts Python${D_RESET}"
        echo ""

        while IFS= read -r arquivo; do
            __enc_em_dir_ignorado "$arquivo" && continue
            __enc_eh_binario "$arquivo" && continue

            local ext="${arquivo##*.}"
            [[ ! "$ext" =~ ^(${extensoes})$ ]] && continue

            local relativo="${arquivo#$dir/}"
            local enc=$(__enc_detectar_encoding "$arquivo")
            local bom=$(__enc_detectar_bom "$arquivo")
            local le=$(__enc_detectar_line_ending "$arquivo")
            local problemas_arquivo=()

            local enc_upper="${enc:u}"
            if [[ "$enc_upper" == "WINDOWS-1252" || "$enc_upper" == "CP1252" || "$enc_upper" == "ISO-8859-1" ]]; then
                problemas_arquivo+=("encoding:${enc}")
            fi
            [[ "$bom" != "nenhum" ]] && problemas_arquivo+=("bom:${bom}")
            [[ "$le" == "CRLF" ]] && problemas_arquivo+=("eol:CRLF")

            if [[ ${#problemas_arquivo[@]} -gt 0 ]]; then
                ((problemas++))
                echo -e "  ${D_YELLOW}${relativo}${D_RESET}"
                for p in "${problemas_arquivo[@]}"; do
                    echo -e "    ${D_COMMENT}${p}${D_RESET}"
                done

                if [[ "$dry_run" == false ]]; then
                    for p in "${problemas_arquivo[@]}"; do
                        case "${p%%:*}" in
                            encoding)
                                enc_converter "$arquivo" "utf-8" "${p#*:}" --no-backup
                                ;;
                            bom)
                                __enc_remover_bom "$arquivo"
                                ;;
                            eol)
                                if command -v dos2unix &>/dev/null; then
                                    dos2unix -q "$arquivo" 2>/dev/null
                                else
                                    sed -i 's/\r$//' "$arquivo" 2>/dev/null
                                fi
                                ;;
                        esac
                    done
                fi
            fi

            ((total++))
        done < <(find "$dir" -type f | sort)

        if [[ "$dry_run" == false ]]; then
            echo ""
            echo -e "  ${D_PURPLE}${D_BOLD}Corrigindo scripts Python...${D_RESET}"
            while IFS= read -r arquivo; do
                __enc_em_dir_ignorado "$arquivo" && continue
                enc_fixar_python "$arquivo" --no-backup 2>/dev/null
            done < <(find "$dir" -name "*.py" -type f)
        fi

    elif [[ "$perfil" == "linux-para-windows" ]]; then
        echo -e "  ${D_PURPLE}${D_BOLD}Operações:${D_RESET}"
        echo -e "    ${D_FG}1. Converter LF -> CRLF${D_RESET}"
        echo -e "    ${D_FG}2. Adicionar BOM a CSVs (compatibilidade Excel)${D_RESET}"
        echo ""

        while IFS= read -r arquivo; do
            __enc_em_dir_ignorado "$arquivo" && continue
            __enc_eh_binario "$arquivo" && continue

            local ext="${arquivo##*.}"
            [[ ! "$ext" =~ ^(${extensoes})$ ]] && continue

            local relativo="${arquivo#$dir/}"
            local le=$(__enc_detectar_line_ending "$arquivo")

            if [[ "$le" == "LF" ]]; then
                ((problemas++))
                echo -e "  ${D_YELLOW}${relativo}${D_RESET} — LF -> CRLF"

                if [[ "$dry_run" == false ]]; then
                    [[ "$no_backup" == false ]] && __enc_backup "$arquivo" false
                    if command -v unix2dos &>/dev/null; then
                        unix2dos -q "$arquivo" 2>/dev/null
                    else
                        sed -i 's/$/\r/' "$arquivo" 2>/dev/null
                    fi
                fi
            fi

            if [[ "$ext" == "csv" ]]; then
                local bom=$(__enc_detectar_bom "$arquivo")
                if [[ "$bom" == "nenhum" ]]; then
                    echo -e "  ${D_YELLOW}${relativo}${D_RESET} — adicionando BOM (Excel)"
                    if [[ "$dry_run" == false ]]; then
                        [[ "$no_backup" == false ]] && __enc_backup "$arquivo" false
                        local temp_file=$(mktemp)
                        printf '\xEF\xBB\xBF' > "$temp_file"
                        cat "$arquivo" >> "$temp_file"
                        mv "$temp_file" "$arquivo"
                    fi
                fi
            fi

            ((total++))
        done < <(find "$dir" -type f | sort)
    fi

    echo ""
    echo -e "  ${D_COMMENT}Arquivos analisados: ${total}${D_RESET}"
    if [[ $problemas -eq 0 ]]; then
        __ok "Nenhum problema encontrado"
    elif [[ "$dry_run" == true ]]; then
        __warn "${problemas} arquivo(s) com problemas (dry-run, nada alterado)"
    else
        __ok "${problemas} arquivo(s) corrigido(s)"
    fi
    echo ""
}

# "O limite da minha linguagem é o limite do meu mundo." — Ludwig Wittgenstein
