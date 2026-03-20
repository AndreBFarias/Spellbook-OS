#!/bin/bash
# Gerenciador de secrets criptografados do Spellbook-OS
# Empacota credentials em GPG simétrico para backup seguro no repo

set -euo pipefail

ZDOTDIR_TARGET="${ZDOTDIR:-$HOME/.config/zsh}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAULT_FILE="$SCRIPT_DIR/vault/secrets.gpg"

# Arquivos de credentials (relativos ao ZDOTDIR)
SECRETS_FILES=(
    ".zsh_secrets"
    "config.local.zsh"
    "profiles.yml"
    "meua-ambiente.json"
    "segape-andre.json"
)

_info()  { echo -e "\033[0;36m>>\033[0m $*"; }
_ok()    { echo -e "\033[0;32mOK\033[0m  $*"; }
_warn()  { echo -e "\033[0;33m!!\033[0m  $*"; }
_err()   { echo -e "\033[0;31mERRO\033[0m $*"; }

export_secrets() {
    local passphrase="${1:-}"

    if [[ -z "$passphrase" ]]; then
        echo -n "Senha para criptografia: "
        read -rs passphrase
        echo
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    local count=0
    for file in "${SECRETS_FILES[@]}"; do
        local src="$ZDOTDIR_TARGET/$file"
        if [[ -f "$src" ]]; then
            cp "$src" "$tmpdir/$file"
            count=$((count + 1))
            _info "Empacotando: $file"
        else
            _warn "Nao encontrado (ignorado): $file"
        fi
    done

    if [[ $count -eq 0 ]]; then
        _err "Nenhum arquivo de credentials encontrado em $ZDOTDIR_TARGET"
        return 1
    fi

    tar -cf "$tmpdir/secrets.tar" -C "$tmpdir" "${SECRETS_FILES[@]}" 2>/dev/null || \
        tar -cf "$tmpdir/secrets.tar" -C "$tmpdir" $(ls "$tmpdir" | grep -v secrets.tar)

    gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase "$passphrase" \
        --output "$VAULT_FILE" \
        "$tmpdir/secrets.tar"

    _ok "$count arquivo(s) criptografado(s) em vault/secrets.gpg"
}

import_secrets() {
    local passphrase="${1:-}"
    local vault_src="${2:-$VAULT_FILE}"

    if [[ ! -f "$vault_src" ]]; then
        _err "Arquivo vault nao encontrado: $vault_src"
        return 1
    fi

    if [[ -z "$passphrase" ]]; then
        echo -n "Senha para descriptografia: "
        read -rs passphrase
        echo
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    if ! gpg --batch --yes --decrypt \
        --passphrase "$passphrase" \
        --output "$tmpdir/secrets.tar" \
        "$vault_src" 2>/dev/null; then
        _err "Senha incorreta ou arquivo corrompido"
        return 1
    fi

    tar -xf "$tmpdir/secrets.tar" -C "$tmpdir"

    local count=0
    for file in "${SECRETS_FILES[@]}"; do
        local src="$tmpdir/$file"
        local dst="$ZDOTDIR_TARGET/$file"
        if [[ -f "$src" ]]; then
            if [[ -f "$dst" ]]; then
                _warn "$file ja existe — sobrescrever? (s/n)"
                read -r resp
                [[ "$resp" != "s" ]] && { _info "Ignorado: $file"; continue; }
            fi
            cp "$src" "$dst"
            chmod 600 "$dst"
            count=$((count + 1))
            _ok "Restaurado: $file"
        fi
    done

    _ok "$count arquivo(s) restaurado(s) em $ZDOTDIR_TARGET"
}

# Modo silencioso para install.sh (sem confirmação de sobrescrita)
import_secrets_auto() {
    local passphrase="${1:-}"
    local vault_src="${2:-$VAULT_FILE}"

    if [[ ! -f "$vault_src" ]]; then
        return 1
    fi

    if [[ -z "$passphrase" ]]; then
        return 1
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf '$tmpdir'" EXIT

    if ! gpg --batch --yes --decrypt \
        --passphrase "$passphrase" \
        --output "$tmpdir/secrets.tar" \
        "$vault_src" 2>/dev/null; then
        return 1
    fi

    tar -xf "$tmpdir/secrets.tar" -C "$tmpdir"

    local count=0
    for file in "${SECRETS_FILES[@]}"; do
        local src="$tmpdir/$file"
        local dst="$ZDOTDIR_TARGET/$file"
        if [[ -f "$src" ]]; then
            cp "$src" "$dst"
            chmod 600 "$dst"
            count=$((count + 1))
        fi
    done

    echo "$count"
}

case "${1:-}" in
    export)
        export_secrets "${2:-}"
        ;;
    import)
        import_secrets "${2:-}"
        ;;
    import-auto)
        import_secrets_auto "${2:-}" "${3:-}"
        ;;
    *)
        echo "Uso: $0 {export|import} [senha]"
        echo ""
        echo "  export [senha]  — criptografa credentials para vault/secrets.gpg"
        echo "  import [senha]  — restaura credentials de vault/secrets.gpg"
        exit 1
        ;;
esac
