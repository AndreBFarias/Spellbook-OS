# Convenção de metadados para autocompletion

Cada função pública em `functions/*.zsh` deve ter um bloco de comentários
imediatamente antes da definição, no padrão:

```zsh
# Propósito: <descrição curta, 1 linha>
# Uso: <nome_funcao> <arg1> [arg2] [--flag1] [--flag2]
# Flags: --flag1=<descrição curta>
#        --flag2=<descrição curta>
# Completa:
#   <arg1>=<nome_do_completer>
#   [arg2]=<nome_do_completer>
nome_funcao() { ... }
```

O parser `scripts/gerar-completions.py` lê esses blocos e gera
automaticamente arquivos `_<nome_funcao>` em `completions/`, no formato
`_arguments` do zsh.

## Regras

1. **Propósito** é obrigatório. É o texto que aparece no menu `fzf-tab` ao lado
   do nome da função.
2. **Uso** é obrigatório. Define a assinatura exibida na RPROMPT.
3. **Flags** é opcional. Se ausente, o gerador infere flags dos `[--xxx]` no
   `Uso:`, mas sem descrição individual.
4. **Completa** é opcional. Aponta argumentos para completers dinâmicos
   escritos em `completions/completers.zsh`. Sem `Completa:`, o argumento é
   tratado como texto livre.

## Convenções de nome de completer

- `__<funcao>_<arg>` — escopo específico daquela função. Ex.: `__santuario_pastas_dev`.
- `__<dominio>_*` — compartilhado entre funções. Ex.: `__git_branches`.

## Override manual

Se um arquivo `completions/_<funcao>` existe e começa com `# OVERRIDE` na
primeira linha, o gerador preserva e não sobrescreve. Use isso para lógica de
completion que exige mais que `_arguments`.

## Funções privadas

Funções começando com `__` (underscore duplo) são ignoradas pelo gerador —
são helpers internos e não precisam de completion.

## Exemplo completo

```zsh
# Propósito: Setup completo de projeto (cd, branch, venv, deps, git context)
# Uso: santuario <Projeto> [Branch] [--sync] [--vit]
# Flags: --sync=Sincroniza dependências (pip install -r)
#        --vit=Usa subdiretório VitoriaMariaDB/
# Completa:
#   <Projeto>=__santuario_pastas_dev
#   [Branch]=__git_branches_locais
santuario() { ... }
```
