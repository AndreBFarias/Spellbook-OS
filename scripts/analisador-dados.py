import pandas as pd
import json
import sys
import io
import csv

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

#1
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

def summarize_dataframe(df, file_path, delimiter=None, sheet_name=None):
    output = []
    file_type = "CSV/TXT" if file_path.lower().endswith(('.csv', '.txt')) else "Excel"

#2
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

    # Análise das colunas (mantida simplificada para não estourar o output)
    summary_data = []
    for col in df.columns:
        col_type = df[col].dtype
        non_nulls = df[col].count()
        total = len(df)
        nulls = total - non_nulls
        col_summary = {
            "Coluna": f"`{col}`",
            "Tipo": col_type,
            "Nulos": nulls
        }
        summary_data.append(col_summary)

    summary_df = pd.DataFrame(summary_data)
    try:
        output.append("#### Resumo das Colunas\n")
        output.append(summary_df.head(10).to_markdown(index=False)) # Limita a 10 colunas no resumo para economizar espaço
        if len(summary_df) > 10:
             output.append(f"\n*(... e mais {len(summary_df) - 10} colunas)*")
    except ImportError:
        output.append(summary_df.head(10).to_string())

    return "\n".join(output)

def main():
    if len(sys.argv) < 2:
        print("Uso: python analisador_dados.py <caminho_do_arquivo>")
        sys.exit(1)
    file_path = sys.argv[1]

    try:
#1
        if file_path.lower().endswith('.json'):
            print(summarize_json(file_path))
            sys.exit(0)

        df = None; delimiter = None

        if file_path.lower().endswith(('.csv', '.txt')):
            delimiter = detect_delimiter(file_path)
            df = pd.read_csv(file_path, sep=delimiter, nrows=1000, engine='python', encoding='utf-8', errors='ignore')
            print(summarize_dataframe(df, file_path, delimiter))

#2
        elif file_path.lower().endswith(('.xlsx', '.xls')):
            xls = pd.ExcelFile(file_path)
            # Itera sobre todas as abas
            for sheet in xls.sheet_names:
                try:
                    df = pd.read_excel(xls, sheet_name=sheet, nrows=1000)
                    print(summarize_dataframe(df, file_path, sheet_name=sheet))
                    print("\n" + "="*40 + "\n") # Separador visual entre abas
                except Exception as e:
                    print(f"Erro ao ler aba '{sheet}': {e}")

        elif file_path.lower().endswith('.parquet'):
            df = pd.read_parquet(file_path)
            print(summarize_dataframe(df, file_path))

        else:
            # Fallback para tentar ler como texto simples se não for reconhecido, mas passado pro script
            print(f"Formato não estruturado padrão. Tentando leitura simples...")
            with open(file_path, 'r', errors='replace') as f:
                print(f.read(2000))

    except Exception as e:
        print(f"### Análise de Dados: `{file_path}`\n")
        print(f"**STATUS**: FALHA NA LEITURA ESTRUTURADA\n")
        print("```")
        print(f"Erro: {e}")
        print("```")
        sys.exit(1)

if __name__ == "__main__":
    main()
