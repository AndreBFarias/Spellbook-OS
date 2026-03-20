#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import pandas as pd
import json
import sys
import io
import csv

#1
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
                pd.read_csv(file_path, sep=sep, nrows=2, encoding='utf-8', errors='ignore')
                return sep
            except Exception:
                continue
        return ','

#2
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
            # Cria um sub-dicionário apenas para visualização
            sample_dict = {k: data[k] for k in keys[:5]}
            output.append(json.dumps(sample_dict, indent=2, ensure_ascii=False))
            output.append("\n```")
        else:
            output.append("#### Conteúdo\n")
            output.append(str(data))

    except Exception as e:
        output.append(f"**ERRO AO LER JSON**: {e}")

    return "\n".join(output)

#3
def summarize_dataframe(df, file_path, delimiter=None, sheet_name=None):
    output = []
    file_type = "CSV/TXT" if file_path.lower().endswith(('.csv', '.txt')) else "Excel/Parquet"

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

    output.append("#### Resumo das Colunas\n")
    summary_data = []
    # Limita a análise a 50 colunas para não travar em datasets gigantes
    cols_to_analyze = df.columns[:50]

    for col in cols_to_analyze:
        col_type = df[col].dtype
        non_nulls = df[col].count()
        total = len(df)
        nulls = total - non_nulls
        fill_rate = (non_nulls / total) * 100 if total > 0 else 0

        col_summary = {
            "Coluna": f"`{col}`", "Tipo": col_type,
            "% Full": f"{fill_rate:.0f}%", "Resumo": "N/A"
        }

        if pd.api.types.is_numeric_dtype(col_type):
            stats = df[col].describe()
            col_summary["Resumo"] = f"Média:{stats.get('mean', 0):.2f} | Max:{stats.get('max', 0):.2f}"
        else:
            try:
                top3 = df[col].value_counts().head(3).to_dict()
                top3_str = ', '.join([f"'{str(k)}'" for k in top3.keys()])
                col_summary["Resumo"] = f"Top: {top3_str}"
            except Exception:
                col_summary["Resumo"] = "Mist/Erro"
        summary_data.append(col_summary)

    summary_df = pd.DataFrame(summary_data)
    try:
        output.append(summary_df.to_markdown(index=False))
    except ImportError:
        output.append(summary_df.to_string())

    if len(df.columns) > 50:
        output.append(f"\n*(... e mais {len(df.columns) - 50} colunas não analisadas)*")

    return "\n".join(output)

def main():
    if len(sys.argv) < 2:
        print("Uso: python __dossie_processar_planilha.py <caminho_do_arquivo>")
        sys.exit(1)
    file_path = sys.argv[1]

    try:
        # Rota JSON
        if file_path.lower().endswith('.json'):
            print(summarize_json(file_path))
            sys.exit(0)

        df = None; delimiter = None

        # Rota CSV / TXT
        if file_path.lower().endswith(('.csv', '.txt')):
            delimiter = detect_delimiter(file_path)
            df = pd.read_csv(file_path, sep=delimiter, nrows=1000, engine='python', encoding='utf-8', errors='ignore')
            print(summarize_dataframe(df, file_path, delimiter))

        # Rota Excel (Multi-Aba)
        elif file_path.lower().endswith(('.xlsx', '.xls')):
            xls = pd.ExcelFile(file_path)
            for sheet in xls.sheet_names:
                try:
                    df = pd.read_excel(xls, sheet_name=sheet, nrows=1000)
                    print(summarize_dataframe(df, file_path, sheet_name=sheet))
                    print("\n" + "="*40 + "\n")
                except Exception as e:
                    print(f"Erro ao ler aba '{sheet}': {e}")

        # Rota Parquet
        elif file_path.lower().endswith('.parquet'):
            df = pd.read_parquet(file_path)
            print(summarize_dataframe(df, file_path))

        else:
            # Fallback forçado: Tenta ler como texto se não for reconhecido
            raise ValueError("Formato desconhecido, tentando leitura bruta.")

    except Exception as e:
        # Fallback de Segurança: Exibe o conteúdo bruto se a análise estruturada falhar
        print(f"### Leitura Bruta: `{file_path}`\n")
        print(f"**AVISO**: A análise estruturada falhou ({e}). Exibindo conteúdo raw:\n")
        print("```")
        try:
            with open(file_path, 'r', encoding='utf-8', errors='replace') as f:
                print(f.read(2000))
        except Exception as e2:
             print(f"Erro fatal até na leitura bruta: {e2}")
        print("\n```")
        # Não sai com erro (sys.exit(1)) para não quebrar o script bash que chama este

if __name__ == "__main__":
    main()
