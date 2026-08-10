# Proveniência

Cópia vendorizada de terceiro. **Não editar nada aqui.** Alterações locais são
perdidas na próxima atualização e quebram a comparação com o upstream.

| Campo | Valor |
| --- | --- |
| Origem | https://github.com/nutlope/hallmark |
| Caminho no upstream | `skills/hallmark/` |
| Commit fixado | `13ac0ec7e148655948100b6396439e481361d690` |
| Branch | `main` |
| Versão da skill | 1.1.0 (frontmatter do `SKILL.md`) |
| Licença | MIT |
| Vendorizado em | 2026-08-10 |
| Conteúdo | 107 arquivos, 976 KB |

`PROVENANCE.md` é o único arquivo deste diretório que não vem do upstream.

## Por que vendorizado

A alternativa seria `npx skills add nutlope/hallmark`, que baixa da rede em cada
máquina, sem fixar versão e fora do controle de idempotência do `install.sh`.
Vendorizado, a skill é versionada aqui e o `_sync_claude_symlinks` a liga em
`$CLAUDE/skills/hallmark` automaticamente — inclusive nas outras máquinas, via
autosync, sem passo extra.

## Exceção no pre-commit

`docs/claude/skills/hallmark/*` está no filtro de exclusão do `.githooks/pre-commit`
(`HALLMARK-VENDOR-EXCEPTION`). Sem isso o hook mutilaria 3 menções soltas ao
produto e removeria 41 emoji do texto original, quebrando a identidade byte a
byte com o upstream.

## Como atualizar

```sh
SHA=$(curl -s https://api.github.com/repos/nutlope/hallmark/commits/HEAD \
      | python3 -c "import sys,json;print(json.load(sys.stdin)['sha'])")
rm -rf docs/claude/skills/hallmark
mkdir -p docs/claude/skills/hallmark
curl -sL "https://github.com/nutlope/hallmark/archive/${SHA}.tar.gz" \
  | tar -xz --strip-components=3 -C docs/claude/skills/hallmark "hallmark-${SHA}/skills/hallmark"
```

Depois recrie este arquivo com o novo SHA e confira se a `description` do
frontmatter mudou — é ela que decide o acionamento automático da skill.
