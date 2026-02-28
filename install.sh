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

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------

_run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

_info()  { echo "  >> $*"; }
_ok()    { echo "  OK  $*"; }
_warn()  { echo "  WARN $*" >&2; }
_err()   { echo "  ERRO $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Detecção de gestor de pacotes
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# TUI: whiptail → dialog → read puro
# ---------------------------------------------------------------------------

_tui_available() {
    command -v whiptail &>/dev/null && echo "whiptail" && return
    command -v dialog   &>/dev/null && echo "dialog"   && return
    echo "plain"
}

_tui() { _tui_available; }

_inputbox() {
    local title="$1" label="$2" default="$3"
    local tui
    tui=$(_tui)

    case "$tui" in
        whiptail|dialog)
            "$tui" --title "$title" --inputbox "$label" 10 60 "$default" 3>&1 1>&2 2>&3
            ;;
        plain)
            printf "  %s [%s]: " "$label" "$default" >&2
            local val
            read -r val
            echo "${val:-$default}"
            ;;
    esac
}

_yesno() {
    local title="$1" question="$2"
    local tui
    tui=$(_tui)

    case "$tui" in
        whiptail|dialog)
            "$tui" --title "$title" --yesno "$question" 10 60 3>&1 1>&2 2>&3
            return $?
            ;;
        plain)
            printf "  %s (s/N): " "$question" >&2
            local val
            read -r val
            [[ "$val" == "s" || "$val" == "S" || "$val" == "y" || "$val" == "Y" ]]
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
            "$tui" --title "$title" --checklist "$question" 20 60 10 "$@" 3>&1 1>&2 2>&3
            ;;
        plain)
            echo "  $question" >&2
            local i=1 result=""
            while [[ $# -ge 3 ]]; do
                local tag="$1" desc="$2" state="$3"
                shift 3
                printf "  [%d] %s - %s (padrão: %s): " "$i" "$tag" "$desc" "$state" >&2
                local val
                read -r val
                if [[ "${val:-$state}" == "on" || "${val:-$state}" == "ON" || "${val:-$state}" == "s" ]]; then
                    result="$result \"$tag\""
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
            "$tui" --title "$title" --msgbox "$msg" 20 70
            ;;
        plain)
            echo ""
            echo "  === $title ==="
            echo "$msg"
            echo ""
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Etapa 1: Dependências do sistema
# ---------------------------------------------------------------------------

_step_deps() {
    _info "Verificando dependências do sistema..."

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
        if [[ -f "$ZDOTDIR_TARGET/requirements.txt" ]]; then
            _run pip3 install --user -r "$ZDOTDIR_TARGET/requirements.txt" --quiet
        else
            _run pip3 install --user pandas openpyxl --quiet
        fi
        _ok "Python deps instaladas"
    fi
}

# ---------------------------------------------------------------------------
# Etapa 2: Oh My Zsh + plugins
# ---------------------------------------------------------------------------

_step_omz() {
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

# ---------------------------------------------------------------------------
# Etapa 3: TUI — coletar configuração do usuário
# ---------------------------------------------------------------------------

_step_tui() {
    local tui
    tui=$(_tui)

    # Boas-vindas
    _msgbox "Instalador zsh-config" \
"O que será configurado:

  - Dependências do sistema (zsh, fzf, git, jq, pv...)
  - Oh My Zsh + plugins (autosuggestions, syntax-highlighting)
  - Configuração local (~/.config/zsh/config.local.zsh)
  - Entrada ZDOTDIR no ~/.zshenv

Pressione OK para continuar."

    # Identidade pessoal
    local git_name git_email
    git_name=$(_inputbox "Identidade Git" "Seu nome (git global):" "SeuNome")
    git_email=$(_inputbox "Identidade Git" "Seu email (git global):" "voce@email.com")

    # Identidade MEC
    local git_name_mec="" git_email_mec=""
    if _yesno "Identidade MEC" "Configurar identidade separada para projetos MEC?"; then
        git_name_mec=$(_inputbox "Identidade MEC" "Nome MEC:" "")
        git_email_mec=$(_inputbox "Identidade MEC" "Email MEC:" "")
    fi

    # Diretórios
    local dev_dir
    dev_dir=$(_inputbox "Diretórios" "Diretório de desenvolvimento:" "${HOME}/Desenvolvimento")

    local mec_root
    mec_root=$(_inputbox "Diretórios" "Raiz do projeto MEC (pipelines):" "${dev_dir}/MEC/pipelines-main")

    # Sync remoto
    local remote_host="" remote_user=""
    if _yesno "Sync Remoto" "Configurar sincronização com servidor remoto?"; then
        remote_host=$(_inputbox "Sync Remoto" "Host/IP do servidor:" "")
        remote_user=$(_inputbox "Sync Remoto" "Usuário SSH:" "")
    fi

    # Features
    local features
    features=$(_checklist "Features" "Selecione as features a ativar:" \
        "claude_quota" "Sistema de quota Claude" "on" \
        "mec_tools" "Ferramentas MEC (dbt, FZF menu)" "on" \
        "remoto" "Sincronização remota" "off" \
        "kimi" "Integração Kimi AI" "off")

    # Exportar vars para uso posterior
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

# ---------------------------------------------------------------------------
# Etapa 4: Gerar config.local.zsh
# ---------------------------------------------------------------------------

_step_gen_config() {
    local config_file="$ZDOTDIR_TARGET/config.local.zsh"

    if [[ -f "$config_file" && "$IS_UPDATE" == true ]]; then
        _ok "config.local.zsh já existe — preservado (modo --update)"
        return 0
    fi

    _info "Gerando config.local.zsh..."

    _run cat > "$config_file" << EOF
# config.local.zsh — Variáveis desta máquina
# Gerado pelo install.sh. Editável manualmente. Gitignored.

# --- Git: identidade pessoal ---
export ZSH_GIT_NAME_PESSOAL="${_TUI_GIT_NAME:-SeuNome}"
export ZSH_GIT_EMAIL_PESSOAL="${_TUI_GIT_EMAIL:-voce@email.com}"

# --- Git: identidade MEC (opcional) ---
export ZSH_GIT_NAME_MEC="${_TUI_GIT_NAME_MEC:-}"
export ZSH_GIT_EMAIL_MEC="${_TUI_GIT_EMAIL_MEC:-}"

# --- Caminhos dos projetos ---
export DEV_DIR="${_TUI_DEV_DIR:-${HOME}/Desenvolvimento}"
export MEC_ROOT="${_TUI_MEC_ROOT:-${HOME}/Desenvolvimento/MEC/pipelines-main}"
export CONTROLE_BORDO_DIR="\${HOME}/Controle de Bordo"
export BEHOLDER_DIR="\${HOME}/Beholder"

# --- Sincronização remota ---
export ZSH_REMOTE_HOST="${_TUI_REMOTE_HOST:-}"
export ZSH_REMOTE_USER="${_TUI_REMOTE_USER:-}"
export ZSH_REMOTE_PASTA_LOCAL="\${BEHOLDER_DIR}"

# --- BigQuery keyfile (dbt) ---
export BQ_KEYFILE_PATH=""
EOF

    _ok "config.local.zsh gerado"
}

# ---------------------------------------------------------------------------
# Etapa 5: Copiar templates se não existirem
# ---------------------------------------------------------------------------

_step_templates() {
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
}

# ---------------------------------------------------------------------------
# Etapa 6: ~/.zshenv com ZDOTDIR
# ---------------------------------------------------------------------------

_step_zshenv() {
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

# ---------------------------------------------------------------------------
# Etapa 7: Trocar shell padrão
# ---------------------------------------------------------------------------

_step_chsh() {
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

# ---------------------------------------------------------------------------
# Etapa 8: Tela final
# ---------------------------------------------------------------------------

_step_summary() {
    _msgbox "Instalação Concluída" \
"O que ainda precisa ser preenchido manualmente:

  [ ] ~/.config/zsh/.zsh_secrets
      Adicionar: GITHUB_TOKEN, GEMINI_API_KEY, ANTHROPIC_API_KEY

  [ ] ~/.config/zsh/config.local.zsh
      Preencher: BQ_KEYFILE_PATH (service account BigQuery)

  [ ] ~/.config/zsh/profiles.yml
      Verificar configurações do projeto dbt

Para ativar agora:
  source ~/.config/zsh/.zshrc

Ou reinicie o terminal."
}

# ---------------------------------------------------------------------------
# Etapa 0: Deploy — sincroniza repo para ~/.config/zsh/
# ---------------------------------------------------------------------------

_step_deploy() {
    if [[ "$SCRIPT_DIR" == "$ZDOTDIR_TARGET" ]]; then
        _ok "Executando direto de ~/.config/zsh/ — deploy desnecessário"
        return 0
    fi

    _info "Sincronizando $SCRIPT_DIR → $ZDOTDIR_TARGET ..."
    _run mkdir -p "$ZDOTDIR_TARGET"

    _run rsync -a --delete \
        --exclude='.oh-my-zsh' \
        --exclude='.zsh_history' \
        --exclude='.zsh_secrets' \
        --exclude='config.local.zsh' \
        --exclude='profiles.yml' \
        --exclude='segape-andre.json' \
        --exclude='*.pre-oh-my-zsh' \
        --exclude='.zcompdump*' \
        --exclude='*.zwc' \
        --exclude='.aider*' \
        --exclude='__pycache__/' \
        --exclude='*.py[cod]' \
        --exclude='.claude_quota' \
        --exclude='.git/' \
        "$SCRIPT_DIR/" "$ZDOTDIR_TARGET/"

    _ok "Arquivos sincronizados para $ZDOTDIR_TARGET"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    echo ""
    echo "  zsh-config installer"
    echo "  ===================="
    if [[ "$DRY_RUN" == true ]];  then echo "  MODO: dry-run (nenhuma alteração será feita)"; fi
    if [[ "$IS_UPDATE" == true ]]; then echo "  MODO: update (config.local.zsh preservado)"; fi
    echo ""

    _step_deploy
    _step_deps
    _step_omz
    _step_tui
    _step_gen_config
    _step_templates
    _step_zshenv
    _step_chsh
    _step_summary
}

main "$@"

# "Conhece-te a ti mesmo, e conhecerás o universo e os deuses." — Sócrates
