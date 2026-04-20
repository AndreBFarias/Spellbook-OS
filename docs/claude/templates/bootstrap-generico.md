# Template genérico — bootstrap VALIDATOR_BRIEF.md

> Use para qualquer projeto novo. Copie o bloco abaixo da linha `---`, substitua
> `<PROJETO>` e `<CAMINHO_ABSOLUTO>` pelos valores reais, cole na sessão Claude
> viva que tem o histórico de expertise daquele projeto.

---

Bootstrap VALIDATOR_BRIEF.md — <PROJETO>

Quero capturar TUDO que você aprendeu deste projeto ao longo das sprints que revisamos juntos. Escreva em `<CAMINHO_ABSOLUTO>/VALIDATOR_BRIEF.md`.

Estrutura universal:
- Seções CORE (sempre presentes): Identidade, Como rodar, Arquitetura essencial
- Seções OPCIONAIS (incluir só se tem conteúdo real): Padrões recorrentes de bug, Invariantes não-óbvios, Decisões arquiteturais chave, Gambiarras conhecidas, Cheiros específicos do projeto, Histórico de sprints relevantes
- Seções específicas deste projeto: crie novas se fizer sentido (ex.: "Protocolo BOOT-FIX", "Gauntlet de invariantes", "Ciclo do executor")

REGRAS:
- Seja concreto: nome de arquivo, função, número de linha quando lembrar.
- Não invente. Se não lembra, omita ou marque `<a preencher>`.
- PT-BR direto. Zero emojis. Acentuação correta obrigatória.
- Rodapé: `*Atualizado em <ISO timestamp> por bootstrap-rico (sessão <PROJETO>)*`

Ao terminar, liste por seção quantas entradas ficaram (ex.: "Padrões de bug: 7, Invariantes: 4, Gambiarras: 2").
