#!/usr/bin/env python3
"""Sanitizador Universal - Auto-corrige e reporta problemas em arquivos staged."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


# Path canônico (realpath) deste próprio sanitizer. Usado em is_excluded()
# para impedir auto-modificação mesmo se chamado via symlink, path relativo
# ou caminho absoluto distinto do __file__ literal.
SANITIZER_REALPATH = os.path.realpath(__file__)

EXCLUDED_DIRS = {
    ".git", "venv", ".venv", "node_modules", "__pycache__",
    ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox",
    ".eggs", "dist", "build", ".next", ".nuxt",
    "hooks",
}

EXCLUDED_EXTENSIONS = {
    ".pyc", ".pyo", ".so", ".dylib", ".dll", ".class", ".o", ".a",
    ".png", ".jpg", ".jpeg", ".gif", ".svg", ".ico", ".bmp", ".webp", ".tiff",
    ".mp4", ".mp3", ".wav", ".flac", ".ogg", ".webm", ".avi", ".mkv",
    ".zip", ".tar", ".gz", ".bz2", ".xz", ".7z", ".rar",
    ".woff", ".woff2", ".ttf", ".eot", ".otf",
    ".pdf", ".doc", ".docx", ".xls", ".xlsx", ".pptx",
    ".lock", ".bin", ".dat", ".db", ".sqlite", ".sqlite3",
    ".map",
    ".key", ".pem", ".cert", ".crt", ".p12",
    ".pt", ".onnx", ".safetensors", ".gguf",
    ".html", ".htm", ".xml",
}

# Suffixes compostos (multi-ponto). Path.suffix só retorna o ÚLTIMO ponto,
# então entradas como ".min.js" NUNCA casavam em EXCLUDED_EXTENSIONS — eram
# código morto. Aqui a checagem é por endswith() no nome completo, em lower.
EXCLUDED_NAME_SUFFIXES = (
    ".min.js",
    ".min.css",
    ".bundle.js",
    ".bundle.css",
    ".metainfo.xml",
)

# Substrings de path que indicam código vendored ou de terceiros. Defesa em
# camadas junto com EXCLUDED_DIRS e EXCLUDED_NAME_SUFFIXES — cobre bundles
# minificados de userscripts e libs externas dentro de subdirs lib/, vendor/,
# third_party/.
EXCLUDED_PATH_SUBSTRINGS = (
    "/userscripts/",
    "/lib/",
    "/vendor/",
    "/third_party/",
    "/node_modules/",
    # Pacotes de terceiros do Obsidian (plugins/temas): emojis sao dados
    # funcionais (mapa glifo->nome do icon-folder, native com emoji, etc.).
    "/.obsidian/",
    "/obsidian/config/plugins/",
    "/obsidian/config/themes/",
    # SANITIZER-SEGAPE-EXCLUDE-01 (2026-08-07): repos de trabalho da SEGAPE/MEC.
    # Paridade com o emoji_guardian. Emoji e DADO nesses repos (o glifo e o valor
    # da coluna descricao_cumprimento do painel do FUNDEB), e o codigo e de outra
    # equipe. Aqui o risco e maior que no guardian: o `ga` roda este sanitizer
    # sobre arquivos JA STAGED, ou seja, no instante do commit.
    "/Projetos_segape/",
    # SANITIZER-MNEMO-EXCLUDE-01 (2026-08-14): repositorio publico proprio.
    # Aqui a redacao de identidade faz o oposto do que deveria: o handle do
    # dono num README publico e informacao necessaria, nao vazamento. Com ele
    # redigido, o `git clone https://github.com/[REDACTED]/Mnemo` que abre as
    # instrucoes de instalacao nao roda -- e o commit sai com o defeito calado,
    # porque o auto-fix re-stageia sem perguntar. O que protege este repo e o
    # hook proprio dele, em .githooks/pre-commit, que bloqueia em vez de
    # reescrever, mais o .gitignore de biometria.
    "/Mnemo/",
)

EXCLUDED_NAMES = {
    ".env", ".env.local", ".env.production", ".env.development",
    "my-mailmap", ".mailmap", ".gitignore", ".gitattributes",
    "package-lock.json", "yarn.lock", "poetry.lock", "Pipfile.lock",
    "Cargo.lock", "pnpm-lock.yaml", "composer.lock",
}

EMOJI_RE = re.compile(
    "["
    "\U0001F600-\U0001F64F"
    "\U0001F300-\U0001F5FF"
    "\U0001F680-\U0001F6FF"
    "\U0001F1E0-\U0001F1FF"
    "\U00002600-\U000026FF"
    "\U00002700-\U000027BF"
    "\U0000FE00-\U0000FE0F"
    "\U0001F900-\U0001F9FF"
    "\U0001FA00-\U0001FA6F"
    "\U0001FA70-\U0001FAFF"
    "\U0000200D"
    "\U000023E9-\U000023F3"
    "\U000023F8-\U000023FA"
    "\U0000203C-\U0000203C"
    "\U00002049-\U00002049"
    "\U000020E3"
    "\U00002122"
    "\U00002139"
    "\U00002194-\U000021AA"
    "\U000025AA-\U000025FE"
    "\U00002934-\U00002935"
    "\U00003030"
    "\U0000303D"
    "\U00003297"
    "\U00003299"
    "]+",
    flags=re.UNICODE,
)

# Glyphs canônicos protegidos contra remoção do EMOJI_RE.
# ALLOWED_GLYPHS centralizado em glyphs_canonicos.py (FONTE UNICA): antes cada
# sanitizer tinha copia própria e divergiram (emoji_guardian sem allowlist
# enquanto este tinha) -- causa da recidiva de estripamento (SPRINT 232).
import os as _os  # noqa: E402
import sys as _sys  # noqa: E402

_sys.path.insert(0, _os.path.dirname(_os.path.abspath(__file__)))
from glyphs_canonicos import ALLOWED_GLYPHS  # noqa: E402


def _strip_emojis_preserving_allowed(text: str) -> tuple[str, int]:
    """Remove emojis exceto ALLOWED_GLYPHS. Retorna (texto novo, n removidos)."""
    removed = 0

    def _repl(m: re.Match) -> str:
        nonlocal removed
        chars = m.group(0)
        kept = "".join(c for c in chars if c in ALLOWED_GLYPHS)
        removed += len(chars) - len(kept)
        return kept

    new = EMOJI_RE.sub(_repl, text)
    return new, removed

SECRET_PATTERNS = [
    re.compile(r"sk-[a-zA-Z0-9]{20,}"),
    re.compile(r"sk-ant-[a-zA-Z0-9]{20,}"),
    re.compile(r"AIza[0-9A-Za-z\-_]{35}"),
    re.compile(r"ghp_[a-zA-Z0-9]{36}"),
    re.compile(r"gho_[a-zA-Z0-9]{36}"),
    re.compile(r"github_pat_[a-zA-Z0-9]{22}_[a-zA-Z0-9]{59}"),
    re.compile(r"glpat-[a-zA-Z0-9\-]{20,}"),
    re.compile(r"xox[bpras]-[a-zA-Z0-9\-]+"),
    re.compile(r"AKIA[0-9A-Z]{16}"),
]

COAUTHOR_RE = re.compile(
    r"^\s*Co[- ]Authored[- ]By:.*$\n?",
    re.IGNORECASE | re.MULTILINE,
)

AI_ARTIFACT_RE = re.compile(
    r"^\s*#\s*(?:Generated by|Gerado por|Created by|Criado por)\s+"
    r"(?:ChatGPT|Claude|GPT|Copilot|DeepSeek|Gemini|Opus|Sonnet|Haiku|Fable|AI|IA).*$\n?",
    re.IGNORECASE | re.MULTILINE,
)


def is_excluded(filepath: str) -> bool:
    path = Path(filepath)
    parts = set(path.parts)

    # Auto-exclusão: o sanitizer NUNCA modifica seu próprio source-code,
    # independente de como tenha sido invocado (path relativo, absoluto,
    # ou via symlink). Usa realpath para canonicalizar inode.
    try:
        if os.path.realpath(filepath) == SANITIZER_REALPATH:
            return True
    except OSError:
        pass

    if parts & EXCLUDED_DIRS:
        return True
    if path.suffix.lower() in EXCLUDED_EXTENSIONS:
        return True
    name_lower = path.name.lower()
    if any(name_lower.endswith(s) for s in EXCLUDED_NAME_SUFFIXES):
        return True
    # Caminho ABSOLUTO para comparar com EXCLUDED_PATH_SUBSTRINGS. O hook do
    # git passa os arquivos como caminho relativo a raiz do repositorio
    # (`git diff --cached --name-only` devolve "README.md", nao o caminho
    # inteiro), entao comparar com a string crua nunca casava nenhuma entrada
    # -- a isencao por caminho ficava inerte justamente no momento em que ela
    # importa, que e o commit. Medido em 14/08/2026.
    path_str = os.path.abspath(str(path))
    if any(s in path_str for s in EXCLUDED_PATH_SUBSTRINGS):
        return True
    if path.name in EXCLUDED_NAMES:
        return True
    # Heuristica generica: arquivo dentro de um pacote de terceiros (manifest.json
    # no mesmo diretório) -- plugin/tema do Obsidian e afins. Emojis sao dados.
    try:
        if (path.parent / "manifest.json").is_file():
            return True
    except OSError:
        pass

    return False


def is_binary(filepath: str) -> bool:
    try:
        with open(filepath, "rb") as f:
            chunk = f.read(8192)
            return b"\0" in chunk
    except Exception:
        return True


def get_git_identity() -> list[str]:
    terms: list[str] = []
    for field in ("user.name", "user.email"):
        try:
            val = subprocess.check_output(
                ["git", "config", field],
                stderr=subprocess.DEVNULL,
            ).decode().strip()
            if val and len(val) > 2:
                terms.append(val)
        except Exception:
            pass
    return terms


# SANITIZER-STAGED-LINES-ONLY-01 (2026-08-03): num arquivo versionado que ja
# existia, so limpa emoji nas linhas que VOCE adicionou ou alterou neste commit.
# A politica "zero emoji" vale para o que voce escreve; reescrever linha alheia
# num repositorio de outra equipe contamina o diff e vira "arquivo fora do escopo"
# na review. Caso real: em SEGAPE/pipelines, um commit de 3 colunas novas no
# schema.yml levou junto a descricao de uma coluna cujo CONTEUDO e emoji
# ("Icone representativo (emoji) ... (<glifo> Habilitado, <glifo> Inabilitado)"),
# que ninguem daquela equipe pediu para mudar.
#
# Arquivo novo, fora de git, ou diff indisponivel: sem restricao, limpa tudo.
def _linhas_adicionadas(filepath: str) -> "set[int] | None":
    """Numeros de linha (1-based, no arquivo em disco) adicionados ou alterados
    no diff staged. None quando nao ha restricao a aplicar."""
    import subprocess

    alvo_abs = str(Path(filepath).resolve())
    try:
        proc = subprocess.run(
            ["git", "diff", "--cached", "-U0", "--", alvo_abs],
            capture_output=True, text=True, timeout=30,
            cwd=str(Path(alvo_abs).parent),
        )
        if proc.returncode != 0:
            return None
    except (OSError, subprocess.SubprocessError):
        return None

    if not proc.stdout.strip():
        return None  # sem diff staged: nao limita (arquivo novo ou nao staged)

    alvo: set[int] = set()
    for linha in proc.stdout.splitlines():
        if not linha.startswith("@@"):
            continue
        m = re.search(r"\+(\d+)(?:,(\d+))?", linha)
        if not m:
            continue
        inicio = int(m.group(1))
        qtd = int(m.group(2)) if m.group(2) is not None else 1
        alvo.update(range(inicio, inicio + qtd))
    return alvo or None


def sanitize_file(filepath: str, identity_terms: list[str]) -> dict[str, int]:
    report: dict[str, int] = {
        "emojis": 0,
        "secrets": 0,
        "coauthor": 0,
        "ai_artifacts": 0,
        "whitespace": 0,
        "identity": 0,
    }

    if not os.path.exists(filepath) or is_binary(filepath) or is_excluded(filepath):
        return report

    try:
        with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
    except Exception:
        return report

    original = content

    # SANITIZER-STAGED-LINES-ONLY-01: emoji e limpo so nas linhas que voce
    # adicionou/alterou. Secrets e identidade continuam varrendo o arquivo
    # inteiro: sao protecao ativa, e vazar credencial ou nome numa linha alheia
    # e pior que carregar uma linha a mais no diff.
    _alvo = _linhas_adicionadas(filepath)
    if _alvo is None:
        content, n = _strip_emojis_preserving_allowed(content)
        report["emojis"] = n
    else:
        _linhas = content.split("\n")
        _total = 0
        for _i, _linha in enumerate(_linhas):
            if (_i + 1) in _alvo:
                _linhas[_i], _k = _strip_emojis_preserving_allowed(_linha)
                _total += _k
        content = "\n".join(_linhas)
        report["emojis"] = _total

    for pattern in SECRET_PATTERNS:
        content, n = pattern.subn("[REDACTED]", content)
        report["secrets"] += n

    content, n = COAUTHOR_RE.subn("", content)
    report["coauthor"] = n

    content, n = AI_ARTIFACT_RE.subn("", content)
    report["ai_artifacts"] = n

    lines = content.splitlines()
    stripped = [line.rstrip() for line in lines]
    report["whitespace"] = sum(1 for a, b in zip(lines, stripped) if a != b)
    content = "\n".join(stripped)
    if content and not content.endswith("\n"):
        content += "\n"

    ext = Path(filepath).suffix.lower()
    safe_config_ext = {".cfg", ".ini", ".toml", ".yaml", ".yml", ".json"}
    safe_names = {"LICENSE", "LICENSE.md", "AUTHORS", "CONTRIBUTORS", "pyproject.toml", "setup.cfg", "SECURITY.md"}

    if ext not in safe_config_ext and Path(filepath).name not in safe_names:
        for term in identity_terms:
            if term in content:
                # Dono de repositorio publico em URL (github.com/<user>/...) nao
                # e vazamento: e o endereco do proprio projeto. Redigir ali
                # quebra badge de CI que nao renderiza e `git clone` que ninguem
                # consegue copiar. O termo segue redigido em toda outra posicao.
                guarda = "\x00GH_OWNER_GUARD\x00"
                url_re = re.compile(
                    r"(github\.com/)" + re.escape(term) + r"(?=[/\"\'\s)\]]|$)"
                )
                content = url_re.sub(r"\1" + guarda, content)
                pattern = re.compile(re.escape(term))
                content, n = pattern.subn("[REDACTED]", content)
                content = content.replace(guarda, term)
                report["identity"] += n

    if content != original:
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(content)

    return report


def main() -> int:
    files = sys.argv[1:]
    identity = get_git_identity()

    totals: dict[str, int] = {
        "emojis": 0,
        "secrets": 0,
        "coauthor": 0,
        "ai_artifacts": 0,
        "whitespace": 0,
        "identity": 0,
    }
    files_fixed = 0

    for f in files:
        report = sanitize_file(f, identity)
        if any(v > 0 for v in report.values()):
            files_fixed += 1
            for k, v in report.items():
                totals[k] += v

    if files_fixed > 0:
        labels = {
            "emojis": "emojis removidos",
            "secrets": "secrets redactados",
            "coauthor": "co-author removidos",
            "ai_artifacts": "artefatos IA removidos",
            "whitespace": "linhas whitespace",
            "identity": "identidade redactada",
        }
        parts = [f"{v} {labels[k]}" for k, v in totals.items() if v > 0]
        print(f"  [sanitizer] {files_fixed} arquivos: {', '.join(parts)}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
