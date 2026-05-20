# MEC — Guia de Contexto do Projeto
# Projeto: pipelines-main | ENV: dev | STATUS: produção

---

## 1. Estrutura do projeto

```
pipelines-main/
├── .pipelines/          # Venv isolado com adaptadores BigQuery
│   └── bin/
│       ├── dbt          # USAR ESTE — tem adaptador BigQuery
│       └── python       # Python do venv do projeto
├── dev/                 # profiles.yml para dbt (dataset dev)
│   └── profiles.yml
├── queries/             # Raiz do projeto dbt
│   ├── dbt_project.yml
│   ├── models/          # Modelos SQL organizados por pasta
│   │   ├── staging/
│   │   ├── intermediate/
│   │   └── marts/
│   ├── tests/           # Testes dbt (singular + generic)
│   ├── macros/          # Macros Jinja2
│   ├── seeds/           # Dados estáticos CSV
│   └── target/          # Saída gerada (não commitar)
│       └── run_results.json   # Resultado do último dbt run/build/test
└── scripts/             # Scripts Python auxiliares
```

---

## 2. Regras obrigatórias

### dbt

- **SEMPRE** usar `.pipelines/bin/dbt`, nunca o `dbt` global do sistema.
  O dbt global não tem o adaptador BigQuery — silently quebra sem erro claro.
- **SEMPRE** entrar em `queries/` antes de rodar dbt:
  ```bash
  cd queries/ && ../.pipelines/bin/dbt run --profiles-dir ../dev
  ```
- `--profiles-dir ../dev` é relativo ao CWD (`queries/`), não ao `--project-dir`.
- Dataset alvo: **dev** (nunca prod direto sem revisão).

### git

- Identidade local: `user.name = andrefariasmec`, `user.email = andrefarias@mec.gov.br`
- **Nunca** commitar direto em `main`. Branches: `feat/xxx`, `fix/xxx`, `refactor/xxx`.
- Pull com rebase: `git pull --rebase` (não merge).
- Nenhum `reset --hard` sem backup ou confirmação explícita.
- Mensagens de commit em **PT-BR com acentuação correta** (obrigatório).
  Exemplos corretos: `migração`, `padrões`, `correção`, `revisão`, `atualização`.
- Fluxo de branches: `feature/xxx` → `develop` → `main` (nunca feature direto em `main`).

---

## 3. Comandos rápidos

| Alias | Expansão | Descrição |
|-------|----------|-----------|
| `mec` | `conjurar_mec` | Menu FZF com 29 operações |
| `conjurar_mec` | — | Abre menu interativo MEC |
| `santuario MEC pipelines-main` | — | Setup completo do projeto |
| `git_info` | — | Exibe identidade git local |

### dbt manual (de dentro de `queries/`)

```bash
# Compilar (valida SQL sem executar)
../.pipelines/bin/dbt compile --profiles-dir ../dev

# Rodar todos os modelos
../.pipelines/bin/dbt run --profiles-dir ../dev

# Rodar modelos específicos
../.pipelines/bin/dbt run --profiles-dir ../dev --select modelo_a modelo_b

# Build completo (run + test)
../.pipelines/bin/dbt build --profiles-dir ../dev

# Testes de qualidade
../.pipelines/bin/dbt test --profiles-dir ../dev

# Listar modelos
../.pipelines/bin/dbt ls --profiles-dir ../dev
```

### Ver resultados do último run

```bash
python3 ~/.config/zsh/scripts/mec-dbt-results.py queries/target/run_results.json
```

---

## 4. Contexto de identidade

A função `__aplicar_contexto_git_automatico` em `git-contexto.zsh` detecta o
diretório atual e aplica `git config --local` automaticamente:

```
/MEC/pipelines-main  →  andrefariasmec / andrefarias@mec.gov.br
/VitoriaMariaDB/     →  vitoriamariadb / vitoriamaria.sds@gmail.com
qualquer outro       →  AndreBFarias   / andre.dsbf@gmail.com
```

Esse contexto é aplicado em:
- `santuario MEC pipelines-main`
- Abertura automática via hooks do projeto

Verificar com: `git config --local user.email`

---

## 5. Variáveis de ambiente (constantes em mec.zsh)

| Variável | Valor |
|----------|-------|
| `__MEC_ROOT` | `~/Desenvolvimento/MEC/pipelines-main` |
| `__MEC_DBT_BIN` | `$__MEC_ROOT/.pipelines/bin/dbt` |
| `__MEC_DBT_DIR` | `$__MEC_ROOT/queries` |
| `__MEC_PROFILES_DIR` | `$__MEC_ROOT/dev` |
| `__MEC_RESULTS_JSON` | `$__MEC_DBT_DIR/target/run_results.json` |
| `__MEC_PYTHON` | `$__MEC_ROOT/.pipelines/bin/python` |
| `__MEC_RESULTS_SCRIPT` | `~/.config/zsh/scripts/mec-dbt-results.py` |

---

## 6. Modelos e schemas

Convenção de pastas em `queries/models/`:

| Pasta | Materialização padrão | Descrição |
|-------|-----------------------|-----------|
| `staging/` | view | Camada raw: renomeio + cast de tipos |
| `intermediate/` | view | Lógica de negócio intermediária |
| `marts/` | table | Dados finais para consumo |
| `seeds/` | — | Tabelas CSV estáticas |

Prefixo de nome: `br_mec_segape.<modelo>` (dataset no BigQuery).

---

## 7. Workflow padrão (9 etapas)

```
1. santuario MEC pipelines-main    # Setup: cd + identidade + venv
2. git pull --rebase               # Sincronizar com remoto
3. git checkout -b feat/nome       # Criar branch de trabalho
4. (editar modelos SQL/YAML)
5. cd queries/ && dbt compile      # Validar SQL
6. dbt run --select modelo         # Testar no dev
7. git add + commit                # Commitar com mensagem PT-BR
8. push com checklist (mec menu)   # 4 checks antes do push
9. Abrir PR no GitHub              # target: develop (NUNCA main)
```

---

## 8. Armadilhas conhecidas

### `--profiles-dir` é relativo ao CWD
Errado: rodar `dbt` da raiz do projeto com `--profiles-dir dev`.
Certo: entrar em `queries/` e usar `--profiles-dir ../dev`.

### `run_results.json` em `queries/target/`
O arquivo fica em `queries/target/run_results.json`, NÃO na raiz.
Script: verificar existência antes de parsear.

### `grep -c` com zero matches
Em alguns sistemas, `grep -c` retorna exit 1 quando não há matches.
Padrão seguro: `grep -c ... 2>/dev/null || echo "0"`.

### Branch sem upstream
`git rev-list --count @{u}..HEAD` falha se branch não tem upstream configurado.
Padrão seguro: `git rev-list --count ... 2>/dev/null || echo "0"`.

### `dbt ls` requer conexão BigQuery
Para seleção local de modelos, usar `find queries/models/ -name "*.sql"`.
`dbt ls` só quando já estiver online e autenticado.

### `__sinc_preservadora` usa `reset --hard`
A função `__sinc_preservadora` em `git-contexto.zsh` faz `reset --hard`.
NÃO reutilizar ela para sincronização no MEC. Usar `__mec_git_pull_seguro`.

### `generate_schema_name` ignora `--target`
A macro `queries/macros/generate_schema_name.sql` usa `+schema` do `dbt_project.yml`
quando configurado. Isso SOBRESCREVE o dataset do target.

Exemplo: `--target andre_teste` com `dataset: andre_teste` NÃO funciona para
`projeto_painel_ministro` porque `dbt_project.yml` define `+schema: projeto_painel_ministro`.

Resultado: todos os runs vão para o dataset `projeto_painel_ministro` no projeto dev,
independente do `--target`. Não existe isolamento por target neste projeto.

### `dbt compile` não detecta erros de runtime
`dbt compile` valida somente: sintaxe SQL, refs existentes, sources definidos.
NÃO detecta: coluna inexistente, type mismatch, policy tag IAM, erros de JOIN.

Esses erros só aparecem em `dbt run` no BigQuery. `compile` deu exit 0 com modelos
que tinham bugs críticos que só quebraram em runtime.

Fluxo correto: compile → run → verificar `run_results.json`.

### PR para `main` bloqueado pelo CI
`.github/workflows/main_protected.yaml` rejeita qualquer PR para `main` que não venha
de `develop`. Feature branches DEVEM apontar PR para `develop`.

Fluxo: `feature/xxx` → PR → `develop` → PR → `main`

### Policy tags IAM em colunas sensíveis
Colunas como `sexo`, `cor_raca` em tabelas ENEM têm policy tags `media:genero` e `media:etnia`.
A service account do dev pode não ter permissão de leitura dessas colunas.
`dbt run` falha com: `Access Denied: BigQuery BigQuery: No column-level permission to read column`.

Ao migrar modelos que acessam essas colunas: tratar como issue separada,
excluir do PR atual e abrir issue específica.
