# Changelog

## [Não lançado]

### Adicionado
- Navegação "Voltar" entre etapas do TUI (máquina de estados com `--cancel-button`)
- Detecção automática de variáveis de ambiente existentes em todas as etapas do TUI
- Label "Perfil Profissional" no lugar de "Identidade MEC" nos diálogos TUI
- Mensagem de sucesso ao final da instalação
- Módulo `encoding.zsh` — detecção e conversão de encoding (UTF-8, CRLF)
- Módulo `fontes.zsh` — instalação e verificação de fontes de compatibilidade
- Módulo `restaurar.zsh` — backup e restauração de sistema via manifesto
- Etapa de instalação de fontes base (ttf-mscorefonts, Liberation, Noto)
- Etapa de ferramentas de encoding (dos2unix)
- `diagnostico_projeto`: pool de senhas acumulativo — senha digitada uma vez é reutilizada automaticamente em todos os arquivos protegidos subsequentes (PDF, xlsx, xls)
- `diagnostico_projeto`: extração de texto de PDFs via PyMuPDF com suporte a senha
- `diagnostico_projeto`: embedding de imagens no dossiê — base64 inline para arquivos < 1 MB, link relativo para arquivos maiores (JPEG, PNG, GIF, SVG, WebP, AVIF, HEIC e outros)
- `diagnostico_projeto`: suporte a todos os formatos de arquivo de dados (CSV, Excel, JSON, Parquet) com análise via `analisador-dados.py`
- `analisador-dados.py`: suporte a `--passwords-file` para pool de senhas externo

### Corrigido
- Bug de corrupção do `config.local.zsh` na substituição `$HOME` → `${HOME}` via heredoc
- Título do TUI invisível no Cosmic DE (lightcyan → white)
- Skip inteligente do TUI quando configuração existente é detectada
- `diagnostico_projeto`: terminal travava após conclusão (`wc -l < /dev/stdin` bloqueava no TTY; prompt `read -k 1` ficava invisível por estar dentro do redirect)
- `diagnostico_projeto`: saída markdown gerada dentro de code fence externo fazia renderização falhar no GitHub e Obsidian
- `analisador-dados.py`: `pd.read_csv(errors='ignore')` inválido no pandas 3.x — substituído por `on_bad_lines='skip', encoding_errors='ignore'`
- `analisador-dados.py`: arquivos `.xls` (OLE2) não eram descriptografados pelo pool de senhas por falso negativo no `is_xlsx_encrypted` — lógica reescrita para tentar abertura direta primeiro e fallback para pool em qualquer falha

### Alterado
- `diagnostico_projeto`: documento gerado reformulado para renderização GitHub/Obsidian — cabeçalho `#`, seções `##` com separadores `---`, árvore em code block direto, arquivos com labels de tipo (`[PDF]`, `[CSV]`, `[Excel]`, `[Imagem]`, `[Python]`, etc.) nos colapsáveis `<details>`
- `diagnostico.zsh`: acentuação corrigida em toda extensão do arquivo
- `analisador-dados.py`: acentuação corrigida em toda extensão do script

## [1.0.0] - 2023-01-01

### Adicionado
- Configuração zsh modular com 23 módulos de funções
- Menu FZF interativo para projetos dbt/BigQuery
- Controle automático de identidade git por contexto
- Integração com Oh My Zsh
- 9 scripts Python utilitários
- Script de instalação único para Linux
- Templates de configuração local
