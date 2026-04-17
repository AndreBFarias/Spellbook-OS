#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import os
import re

def sanitize_filename(name):
    # Substitui caracteres proibidos em sistemas de arquivos
    return re.sub(r'[<>:"/\\|?*]', '_', name)

def main(input_file, output_dir):
    if not os.path.exists(input_file):
        print(f"Erro Crítico: O arquivo '{input_file}' não existe.")
        sys.exit(1)

    print(f"Lendo pergaminho: '{os.path.basename(input_file)}'...")

    try:
        with open(input_file, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
    except Exception as e:
        print(f"Falha fatal na leitura: {e}")
        sys.exit(1)

    # Regex para capturar caminhos e metadados nos blocos <details> do Markdown
    re_file = re.compile(r'<details.*><summary>.*<code>(.*?)</code>.*</summary>')
    re_meta = re.compile(r'<details.*><summary>.*<strong>(.*?)</strong>.*</summary>')

    current_path = None
    is_metadata = False
    content_buffer = []
    state = "SEARCHING"

    count_files = 0
    count_meta = 0

    for line in lines:
        line_stripped = line.strip()

        # ESTADO 1: Procurando marcadores de início
        if state == "SEARCHING":
            # Caso 1: Arquivo de código real
            match_file = re_file.search(line)
            if match_file:
                raw_path = match_file.group(1).strip()
                # Proteção básica contra path traversal
                if ".." in raw_path or raw_path.startswith("/"):
                    print(f"Caminho inseguro ignorado: {raw_path}")
                    continue

                current_path = os.path.join(output_dir, raw_path)
                is_metadata = False
                state = "WAITING_BLOCK"
                content_buffer = []
                continue

            # Caso 2: Metadados (Git, Ambiente, etc)
            match_meta = re_meta.search(line)
            if match_meta:
                title = match_meta.group(1).strip()
                filename = f"_INFO_{sanitize_filename(title)}.txt"
                current_path = os.path.join(output_dir, filename)
                is_metadata = True
                state = "WAITING_BLOCK"
                content_buffer = []
                continue

        # ESTADO 2: Esperando o bloco de código abrir (```)
        elif state == "WAITING_BLOCK":
            if line_stripped.startswith("```"):
                state = "READING"
                continue

        # ESTADO 3: Lendo o conteúdo até o bloco fechar
        elif state == "READING":
            if line_stripped.startswith("```"):
                # Fim do bloco - Hora de gravar
                if current_path:
                    try:
                        # Garante que a pasta pai existe
                        dir_name = os.path.dirname(current_path)
                        if dir_name and not os.path.exists(dir_name):
                            os.makedirs(dir_name, exist_ok=True)

                        content_str = "".join(content_buffer)

                        # Lógica para marcadores especiais (Binários/Vazios)
                        if "[ARQUIVO BINÁRIO]" in content_str and not is_metadata:
                            with open(current_path + ".txt", 'w', encoding='utf-8') as f:
                                f.write(f"--- MARKER: ARQUIVO BINÁRIO ORIGINAL ---\nO conteúdo original era binário e não foi incluído no markdown.\nCaminho original: {current_path}")
                            print(f"Binario (Placeholder): {os.path.basename(current_path)}")

                        elif "[ARQUIVO VAZIO]" in content_str and len(content_str.strip()) < 20:
                             # Cria arquivo vazio
                             with open(current_path, 'w', encoding='utf-8') as f:
                                 pass
                             # print(f"Vazio: {os.path.relpath(current_path, output_dir)}")
                             count_files += 1

                        else:
                            # Gravação normal
                            with open(current_path, 'w', encoding='utf-8') as f:
                                f.write(content_str)

                            if is_metadata:
                                print(f"Metadado: {os.path.basename(current_path)}")
                                count_meta += 1
                            else:
                                rel_path = os.path.relpath(current_path, output_dir)
                                print(f"Restaurado: {rel_path}")
                                count_files += 1

                    except Exception as e:
                        print(f"Erro de gravacao em {current_path}: {e}")

                current_path = None
                state = "SEARCHING"
            else:
                # Acumula linha no buffer
                content_buffer.append(line)

    print("-" * 40)
    print(f"Materializacao concluida em: {output_dir}")
    print(f"   Arquivos: {count_files} | Infos: {count_meta}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Uso: python _reconstrutor_helper.py <arquivo_entrada> <diretorio_destino>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
