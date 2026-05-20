#!/usr/bin/env bash
# Teste de regressão do universal-sanitizer.py.
# Cobre as três classes de bug do incidente 2026-05-19/20:
#   1. Auto-modificação do próprio sanitizer.
#   2. Modificação de libs vendored minificadas (html2pdf.bundle.min.js).
#   3. Remoção acidental dos glifos canônicos de ALLOWED_GLYPHS.
# Também valida que a funcionalidade primária (remoção de emoji legítimo)
# segue preservada.
#
# Uso: bash scripts/tests/test_sanitizer_invariance.sh
# Exit 0 = todos OK. Exit != 0 = pelo menos uma regressão.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SANITIZER="scripts/universal-sanitizer.py"
VENDORED="aurora/userscripts/control-c-ilimitado-ext/lib/html2pdf.bundle.min.js"

FAIL=0

__ok() { printf '[OK] %s\n' "$1"; }
__fail() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

# 1. Sintaxe Python válida
if python3 -m py_compile "$SANITIZER"; then
    __ok "py_compile do sanitizer"
else
    __fail "py_compile do sanitizer"
fi

# 2. Invariância byte-a-byte do próprio sanitizer
H1=$(sha256sum "$SANITIZER" | cut -d' ' -f1)
python3 "$SANITIZER" "$SANITIZER" >/dev/null 2>&1 || true
H2=$(sha256sum "$SANITIZER" | cut -d' ' -f1)
if [ "$H1" = "$H2" ]; then
    __ok "sanitizer não modifica a si mesmo"
else
    __fail "sanitizer alterou o próprio source (sha256 mudou)"
fi

# 3. Invariância da lib vendored html2pdf.bundle.min.js
if [ -f "$VENDORED" ]; then
    H3=$(sha256sum "$VENDORED" | cut -d' ' -f1)
    python3 "$SANITIZER" "$VENDORED" >/dev/null 2>&1 || true
    H4=$(sha256sum "$VENDORED" | cut -d' ' -f1)
    if [ "$H3" = "$H4" ]; then
        __ok "sanitizer não modifica lib vendored html2pdf"
    else
        __fail "sanitizer alterou lib vendored (sha256 mudou)"
    fi
else
    __fail "arquivo vendored ausente: $VENDORED"
fi

# 4. Funcionalidade primária preservada: emoji removido em arquivo legítimo.
#    Emoji gerado via bytes UTF-8 (U+1F389, party popper) para evitar literal.
TESTFILE=$(mktemp --suffix=.py)
EMOJI=$(printf '\xf0\x9f\x8e\x89')
printf 'x = "ola %s"\n' "$EMOJI" > "$TESTFILE"
python3 "$SANITIZER" "$TESTFILE" >/dev/null 2>&1 || true
if grep -q "$EMOJI" "$TESTFILE"; then
    __fail "emoji legítimo não foi removido"
else
    __ok "emoji legítimo removido (função primária preservada)"
fi
rm -f "$TESTFILE"

# 5. Preservação dos 11 glifos canônicos de ALLOWED_GLYPHS.
#    Bytes UTF-8 literais: U+25CB U+25D0 U+25CF U+25C6 U+25C7 U+25B6
#    U+25BC U+25B8 U+25FC U+25FB U+2197.
TESTFILE2=$(mktemp --suffix=.py)
printf 'glyphs = "\xe2\x97\x8b\xe2\x97\x90\xe2\x97\x8f\xe2\x97\x86\xe2\x97\x87\xe2\x96\xb6\xe2\x96\xbc\xe2\x96\xb8\xe2\x97\xbc\xe2\x97\xbb\xe2\x86\x97"\n' > "$TESTFILE2"
H5=$(sha256sum "$TESTFILE2" | cut -d' ' -f1)
python3 "$SANITIZER" "$TESTFILE2" >/dev/null 2>&1 || true
H6=$(sha256sum "$TESTFILE2" | cut -d' ' -f1)
if [ "$H5" = "$H6" ]; then
    __ok "11 glifos canônicos preservados"
else
    __fail "ALLOWED_GLYPHS quebrado (sha256 do arquivo de teste mudou)"
fi
rm -f "$TESTFILE2"

# 6. Auto-exclusão via path alternativo (symlink) — defesa em profundidade.
#    Garante que SANITIZER_REALPATH funciona mesmo se o caller passar um path
#    diferente do __file__ literal.
TMPLINK=$(mktemp -u --suffix=.py)
ln -s "$ROOT/$SANITIZER" "$TMPLINK"
H7=$(sha256sum "$SANITIZER" | cut -d' ' -f1)
python3 "$SANITIZER" "$TMPLINK" >/dev/null 2>&1 || true
H8=$(sha256sum "$SANITIZER" | cut -d' ' -f1)
if [ "$H7" = "$H8" ]; then
    __ok "auto-exclusão via symlink funciona"
else
    __fail "sanitizer modificou a si mesmo via symlink"
fi
rm -f "$TMPLINK"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "Resultado: todos os testes passaram."
    exit 0
else
    echo "Resultado: $FAIL teste(s) falharam."
    exit 1
fi
