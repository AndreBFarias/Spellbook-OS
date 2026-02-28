#!/bin/zsh

# -- Paleta Dracula (truecolor) --
D_FG="\033[38;2;248;248;242m"
D_BG="\033[38;2;40;42;54m"
D_COMMENT="\033[38;2;98;114;164m"
D_CYAN="\033[38;2;139;233;253m"
D_GREEN="\033[38;2;80;250;123m"
D_ORANGE="\033[38;2;255;184;108m"
D_PINK="\033[38;2;255;121;198m"
D_PURPLE="\033[38;2;189;147;249m"
D_RED="\033[38;2;255;85;85m"
D_YELLOW="\033[38;2;241;250;140m"
D_RESET="\033[0m"
D_BOLD="\033[1m"
D_DIM="\033[2m"

# -- Compat: aliases antigos para nao quebrar nada --
C_VERDE="$D_GREEN"
C_VERMELHO="$D_RED"
C_AMARELO="$D_YELLOW"
C_AZUL="$D_PURPLE"
C_MAGENTA="$D_PINK"
C_CYAN="$D_CYAN"
C_NORMAL="$D_RESET"

# -- Diretorio de desenvolvimento (portavel entre maquinas) --
export DEV_DIR="${DEV_DIR:-$HOME/Desenvolvimento}"

# -- Helpers de formatacao --
__header() {
    local titulo="$1"
    local cor="${2:-$D_PURPLE}"
    echo ""
    echo -e "${cor}${D_BOLD}  $titulo${D_RESET}"
    echo -e "${D_COMMENT}  $(printf '%.0s─' {1..48})${D_RESET}"
}

__item() {
    local label="$1"
    local value="$2"
    local cor_label="${3:-$D_COMMENT}"
    local cor_value="${4:-$D_FG}"
    printf "  ${cor_label}%-12s${D_RESET} ${cor_value}%s${D_RESET}\n" "$label" "$value"
}

__ok()   { echo -e "  ${D_GREEN}[OK]${D_RESET} $1"; }
__warn() { echo -e "  ${D_YELLOW}[!]${D_RESET} $1"; }
__err()  { echo -e "  ${D_RED}[ERRO]${D_RESET} $1" >&2; }

# -- Verificacao de dependencias --
__verificar_dependencias() {
    local ferramentas_faltantes=()
    for ferramenta in "$@"; do
        if ! command -v "$ferramenta" &> /dev/null; then
            ferramentas_faltantes+=("$ferramenta")
        fi
    done
    if [ ${#ferramentas_faltantes[@]} -gt 0 ]; then
        __warn "Ferramentas nao encontradas: ${ferramentas_faltantes[*]}"
        echo "  Instalando via apt..." >&2
        if sudo apt update -qq && sudo apt install -y -qq "${ferramentas_faltantes[@]}"; then
            __ok "Instalado com sucesso." >&2
        else
            __err "Falha ao instalar. Abortando." >&2
            return 1
        fi
    fi
    return 0
}

__verificar_dependencias_python() {
    local PYTHON_EXEC="$1"; shift
    if ! command -v "$PYTHON_EXEC" &> /dev/null; then
        __err "Python '$PYTHON_EXEC' nao encontrado."
        return 1
    fi
    if ! "$PYTHON_EXEC" -m pip --version >/dev/null 2>&1; then
        __err "pip nao disponivel em '$PYTHON_EXEC'. Rode: sudo apt install python3-pip"
        return 1
    fi
    local pacotes_instalados=$($PYTHON_EXEC -m pip list 2>/dev/null)
    local pacotes_faltantes=()
    for pacote in "$@"; do
        if ! echo "$pacotes_instalados" | grep -i "^${pacote}[[:space:]]" > /dev/null; then
            pacotes_faltantes+=("$pacote")
        fi
    done
    if [ ${#pacotes_faltantes[@]} -gt 0 ]; then
        __warn "Libs Python faltantes: ${pacotes_faltantes[*]}"
        if "$PYTHON_EXEC" -m pip install -q "${pacotes_faltantes[@]}"; then
            __ok "Instalado." >&2
        else
            __err "Falha ao instalar libs Python." >&2
            return 1
        fi
    fi
    return 0
}

__preparar_ambiente_python() {
    local VENV_PATH="$1"
    if [ ! -d "$VENV_PATH" ]; then
        echo "  Criando venv em '$VENV_PATH'..." >&2
        if ! python3 -m venv "$VENV_PATH" &>/dev/null; then
            __warn "python3-venv ausente. Instalando..." >&2
            if sudo apt update -qq && sudo apt install -y -qq python3-venv; then
                python3 -m venv "$VENV_PATH" || { __err "Falha ao criar venv."; return 1; }
            else
                __err "Falha ao instalar python3-venv."; return 1
            fi
        fi
    fi
    local PYTHON_EXEC="$VENV_PATH/bin/python"
    __verificar_dependencias_python "$PYTHON_EXEC" "pandas" "openpyxl" "tabulate" "pyarrow" >&2 || return 1
    echo "$PYTHON_EXEC"
}
