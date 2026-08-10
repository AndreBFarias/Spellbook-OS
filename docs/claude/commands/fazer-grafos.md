---
description: Constrói ou atualiza o índice de código do repositório atual, que habilita as ferramentas de consulta ao grafo na próxima sessão
argument-hint: [--full]
---

Construa o índice de código deste repositório.

## Passos

### 1. Localizar a raiz

Execute `git rev-parse --show-toplevel`. Sem repositório, use o diretório atual
e avise que o índice ficará preso a ele.

### 2. Conferir a ferramenta

Se `code-review-graph` não estiver disponível, pare e informe o comando de
instalação: `pipx install code-review-graph`. Não tente instalar sozinho.

### 3. Construir

Rode `code-review-graph build $ARGUMENTS` a partir da raiz. O build de um
repositório médio leva de segundos a poucos minutos — não interrompa antes de
2 minutos de silêncio.

### 4. Confirmar

Verifique que `.code-review-graph/` existe na raiz e informe:

- quantos arquivos, nós e arestas o build reportou
- o tamanho do diretório
- que o servidor de consulta sobe sozinho na **próxima** sessão aberta aqui,
  porque a detecção acontece na abertura

Se o build terminou sem erro mas o diretório não apareceu, isso é falha — diga
claramente em vez de reportar sucesso.

## Observações

- O diretório se auto-ignora: ele traz o próprio `.gitignore` com `*`. Não
  adicione nada ao `.gitignore` do repositório.
- Em sessão já aberta, as ferramentas novas não aparecem: elas são registradas
  na abertura. Avise que é preciso reabrir.
