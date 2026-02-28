# AGENTS.md - Protocolo para Projeto kimi-ultra
# Herdado de AI.md universal | PT-BR | v1.0

## REGRA ZERO (ABSOLUTA)

**ZERO EMOJIS** em TODAS as interacoes, respostas, codigo, commits e documentacao.

Exemplos proibidos:    ️      ⭐
Use apenas texto puro com marcadores (-, *, >) quando necessario.

## REGRA DE OURO

Antes de modificar QUALQUER arquivo, leia o codigo existente e entenda o contexto completo.

---

## 1. COMUNICACAO

- PT-BR direto e tecnico
- **ZERO emojis** - ver REGRA ZERO acima
- Sem formalidades vazias
- Sem formalidades vazias
- Explicacoes tecnicas e concisas

---

## 2. ANONIMATO ABSOLUTO

**PROIBIDO em qualquer arquivo ou commit:**
- Nomes de IAs: "Claude", "GPT", "Gemini", "Copilot", "Anthropic", "OpenAI", "Kimi"
- Atribuicoes: "by AI", "AI-generated", "Gerado por", "Co-Authored-By"
- **NUNCA** incluir `Co-Authored-By:` em commits
- Commits devem ser totalmente limpos e anonimos

**Excecoes permitidas:**
- Nome do projeto "kimi-ultra" (e o nome do repo)
- Documentacao de API de terceiros
- Variaveis de ambiente: `KIMI_API_KEY`, `MOONSHOT_API_KEY`

---

## 3. CODIGO LIMPO

- Type hints em Python
- Arquivo completo, nunca fragmentos
- Nunca use `# TODO` ou `# FIXME` inline (crie issue no GitHub)
- Logging rotacionado obrigatorio (nunca `print()` em producao)
- Zero comentarios desnecessarios dentro do codigo
- Paths relativos via Path (nunca hardcoded absolutos)
- Error handling explicito (nunca silent failures)
- Bash: usar `#!/bin/bash` com `set -euo pipefail`

---

## 4. GIT

### Formato de Commit (sempre PT-BR)

```
tipo: descricao imperativa

# Tipos: feat, fix, refactor, docs, test, perf, chore
```

### Proibicoes

- Zero emojis em mensagens de commit
- Zero mencoes a IA
- Zero `Co-Authored-By`
- Nunca `--force` sem autorizacao explicita

---

## 5. PROTECOES

- **NUNCA** remover codigo funcional sem autorizacao explicita
- Se usuario pedir refatoracao, perguntar: "Quer adicionar novo ou melhorar o existente?"
- Perguntar antes de alterar arquivos criticos ou de alto impacto

---

## 6. LIMITES

- **800 linhas** por arquivo (excecoes: config, testes, registries)
- Se ultrapassar: extrair para modulos separados, manter imports limpos

---

## 7. PRINCIPIOS

- **Simplicidade** - Codigo simples > codigo "elegante". Evitar over-engineering.
- **Observabilidade** - Tudo tem log. Se nao pode medir, nao pode melhorar.
- **Graceful Degradation** - Falha parcial != crash total. Sempre fallback minimo.
- **Local First** - Tudo funciona offline por padrao. APIs pagas sao opcionais.

---

## 8. CHECKLIST PRE-COMMIT

- [ ] Testes passando
- [ ] Zero emojis no codigo
- [ ] Zero mencoes a IA
- [ ] Zero hardcoded values introduzidos
- [ ] Commit message descritivo (PT-BR)
- [ ] Documentacao atualizada se necessario

---

## 9. ASSINATURA

Todo script finalizado recebe uma citacao de filosofo/estoico/libertario como comentario final.

---

*"Codigo que nao pode ser entendido nao pode ser mantido."*
*"Local First. Zero Emojis. Zero Bullshit."*
