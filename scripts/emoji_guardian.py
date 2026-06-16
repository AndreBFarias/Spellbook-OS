#!/usr/bin/env python3
"""
Emoji Guardian - Sistema de Detecção e Limpeza de Emojis
=======================================================
Detecta e remove emojis de arquivos de texto.

REGRA: ZERO EMOJIS. SEMPRE.
"""

import os
import re
import sys
import argparse
from pathlib import Path
from typing import List, Tuple, Optional

SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))


def safe_write(path: Path, content: str, encoding: str = "utf-8") -> bool:
    """Escrita atômica self-contained (temp no mesmo dir + os.replace).

    Decoupled de vault_backup ao centralizar este guardian em
    ~/.config/zsh/scripts/ (EMOJI-GUARDIAN-ZSH-RELOCATE-01). vault_backup
    permanece no vault (sistema de backup próprio dele); este guardian não
    depende mais dele. Os repos-alvo são versionados (git é o backup), então
    a escrita atômica basta.
    """
    import tempfile

    path = Path(path)
    fd, tmp = tempfile.mkstemp(
        dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp"
    )
    try:
        with os.fdopen(fd, "w", encoding=encoding) as f:
            f.write(content)
        os.replace(tmp, str(path))
        return True
    except Exception as exc:  # noqa: BLE001 -- escrita best-effort
        try:
            os.unlink(tmp)
        except OSError:
            pass
        print(f"safe_write falhou: {exc}", file=sys.stderr)
        return False

# ============================================================================
# PATTERNS DE EMOJI (apenas emojis gráficos, não caracteres de desenho ASCII)
# ============================================================================

# Emojis de faces e emoções
EMOJI_FACES = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # emoticons
    "]+", flags=re.UNICODE
)

# Emojis de símbolos e pictogramas
EMOJI_SYMBOLS = re.compile(
    "["
    "\U0001F300-\U0001F5FF"  # symbols & pictographs
    "\U0001F900-\U0001F9FF"  # supplemental symbols
    "\U0001FA70-\U0001FAFF"  # symbols extended
    "]+", flags=re.UNICODE
)

# Emojis de transporte, mapas, bandeiras
EMOJI_FLAGS = re.compile(
    "["
    "\U0001F680-\U0001F6FF"  # transport & map
    "\U0001F1E0-\U0001F1FF"  # flags
    "]+", flags=re.UNICODE
)

# Símbolos diversos (estrelas, corações, setas coloridas)
EMOJI_MISC = re.compile(
    "["
    "\u2764-\u2767"      # corações
    "\u2B50-\u2B55"     # estrelas
    "\u2B05-\u2B0D"     # setas negras
    "\u23E9-\u23FA"     # símbolos de mídia
    "\u25AA-\u25FF"     # quadrados coloridos
    "\u2600-\u26FF"     # misc symbols
    "\u2700-\u27BF"     # dingbats
    "]+", flags=re.UNICODE
)

# Emojis com variante de seleção
EMOJI_VARIATION = re.compile(
    "["
    "\U0001F004\uFE0F"   # mahjong red dragon
    "\U0001F0CF\uFE0F"   # joker
    "]+", flags=re.UNICODE
)

# Todos os patterns combinados
ALL_EMOJI_PATTERNS = [
    EMOJI_FACES,
    EMOJI_SYMBOLS,
    EMOJI_FLAGS,
    EMOJI_MISC,
    EMOJI_VARIATION,
]

# Glyphs canônicos protegidos contra remoção. FONTE UNICA em
# ~/.config/zsh/scripts/glyphs_canonicos.py -- antes este sanitizer e o
# universal-sanitizer.py tinham copias próprias e divergiram (este sem
# allowlist, causa da recidiva 06/07/08 -- SPRINT 232/VECTOR-AUDIT-01).
# Centralizado em SPRINT 234. Fallback inline cobre o vault sincronizado
# isolado (sem o zsh); a paridade fallback<->canônico e garantida por teste.
_ZSH_GLYPHS = Path.home() / ".config" / "zsh" / "scripts"
if _ZSH_GLYPHS.is_dir() and str(_ZSH_GLYPHS) not in sys.path:
    sys.path.insert(0, str(_ZSH_GLYPHS))
try:
    from glyphs_canonicos import ALLOWED_GLYPHS
except ImportError:
    ALLOWED_GLYPHS = frozenset({
        "○", "◐", "●", "◆", "◇", "▶", "▼", "▸", "◼", "◻", "↗", "↘", "↔",
    })


def _preserve_allowed_in_match(match: re.Match) -> str:
    """Retorna apenas os caracteres em ALLOWED_GLYPHS do match; remove o resto."""
    return "".join(c for c in match.group(0) if c in ALLOWED_GLYPHS)

# ============================================================================
# CONFIGURAÇÕES
# ============================================================================

# Diretórios para ignorar
IGNORE_DIRS = {
    '.git', '.obsidian', 'node_modules', '__pycache__',
    '.venv', 'venv', '.stfolder', '.sistema', '.tags',
    '_reorganizacao_backup', 'target', 'dist', 'build',
    'venv_requirements-dev', '.tox', '.eggs', '.pytest_cache',
    '.mypy_cache', 'site-packages',
    # SANITIZER-VENDOR-EXCLUDE-HARDEN-01: código vendored/terceiros nunca deve
    # ser varrido (paridade com universal-sanitizer EXCLUDED_PATH_SUBSTRINGS).
    # Foi o emoji_guardian que corrompeu nyx/cockpit/static/vendor/xterm.js (U+25C6).
    'vendor', 'third_party',
    # SANITIZER-GUARDIAN-DOC-PRESERVE-01: docs de auditoria/sprint citam glifos
    # (ex.: U+26A1) para documentar a remoção deles do código; são registro
    # histórico, não saída de produto. Stripar corromperia a citação. O guard
    # check_sanitizer_attack.py defende no commit; isto fecha a fonte.
    'dev-journey',
}

# Extensões de arquivo para verificar
TEXT_EXTENSIONS = {
    '.md', '.txt', '.py', '.sh', '.zsh', '.bash',
    '.js', '.ts', '.jsx', '.tsx', '.json', '.yaml', '.yml',
    '.toml', '.ini', '.cfg', '.conf', '.html', '.css',
    '.sql', '.r', '.ipynb', '.csv'
}

# Extensões para ignorar completamente
BINARY_EXTENSIONS = {
    '.png', '.jpg', '.jpeg', '.gif', '.ico', '.svg',
    '.woff', '.woff2', '.ttf', '.eot', '.otf',
    '.mp3', '.mp4', '.webm', '.wav', '.ogg',
    '.pdf', '.zip', '.tar', '.gz', '.bz2', '.7z',
    '.exe', '.dll', '.so', '.dylib', '.bin',
    '.db', '.sqlite', '.sqlite3'
}

# ============================================================================
# FUNÇÕES
# ============================================================================

def find_emojis_in_line(line: str) -> List[str]:
    """Encontra todos os emojis em uma linha, ignorando ALLOWED_GLYPHS.

    SPRINT 233 (INFRA-SANITIZER-CHECK-ALLOWLIST-01, 2026-05-25): paridade
    semântica com clean_emojis_from_text(replacement=""). Match cujos
    caracteres TODOS estão em ALLOWED_GLYPHS é considerado glifo canônico
    legítimo, não emoji. Evita falso-positivo do `check`/`santuario` em
    arquivos que usam U+25xx como UI signature (Nyx-Code et al).
    """
    found = []
    for pattern in ALL_EMOJI_PATTERNS:
        for match in pattern.findall(line):
            if not all(c in ALLOWED_GLYPHS for c in match):
                found.append(match)
    return found


def has_emoji(text: str) -> bool:
    """Verifica se o texto contém algum emoji."""
    return len(find_emojis_in_line(text)) > 0


def clean_emojis_from_text(text: str, replacement: str = '') -> str:
    """Remove todos os emojis de um texto, preservando ALLOWED_GLYPHS.

    SPRINT 232 (INFRA-SANITIZER-ALLOWLIST-EXPAND-01, 2026-05-25): quando
    replacement="" (default), usa _preserve_allowed_in_match para preservar
    glifos canônicos de UI (U+25xx + ↗) que projetos como Nyx-Code usam
    como signature visual. Quando replacement!="" (uso explícito de
    substituição), aplica replacement em tudo (semântica antiga preservada).
    """
    result = text
    if replacement == '':
        for pattern in ALL_EMOJI_PATTERNS:
            result = pattern.sub(_preserve_allowed_in_match, result)
    else:
        for pattern in ALL_EMOJI_PATTERNS:
            result = pattern.sub(replacement, result)
    return result


def find_emojis_in_file(filepath: str) -> List[Tuple[int, str, List[str]]]:
    """
    Retorna lista de tuplas (linha_num, linha_conteudo, emojis_encontrados).
    """
    results = []
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            for i, line in enumerate(f, 1):
                emojis = find_emojis_in_line(line)
                if emojis:
                    results.append((i, line.rstrip(), emojis))
    except Exception as e:
        results.append((0, f"ERRO: {e}", []))
    return results


def should_check_file(filepath: str) -> bool:
    """Determina se o arquivo deve ser verificado."""
    path = Path(filepath)

    # Verificar extensão
    ext = path.suffix.lower()
    if ext in BINARY_EXTENSIONS:
        return False

    # Se não tem extensão, verificar se é arquivo de texto conhecido
    if not ext:
        basename = path.name.lower()
        if basename in {'dockerfile', 'makefile', 'license', 'readme'}:
            return True
        return False

    return ext in TEXT_EXTENSIONS or not ext


def scan_directory(
    directory: str,
    verbose: bool = False,
    max_files: Optional[int] = None
) -> List[Tuple[str, List[Tuple[int, str, List[str]]]]]:
    """
    Escaneia diretório procurando emojis.
    Retorna lista de (filepath, [(linha, conteudo, emojis), ...]).
    """
    files_with_emojis = []
    count = 0

    for root, dirs, files in os.walk(directory):
        # Ignorar diretórios
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]

        for file in files:
            filepath = os.path.join(root, file)

            if not should_check_file(filepath):
                continue

            results = find_emojis_in_file(filepath)

            if results and results[0][0] != 0:  # Skip erros de leitura
                files_with_emojis.append((filepath, results))
                count += 1

                if verbose:
                    rel_path = filepath.replace(directory, "").lstrip("/")
                    print(f"[ENCONTRADO] {rel_path}: {len(results)} linha(s)")

                if max_files and count >= max_files:
                    return files_with_emojis

    return files_with_emojis


def clean_file(filepath: str, dry_run: bool = True) -> Tuple[int, int]:
    """
    Limpa emojis de um arquivo.
    Retorna (linhas_modificadas, total_emojis_removidos).
    """
    # SANITIZER-GUARDIAN-DOC-PRESERVE-01: defesa em profundidade -- mesmo numa
    # invocação direta de arquivo (fora do os.walk que respeita IGNORE_DIRS),
    # docs de dev-journey nunca são modificados.
    if 'dev-journey' in Path(filepath).parts:
        return (0, 0)

    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return (0, 0)

    modified_lines = []
    lines_changed = 0
    total_emojis = 0

    for line in lines:
        emojis = find_emojis_in_line(line)
        if emojis:
            cleaned_line = clean_emojis_from_text(line)
            modified_lines.append(cleaned_line)
            lines_changed += 1
            total_emojis += len(emojis)
        else:
            modified_lines.append(line)

    if lines_changed > 0 and not dry_run:
        new_content = "".join(modified_lines)
        if not safe_write(Path(filepath), new_content):
            print(f"ERRO: safe_write falhou para {filepath}", file=sys.stderr)
            return (0, 0)

    return (lines_changed, total_emojis)


def print_report(
    files_with_emojis: List[Tuple[str, List[Tuple[int, str, List[str]]]]],
    directory: str,
    max_examples: int = 3
):
    """Imprime relatório de emojis encontrados."""
    if not files_with_emojis:
        print("\n[OK] Nenhum emoji encontrado!")
        return

    print(f"\n[ALERTA] {len(files_with_emojis)} arquivo(s) com emojis encontrado(s):\n")

    for filepath, results in files_with_emojis:
        rel_path = filepath.replace(directory, "").lstrip("/")
        print(f"[ARQUIVO] {rel_path}")

        for line_num, line_content, emojis in results[:max_examples]:
            emoji_str = ''.join(emojis[:5])  # Limita a 5 emojis
            if len(emojis) > 5:
                emoji_str += f" (+{len(emojis)-5})"
            preview = line_content[:70].replace('\t', ' ')
            print(f"   Linha {line_num:4d}: {preview}")
            print(f"            Emojis: {emoji_str}")

        if len(results) > max_examples:
            print(f"   ... e mais {len(results) - max_examples} linha(s)")
        print()


def clean_directory(
    directory: str,
    dry_run: bool = True,
    verbose: bool = False
) -> Tuple[int, int, int]:
    """
    Limpa emojis de todos os arquivos em um diretório.
    Retorna (arquivos_limpos, linhas_modificadas, total_emojis).
    """
    files_with_emojis = scan_directory(directory, verbose=verbose)

    files_cleaned = 0
    total_lines = 0
    total_emojis = 0

    for filepath, _ in files_with_emojis:
        lines_changed, emojis_removed = clean_file(filepath, dry_run=dry_run)

        if lines_changed > 0:
            files_cleaned += 1
            total_lines += lines_changed
            total_emojis += emojis_removed

            if verbose or dry_run:
                action = "[LIMPO]" if not dry_run else "[DRY-RUN]"
                rel_path = filepath.replace(directory, "").lstrip("/")
                print(f"{action} {rel_path}: {emojis_removed} emoji(s) em {lines_changed} linha(s)")

    return (files_cleaned, total_lines, total_emojis)


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description='Emoji Guardian - Detecta e remove emojis de arquivos',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Exemplos:
  %(prog)s check /caminho/para/diretório     # Verifica emojis
  %(prog)s clean /caminho/para/diretório     # Remove emojis (dry-run)
  %(prog)s clean --apply /caminho/dir        # Remove emojis (aplica)
  %(prog)s check . --verbose                 # Verbose mode
        """
    )

    parser.add_argument('command', choices=['check', 'clean'],
                       help='Comando: check (verificar) ou clean (limpar)')
    parser.add_argument('directory', help='Diretório para verificar/limpar')
    parser.add_argument('--apply', action='store_true',
                       help='Aplicar limpeza (sem isso, clean é dry-run)')
    parser.add_argument('--verbose', '-v', action='store_true',
                       help='Modo verbose')
    parser.add_argument('--max-files', type=int, default=None,
                       help='Limite de arquivos a processar')

    args = parser.parse_args()

    # Validar diretório
    if not os.path.isdir(args.directory):
        print(f"ERRO: Diretório não existe: {args.directory}", file=sys.stderr)
        sys.exit(1)

    abs_path = os.path.abspath(args.directory)

    if args.command == 'check':
        print(f"=== Verificando emojis em: {abs_path} ===\n")
        files_with_emojis = scan_directory(
            abs_path,
            verbose=args.verbose,
            max_files=args.max_files
        )
        print_report(files_with_emojis, abs_path)

        # Exit code
        sys.exit(1 if files_with_emojis else 0)

    elif args.command == 'clean':
        dry_run = not args.apply
        action = "LIMPANDO" if not dry_run else "SIMULANDO LIMPEZA"
        print(f"=== {action} emojis em: {abs_path} ===\n")

        files_cleaned, total_lines, total_emojis = clean_directory(
            abs_path,
            dry_run=dry_run,
            verbose=args.verbose
        )

        print(f"\n{'='*50}")
        print(f"Arquivos processados: {files_cleaned}")
        print(f"Linhas modificadas:   {total_lines}")
        print(f"Total de emojis:      {total_emojis}")

        if dry_run:
            print("\n[DRY-RUN] Nenhuma alteração foi feita.")
            print("Use --apply para aplicar as alterações.")

        sys.exit(0)


if __name__ == '__main__':
    main()
