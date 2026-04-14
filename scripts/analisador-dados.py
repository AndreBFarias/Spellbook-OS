#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import base64
import csv
import io
import json
import mimetypes
import os
import sys

import pandas as pd

IMAGE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.gif', '.svg', '.webp',
                    '.bmp', '.tiff', '.tif', '.heic', '.avif'}
IMAGE_THRESHOLD_MB = 1.0


def load_password_pool(passwords_file):
    if not passwords_file or not os.path.exists(passwords_file):
        return []
    with open(passwords_file, 'r', encoding='utf-8') as f:
        return [line.strip() for line in f if line.strip()]


def detect_delimiter(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            sample = f.read(2048)
            sniffer = csv.Sniffer()
            dialect = sniffer.sniff(sample)
            return dialect.delimiter
    except Exception:
        for sep in [',', ';', '\t', '|']:
            try:
                pd.read_csv(file_path, sep=sep, nrows=2, encoding='utf-8',
                            on_bad_lines='skip', encoding_errors='ignore')
                return sep
            except Exception:
                continue
        return ','


def handle_image(file_path):
    size_bytes = os.path.getsize(file_path)
    size_mb = size_bytes / (1024 * 1024)
    filename = os.path.basename(file_path)

    mime_type, _ = mimetypes.guess_type(file_path)
    if not mime_type:
        ext = os.path.splitext(file_path)[1].lower()
        fallback = {'.heic': 'image/heic', '.avif': 'image/avif', '.webp': 'image/webp'}
        mime_type = fallback.get(ext, 'image/jpeg')

    output = [
        f"### Imagem: `{file_path}`\n",
        f"- **Tamanho**: {size_mb:.2f} MB",
        f"- **Formato**: {mime_type}\n",
    ]

    if size_mb < IMAGE_THRESHOLD_MB:
        with open(file_path, 'rb') as f:
            data = base64.b64encode(f.read()).decode('ascii')
        output.append(f"![{filename}](data:{mime_type};base64,{data})")
    else:
        output.append(f"![{filename}]({file_path})")
        output.append(f"\n> Imagem grande ({size_mb:.1f} MB) — link relativo ao projeto")

    return "\n".join(output)


def summarize_pdf(file_path, passwords=None, max_lines=300):
    try:
        import fitz
    except ImportError:
        return (f"### PDF: `{file_path}`\n\n"
                "[PyMuPDF não instalado — instale com: pip install pymupdf]")

    try:
        doc = fitz.open(file_path)
    except Exception as e:
        return f"### PDF: `{file_path}`\n\n[ERRO ao abrir: {e}]"

    if doc.is_encrypted:
        opened = False
        for pwd in (passwords or []):
            if doc.authenticate(pwd):
                opened = True
                break
        if not opened:
            doc.close()
            sys.exit(125)

    output = [f"### PDF: `{file_path}`\n"]
    meta = doc.metadata
    if meta.get('title'):
        output.append(f"- **Título**: {meta['title']}")
    if meta.get('author'):
        output.append(f"- **Autor**: {meta['author']}")
    output.append(f"- **Páginas**: {doc.page_count}\n")

    lines_remaining = max_lines
    has_text = False

    for i, page in enumerate(doc):
        if lines_remaining <= 0:
            output.append(f"\n> Truncado em {max_lines} linhas.")
            break
        text = page.get_text().strip()
        if not text:
            continue
        has_text = True
        output.append(f"#### Página {i + 1}\n\n```")
        page_lines = text.splitlines()
        if len(page_lines) > lines_remaining:
            output.append('\n'.join(page_lines[:lines_remaining]))
            output.append(f"\n... (truncado: {lines_remaining}/{len(page_lines)} linhas)")
            lines_remaining = 0
        else:
            output.append('\n'.join(page_lines))
            lines_remaining -= len(page_lines)
        output.append("```\n")

    if not has_text:
        output.append("[PDF sem camada de texto — provavelmente escaneado sem OCR]")

    doc.close()
    return "\n".join(output)


def open_protected_xlsx(file_path, passwords):
    try:
        import msoffcrypto
    except ImportError:
        return None

    for pwd in (passwords or []):
        try:
            with open(file_path, 'rb') as f:
                office_file = msoffcrypto.OfficeFile(f)
                office_file.load_key(password=pwd)
                buf = io.BytesIO()
                office_file.decrypt(buf)
                buf.seek(0)
                return buf
        except Exception:
            continue
    return None


def summarize_xlsx(file_path, passwords=None):
    # Tentativa direta (sem senha)
    xls = None
    try:
        xls = pd.ExcelFile(file_path)
    except Exception:
        pass

    # Se falhou, tentar descriptografar com cada senha do pool
    if xls is None and passwords:
        buf = open_protected_xlsx(file_path, passwords)
        if buf is not None:
            try:
                xls = pd.ExcelFile(buf)
            except Exception:
                xls = None

    # Sem sucesso: arquivo precisa de senha não disponível no pool
    if xls is None:
        sys.exit(125)

    output = []
    for sheet in xls.sheet_names:
        try:
            df = pd.read_excel(xls, sheet_name=sheet, nrows=1000)
            output.append(summarize_dataframe(df, file_path, sheet_name=sheet))
            output.append("\n" + "=" * 40 + "\n")
        except Exception as e:
            output.append(f"Erro ao ler aba '{sheet}': {e}")

    return "\n".join(output)


def summarize_json(file_path):
    output = []
    output.append(f"### Análise JSON: `{file_path}`\n")
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)

        file_type = type(data).__name__
        output.append(f"- **Estrutura Raiz**: {file_type}")

        if isinstance(data, list):
            output.append(f"- **Total de Itens**: {len(data)}")
            output.append("#### Amostra (Primeiros 5 itens)\n")
            output.append("```json")
            output.append(json.dumps(data[:5], indent=2, ensure_ascii=False))
            output.append("\n```")
        elif isinstance(data, dict):
            keys = list(data.keys())
            output.append(f"- **Chaves Principais ({len(keys)})**: {', '.join(keys[:10])}...")
            output.append("#### Amostra (Resumo)\n")
            output.append("```json")
            sample_dict = {k: data[k] for k in keys[:5]}
            output.append(json.dumps(sample_dict, indent=2, ensure_ascii=False))
            output.append("\n```")
        else:
            output.append("#### Conteúdo\n")
            output.append(str(data))

    except Exception as e:
        output.append(f"**ERRO AO LER JSON**: {e}")

    return "\n".join(output)


def summarize_dataframe(df, file_path, delimiter=None, sheet_name=None):
    output = []
    file_type = "CSV/TXT" if file_path.lower().endswith(('.csv', '.txt')) else "Excel"

    if sheet_name:
        output.append(f"### Análise: `{file_path}` | Aba: `{sheet_name}`\n")
    else:
        output.append(f"### Análise de Dados: `{file_path}`\n")

    output.append(f"- **Tipo**: {file_type}")
    if delimiter:
        output.append(f"- **Separador Detectado**: `{delimiter}`")
    output.append(f"- **Estrutura**: {df.shape[0]} linhas x {df.shape[1]} colunas\n")
    output.append("#### Amostra dos Dados (5 primeiras linhas)\n")
    try:
        output.append(df.head(5).to_markdown(index=False))
    except ImportError:
        output.append("AVISO: Biblioteca 'tabulate' não encontrada. Exibindo em formato simples.\n")
        output.append(df.head(5).to_string())
    output.append("\n")

    summary_data = []
    for col in df.columns:
        col_type = df[col].dtype
        non_nulls = df[col].count()
        nulls = len(df) - non_nulls
        summary_data.append({"Coluna": f"`{col}`", "Tipo": col_type, "Nulos": nulls})

    summary_df = pd.DataFrame(summary_data)
    try:
        output.append("#### Resumo das Colunas\n")
        output.append(summary_df.head(10).to_markdown(index=False))
        if len(summary_df) > 10:
            output.append(f"\n*(... e mais {len(summary_df) - 10} colunas)*")
    except ImportError:
        output.append(summary_df.head(10).to_string())

    return "\n".join(output)


def main():
    parser = argparse.ArgumentParser(description="Analisador de dados para diagnostico_projeto")
    parser.add_argument('file_path', help="Arquivo a analisar")
    parser.add_argument('--passwords-file', default=None,
                        help="Arquivo com pool de senhas (uma por linha)")
    args = parser.parse_args()

    file_path = args.file_path
    passwords = load_password_pool(args.passwords_file)
    ext = os.path.splitext(file_path)[1].lower()

    try:
        if ext in IMAGE_EXTENSIONS:
            print(handle_image(file_path))
            sys.exit(0)

        if ext == '.pdf':
            print(summarize_pdf(file_path, passwords, max_lines=300))
            sys.exit(0)

        if ext == '.json':
            print(summarize_json(file_path))
            sys.exit(0)

        if ext in ('.csv', '.txt'):
            delimiter = detect_delimiter(file_path)
            df = pd.read_csv(file_path, sep=delimiter, nrows=1000, encoding='utf-8',
                             on_bad_lines='skip', encoding_errors='ignore')
            print(summarize_dataframe(df, file_path, delimiter))
            sys.exit(0)

        if ext in ('.xlsx', '.xls'):
            print(summarize_xlsx(file_path, passwords))
            sys.exit(0)

        if ext == '.parquet':
            df = pd.read_parquet(file_path)
            print(summarize_dataframe(df, file_path))
            sys.exit(0)

        # Fallback: leitura simples como texto
        with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
            print(f.read(2000))

    except SystemExit:
        raise
    except Exception as e:
        print(f"### Análise de Dados: `{file_path}`\n")
        print(f"**STATUS**: FALHA NA LEITURA ESTRUTURADA\n")
        print("```")
        print(f"Erro: {e}")
        print("```")
        sys.exit(1)


if __name__ == "__main__":
    main()
