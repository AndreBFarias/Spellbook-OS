#!/bin/bash
set -uo pipefail

DEV_DIR="${DEV_DIR:-$HOME/Desenvolvimento}"
DRY_RUN=false
VERBOSE=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true
[[ "${1:-}" == "--verbose" || "${2:-}" == "--verbose" ]] && VERBOSE=true

CONTAS_GERENCIADAS=(
    "AndreBFarias"
    "andrebfarias"
    "vitoriamariadb"
    "SEGAPE"
    "andrefariasmec"
)

resolver_alias_ssh() {
    local repo_path="$1"

    if [[ "$repo_path" == *"/MEC/"* || "$repo_path" == *"/MEC" ]]; then
        echo "github.com-mec"
    elif [[ "$repo_path" == *"/VitoriaMariaDB/"* || "$repo_path" == *"/VitoriaMariaDB" ]]; then
        echo "github.com-vit"
    else
        echo "github.com-personal"
    fi
}

eh_conta_gerenciada() {
    local owner="$1"
    local owner_lower
    owner_lower=$(echo "$owner" | tr '[:upper:]' '[:lower:]')

    for conta in "${CONTAS_GERENCIADAS[@]}"; do
        local conta_lower
        conta_lower=$(echo "$conta" | tr '[:upper:]' '[:lower:]')
        [[ "$owner_lower" == "$conta_lower" ]] && return 0
    done
    return 1
}

extrair_owner_repo() {
    local url="$1"
    local path_part=""

    if [[ "$url" == https://* ]]; then
        path_part=$(echo "$url" | sed -E 's|https://([^@]+@)?github\.com/||')
    elif [[ "$url" == git@* ]]; then
        path_part=$(echo "$url" | sed -E 's|git@[^:]+:||')
    fi

    echo "$path_part"
}

extrair_owner() {
    local owner_repo="$1"
    echo "$owner_repo" | cut -d'/' -f1
}

total=0
corrigidos=0
ignorados=0
ja_corretos=0
sem_remote=0

echo "========================================"
echo " Fix All Remotes - SSH Alias"
echo "========================================"
echo ""
$DRY_RUN && echo "[DRY-RUN] Nenhuma alteracao sera feita."
echo "Diretorio: $DEV_DIR"
echo ""

while IFS= read -r repo_path; do
    total=$((total + 1))
    repo_name=$(basename "$repo_path")
    remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || echo "")

    if [[ -z "$remote_url" ]]; then
        sem_remote=$((sem_remote + 1))
        $VERBOSE && echo "[SKIP] $repo_path (sem remote)"
        continue
    fi

    alias_correto=$(resolver_alias_ssh "$repo_path")

    if [[ "$remote_url" == git@${alias_correto}:* ]]; then
        ja_corretos=$((ja_corretos + 1))
        $VERBOSE && echo "[OK]   $repo_name -> $remote_url"
        continue
    fi

    owner_repo=$(extrair_owner_repo "$remote_url")
    if [[ -z "$owner_repo" ]]; then
        ignorados=$((ignorados + 1))
        $VERBOSE && echo "[SKIP] $repo_name (URL nao reconhecida: $remote_url)"
        continue
    fi

    owner=$(extrair_owner "$owner_repo")
    if ! eh_conta_gerenciada "$owner"; then
        ignorados=$((ignorados + 1))
        $VERBOSE && echo "[SKIP] $repo_name (conta third-party: $owner)"
        continue
    fi

    owner_repo="${owner_repo%.git}.git"
    owner_repo=$(echo "$owner_repo" | sed 's|\.git\.git|.git|')
    novo_url="git@${alias_correto}:${owner_repo}"

    if [[ "$remote_url" == *"@"*":"*"@"* ]] || [[ "$remote_url" == *"ghp_"* ]] || [[ "$remote_url" == *"gho_"* ]]; then
        echo "[TOKEN] $repo_name"
        echo "        ANTES:  $remote_url"
        echo "        DEPOIS: $novo_url"
    else
        echo "[FIX]  $repo_name"
        echo "        ANTES:  $remote_url"
        echo "        DEPOIS: $novo_url"
    fi

    if ! $DRY_RUN; then
        git -C "$repo_path" remote set-url origin "$novo_url"
    fi
    corrigidos=$((corrigidos + 1))

done < <(find "$DEV_DIR" -maxdepth 4 -name ".git" -type d -prune | sed 's/\/\.git//' | sort)

echo ""
echo "========================================"
echo " Relatorio"
echo "========================================"
echo "  Total:        $total"
echo "  Ja corretos:  $ja_corretos"
echo "  Corrigidos:   $corrigidos"
echo "  Ignorados:    $ignorados (third-party/URL invalida)"
echo "  Sem remote:   $sem_remote"
echo "========================================"
$DRY_RUN && echo "[DRY-RUN] Rode sem --dry-run para aplicar."
