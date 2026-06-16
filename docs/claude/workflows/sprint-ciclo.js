export const meta = {
  name: 'sprint-ciclo',
  description: 'Ciclo de sprint deterministico: planejar -> executar -> validar (painel adversarial por lente) com retry e veredicto para auto-commit',
  whenToUse: 'Invocado por /sprint-ciclo <ideia>. Orquestra planejador/executor/validador com loop de retry em codigo (nao na memoria do modelo) e validacao adversarial multi-lente.',
  phases: [
    { title: 'Planejar', detail: 'planejador-sprint redige a spec' },
    { title: 'Executar', detail: 'executor-sprint implementa (protocolo v2)' },
    { title: 'Validar', detail: 'painel adversarial de validadores por lente (read-only)' },
  ],
}

// args: string (a ideia) OU objeto { ideia, maxRetries }.
const ideia = (typeof args === 'string') ? args : (args && args.ideia) || ''
const MAX_RETRIES = (args && Number(args.maxRetries)) || 3  // espelha CLAUDE_SPRINT_CICLO_MAX_RETRIES (default 3)

if (!ideia || !String(ideia).trim()) {
  return { status: 'ERRO', motivo: 'Sem ideia de sprint. Uso: /sprint-ciclo <ideia>.' }
}

// -- Schemas: forcam StructuredOutput nos subagentes (validacao na camada da tool) ----------

const SPEC_SCHEMA = {
  type: 'object',
  required: ['specPath', 'titulo', 'ambiguidade'],
  properties: {
    specPath: { type: 'string', description: 'Caminho do arquivo de spec gravado pelo planejador' },
    titulo: { type: 'string', description: 'Titulo da sprint (vira mensagem de commit)' },
    resumo: { type: 'string', description: '2-3 linhas do que a sprint faz' },
    ambiguidade: { type: 'boolean', description: 'true se a ideia e ambigua e precisa clarificacao do usuario' },
    perguntas: { type: 'array', items: { type: 'string' }, description: 'Perguntas de clarificacao se ambiguidade=true' },
  },
}

const EXEC_SCHEMA = {
  type: 'object',
  required: ['bloqueador', 'diffResumo'],
  properties: {
    bloqueador: { type: 'boolean', description: 'true se hipotese divergente (grep), aritmetica nao fecha, ou touches fora do escopo' },
    motivo: { type: 'string', description: 'Motivo do bloqueio, se bloqueador=true' },
    arquivosTocados: { type: 'array', items: { type: 'string' } },
    diffResumo: { type: 'string', description: 'Resumo do diff aplicado (arquivos + natureza das mudancas)' },
    proofOfWork: { type: 'string', description: 'Saida literal dos comandos runtime-real do BRIEF' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  required: ['status', 'achados'],
  properties: {
    status: { type: 'string', enum: ['APROVADO', 'APROVADO_COM_RESSALVAS', 'REPROVADO'] },
    achados: {
      type: 'array',
      items: {
        type: 'object',
        required: ['severidade', 'descricao'],
        properties: {
          severidade: { type: 'string', enum: ['CRITICO', 'IMPORTANTE', 'PONTO-CEGO', 'MINUCIA'] },
          descricao: { type: 'string' },
          arquivo: { type: 'string' },
          fix: { type: 'string', description: 'Edit-pronto OU sprint-ID nova (anti-debito; nunca "issue depois")' },
        },
      },
    },
  },
}

// Lentes adversariais: cada validador ve o MESMO diff com um foco distinto (diversidade > redundancia).
const LENTES = [
  { key: 'correcao-runtime', foco: 'Correcao logica, regressoes, contratos quebrados, sincronizacao N-para-N, proof-of-work runtime-real (licoes 1, 11). Hipoteses verificadas via grep (licao 4); aritmetica de refactor (licao 7).' },
  { key: 'acentuacao', foco: 'Acentuacao PT-BR em linhas perifericas de TODOS os arquivos tocados (licao 3). Rode validar-acentuacao.py se disponivel.' },
  { key: 'visual', foco: 'Se o diff toca UI/TUI/CSS/HTML/template/widget: evidencia visual obrigatoria via skill validacao-visual antes de qualquer claim de "concluida" (licoes 2, 12). Se NAO toca visual, retorne APROVADO com achados vazios.' },
  { key: 'anti-debito-integracao', foco: 'Integracao obrigatoria em registry/command/service (nada solto, licoes 11, 13). Zero follow-up acumulado: cada achado colateral vira Edit-pronto OU sprint-ID nova (licoes 5, 6, 9).' },
]

// -- Fase 1: Planejar -----------------------------------------------------------------------

phase('Planejar')
const spec = await agent(
  `Voce e o planejador-sprint. Redija a spec da sprint para esta ideia:\n\n"${ideia}"\n\n` +
  `Siga seu protocolo: leia VALIDATOR_BRIEF.md + GSD.md da raiz + GUIDE.md; explore o codigo read-only; ` +
  `confirme via grep que os identificadores citados existem (licao 4); divida em sub-sprints se monolitico (licao 10). ` +
  `Grave a spec em arquivo. Se a ideia for ambigua (multiplas interpretacoes validas), marque ambiguidade=true e liste perguntas.`,
  { agentType: 'planejador-sprint', schema: SPEC_SCHEMA, label: 'planejar', phase: 'Planejar' }
)

if (!spec) return { status: 'ERRO', motivo: 'planejador-sprint nao retornou (skip ou erro terminal).' }
if (spec.ambiguidade) {
  return { status: 'PAUSA_AMBIGUIDADE', perguntas: spec.perguntas || [], specPath: spec.specPath, titulo: spec.titulo }
}

// -- Fases 2 e 3: loop Executar -> Validar (adversarial) com retry deterministico ------------

let patchBrief = null
let iter = 0
let ultimoExec = null
let sintese = null

while (iter < MAX_RETRIES) {
  iter++

  // --- Executar ---
  phase('Executar')
  const execPrompt = patchBrief
    ? `Voce e o executor-sprint. RETRY patch-brief (iteracao ${iter}/${MAX_RETRIES}) da spec em ${spec.specPath}.\n` +
      `Corrija SOMENTE estes achados criticos:\n${JSON.stringify(patchBrief, null, 2)}\n` +
      `Escopo RESTRITO ao spec original — nao expanda touches. Nao use --force/--no-verify. ` +
      `Re-rode o proof-of-work runtime-real apos corrigir.`
    : `Voce e o executor-sprint. Implemente a sprint conforme a spec em ${spec.specPath}. ` +
      `Siga o protocolo v2 (PRE-0 le BRIEF+GSD, 0.3 verifica hipotese via grep, 0.4 aritmetica, passos 1-7). ` +
      `Nao force, nunca --no-verify. Achados colaterais viram sprint nova (anti-debito), nao fixe inline. ` +
      `Rode o proof-of-work runtime-real do BRIEF e a varredura de acentuacao.`
  const exec = await agent(execPrompt, { agentType: 'executor-sprint', schema: EXEC_SCHEMA, label: `executar#${iter}`, phase: 'Executar' })

  if (!exec) return { status: 'ERRO', motivo: 'executor-sprint nao retornou.', iter, specPath: spec.specPath }
  if (exec.bloqueador) {
    return { status: 'PAUSA_BLOQUEADOR', motivo: exec.motivo || 'bloqueador sem motivo', exec, iter, specPath: spec.specPath }
  }
  ultimoExec = exec

  // --- Validar: painel adversarial (paralelo, read-only por lente) ---
  phase('Validar')
  const veredictos = (await parallel(LENTES.map((l) => () =>
    agent(
      `Voce e o validador-sprint em MODO VALIDATE, LENTE "${l.key}".\n` +
      `Foco EXCLUSIVO desta lente: ${l.foco}\n\n` +
      `Leia: VALIDATOR_BRIEF.md + GSD.md da raiz + a spec ${spec.specPath}.\n` +
      `Diff/proof-of-work do executor:\n${exec.diffResumo}\n\nProof:\n${exec.proofOfWork || '(nao informado)'}\n\n` +
      `IMPORTANTE: opere READ-ONLY. Apenas reporte achados estruturados; NAO aplique Edits nem auto-dispatch de planejador. ` +
      `A sintese do ciclo decide. Para cada achado, de severidade + descricao + arquivo + fix (Edit-pronto OU sprint-ID; nunca "depois").`,
      { agentType: 'validador-sprint', schema: VERDICT_SCHEMA, label: `validar:${l.key}#${iter}`, phase: 'Validar' }
    )
  ))).filter(Boolean)

  if (!veredictos.length) return { status: 'ERRO', motivo: 'nenhuma lente de validacao retornou.', iter, specPath: spec.specPath }

  // --- Sintese: agrega achados de todas as lentes e decide ---
  const achados = veredictos.flatMap((v) => v.achados || [])
  const criticos = achados.filter((a) => a.severidade === 'CRITICO' || a.severidade === 'PONTO-CEGO')
  const reprovou = veredictos.some((v) => v.status === 'REPROVADO') || criticos.length > 0
  sintese = { iter, achados, criticos, reprovou, statusLentes: veredictos.map((v, i) => ({ lente: LENTES[i].key, status: v.status })) }

  if (!reprovou) break  // APROVADO ou APROVADO_COM_RESSALVAS — sai do loop

  // Retry: so achados CRITICO/PONTO-CEGO entram no patch-brief. MINUCIA/IMPORTANTE viram sprint futura (anti-debito).
  patchBrief = criticos
  log(`Iteracao ${iter}/${MAX_RETRIES}: REPROVADO com ${criticos.length} achado(s) critico(s).` + (iter < MAX_RETRIES ? ' Retry...' : ' Limite de retries atingido.'))
}

// -- Veredicto final ------------------------------------------------------------------------

if (sintese.reprovou) {
  return {
    status: 'REPROVADO_APOS_RETRIES',
    iteracoes: iter,
    criticosPersistentes: sintese.criticos,
    specPath: spec.specPath,
    diff: ultimoExec ? ultimoExec.diffResumo : null,
    sugestao: 'Ajustar a spec, promover achado para sprint dedicada, ou abandonar. Apresente o diff acumulado ao usuario.',
  }
}

const ressalvas = sintese.achados.filter((a) => a.severidade === 'IMPORTANTE' || a.severidade === 'MINUCIA')
return {
  status: ressalvas.length ? 'APROVADO_COM_RESSALVAS' : 'APROVADO',
  iteracoes: iter,
  titulo: spec.titulo,
  resumo: spec.resumo,
  specPath: spec.specPath,
  arquivosTocados: ultimoExec ? ultimoExec.arquivosTocados : [],
  diff: ultimoExec ? ultimoExec.diffResumo : null,
  proofOfWork: ultimoExec ? ultimoExec.proofOfWork : null,
  ressalvas,
  proximo: 'Main loop: rodar /commit-push-pr com commit curado por path (sem emoji, sem atribuicao IA — guardian.py bloqueia). MINUCIA/IMPORTANTE ja viraram sprints futuras (anti-debito).',
}
