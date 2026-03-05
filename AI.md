# AI.md - Protocolo Universal para Agentes de IA
# Regras para qualquer projeto | PT-BR | v4.0

## REGRA DE OURO

Antes de modificar QUALQUER arquivo, leia o código existente e entenda o contexto completo.

---

## 1. COMUNICAÇÃO

- PT-BR direto e técnico (acentuação correta obrigatória)
- **ZERO emojis** em código, commits, docs, respostas
- Sem formalidades vazias
- Explicações técnicas e concisas

---

## 2. ANONIMATO ABSOLUTO

**PROIBIDO em qualquer arquivo ou commit:**
- Nomes de IAs: "Claude", "GPT", "Gemini", "Copilot", "Anthropic", "OpenAI"
- Atribuições: "by AI", "AI-generated", "Gerado por", "Co-Authored-By"
- **NUNCA** incluir `Co-Authored-By:` em commits
- Commits devem ser totalmente limpos e anônimos

**Exceções permitidas:**
- Strings técnicas: `api_key`, `provider`, `model`, `config`, `client`
- Documentação de API de terceiros
- Variáveis de ambiente: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`

---

## 3. CÓDIGO LIMPO

- Type hints quando a linguagem suportar
- Arquivo completo, nunca fragmentos
- Nunca use `# TODO` ou `# FIXME` inline (crie issue no GitHub)
- Logging rotacionado obrigatório (nunca `print()` / `console.log()`)
- Zero comentários desnecessários dentro do código
- Paths relativos via Path/equivalente (nunca hardcoded absolutos)
- Error handling explícito (nunca silent failures)

### SQL e YAML

- Comentários de migração PROIBIDOS inline (ex: `-- migração: alias para compatibilidade`).
  Se precisar registrar a mudança, use o corpo do commit.
- Descriptions em `source.yml` devem ser neutras e técnicas. PROIBIDO codificar
  histórico de implementação (ex: "substituindo tabela X"). Descrever o dado em si.
- Comentários Jinja (`{# ... #}`) adicionados durante desenvolvimento devem ser
  removidos antes do commit — eles aparecem no código-fonte, não no SQL compilado.

---

## 4. GIT

### Formato de Commit (sempre PT-BR)

```
tipo: descrição imperativa com acentuação correta

# Tipos: feat, fix, refactor, docs, test, perf, chore
```

Exemplos corretos: `migração`, `correção`, `padrões`, `revisão`, `atualização`, `remoção`.

### Proibições

- Zero emojis em mensagens de commit
- Zero menções a IA
- Zero `Co-Authored-By`
- Nunca `--force` sem autorização explícita
- Acentuação PT-BR obrigatória em títulos e corpo do commit
- PR description: uma linha descritiva, sem tabelas, sem bullet points extensos.
  Descrições elaboradas parecem geradas por IA e comprometem o anonimato.
- Antes de abrir PR, verificar o branch target do projeto (ex: `develop`, não `main`).

---

## 5. PROTEÇÕES

- **NUNCA** remover código funcional sem autorização explícita
- Se usuário pedir refatoração, perguntar: "Quer adicionar novo ou melhorar o existente?"
- Perguntar antes de alterar arquivos críticos ou de alto impacto

---

## 6. LIMITES

- **800 linhas** por arquivo (exceções: config, testes, registries)
- Se ultrapassar: extrair para módulos separados, manter imports limpos

---

## 7. GITIGNORE OBRIGATÓRIO

```gitignore
# Caches
__pycache__/
*.py[cod]
node_modules/
venv/
.venv/

# Logs e dados
logs/
*.log

# Evidências de IA
Task_Final/
IMPORTANT.md
*.claude.md
*_AI_*.md

# Secrets
.env
*.key
*.pem
.git-credentials

# IDE
.vscode/
.idea/
*.swp

# Sistema
.DS_Store
Thumbs.db
```

---

## 8. PRINCÍPIOS

- **Simplicidade** - Código simples > código "elegante". Evitar over-engineering.
- **Observabilidade** - Tudo tem log. Se não pode medir, não pode melhorar.
- **Graceful Degradation** - Falha parcial != crash total. Sempre fallback mínimo.
- **Local First** - Tudo funciona offline por padrão. APIs pagas são opcionais.

---

## 9. META-REGRAS ANTI-REGRESSÃO

1. **Sincronização N-para-N** - Se um valor existe em N lugares, atualizar TODOS ou nenhum.
2. **Filtros sem falso-positivo** - Todo regex/filtro DEVE ser testado contra inputs que NÃO devem casar.
3. **Soberania de subsistema** - Subsistema A NUNCA descarrega/mata recurso de subsistema B.
4. **Observabilidade adaptativa** - Sistema adaptativo sem métrica de saúde = bomba-relógio.
5. **Scope atômico** - Bug encontrado ao testar feature Y NÃO é fixado inline. Registrar como nova issue.

---

## 10. WORKFLOW

```
1. Ler arquivos relacionados
2. Entender fluxo completo
3. Procurar testes existentes
4. Implementar mantendo compatibilidade
5. Testar incrementalmente
6. Documentar mudanças
```

---

## 11. CHECKLIST PRÉ-COMMIT

- [ ] Testes passando
- [ ] Zero emojis no código
- [ ] Zero menções a IA
- [ ] Zero hardcoded values introduzidos
- [ ] Commit message descritivo (PT-BR)
- [ ] Sincronização N-para-N verificada
- [ ] Documentação atualizada se necessário

---

## 12. ASSINATURA

Todo script finalizado recebe uma citação de filósofo/estoico/libertário como comentário final.

---

*"Código que não pode ser entendido não pode ser mantido."*
*"Local First. Zero Emojis. Zero Bullshit."*
