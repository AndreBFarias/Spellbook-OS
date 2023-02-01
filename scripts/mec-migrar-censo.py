#!/usr/bin/env python3

import argparse
import difflib
import json
import logging
import os
import re
import subprocess
import sys
from pathlib import Path

logging.basicConfig(level=logging.WARNING, format="%(levelname)s: %(message)s")

# -- Exit codes --
EXIT_OK              = 0
EXIT_ERROR           = 1
EXIT_NEEDS_MIGRATION = 2

# -- Constantes do projeto MEC --
PROJECT_DEV   = "br-mec-segape-dev"
DATASET       = "educacao_inep_dados_abertos"
OLD_TABLE     = "censo_escolar_escola"
NEW_TABLE     = "inep_censo_escolar_educacao_basica"
OLD_SOURCE_ID = f"{{{{source('{DATASET}','{OLD_TABLE}')}}}}"
NEW_SOURCE_ID = f"{{{{source('{DATASET}','{NEW_TABLE}')}}}}"
SAMPLE_ROWS   = 5
MAX_DISTINCT  = 1_000_000

MEC_ROOT   = Path(os.environ.get("MEC_ROOT", Path.home() / "Desenvolvimento" / "MEC" / "pipelines-main"))
MODELS_REL = "queries/models"

# -- Cores ANSI (inicializadas em _init_colors) --
RESET = BOLD = DIM = GREEN = RED = YELLOW = GRAY = CYAN = ORANGE = PURPLE = FG = ""
_JSON_MODE = False


def _init_colors(enabled: bool) -> None:
    global RESET, BOLD, DIM, GREEN, RED, YELLOW, GRAY, CYAN, ORANGE, PURPLE, FG
    if enabled:
        RESET  = "\033[0m"
        BOLD   = "\033[1m"
        DIM    = "\033[2m"
        GREEN  = "\033[38;2;80;250;123m"
        RED    = "\033[38;2;255;85;85m"
        YELLOW = "\033[38;2;241;250;140m"
        GRAY   = "\033[38;2;98;114;164m"
        CYAN   = "\033[38;2;139;233;253m"
        ORANGE = "\033[38;2;255;184;108m"
        PURPLE = "\033[38;2;189;147;249m"
        FG     = "\033[38;2;248;248;242m"


def _p(*args, **kwargs) -> None:
    """Print que respeita _JSON_MODE: em modo json, redireciona para stderr."""
    if _JSON_MODE and "file" not in kwargs:
        kwargs["file"] = sys.stderr
    print(*args, **kwargs)


# -- Dados ficticios para modo --mock --
MOCK_DATA: dict[str, dict] = {
    "quantidade_matricula_infantil_integral": {
        "new_col": "quantidade_matricula_educacao_infantil_integral",
        "old_type": "INTEGER", "new_type": "INTEGER",
        "old_head": [0, 12, 5, 8, 0], "new_head": [0, 12, 5, 8, 0],
        "old_distinct": 847, "new_distinct": 847,
        "old_sum": 1234567, "new_sum": 1234567,
    },
    "quantidade_matricula_fundamental_anos_iniciais_integral": {
        "new_col": "quantidade_matricula_educacao_fundamental_anos_iniciais_integral",
        "old_type": "INTEGER", "new_type": "INTEGER",
        "old_head": [3, 7, 21, 0, 14], "new_head": [3, 7, 21, 0, 14],
        "old_distinct": 512, "new_distinct": 512,
        "old_sum": 987654, "new_sum": 987654,
    },
    "quantidade_matricula_fundamental_anos_finais_integral": {
        "new_col": "quantidade_matricula_educacao_fundamental_anos_finais_integral",
        "old_type": "INTEGER", "new_type": "INTEGER",
        "old_head": [0, 0, 9, 15, 2], "new_head": [0, 0, 9, 15, 2],
        "old_distinct": 334, "new_distinct": 334,
        "old_sum": 543210, "new_sum": 543210,
    },
    "quantidade_matricula_medio_integral": {
        "new_col": "quantidade_matricula_educacao_media_integral",
        "old_type": "INTEGER", "new_type": "INTEGER",
        "old_head": [0, 0, 0, 4, 1], "new_head": [0, 0, 0, 4, 1],
        "old_distinct": 178, "new_distinct": 178,
        "old_sum": 210000, "new_sum": 210000,
    },
}

KNOWN_RENAMES: dict[str, str] = {
    old: data["new_col"]
    for old, data in MOCK_DATA.items()
}


def _hr(char: str = "─", width: int = 50) -> str:
    return f"  {GRAY}{char * width}{RESET}"


def _ok(msg: str) -> str:
    return f"{GREEN}OK{RESET}  {GRAY}{msg}{RESET}"


def _fail(msg: str) -> str:
    return f"{RED}FALHA{RESET}  {GRAY}{msg}{RESET}"


def _warn_label(msg: str) -> str:
    return f"{YELLOW}AVISO{RESET}  {GRAY}{msg}{RESET}"


# ---------------------------------------------------------------------------
# Auto-sync
# ---------------------------------------------------------------------------

def sync_sql_files(mec_root: Path, quiet: bool = False) -> dict:
    root_str = str(mec_root)
    fetch = subprocess.run(
        ["git", "-C", root_str, "fetch", "origin", "main"],
        capture_output=True, text=True, timeout=30,
    )
    if fetch.returncode != 0:
        return {"error": fetch.stderr.strip(), "updated": []}

    diff = subprocess.run(
        ["git", "-C", root_str, "diff", "--name-only", "HEAD..origin/main", "--", MODELS_REL],
        capture_output=True, text=True,
    )
    changed = [ln for ln in diff.stdout.splitlines() if ln.strip()]

    checkout = subprocess.run(
        ["git", "-C", root_str, "checkout", "origin/main", "--", MODELS_REL],
        capture_output=True, text=True,
    )
    if checkout.returncode != 0:
        return {"error": checkout.stderr.strip(), "updated": []}

    if not quiet:
        if changed:
            print(
                f"  {GRAY}[sync]{RESET} {GREEN}{len(changed)} arquivo(s) atualizado(s){RESET}",
                file=sys.stderr,
            )
        else:
            print(f"  {GRAY}[sync] ja atualizado{RESET}", file=sys.stderr)

    return {"error": None, "updated": changed}


# ---------------------------------------------------------------------------
# BigQuery helpers
# ---------------------------------------------------------------------------

def get_bq_client(project: str):
    try:
        from google.cloud import bigquery
        return bigquery.Client(project=project)
    except ImportError as exc:
        print(f"  {RED}google-cloud-bigquery nao encontrado: {exc}{RESET}", file=sys.stderr)
        sys.exit(EXIT_ERROR)


def get_table_schema(client, dataset: str, table: str) -> dict[str, str]:
    full_id = f"{client.project}.{dataset}.{table}"
    try:
        bq_table = client.get_table(full_id)
        return {field.name: field.field_type for field in bq_table.schema}
    except Exception as exc:
        print(f"  {RED}Erro ao obter schema de {full_id}: {exc}{RESET}", file=sys.stderr)
        return {}


def _run_query(client, sql: str) -> list:
    return list(client.query(sql).result())


def _get_type_from_schema(client, dataset: str, table: str, col: str) -> str:
    sql = f"""
        SELECT data_type
        FROM `{client.project}.{dataset}.INFORMATION_SCHEMA.COLUMNS`
        WHERE table_name = '{table}'
          AND column_name = '{col}'
    """
    rows = _run_query(client, sql)
    return rows[0][0] if rows else "UNKNOWN"


def _get_head(client, dataset: str, table: str, col: str) -> list:
    sql = f"SELECT {col} FROM `{client.project}.{dataset}.{table}` LIMIT {SAMPLE_ROWS}"
    return [row[0] for row in _run_query(client, sql)]


def _get_count_distinct(client, dataset: str, table: str, col: str) -> int:
    sql = f"SELECT COUNT(DISTINCT {col}) AS cnt FROM `{client.project}.{dataset}.{table}`"
    rows = _run_query(client, sql)
    return rows[0][0] if rows else 0


def _get_sum(client, dataset: str, table: str, col: str) -> float | None:
    sql = f"SELECT SUM({col}) AS total FROM `{client.project}.{dataset}.{table}`"
    rows = _run_query(client, sql)
    return rows[0][0] if rows else None


# ---------------------------------------------------------------------------
# validate_pair
# ---------------------------------------------------------------------------

def validate_pair(client, old_col: str, new_col: str, verbose: bool = True) -> dict:
    result = {
        "old_col": old_col, "new_col": new_col,
        "type_ok": False, "head_ok": False, "distinct_ok": False, "sum_ok": False,
        "all_ok": False, "old_type": "", "new_type": "",
        "old_head": [], "new_head": [],
        "old_distinct": 0, "new_distinct": 0,
        "old_sum": None, "new_sum": None,
        "alias": f"{new_col} AS {old_col}",
    }

    if verbose:
        _p()
        _p(f"  {PURPLE}{BOLD}VALIDACAO DE COLUNA{RESET}")
        _p(_hr())
        _p(f"  {GRAY}Antigo{RESET}   {FG}{OLD_TABLE}.{old_col}{RESET}")
        _p(f"  {GRAY}Novo  {RESET}   {FG}{NEW_TABLE}.{new_col}{RESET}")
        _p(_hr())

    old_type = _get_type_from_schema(client, DATASET, OLD_TABLE, old_col)
    new_type = _get_type_from_schema(client, DATASET, NEW_TABLE, new_col)
    result["old_type"] = old_type
    result["new_type"] = new_type
    type_ok = old_type == new_type
    result["type_ok"] = type_ok

    if verbose:
        status = _ok(f"{old_type} = {new_type}") if type_ok else _fail(f"{old_type} != {new_type}")
        _p(f"  {GRAY}[1/4]{RESET} Tipos     {status}")

    old_head = _get_head(client, DATASET, OLD_TABLE, old_col)
    new_head = _get_head(client, DATASET, NEW_TABLE, new_col)
    result["old_head"] = old_head
    result["new_head"] = new_head
    head_ok = old_head == new_head
    result["head_ok"] = head_ok

    if verbose:
        status_label = _ok("") if head_ok else _fail("valores divergem")
        _p(f"  {GRAY}[2/4]{RESET} HEAD      antigo: {CYAN}{old_head}{RESET}")
        _p(f"  {GRAY}      {RESET}            novo:   {CYAN}{new_head}{RESET}      {status_label}")

    old_distinct = _get_count_distinct(client, DATASET, OLD_TABLE, old_col)
    new_distinct = _get_count_distinct(client, DATASET, NEW_TABLE, new_col)
    result["old_distinct"] = old_distinct
    result["new_distinct"] = new_distinct
    distinct_ok = old_distinct == new_distinct
    result["distinct_ok"] = distinct_ok

    if verbose:
        status = _ok(f"antigo: {old_distinct} | novo: {new_distinct}") if distinct_ok \
            else _fail(f"antigo: {old_distinct} | novo: {new_distinct}")
        _p(f"  {GRAY}[3/4]{RESET} DISTINCT  {status}")

    numeric_types = {"INTEGER", "INT64", "FLOAT", "FLOAT64", "NUMERIC", "BIGNUMERIC"}
    if old_type.upper() in numeric_types:
        old_sum = _get_sum(client, DATASET, OLD_TABLE, old_col)
        new_sum = _get_sum(client, DATASET, NEW_TABLE, new_col)
        result["old_sum"] = old_sum
        result["new_sum"] = new_sum

        if old_sum is not None and new_sum is not None:
            delta = abs((old_sum or 0) - (new_sum or 0))
            delta_pct = (delta / max(abs(old_sum or 1), 1)) * 100
            sum_ok = delta == 0
            result["sum_ok"] = sum_ok

            if verbose:
                old_fmt = f"{old_sum:,.0f}".replace(",", ".")
                new_fmt = f"{new_sum:,.0f}".replace(",", ".")
                delta_fmt = f"{delta:,.0f}".replace(",", ".")
                status = _ok("delta: 0 (0.00%)") if sum_ok \
                    else _fail(f"delta: {delta_fmt} ({delta_pct:.2f}%)")
                _p(f"  {GRAY}[4/4]{RESET} SUM       antigo: {CYAN}{old_fmt}{RESET}")
                _p(f"  {GRAY}      {RESET}            novo:   {CYAN}{new_fmt}{RESET}")
                _p(f"  {GRAY}      {RESET}            {status}")
        else:
            result["sum_ok"] = True
            if verbose:
                _p(f"  {GRAY}[4/4]{RESET} SUM       {GRAY}(sem dados){RESET}")
    else:
        result["sum_ok"] = True
        if verbose:
            _p(f"  {GRAY}[4/4]{RESET} SUM       {GRAY}(nao aplicavel para tipo {old_type}){RESET}")

    result["all_ok"] = all([
        result["type_ok"], result["head_ok"],
        result["distinct_ok"], result["sum_ok"],
    ])

    if verbose:
        _p()
        if result["all_ok"]:
            _p(f"  {GRAY}Alias sugerido:{RESET}")
            _p(f"  {CYAN}{result['alias']}{RESET}")
        else:
            _p(f"  {YELLOW}Validacao com divergencias — revisar antes de aplicar.{RESET}")

    return result


# ---------------------------------------------------------------------------
# mock_validate
# ---------------------------------------------------------------------------

def mock_validate(old_col: str, new_col: str, verbose: bool = True) -> dict:
    data = MOCK_DATA.get(old_col) or {
        "new_col": new_col,
        "old_type": "INTEGER", "new_type": "INTEGER",
        "old_head": [1, 2, 3, 4, 5], "new_head": [1, 2, 3, 4, 5],
        "old_distinct": 100, "new_distinct": 100,
        "old_sum": 500, "new_sum": 500,
    }

    result = {
        "old_col": old_col, "new_col": new_col,
        "type_ok": data["old_type"] == data["new_type"],
        "head_ok": data["old_head"] == data["new_head"],
        "distinct_ok": data["old_distinct"] == data["new_distinct"],
        "sum_ok": data["old_sum"] == data["new_sum"],
        "all_ok": False,
        "old_type": data["old_type"], "new_type": data["new_type"],
        "old_head": data["old_head"], "new_head": data["new_head"],
        "old_distinct": data["old_distinct"], "new_distinct": data["new_distinct"],
        "old_sum": data["old_sum"], "new_sum": data["new_sum"],
        "alias": f"{new_col} AS {old_col}",
    }
    result["all_ok"] = all([
        result["type_ok"], result["head_ok"],
        result["distinct_ok"], result["sum_ok"],
    ])

    if verbose:
        _p()
        _p(f"  {PURPLE}{BOLD}VALIDACAO DE COLUNA{RESET}  {YELLOW}[mock]{RESET}")
        _p(_hr())
        _p(f"  {GRAY}Antigo{RESET}   {FG}{OLD_TABLE}.{old_col}{RESET}")
        _p(f"  {GRAY}Novo  {RESET}   {FG}{NEW_TABLE}.{new_col}{RESET}")
        _p(_hr())

        type_ok = result["type_ok"]
        type_status = _ok(f"{data['old_type']} = {data['new_type']}") if type_ok \
            else _fail(f"{data['old_type']} != {data['new_type']}")
        _p(f"  {GRAY}[1/4]{RESET} Tipos     {type_status}")

        head_ok = result["head_ok"]
        head_status = _ok("") if head_ok else _fail("valores divergem")
        _p(f"  {GRAY}[2/4]{RESET} HEAD      antigo: {CYAN}{data['old_head']}{RESET}")
        _p(f"  {GRAY}      {RESET}            novo:   {CYAN}{data['new_head']}{RESET}      {head_status}")

        dist_ok = result["distinct_ok"]
        dist_status = _ok(f"antigo: {data['old_distinct']} | novo: {data['new_distinct']}") if dist_ok \
            else _fail(f"antigo: {data['old_distinct']} | novo: {data['new_distinct']}")
        _p(f"  {GRAY}[3/4]{RESET} DISTINCT  {dist_status}")

        old_sum = data["old_sum"]
        new_sum = data["new_sum"]
        delta = abs(old_sum - new_sum)
        delta_pct = (delta / max(abs(old_sum or 1), 1)) * 100
        sum_ok = result["sum_ok"]
        old_fmt = f"{old_sum:,.0f}".replace(",", ".")
        new_fmt = f"{new_sum:,.0f}".replace(",", ".")
        sum_status = _ok("delta: 0 (0.00%)") if sum_ok \
            else _fail(f"delta: {abs(old_sum - new_sum):,.0f} ({delta_pct:.2f}%)")
        _p(f"  {GRAY}[4/4]{RESET} SUM       antigo: {CYAN}{old_fmt}{RESET}")
        _p(f"  {GRAY}      {RESET}            novo:   {CYAN}{new_fmt}{RESET}")
        _p(f"  {GRAY}      {RESET}            {sum_status}")

        _p()
        if result["all_ok"]:
            _p(f"  {GRAY}Alias sugerido:{RESET}")
            _p(f"  {CYAN}{result['alias']}{RESET}")
        else:
            _p(f"  {YELLOW}Validacao com divergencias — revisar antes de aplicar.{RESET}")

    return result


# ---------------------------------------------------------------------------
# SQL analysis helpers
# ---------------------------------------------------------------------------

def find_cols_in_sql(sql: str, schema_cols: list[str]) -> list[str]:
    found = []
    for col in schema_cols:
        if re.search(rf"\b{re.escape(col)}\b", sql):
            found.append(col)
    return found


def find_primary_cte(sql: str, source_name: str) -> tuple[int, int] | None:
    source_pattern = re.compile(
        r"\{\{source\(['\"][^'\"]+['\"],\s*['\"]" + re.escape(source_name) + r"['\"]",
        re.IGNORECASE,
    )
    source_match = source_pattern.search(sql)
    if not source_match:
        return None

    source_pos = source_match.start()
    cte_pattern = re.compile(r"\b(\w+)\s+AS\s*\(", re.IGNORECASE)

    containing_cte_start = None
    containing_paren_pos = None

    for m in cte_pattern.finditer(sql):
        if m.start() < source_pos:
            containing_cte_start = m.start()
            containing_paren_pos = m.end() - 1
        else:
            break

    if containing_cte_start is None or containing_paren_pos is None:
        return None

    depth = 0
    i = containing_paren_pos
    while i < len(sql):
        if sql[i] == "(":
            depth += 1
        elif sql[i] == ")":
            depth -= 1
            if depth == 0:
                return (containing_cte_start, i + 1)
        i += 1

    return None


def _infer_new_col(old_col: str) -> str | None:
    if old_col in KNOWN_RENAMES:
        return KNOWN_RENAMES[old_col]

    patterns = [
        (r"^quantidade_matricula_infantil_(.+)$",
         r"quantidade_matricula_educacao_infantil_\1"),
        (r"^quantidade_matricula_fundamental_(.+)$",
         r"quantidade_matricula_educacao_fundamental_\1"),
        (r"^quantidade_matricula_medio_(.+)$",
         r"quantidade_matricula_educacao_media_\1"),
    ]
    for pat, repl in patterns:
        if re.match(pat, old_col):
            return re.sub(pat, repl, old_col)

    return None


def find_renamed_cols_in_sql(
    sql: str,
    old_schema: dict[str, str],
) -> list[tuple[str, str | None]]:
    old_cols = list(old_schema.keys())
    referenced = find_cols_in_sql(sql, old_cols)

    result = []
    for col in referenced:
        new_col = _infer_new_col(col)
        if new_col and new_col != col:
            result.append((col, new_col))

    return result


def scan_sql_file(sql: str) -> dict:
    """Analisa arquivo SQL sem BQ: detecta old source e colunas com rename."""
    has_old_source = bool(re.search(
        rf"source\(['\"][^'\"]+['\"],\s*['\"]" + re.escape(OLD_TABLE) + r"['\"]",
        sql,
    ))

    renamed_cols: list[dict] = []
    unknown_cols: list[str] = []

    if has_old_source:
        seen: set[str] = set()

        for old_col, new_col in KNOWN_RENAMES.items():
            if re.search(rf"\b{re.escape(old_col)}\b", sql):
                seen.add(old_col)
                renamed_cols.append({"old": old_col, "new": new_col, "status": "known"})

        rename_patterns = [
            r"\bquantidade_matricula_infantil_\w+\b",
            r"\bquantidade_matricula_fundamental_\w+\b",
            r"\bquantidade_matricula_medio_\w+\b",
        ]
        for pat in rename_patterns:
            for col in re.findall(pat, sql):
                if col in seen:
                    continue
                seen.add(col)
                new_col = _infer_new_col(col)
                if new_col:
                    renamed_cols.append({"old": col, "new": new_col, "status": "inferred"})
                else:
                    unknown_cols.append(col)

    if not has_old_source:
        action = "ok"
    elif renamed_cols:
        action = "source+aliases"
    else:
        action = "source_only"

    return {
        "needs_source_change": has_old_source,
        "renamed_cols": renamed_cols,
        "unknown_cols": unknown_cols,
        "action": action,
    }


# ---------------------------------------------------------------------------
# SQL transformation
# ---------------------------------------------------------------------------

def format_except_multiline(cols: list[str], base_indent: str) -> str:
    """['rede', 'col1', 'col2'] -> 'EXCEPT(\\n    rede,\\n    col1,\\n    col2)'"""
    inner = f",\n{base_indent}    ".join(cols)
    return f"EXCEPT(\n{base_indent}    {inner})"


def inject_alias_in_cte(sql: str, col_map: dict[str, str]) -> str:
    """
    col_map = {"new_col": "old_col", ...}

    1. Adiciona new_cols ao EXCEPT(...)  com formatacao multiline se >1 coluna
    2. Adiciona linhas de alias antes do FROM
    3. Troca OLD_SOURCE_ID -> NEW_SOURCE_ID
    """
    if not col_map:
        return sql

    cte_bounds = find_primary_cte(sql, OLD_TABLE)
    if cte_bounds is None:
        return sql

    start, end = cte_bounds
    cte_block = sql[start:end]

    except_pattern = re.compile(r"(\.\*\s+EXCEPT\s*\()([^)]*?)(\))", re.IGNORECASE)
    except_match = except_pattern.search(cte_block)
    new_cols_to_except = list(col_map.keys())

    if except_match:
        prefix = except_match.group(1)
        existing = except_match.group(2)

        existing_cols = [c.strip() for c in existing.split(",") if c.strip()]
        all_except = existing_cols + new_cols_to_except

        if len(all_except) > 1:
            line_start_pos = cte_block.rfind("\n", 0, except_match.start())
            if line_start_pos != -1:
                line_content = cte_block[line_start_pos + 1 : except_match.start()]
                base_indent = re.match(r"^(\s*)", line_content).group(1)
            else:
                base_indent = "        "
            star_part = re.sub(r"EXCEPT\s*\($", "", prefix, flags=re.IGNORECASE)
            new_except_str = star_part + format_except_multiline(all_except, base_indent)
            cte_block = (
                cte_block[: except_match.start()]
                + new_except_str
                + cte_block[except_match.end() :]
            )
        else:
            suffix = except_match.group(3)
            new_except = f"{prefix}{', '.join(all_except)}{suffix}"
            cte_block = (
                cte_block[: except_match.start()]
                + new_except
                + cte_block[except_match.end() :]
            )

    alias_lines = []
    indent = "    "
    for new_col, old_col in col_map.items():
        alias_lines.append(f"{indent}-- migracao censo: alias para compatibilidade de painel")
        alias_lines.append(f"{indent}{new_col} AS {old_col},")

    from_pattern = re.compile(r"(\bFROM\b)", re.IGNORECASE)
    from_match = from_pattern.search(cte_block)
    if from_match and alias_lines:
        nl_before_from = cte_block.rfind("\n", 0, from_match.start())
        insert_pos = nl_before_from + 1 if nl_before_from != -1 else from_match.start()
        aliases_str = "\n".join(alias_lines) + "\n"
        cte_block = cte_block[:insert_pos] + aliases_str + cte_block[insert_pos:]

    cte_block = cte_block.replace(OLD_SOURCE_ID, NEW_SOURCE_ID)
    new_sql = sql[:start] + cte_block + sql[end:]
    new_sql = new_sql.replace(OLD_SOURCE_ID, NEW_SOURCE_ID)

    return new_sql


def replace_source_ref(sql: str, old_src: str, new_src: str) -> str:
    old_id = f"{{{{source('{DATASET}','{old_src}')}}}}"
    new_id = f"{{{{source('{DATASET}','{new_src}')}}}}"
    return sql.replace(old_id, new_id)


def _show_diff(original: str, modified: str, filepath: str) -> None:
    diff = difflib.unified_diff(
        original.splitlines(keepends=True),
        modified.splitlines(keepends=True),
        fromfile=f"a/{Path(filepath).name}",
        tofile=f"b/{Path(filepath).name}",
        lineterm="",
    )
    lines = list(diff)
    if not lines:
        _p(f"  {GRAY}(sem alteracoes){RESET}")
        return

    for line in lines:
        if line.startswith("+") and not line.startswith("+++"):
            _p(f"{GREEN}{line}{RESET}")
        elif line.startswith("-") and not line.startswith("---"):
            _p(f"{RED}{line}{RESET}")
        elif line.startswith("@@"):
            _p(f"{CYAN}{line}{RESET}")
        else:
            _p(f"{GRAY}{line}{RESET}")


# ---------------------------------------------------------------------------
# Modo: scan (default)
# ---------------------------------------------------------------------------

def cmd_scan(args) -> int:
    json_mode = getattr(args, "json", False)
    models_dir = MEC_ROOT / MODELS_REL

    if not models_dir.exists():
        print(
            f"  {RED}Diretorio de modelos nao encontrado: {models_dir}{RESET}",
            file=sys.stderr,
        )
        return EXIT_ERROR

    sql_files = sorted(models_dir.rglob("*.sql"))
    files_result = []
    pending_count = 0

    for sql_path in sql_files:
        try:
            sql = sql_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        scan = scan_sql_file(sql)
        if scan["needs_source_change"]:
            pending_count += 1
            files_result.append({
                "file": sql_path.name,
                "path": str(sql_path),
                "needs_source_change": True,
                "renamed_cols": scan["renamed_cols"],
                "unknown_cols": scan["unknown_cols"],
                "action": scan["action"],
            })

    if json_mode:
        output = {
            "scan": {
                "total_sql": len(sql_files),
                "with_old_source": pending_count,
                "files": files_result,
            }
        }
        print(json.dumps(output, ensure_ascii=False, indent=2))
        return EXIT_NEEDS_MIGRATION if pending_count > 0 else EXIT_OK

    _p()
    _p(f"  {PURPLE}{BOLD}SCAN DO PROJETO{RESET}")
    _p(_hr("─", 70))

    if not files_result:
        _p(f"  {GREEN}Nenhum arquivo com referencia a '{OLD_TABLE}' encontrado.{RESET}")
        _p(_hr("─", 70))
        return EXIT_OK

    _p(
        f"  {GRAY}{'ARQUIVO':<45} {'ACAO':<15} {'ALIASES':>7}  {'DESCONH.':>8}{RESET}"
    )
    _p(
        f"  {GRAY}{'─' * 45} {'─' * 15} {'─' * 7}  {'─' * 8}{RESET}"
    )

    for f in files_result:
        action_color = ORANGE if f["action"] == "source+aliases" else YELLOW
        _p(
            f"  {FG}{f['file']:<45}{RESET} {action_color}{f['action']:<15}{RESET}"
            f" {CYAN}{len(f['renamed_cols']):>7}{RESET}  {RED}{len(f['unknown_cols']):>8}{RESET}"
        )

    _p()
    _p(f"  {YELLOW}{pending_count} arquivo(s) precisam de migracao.{RESET}")
    _p(_hr("─", 70))

    return EXIT_NEEDS_MIGRATION if pending_count > 0 else EXIT_OK


# ---------------------------------------------------------------------------
# Modo: analyze
# ---------------------------------------------------------------------------

def cmd_analyze(args, client) -> int:
    sql_path = Path(args.sql_file).expanduser()
    if not sql_path.exists():
        print(f"  {RED}Arquivo nao encontrado: {sql_path}{RESET}", file=sys.stderr)
        return EXIT_ERROR

    sql = sql_path.read_text(encoding="utf-8")
    json_mode = getattr(args, "json", False)

    if not json_mode:
        _p()
        _p(f"  {PURPLE}{BOLD}ANALISE DE MODELO SQL{RESET}  {YELLOW}{'[mock]' if args.mock else ''}{RESET}")
        _p(_hr())
        _p(f"  {GRAY}Arquivo{RESET}  {FG}{sql_path.name}{RESET}")

    source_ref = re.search(
        rf"source\(['\"][^'\"]+['\"],\s*['\"]" + re.escape(OLD_TABLE) + r"['\"]",
        sql,
    )
    has_old_source = bool(source_ref)

    if not has_old_source:
        if json_mode:
            print(json.dumps({
                "file": sql_path.name,
                "has_old_source": False,
                "renamed_cols": [],
                "unknown_cols": [],
                "action": "ok",
            }, ensure_ascii=False, indent=2))
        else:
            _p(
                f"  {GRAY}Nenhuma referencia a '{OLD_TABLE}' encontrada. "
                f"Arquivo ja migrado ou nao usa censo.{RESET}"
            )
            _p(_hr())
        return EXIT_OK

    if not json_mode:
        _p(f"  {GREEN}Referencia a '{OLD_TABLE}' detectada.{RESET}")
        _p(_hr())

    if args.mock:
        old_schema = {col: "INTEGER" for col in MOCK_DATA.keys()}
        old_schema.update({
            "id_escola": "STRING", "ano": "INTEGER", "rede": "STRING",
            "id_municipio": "STRING", "tipo_situacao_funcionamento": "STRING",
            "escolarizacao": "INTEGER",
        })
    else:
        old_schema = get_table_schema(client, DATASET, OLD_TABLE)
        if not old_schema:
            print(
                f"  {RED}Nao foi possivel obter schema de {OLD_TABLE}{RESET}",
                file=sys.stderr,
            )
            return EXIT_ERROR

    renamed = find_renamed_cols_in_sql(sql, old_schema)
    referenced = find_cols_in_sql(sql, list(old_schema.keys()))

    if json_mode:
        print(json.dumps({
            "file": sql_path.name,
            "has_old_source": True,
            "referenced_cols": len(referenced),
            "renamed_cols": [
                {"old": o, "new": n, "status": "inferred"} for o, n in renamed
            ],
            "unknown_cols": [],
            "action": "source+aliases" if renamed else "source_only",
        }, ensure_ascii=False, indent=2))
        return EXIT_OK

    _p(f"\n  {GRAY}Colunas do schema antigo referenciadas no SQL: {CYAN}{len(referenced)}{RESET}")
    _p(f"  {GRAY}Colunas com renomeacao detectada:             {ORANGE}{len(renamed)}{RESET}")
    _p()

    if not renamed:
        _p(
            f"  {YELLOW}Nenhuma coluna renomeada detectada pelos padroes conhecidos.{RESET}"
        )
        _p(
            f"  {GRAY}Mas o source ainda precisa ser trocado. Use:{RESET}"
        )
        _p(
            f"    {CYAN}apply --sql-file {sql_path} --source-only{RESET}"
        )
        _p(_hr())
        return EXIT_OK

    _p(f"  {GRAY}{'COLUNA ANTIGA':<55} {'STATUS'}{RESET}")
    _p(f"  {GRAY}{'─' * 55} {'─' * 25}{RESET}")
    for old_col, new_col in renamed:
        if new_col:
            _p(f"  {FG}{old_col:<55}{RESET} {YELLOW}-> {new_col}{RESET}")
        else:
            _p(f"  {FG}{old_col:<55}{RESET} {RED}nao mapeada{RESET}")

    _p()
    _p(
        f"  {GRAY}Use{RESET} {CYAN}apply --sql-file {sql_path}{RESET} "
        f"{GRAY}para aplicar aliases interativamente.{RESET}"
    )
    _p(_hr())
    return EXIT_OK


# ---------------------------------------------------------------------------
# Modo: apply --source-only
# ---------------------------------------------------------------------------

def apply_source_only(sql_path: Path, dry_run: bool) -> int:
    sql = sql_path.read_text(encoding="utf-8")
    new_sql = sql.replace(OLD_SOURCE_ID, NEW_SOURCE_ID)

    if new_sql == sql:
        _p(
            f"  {YELLOW}Nenhuma referencia a '{OLD_TABLE}' encontrada. Nada a fazer.{RESET}"
        )
        return EXIT_OK

    _p()
    _p(f"  {PURPLE}{BOLD}DIFF GERADO:{RESET}")
    _p(_hr())
    _show_diff(sql, new_sql, str(sql_path))
    _p(_hr())

    if dry_run:
        _p(f"\n  {YELLOW}[dry-run]{RESET} {GRAY}Nenhum arquivo modificado.{RESET}")
        return EXIT_OK

    _p(
        f"\n  Confirmar escrita em {FG}{sql_path.name}{RESET}?"
        f" [{GREEN}s{RESET}/{RED}N{RESET}] ",
        end="", flush=True,
    )
    try:
        confirm = input().strip().lower()
    except (EOFError, KeyboardInterrupt):
        _p()
        return EXIT_OK

    if confirm == "s":
        sql_path.write_text(new_sql, encoding="utf-8")
        _p(f"  {GREEN}Arquivo atualizado: {sql_path}{RESET}")
    else:
        _p(f"  {GRAY}Escrita cancelada.{RESET}")

    return EXIT_OK


# ---------------------------------------------------------------------------
# Modo: apply (interativo)
# ---------------------------------------------------------------------------

def interactive_apply(
    sql_path: Path,
    client,
    mock: bool = False,
    dry_run: bool = False,
    yes_all: bool = False,
    quiet: bool = False,
    source_only: bool = False,
) -> int:
    if source_only:
        return apply_source_only(sql_path, dry_run)

    sql = sql_path.read_text(encoding="utf-8")

    _p()
    _p(
        f"  {PURPLE}{BOLD}MIGRACAO INTERATIVA{RESET}"
        f"  {YELLOW}{'[mock]' if mock else ''}{RESET}"
        f"  {GRAY}{'[dry-run]' if dry_run else ''}{RESET}"
        f"  {GRAY}{'[yes-all]' if yes_all else ''}{RESET}"
    )
    _p(_hr())
    _p(f"  {GRAY}Arquivo{RESET}  {FG}{sql_path.name}{RESET}")
    _p(_hr())

    source_ref = re.search(
        rf"source\(['\"][^'\"]+['\"],\s*['\"]" + re.escape(OLD_TABLE) + r"['\"]",
        sql,
    )
    if not source_ref:
        _p(f"  {YELLOW}Nenhuma referencia a '{OLD_TABLE}' encontrada. Nada a migrar.{RESET}")
        return EXIT_OK

    if mock:
        old_schema = {col: "INTEGER" for col in MOCK_DATA.keys()}
        old_schema.update({
            "id_escola": "STRING", "ano": "INTEGER", "rede": "STRING",
            "id_municipio": "STRING", "tipo_situacao_funcionamento": "STRING",
            "escolarizacao": "INTEGER",
        })
    else:
        old_schema = get_table_schema(client, DATASET, OLD_TABLE)
        if not old_schema:
            print(
                f"  {RED}Nao foi possivel obter schema de {OLD_TABLE}{RESET}",
                file=sys.stderr,
            )
            return EXIT_ERROR

    renamed = find_renamed_cols_in_sql(sql, old_schema)

    if not renamed:
        _p(f"  {GREEN}Nenhuma coluna para migrar detectada.{RESET}")
        _p(
            f"  {GRAY}Se o source ainda precisa ser trocado, use:{RESET}"
            f" {CYAN}apply --source-only{RESET}"
        )
        return EXIT_OK

    _p(f"\n  {FG}{len(renamed)} coluna(s) detectada(s) para migracao:{RESET}\n")

    col_map: dict[str, str] = {}

    for old_col, new_col in renamed:
        if new_col is None:
            _p(f"  {YELLOW}Coluna sem mapeamento: {old_col} — pulando.{RESET}")
            continue

        if quiet:
            _p(
                f"  {ORANGE}{old_col}{RESET} {GRAY}->{RESET} {CYAN}{new_col}{RESET}"
                f"  [{GREEN}s{RESET}/{RED}N{RESET}] ",
                end="", flush=True,
            )
        else:
            _p(f"  {GRAY}{'─' * 50}{RESET}")
            _p(f"  {ORANGE}Coluna:{RESET} {FG}{old_col}{RESET}")
            _p(f"  {GRAY}Nova  :{RESET} {CYAN}{new_col}{RESET}")

            if mock:
                mock_validate(old_col, new_col, verbose=True)
            else:
                validate_pair(client, old_col, new_col, verbose=True)

            _p()
            _p(
                f"  Aplicar alias {CYAN}{new_col} AS {old_col}{RESET}?"
                f" [{GREEN}s{RESET}/{RED}N{RESET}] ",
                end="", flush=True,
            )

        if yes_all:
            _p("s (auto)")
            col_map[new_col] = old_col
            if not quiet:
                _p(f"  {GREEN}Adicionado ao mapeamento.{RESET}")
            continue

        try:
            resp = input().strip().lower()
        except (EOFError, KeyboardInterrupt):
            _p()
            _p(f"\n  {GRAY}Cancelado.{RESET}")
            return EXIT_OK

        if resp == "s":
            col_map[new_col] = old_col
            if not quiet:
                _p(f"  {GREEN}Adicionado ao mapeamento.{RESET}")
        else:
            if not quiet:
                _p(f"  {GRAY}Ignorado.{RESET}")

    if not col_map:
        _p(f"\n  {GRAY}Nenhuma coluna selecionada para aplicacao.{RESET}")
        return EXIT_OK

    new_sql = inject_alias_in_cte(sql, col_map)

    _p()
    _p(f"  {PURPLE}{BOLD}DIFF GERADO:{RESET}")
    _p(_hr())
    _show_diff(sql, new_sql, str(sql_path))
    _p(_hr())

    if dry_run:
        _p(f"\n  {YELLOW}[dry-run]{RESET} {GRAY}Nenhum arquivo modificado.{RESET}")
        return EXIT_OK

    _p(
        f"\n  Confirmar escrita em {FG}{sql_path.name}{RESET}?"
        f" [{GREEN}s{RESET}/{RED}N{RESET}] ",
        end="", flush=True,
    )
    try:
        confirm = input().strip().lower()
    except (EOFError, KeyboardInterrupt):
        _p()
        _p(f"  {GRAY}Cancelado.{RESET}")
        return EXIT_OK

    if confirm == "s":
        sql_path.write_text(new_sql, encoding="utf-8")
        _p(f"  {GREEN}Arquivo atualizado: {sql_path}{RESET}")
    else:
        _p(f"  {GRAY}Escrita cancelada.{RESET}")

    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mec-migrar-censo",
        description="Validacao e migracao semi-automatizada de colunas do Censo Escolar",
    )
    parser.add_argument(
        "--no-sync", action="store_true",
        help="Pular sync automatico com origin/main",
    )
    parser.add_argument(
        "--json", action="store_true",
        help="Saida JSON em stdout (desabilita cores ANSI; progresso vai para stderr)",
    )

    sub = parser.add_subparsers(dest="cmd")

    p_validate = sub.add_parser("validate", help="Comparar par old_col vs new_col")
    p_validate.add_argument("--old-col", required=True, metavar="COL")
    p_validate.add_argument("--new-col", required=True, metavar="COL")
    p_validate.add_argument("--mock", action="store_true", help="Usar dados ficticios (sem BQ)")
    p_validate.add_argument("--no-sync", action="store_true")

    p_analyze = sub.add_parser("analyze", help="Inspecionar SQL file e listar colunas a migrar")
    p_analyze.add_argument("--sql-file", required=True, metavar="PATH")
    p_analyze.add_argument("--mock", action="store_true", help="Usar dados ficticios (sem BQ)")
    p_analyze.add_argument("--json", action="store_true")
    p_analyze.add_argument("--no-sync", action="store_true")

    p_apply = sub.add_parser("apply", help="Migracao interativa em SQL file")
    p_apply.add_argument("--sql-file", required=True, metavar="PATH")
    p_apply.add_argument("--mock", action="store_true", help="Usar dados ficticios (sem BQ)")
    p_apply.add_argument("--dry-run", action="store_true", help="Exibir diff sem escrever")
    p_apply.add_argument(
        "--yes-all", action="store_true",
        help="Aceitar automaticamente todos os aliases inferidos",
    )
    p_apply.add_argument(
        "--quiet", action="store_true",
        help="Suprimir passos de validacao; exibir apenas linha de rename",
    )
    p_apply.add_argument(
        "--source-only", action="store_true",
        help="Trocar apenas OLD_SOURCE_ID -> NEW_SOURCE_ID, sem aliases",
    )
    p_apply.add_argument("--no-sync", action="store_true")

    return parser


def main() -> int:
    global _JSON_MODE

    parser = build_parser()
    args = parser.parse_args()

    json_mode = getattr(args, "json", False)
    _JSON_MODE = json_mode
    _init_colors(not json_mode)

    no_sync = getattr(args, "no_sync", False)

    sync_result: dict | None = None
    if not no_sync and MEC_ROOT.exists():
        try:
            sync_result = sync_sql_files(MEC_ROOT, quiet=json_mode)
            if sync_result.get("error"):
                print(
                    f"  {YELLOW}[sync] aviso: {sync_result['error']}{RESET}",
                    file=sys.stderr,
                )
        except (subprocess.TimeoutExpired, FileNotFoundError):
            print("  [sync] aviso: falha ao contactar remoto — continuando offline.", file=sys.stderr)
            sync_result = {"error": "timeout", "updated": []}

    # Scan e o modo default (sem subcomando)
    if args.cmd is None:
        if json_mode and sync_result is not None:
            # Incluir sync no JSON de saida
            pass  # cmd_scan produz o JSON; sync_result e passado via stderr
        return cmd_scan(args)

    mock = getattr(args, "mock", False)
    client = None
    if not mock:
        client = get_bq_client(PROJECT_DEV)

    if args.cmd == "validate":
        if mock:
            result = mock_validate(args.old_col, args.new_col, verbose=True)
        else:
            result = validate_pair(client, args.old_col, args.new_col, verbose=True)

        if result["all_ok"]:
            _p()
            _p(
                f"  Aplicar em arquivos SQL? [{GREEN}s{RESET}/{RED}N{RESET}] ",
                end="", flush=True,
            )
            try:
                resp = input().strip().lower()
            except (EOFError, KeyboardInterrupt):
                _p()
                return EXIT_OK
            if resp == "s":
                _p(f"  {GRAY}Use o modo 'apply' para aplicar em um arquivo especifico.{RESET}")
        return EXIT_OK

    elif args.cmd == "analyze":
        return cmd_analyze(args, client)

    elif args.cmd == "apply":
        sql_path = Path(args.sql_file).expanduser()
        return interactive_apply(
            sql_path,
            client,
            mock=mock,
            dry_run=args.dry_run,
            yes_all=args.yes_all,
            quiet=args.quiet,
            source_only=args.source_only,
        )

    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())

# "A virtude consiste na disposicao para agir com proposito." — Aristoteles
