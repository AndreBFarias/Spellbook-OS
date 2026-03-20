#!/usr/bin/env bash
# install.sh — Instalador do ambiente zsh com TUI whiptail
# Uso: bash install.sh [--update] [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZDOTDIR_TARGET="${HOME}/.config/zsh"
DRY_RUN=false
IS_UPDATE=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --update)  IS_UPDATE=true ;;
    esac
done

# --- Paleta Dracula para whiptail (NEWT_COLORS) ---
export NEWT_COLORS='
root=white,black
window=white,black
border=lightcyan,black
shadow=black,black
title=white,black
button=black,white
actbutton=black,lightcyan
checkbox=white,black
actcheckbox=black,lightcyan
entry=white,black
label=white,black
listbox=white,black
actlistbox=black,lightcyan
textbox=white,black
acttextbox=lightcyan,black
helpline=white,black
roottext=lightcyan,black
emptyscale=black,black
fullscale=lightcyan,black
disentry=cyan,black
compactbutton=white,black
actsellistbox=black,lightcyan
sellistbox=lightcyan,black
'

# --- Utilitários ---
_run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

_C_PURPLE='\033[0;35m'
_C_GREEN='\033[0;32m'
_C_YELLOW='\033[0;33m'
_C_RED='\033[0;31m'
_C_CYAN='\033[0;36m'
_C_DIM='\033[2m'
_C_BOLD='\033[1m'
_C_RESET='\033[0m'

_info()  { echo -e "  ${_C_CYAN}>>${_C_RESET} $*"; }
_ok()    { echo -e "  ${_C_GREEN}OK${_C_RESET}  $*"; }
_warn()  { echo -e "  ${_C_YELLOW}!!${_C_RESET} $*" >&2; }
_err()   { echo -e "  ${_C_RED}ERRO${_C_RESET} $*" >&2; exit 1; }

TOTAL_STEPS=15
CURRENT_STEP=0
_EXISTING_CONFIG=false

_step() {
    ((++CURRENT_STEP))
    local desc="$1"
    echo ""
    echo -e "  ${_C_PURPLE}${_C_BOLD}[${CURRENT_STEP}/${TOTAL_STEPS}]${_C_RESET} ${desc}"
    echo -e "  ${_C_DIM}$(printf '%.0s─' {1..48})${_C_RESET}"
}

# --- Detecção de gestor de pacotes ---
_detect_pkg_manager() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v pacman &>/dev/null; then echo "pacman"
    elif command -v brew &>/dev/null;   then echo "brew"
    else echo "unknown"; fi
}

_install_pkg() {
    local pkg="$1"
    local mgr
    mgr=$(_detect_pkg_manager)

    if command -v "$pkg" &>/dev/null; then
        _ok "$pkg já instalado"
        return 0
    fi

    _info "Instalando $pkg..."
    case "$mgr" in
        apt)    _run sudo apt-get install -y "$pkg" ;;
        pacman) _run sudo pacman -S --noconfirm "$pkg" ;;
        brew)   _run brew install "$pkg" ;;
        *)      _warn "Gestor de pacotes não detectado. Instale $pkg manualmente."; return 1 ;;
    esac
}

# --- TUI: whiptail → dialog → read puro ---
_tui_available() {
    command -v whiptail &>/dev/null && echo "whiptail" && return
    command -v dialog   &>/dev/null && echo "dialog"   && return
    echo "plain"
}

_tui() { _tui_available; }

_inputbox() {
    local title="$1" label="$2" default="$3"
    local tui display_label result
    tui=$(_tui)

    if [[ -n "$default" ]]; then
        display_label="${label}\n\nAtual: ${default}\n(deixe vazio para manter)"
    else
        display_label="$label"
    fi

    case "$tui" in
        whiptail|dialog)
            result=$("$tui" --title "$title" --backtitle "Spellbook-OS" \
                --cancel-button "Voltar" \
                --inputbox "$display_label" 12 65 "" 3>&1 1>&2 2>&3) || return 1
            ;;
        plain)
            if [[ -n "$default" ]]; then
                printf "  %s [%s]: " "$label" "$default" >&2
            else
                printf "  %s: " "$label" >&2
            fi
            read -r result
            ;;
    esac

    if [[ -z "$result" && -n "$default" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}

_yesno() {
    local title="$1" question="$2" defaultno="${3:-}"
    local tui extra_flags=""
    tui=$(_tui)

    [[ "$defaultno" == "defaultno" ]] && extra_flags="--defaultno"

    case "$tui" in
        whiptail|dialog)
            "$tui" --title "$title" --backtitle "Spellbook-OS" \
                $extra_flags --yesno "$question" 10 65 3>&1 1>&2 2>&3
            return $?
            ;;
        plain)
            local hint="s/N"
            [[ -z "$defaultno" ]] && hint="S/n"
            printf "  %s (%s): " "$question" "$hint" >&2
            local val
            read -r val
            if [[ -n "$defaultno" ]]; then
                [[ "$val" == "s" || "$val" == "S" || "$val" == "y" || "$val" == "Y" ]]
            else
                [[ -z "$val" || "$val" == "s" || "$val" == "S" || "$val" == "y" || "$val" == "Y" ]]
            fi
            return $?
            ;;
    esac
}

_checklist() {
    local title="$1"; shift
    local question="$1"; shift
    local tui
    tui=$(_tui)

    case "$tui" in
        whiptail|dialog)
            "$tui" --title "$title" --backtitle "Spellbook-OS" \
                --cancel-button "Voltar" \
                --checklist "$question" 20 65 10 "$@" 3>&1 1>&2 2>&3 || return 1
            ;;
        plain)
            echo "  $question" >&2
            local i=1 result=""
            while [[ $# -ge 3 ]]; do
                local tag="$1" desc="$2" state="$3"
                shift 3
                local default_hint
                if [[ "$state" == "on" ]]; then
                    default_hint="S/n"
                else
                    default_hint="s/N"
                fi
                printf "  [%d] %s - %s (%s): " "$i" "$tag" "$desc" "$default_hint" >&2
                local val
                read -r val
                if [[ "$state" == "on" ]]; then
                    if [[ -z "$val" || "$val" == "s" || "$val" == "S" || "$val" == "y" || "$val" == "Y" ]]; then
                        result="$result \"$tag\""
                    fi
                else
                    if [[ "$val" == "s" || "$val" == "S" || "$val" == "y" || "$val" == "Y" ]]; then
                        result="$result \"$tag\""
                    fi
                fi
                ((i++))
            done
            echo "$result"
            ;;
    esac
}

_msgbox() {
    local title="$1" msg="$2"
    local tui
    tui=$(_tui)

    case "$tui" in
        whiptail|dialog)
            "$tui" --title "$title" --backtitle "Spellbook-OS" --msgbox "$msg" 20 70
            ;;
        plain)
            echo ""
            echo "  === $title ==="
            echo "$msg"
            echo ""
            ;;
    esac
}

_tui_sim_nao() {
    local title="$1" question="$2" tui result
    tui=$(_tui)
    case "$tui" in
        whiptail|dialog)
            result=$("$tui" --title "$title" --backtitle "Spellbook-OS" \
                --cancel-button "Voltar" --notags \
                --menu "$question" 12 65 2 \
                "sim" "Sim" "nao" "Não" 3>&1 1>&2 2>&3) || return 2
            [[ "$result" == "sim" ]] && return 0 || return 1 ;;
        plain)
            printf "  %s (S/n/v=voltar): " "$question" >&2
            local val; read -r val
            case "$val" in v|V) return 2 ;; n|N) return 1 ;; *) return 0 ;; esac ;;
    esac
}

# --- Etapa 1: Dependências do sistema ---
_step_deps() {
    _step "Verificando dependências"

    local pkgs=(zsh fzf git python3-pip rsync tree jq pv)

    local mgr
    mgr=$(_detect_pkg_manager)
    if [[ "$mgr" == "apt" ]]; then
        pkgs+=(whiptail)
    fi

    for pkg in "${pkgs[@]}"; do
        _install_pkg "$pkg" || _warn "Falha ao instalar $pkg — continue manualmente"
    done

    if command -v pip3 &>/dev/null; then
        _info "Instalando dependências Python..."
        local pip_flags="--quiet"
        [[ -z "${VIRTUAL_ENV:-}" ]] && pip_flags="--user $pip_flags"
        if [[ -f "$SCRIPT_DIR/requirements.txt" ]]; then
            _run pip3 install $pip_flags -r "$SCRIPT_DIR/requirements.txt"
        else
            _run pip3 install $pip_flags pandas openpyxl
        fi
        _ok "Python deps instaladas"
    fi
}

# --- Etapa 2: Oh My Zsh + plugins ---
_step_omz() {
    _step "Oh My Zsh + plugins"

    local omz_dir="$ZDOTDIR_TARGET/.oh-my-zsh"

    if [[ -d "$omz_dir" ]]; then
        _ok "Oh My Zsh já instalado"
    else
        _info "Instalando Oh My Zsh..."
        _run env ZSH="$omz_dir" RUNZSH=no CHSH=no \
            sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        _ok "Oh My Zsh instalado em $omz_dir"
    fi

    local plugins_dir="$omz_dir/custom/plugins"

    _install_omz_plugin() {
        local name="$1" url="$2"
        local dest="$plugins_dir/$name"
        if [[ -d "$dest" ]]; then
            _ok "Plugin $name já instalado"
        else
            _info "Instalando plugin $name..."
            _run git clone --depth=1 "$url" "$dest"
            _ok "Plugin $name instalado"
        fi
    }

    _install_omz_plugin "zsh-autosuggestions" \
        "https://github.com/zsh-users/zsh-autosuggestions"
    _install_omz_plugin "zsh-syntax-highlighting" \
        "https://github.com/zsh-users/zsh-syntax-highlighting"
    _install_omz_plugin "zsh-history-substring-search" \
        "https://github.com/zsh-users/zsh-history-substring-search"
}

# --- Helpers de detecção ---
_detect_git_identity() {
    _DETECTED_GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
    _DETECTED_GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"
}

_parse_config_value() {
    local key="$1" file="$2"
    sed -n "s/^export ${key}=\"\(.*\)\"/\1/p" "$file" 2>/dev/null | head -1
}

_detect_existing_config() {
    local config_file="$ZDOTDIR_TARGET/config.local.zsh"
    _EXISTING_CONFIG=false
    [[ -f "$config_file" ]] || return 1

    local name_val email_val
    name_val=$(_parse_config_value "ZSH_GIT_NAME_PESSOAL" "$config_file")
    email_val=$(_parse_config_value "ZSH_GIT_EMAIL_PESSOAL" "$config_file")

    if [[ -n "$name_val" && "$name_val" != "SeuNome" \
       && -n "$email_val" && "$email_val" != "voce@email.com" ]]; then
        _EXISTING_CONFIG=true
        _EXISTING_GIT_NAME="$name_val"
        _EXISTING_GIT_EMAIL="$email_val"
        _EXISTING_GIT_NAME_MEC=$(_parse_config_value "ZSH_GIT_NAME_MEC" "$config_file")
        _EXISTING_GIT_EMAIL_MEC=$(_parse_config_value "ZSH_GIT_EMAIL_MEC" "$config_file")
        _EXISTING_DEV_DIR=$(_parse_config_value "DEV_DIR" "$config_file")
        _EXISTING_MEC_ROOT=$(_parse_config_value "MEC_ROOT" "$config_file")
        _EXISTING_REMOTE_HOST=$(_parse_config_value "ZSH_REMOTE_HOST" "$config_file")
        _EXISTING_REMOTE_USER=$(_parse_config_value "ZSH_REMOTE_USER" "$config_file")
        return 0
    fi
    return 1
}

# --- Etapa 3: TUI — coletar configuração do usuário ---
_step_tui() {
    _step "Configuração interativa"
    if [[ "$DRY_RUN" == true ]]; then
        _TUI_GIT_NAME="SeuNome"
        _TUI_GIT_EMAIL="voce@email.com"
        _TUI_GIT_NAME_MEC=""
        _TUI_GIT_EMAIL_MEC=""
        _TUI_DEV_DIR="\${HOME}/Desenvolvimento"
        _TUI_MEC_ROOT="\${HOME}/Desenvolvimento/MEC/pipelines-main"
        _TUI_REMOTE_HOST=""
        _TUI_REMOTE_USER=""
        _TUI_FEATURES='"mec_tools"'
        _info "Usando valores padrão (dry-run)"
        return 0
    fi
    _detect_git_identity
    _detect_existing_config || true
    # Config existente com valores reais → pular TUI
    if [[ "$_EXISTING_CONFIG" == true ]]; then
        _TUI_GIT_NAME="$_EXISTING_GIT_NAME"
        _TUI_GIT_EMAIL="$_EXISTING_GIT_EMAIL"
        _TUI_GIT_NAME_MEC="${_EXISTING_GIT_NAME_MEC:-}"
        _TUI_GIT_EMAIL_MEC="${_EXISTING_GIT_EMAIL_MEC:-}"
        _TUI_DEV_DIR="${_EXISTING_DEV_DIR:-\${HOME}/Desenvolvimento}"
        _TUI_MEC_ROOT="${_EXISTING_MEC_ROOT:-\${HOME}/Desenvolvimento/MEC/pipelines-main}"
        _TUI_REMOTE_HOST="${_EXISTING_REMOTE_HOST:-}"
        _TUI_REMOTE_USER="${_EXISTING_REMOTE_USER:-}"
        _TUI_FEATURES='"mec_tools"'
        _ok "Configuração existente detectada — preservando valores"
        _info "Para reconfigurar, remova config.local.zsh e execute novamente"
        return 0
    fi
    local git_name="" git_email="" git_name_mec="" git_email_mec=""
    local dev_dir="" mec_root="" remote_host="" remote_user="" features=""
    local detected_name="${_DETECTED_GIT_NAME:-}" detected_email="${_DETECTED_GIT_EMAIL:-}"
    local detected_mec_name="${ZSH_GIT_NAME_MEC:-}" detected_mec_email="${ZSH_GIT_EMAIL_MEC:-}" _cf="$ZDOTDIR_TARGET/config.local.zsh"
    [[ -z "$detected_mec_name" && -f "$_cf" ]] && { detected_mec_name=$(_parse_config_value "ZSH_GIT_NAME_MEC" "$_cf")
        detected_mec_email=$(_parse_config_value "ZSH_GIT_EMAIL_MEC" "$_cf"); }
    local tui_step=1 rc=0
    while [[ $tui_step -le 6 ]]; do
    case $tui_step in
    1) # Boas-vindas
        _msgbox "Instalador Spellbook-OS" \
"O que será configurado:

  - Dependências do sistema (zsh, fzf, git, jq, pv...)
  - Oh My Zsh + plugins (autosuggestions, syntax-highlighting)
  - Configuração local (~/.config/zsh/config.local.zsh)
  - Entrada ZDOTDIR no ~/.zshenv

Pressione OK para continuar."
        tui_step=2 ;;
    2) # Identidade Git
        if [[ -n "$detected_name" && -n "$detected_email" ]]; then
            rc=0; _tui_sim_nao "Identidade Git" \
                "Identidade detectada:\n\n  Nome:  ${detected_name}\n  Email: ${detected_email}\n\nDeseja alterar?" || rc=$?
            case $rc in
                2) tui_step=1; continue ;;
                0) git_name=$(_inputbox "Identidade Git" "Nome (git global):" "$detected_name") \
                        || { tui_step=1; continue; }
                    git_email=$(_inputbox "Identidade Git" "Email (git global):" "$detected_email") \
                        || { tui_step=1; continue; } ;;
                *) git_name="$detected_name"; git_email="$detected_email" ;;
            esac
        else
            git_name=$(_inputbox "Identidade Git" "Nome (git global):" "") \
                || { tui_step=1; continue; }
            git_email=$(_inputbox "Identidade Git" "Email (git global):" "") \
                || { tui_step=1; continue; }
        fi
        tui_step=3 ;;
    3) # Perfil Profissional
        if [[ -n "$detected_mec_name" && -n "$detected_mec_email" ]]; then
            rc=0; _tui_sim_nao "Perfil Profissional" \
                "Perfil detectado:\n\n  Nome:  ${detected_mec_name}\n  Email: ${detected_mec_email}\n\nDeseja alterar?" || rc=$?
        else
            rc=0; _tui_sim_nao "Perfil Profissional" \
                "Configurar identidade separada para Perfil Profissional?" || rc=$?
        fi
        case $rc in
            2) tui_step=2; continue ;;
            0) git_name_mec=$(_inputbox "Perfil Profissional" "Nome:" "${detected_mec_name:-}") \
                    || { tui_step=2; continue; }
                git_email_mec=$(_inputbox "Perfil Profissional" "Email:" "${detected_mec_email:-}") \
                    || { tui_step=2; continue; } ;;
            *) git_name_mec="${detected_mec_name:-}"; git_email_mec="${detected_mec_email:-}" ;;
        esac
        tui_step=4 ;;
    4) # Diretórios
        dev_dir=$(_inputbox "Diretórios" "Diretório de desenvolvimento:" "${DEV_DIR:-${HOME}/Desenvolvimento}") \
            || { tui_step=3; continue; }
        mec_root=$(_inputbox "Diretórios" "Raiz do projeto MEC (pipelines):" "${MEC_ROOT:-${dev_dir}/MEC/pipelines-main}") \
            || { tui_step=3; continue; }
        tui_step=5 ;;
    5) # Sincronização Remota
        if [[ -n "${ZSH_REMOTE_HOST:-}" && -n "${ZSH_REMOTE_USER:-}" ]]; then
            rc=0; _tui_sim_nao "Sincronização Remota" \
                "Sync detectado:\n\n  Host: ${ZSH_REMOTE_HOST}\n  User: ${ZSH_REMOTE_USER}\n\nDeseja alterar?" || rc=$?
        else
            rc=0; _tui_sim_nao "Sincronização Remota" \
                "Configurar sincronização com servidor remoto?" || rc=$?
        fi
        case $rc in
            2) tui_step=4; continue ;;
            0) remote_host=$(_inputbox "Sincronização Remota" "Host/IP do servidor:" "${ZSH_REMOTE_HOST:-}") \
                    || { tui_step=4; continue; }
                remote_user=$(_inputbox "Sincronização Remota" "Usuário SSH:" "${ZSH_REMOTE_USER:-}") \
                    || { tui_step=4; continue; } ;;
            *) remote_host="${ZSH_REMOTE_HOST:-}"; remote_user="${ZSH_REMOTE_USER:-}" ;;
        esac
        tui_step=6 ;;
    6) # Features
        features=$(_checklist "Features" "Selecione as features a ativar:" \
            "mec_tools" "Ferramentas MEC (dbt, FZF menu)" "on" \
            "remoto" "Sincronização remota" "off" \
            "kimi" "Integração Kimi AI" "off") \
            || { tui_step=5; continue; }
        tui_step=7 ;;
    esac
    done

    _TUI_GIT_NAME="$git_name"
    _TUI_GIT_EMAIL="$git_email"
    _TUI_GIT_NAME_MEC="$git_name_mec"
    _TUI_GIT_EMAIL_MEC="$git_email_mec"
    _TUI_DEV_DIR="$dev_dir"
    _TUI_MEC_ROOT="$mec_root"
    _TUI_REMOTE_HOST="$remote_host"
    _TUI_REMOTE_USER="$remote_user"
    _TUI_FEATURES="$features"
}

# --- Etapa 4: Gerar config.local.zsh ---
_step_gen_config() {
    _step "Gerando config.local.zsh"
    local config_file="$ZDOTDIR_TARGET/config.local.zsh"
    if [[ -f "$config_file" && ( "$IS_UPDATE" == true || "$_EXISTING_CONFIG" == true ) ]]; then
        _ok "config.local.zsh já existe — preservado"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        _info "Geraria config.local.zsh (dry-run)"
        return 0
    fi

    _info "Gerando config.local.zsh..."
    local _name="${_TUI_GIT_NAME:-SeuNome}"
    local _email="${_TUI_GIT_EMAIL:-voce@email.com}"
    local _name_mec="${_TUI_GIT_NAME_MEC:-}"
    local _email_mec="${_TUI_GIT_EMAIL_MEC:-}"
    local _remote_host="${_TUI_REMOTE_HOST:-}"
    local _remote_user="${_TUI_REMOTE_USER:-}"
    local _dev_dir="${_TUI_DEV_DIR:-${HOME}/Desenvolvimento}"
    local _mec_root="${_TUI_MEC_ROOT:-${HOME}/Desenvolvimento/MEC/pipelines-main}"
    _dev_dir="${_dev_dir//\$\{HOME\}/$HOME}"
    _mec_root="${_mec_root//\$\{HOME\}/$HOME}"

    cat > "$config_file" << EOF
# config.local.zsh — Variáveis desta máquina
# Gerado pelo install.sh. Editável manualmente. Gitignored.

# --- Git: identidade pessoal ---
export ZSH_GIT_NAME_PESSOAL="${_name}"
export ZSH_GIT_EMAIL_PESSOAL="${_email}"

# --- Git: identidade MEC (opcional) ---
export ZSH_GIT_NAME_MEC="${_name_mec}"
export ZSH_GIT_EMAIL_MEC="${_email_mec}"

# --- Caminhos dos projetos ---
export DEV_DIR="${_dev_dir}"
export MEC_ROOT="${_mec_root}"
export CONTROLE_BORDO_DIR="\${HOME}/Controle de Bordo"
export BEHOLDER_DIR="\${HOME}/Beholder"

# --- SSH key alternativa (opcional) ---
export ZSH_SSH_KEY_ALT=""

# --- Sincronização remota ---
export ZSH_REMOTE_HOST="${_remote_host}"
export ZSH_REMOTE_USER="${_remote_user}"
export ZSH_REMOTE_PASTA_LOCAL="\${BEHOLDER_DIR}"

# --- BigQuery keyfile (dbt) ---
export BQ_KEYFILE_PATH=""
EOF

    _ok "config.local.zsh gerado"
}

# --- Etapa 5: Copiar templates se não existirem ---
_step_templates() {
    _step "Copiando templates"
    local secrets_file="$ZDOTDIR_TARGET/.zsh_secrets"
    local profiles_file="$ZDOTDIR_TARGET/profiles.yml"
    if [[ ! -f "$secrets_file" ]]; then
        _run cp "$ZDOTDIR_TARGET/.zsh_secrets.template" "$secrets_file"
        _ok ".zsh_secrets criado a partir do template"
    else
        _ok ".zsh_secrets já existe — preservado"
    fi

    if [[ ! -f "$profiles_file" ]]; then
        _run cp "$ZDOTDIR_TARGET/profiles.yml.template" "$profiles_file"
        _ok "profiles.yml criado a partir do template"
    else
        _ok "profiles.yml já existe — preservado"
    fi

    local config_local="$ZDOTDIR_TARGET/config.local.zsh"
    if [[ ! -f "$config_local" ]]; then
        _run cp "$ZDOTDIR_TARGET/config.local.zsh.template" "$config_local"
        _ok "config.local.zsh criado a partir do template"
    else
        _ok "config.local.zsh já existe — preservado"
    fi
}

# --- Etapa 5.5: Restaurar secrets do vault criptografado ---
_step_secrets_vault() {
    _step "Restaurando credentials do vault"

    local vault_file="$SCRIPT_DIR/vault/secrets.gpg"

    if [[ ! -f "$vault_file" ]]; then
        _info "Nenhum vault encontrado — pule e configure manualmente"
        return 0
    fi

    # Verificar se já existem credentials
    local existing=0
    for f in .zsh_secrets config.local.zsh profiles.yml meua-ambiente.json segape-andre.json; do
        [[ -f "$ZDOTDIR_TARGET/$f" ]] && existing=$((existing + 1))
    done

    if [[ $existing -eq 5 ]]; then
        _ok "Todos os credentials já existem — vault ignorado"
        return 0
    fi

    _info "Vault criptografado encontrado ($(du -h "$vault_file" | cut -f1))"

    if [[ "$DRY_RUN" == true ]]; then
        _info "Pular restauração de vault (dry-run)"
        return 0
    fi

    local passphrase=""
    echo -n "  Senha do vault (Enter para pular): "
    read -rs passphrase
    echo

    if [[ -z "$passphrase" ]]; then
        _info "Vault pulado — configure credentials manualmente"
        return 0
    fi

    local result
    result=$(bash "$SCRIPT_DIR/scripts/spellbook-secrets.sh" import-auto "$passphrase" "$vault_file" 2>/dev/null) || {
        _warn "Senha incorreta ou vault corrompido — configure manualmente"
        return 0
    }

    if [[ -n "$result" && "$result" -gt 0 ]]; then
        _ok "$result credential(s) restaurado(s) do vault"
    else
        _warn "Nenhum credential restaurado do vault"
    fi
}

# --- Etapa 6: ~/.zshenv com ZDOTDIR ---
_step_zshenv() {
    _step "Configurando ZDOTDIR"
    local zshenv="$HOME/.zshenv"
    local zdotdir_line="export ZDOTDIR=\"$ZDOTDIR_TARGET\""
    if grep -qF "ZDOTDIR" "$zshenv" 2>/dev/null; then
        _ok "ZDOTDIR já configurado em ~/.zshenv"
    else
        _info "Adicionando ZDOTDIR ao ~/.zshenv..."
        _run sh -c "echo '$zdotdir_line' >> \"$zshenv\""
        _ok "~/.zshenv atualizado"
    fi
}

# --- Etapa 7: Trocar shell padrão ---
_step_chsh() {
    _step "Shell padrão"
    if [[ "$DRY_RUN" == true ]]; then
        _info "Pular troca de shell (dry-run)"
        return 0
    fi
    local zsh_path
    zsh_path=$(command -v zsh 2>/dev/null || echo "/bin/zsh")

    if [[ "$SHELL" == "$zsh_path" ]]; then
        _ok "Shell padrão já é zsh ($zsh_path)"
        return 0
    fi

    if _yesno "Shell Padrão" "Trocar shell padrão para zsh ($zsh_path)?"; then
        _run chsh -s "$zsh_path"
        _ok "Shell padrão alterado para $zsh_path"
    fi
}

# --- Etapa 8: Fontes base para compatibilidade cross-platform ---
_step_fonts() {
    _step "Instalando fontes base"

    local mgr
    mgr=$(_detect_pkg_manager)

    if [[ "$mgr" != "apt" ]]; then
        _warn "Instalação de fontes disponível apenas para apt — pule esta etapa"
        return 0
    fi

    _run sh -c 'echo "ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true" | sudo debconf-set-selections'

    local font_pkgs=(
        ttf-mscorefonts-installer
        fonts-liberation2
        fonts-crosextra-carlito
        fonts-crosextra-caladea
        fonts-noto-core
    )

    for pkg in "${font_pkgs[@]}"; do
        if dpkg -l "$pkg" &>/dev/null; then
            _ok "$pkg já instalado"
        else
            _info "Instalando $pkg..."
            _run sudo apt-get install -y "$pkg" || _warn "Falha ao instalar $pkg"
        fi
    done

    _info "Atualizando cache de fontes..."
    _run fc-cache -f

    _ok "Fontes base instaladas (execute 'fontes_instalar' para cobertura completa)"
}

# --- Etapa 9: Ferramentas de encoding ---
_step_encoding_tools() {
    _step "Ferramentas de encoding"
    _install_pkg "dos2unix" || _warn "Falha ao instalar dos2unix — conversão CRLF usará fallback via sed"
    _ok "Ferramentas de encoding prontas"
}

# --- Etapa 10: Spicetify (opcional) ---
_step_spicetify() {
    _step "Spicetify (customizacao do Spotify)"

    if [[ "$DRY_RUN" == true ]]; then
        _info "Pular Spicetify (dry-run)"
        return 0
    fi

    if ! _yesno "Spicetify" "Instalar/configurar Spicetify para o Spotify?" "defaultno"; then
        _info "Spicetify pulado"
        return 0
    fi

    local setup_script="$ZDOTDIR_TARGET/scripts/spicetify-setup.sh"
    if [[ -f "$setup_script" ]]; then
        _run bash "$setup_script"
    else
        _warn "Script spicetify-setup.sh nao encontrado em $setup_script"
    fi
}

# --- Etapa 11: Validação pós-instalação ---
_step_validate() {
    _step "Validação pós-instalação"

    local erros=0
    _info "Validando instalação..."

    grep -q "ZDOTDIR" "$HOME/.zshenv" 2>/dev/null \
        || { _warn "ZDOTDIR não está em ~/.zshenv"; ((erros++)); }

    [[ -f "$ZDOTDIR_TARGET/.oh-my-zsh/oh-my-zsh.sh" ]] \
        || { _warn "Oh My Zsh não encontrado em $ZDOTDIR_TARGET/.oh-my-zsh/"; ((erros++)); }

    bash -n "$ZDOTDIR_TARGET/install.sh" 2>/dev/null \
        || { _warn "Sintaxe do install.sh inválida"; ((erros++)); }

    [[ -f "$ZDOTDIR_TARGET/cca/aliases_cca.zsh" ]] \
        || { _warn "cca/aliases_cca.zsh não encontrado — comando cca indisponível"; ((erros++)); }

    [[ -d "$ZDOTDIR_TARGET/kca" ]] \
        || { _warn "kca/ não encontrado — comandos kimi indisponíveis"; ((erros++)); }

    [[ -d "$ZDOTDIR_TARGET/functions" ]] \
        || { _warn "functions/ não encontrado — funções do Spellbook indisponíveis"; ((erros++)); }

    [[ -d "$ZDOTDIR_TARGET/scripts" ]] \
        || { _warn "scripts/ não encontrado — scripts auxiliares indisponíveis"; ((erros++)); }

    [[ -f "$ZDOTDIR_TARGET/aliases.zsh" ]] \
        || { _warn "aliases.zsh não encontrado"; ((erros++)); }

    [[ -f "$ZDOTDIR_TARGET/functions.zsh" ]] \
        || { _warn "functions.zsh não encontrado — loader de funções ausente"; ((erros++)); }

    # Spicetify: validar apenas se binario existe
    if [[ -x "$HOME/.spicetify/spicetify" ]]; then
        local spice_ext
        spice_ext=$("$HOME/.spicetify/spicetify" config extensions 2>/dev/null | head -1)
        if [[ -z "$spice_ext" || "$spice_ext" == "custom_apps" ]]; then
            _warn "Spicetify: campo extensions corrompido ou vazio"
            ((erros++))
        else
            _ok "Spicetify: extensions configuradas"
        fi
    fi

    if [[ $erros -eq 0 ]]; then
        _ok "Validação pós-instalação: tudo OK"
    else
        _warn "$erros problema(s) detectado(s) — verifique os avisos acima"
    fi
}

# --- Etapa 11: Sugerir captura de manifesto inicial ---
_step_manifest() {
    _step "Manifesto do sistema"

    if [[ "$DRY_RUN" == true ]]; then
        _info "Pular captura de manifesto (dry-run)"
        return 0
    fi

    if _yesno "Manifesto do Sistema" "Deseja capturar o estado atual do sistema? (recomendado na primeira instalação)"; then
        _info "O manifesto será capturado ao abrir o terminal com 'sistema_capturar'"
        _ok "Lembrete adicionado ao resumo final"
    fi
}

# --- Etapa 12: Tela final ---
_step_summary() {
    _step "Resumo final"

    local summary_text
    summary_text='Configuração manual pendente:

  [ ] ~/.config/zsh/.zsh_secrets
      GITHUB_TOKEN, GEMINI_API_KEY

  [ ] ~/.config/zsh/config.local.zsh
      BQ_KEYFILE_PATH, CONTROLE_BORDO_DIR, BEHOLDER_DIR

  [ ] ~/.config/zsh/profiles.yml
      Projeto dbt BigQuery

Comandos disponíveis:
  fontes_instalar    -- fontes de compatibilidade
  fontes_verificar   -- cobertura de fontes
  enc_detectar       -- encoding de arquivos
  sistema_capturar   -- manifesto JSON do sistema
  sistema_restaurar  -- restaurar de manifesto
  diagnostico_pop    -- diagnóstico completo
  cca                -- claude code (--dangerously-skip-permissions)
  claude-safe        -- claude code com quota guard
  claude-quota       -- verificar quota de uso
  spicetify_status   -- versao, tema, extensions
  spicetify_reparar  -- detectar e corrigir config
  spicetify_instalar -- setup completo do Spicetify
  spellbook_export   -- criptografar credentials no vault
  spellbook_import   -- restaurar credentials do vault

Para ativar: source ~/.config/zsh/.zshrc
Ou reinicie o terminal.'

    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo -e "  ${_C_CYAN}=== Instalação Concluída ===${_C_RESET}"
        echo "$summary_text"
        return 0
    fi

    _msgbox "Instalação Concluída" "$summary_text"
}

# --- Etapa 0: Deploy — sincroniza repo para ~/.config/zsh/ ---
_step_deploy() {
    _step "Sincronizando arquivos"

    if [[ "$SCRIPT_DIR" == "$ZDOTDIR_TARGET" ]]; then
        _ok "Executando direto de ~/.config/zsh/ — deploy desnecessário"
        return 0
    fi

    _info "Sincronizando $SCRIPT_DIR → $ZDOTDIR_TARGET ..."
    _run mkdir -p "$ZDOTDIR_TARGET"

    # Backup antes de sincronizar (proteção contra rsync --delete)
    if [[ -d "$ZDOTDIR_TARGET" && "$ZDOTDIR_TARGET" != "$SCRIPT_DIR" ]]; then
        local backup_dir="$HOME/.config/zsh.backup.$(date +%Y%m%d_%H%M%S)"
        _info "Criando backup em $backup_dir ..."
        _run cp -a "$ZDOTDIR_TARGET" "$backup_dir"
        _ok "Backup salvo: $backup_dir"
    fi

    _run rsync -a --delete \
        --exclude='.oh-my-zsh' \
        --exclude='.zsh_history' \
        --exclude='.zsh_secrets' \
        --exclude='config.local.zsh' \
        --exclude='profiles.yml' \
        --exclude='segape-andre.json' \
        --exclude='meua-ambiente.json' \
        --exclude='novo_login_de_acesso.json' \
        --exclude='.cca_quota' \
        --exclude='.cca_guard_config' \
        --exclude='.claude_quota' \
        --exclude='*.pre-oh-my-zsh' \
        --exclude='.zcompdump*' \
        --exclude='*.zwc' \
        --exclude='.aider*' \
        --exclude='__pycache__/' \
        --exclude='*.py[cod]' \
        --exclude='.git/' \
        "$SCRIPT_DIR/" "$ZDOTDIR_TARGET/"

    _ok "Arquivos sincronizados para $ZDOTDIR_TARGET"
}

# --- Main ---
main() {
    local start_time=$SECONDS

    echo ""
    echo -e "  ${_C_PURPLE}${_C_BOLD}"
    echo '    ____              _ _ _                 _'
    echo '   / ___| _ __   ___| | | |__   ___   ___ | | __'
    echo '   \___ \|  _ \ / _ \ | | |_ \ / _ \ / _ \| |/ /'
    echo '    ___) | |_) |  __/ | | |_) | (_) | (_) |   <'
    echo '   |____/| .__/ \___|_|_|_.__/ \___/ \___/|_|\_\'
    echo '         |_|                               OS'
    echo -e "  ${_C_RESET}"
    echo -e "  ${_C_DIM}  Configuração zsh modular e portável${_C_RESET}"
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "  ${_C_YELLOW}  MODO: dry-run (nenhuma alteração será feita)${_C_RESET}"
    fi
    if [[ "$IS_UPDATE" == true ]]; then
        echo -e "  ${_C_CYAN}  MODO: update (config.local.zsh preservado)${_C_RESET}"
    fi

    _step_deploy
    _step_deps
    _step_fonts
    _step_encoding_tools
    _step_omz
    _step_tui
    _step_gen_config
    _step_templates
    _step_secrets_vault
    _step_zshenv
    _step_chsh
    _step_spicetify
    _step_validate
    _step_manifest
    _step_summary

    local elapsed=$(( SECONDS - start_time ))
    echo ""
    echo -e "  ${_C_GREEN}${_C_BOLD}Spellbook-OS instalado com sucesso.${_C_RESET}"
    echo -e "  ${_C_DIM}Tempo total: $((elapsed/60))m $((elapsed%60))s${_C_RESET}"
}

main "$@"

# "Conhece-te a ti mesmo, e conhecerás o universo e os deuses." — Sócrates
