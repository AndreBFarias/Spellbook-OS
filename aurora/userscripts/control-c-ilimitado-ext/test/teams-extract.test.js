// Teste de lib/teams-extract.js — Node puro, sem dependencias.
//   node test/teams-extract.test.js
//
// Cobre blockText/codeText: a extracao de texto de bloco preservando quebras de
// linha. Nao usa jsdom de proposito — as funcoes sob teste tocam so 4 campos do
// DOM (nodeType/nodeValue/tagName/childNodes), entao nos falsos bastam e o teste
// roda em qualquer lugar sem instalar nada.

const fs = require('fs');
const path = require('path');

// ── Nos DOM falsos ──
const T = (v) => ({ nodeType: 3, nodeValue: v });
const E = (tag, kids) => ({ nodeType: 1, tagName: tag, childNodes: kids || [] });
const BR = () => E('BR');

// ── Carrega o modulo (ele faz (function(root){...})(self)) ──
global.Node = { TEXT_NODE: 3, ELEMENT_NODE: 1 };
const fake = { Node: global.Node };
const src = fs.readFileSync(path.join(__dirname, '..', 'lib', 'teams-extract.js'), 'utf8');
new Function('self', src)(fake);
const { blockText, codeText } = fake.CCI._teams;

// ── Runner minimo ──
let pass = 0, fail = 0;
function eq(nome, atual, esperado) {
  const ok = atual === esperado;
  if (ok) { pass++; console.log('  ok  ' + nome); }
  else {
    fail++;
    console.log('  FALHOU  ' + nome);
    console.log('    esperado: ' + JSON.stringify(esperado));
    console.log('    atual:    ' + JSON.stringify(atual));
  }
}

console.log('blockText / codeText');

// 1. O caso real do Teams: <pre><code> com <br> entre as linhas.
//    Medido no DOM ao vivo (cci-diag): 197 <br> para 198 linhas de SQL.
eq('br vira quebra de linha',
  blockText(E('PRE', [E('CODE', [T('a'), BR(), T('b'), BR(), T('c')])])),
  'a\nb\nc');

// 2. <br><br> e linha em branco intencional no codigo — nao pode ser colapsado.
eq('br duplo preserva linha em branco',
  blockText(E('PRE', [T('a'), BR(), BR(), T('b')])),
  'a\n\nb');

// 3. Fronteira de bloco tambem quebra (o Teams as vezes usa div por linha).
eq('div vira quebra de linha',
  blockText(E('DIV', [E('DIV', [T('a')]), E('DIV', [T('b')])])),
  'a\nb');

// 4. Blocos aninhados nao geram quebras duplicadas espurias.
eq('blocos aninhados nao duplicam quebra',
  blockText(E('DIV', [E('DIV', [E('DIV', [T('a')])]), E('DIV', [T('b')])])),
  'a\nb');

// 5. Inline nao quebra.
eq('span nao quebra',
  blockText(E('P', [E('SPAN', [T('a')]), E('SPAN', [T('b')])])),
  'ab');

// 6. codeText: o Teams indenta com NBSP ( ) — invisivel e rejeitado por
//    alguns parsers quando o SQL e colado direto no editor.
eq('codeText troca NBSP por espaco',
  codeText(E('PRE', [T('WITH PE AS ('), BR(), T('   SELECT')])),
  'WITH PE AS (\n   SELECT');

// 7. codeText apara espaco no fim de cada linha e no fim do bloco.
eq('codeText apara whitespace de sobra',
  codeText(E('PRE', [T('SELECT 1   '), BR(), T('FROM t'), BR(), BR()])),
  'SELECT 1\nFROM t');

// 8. Regressao do bug real: fixture montado a partir do SQL capturado ao vivo
//    (cci-diag.json, bloco 0) — text nodes separados por <br>, indentacao NBSP.
const LINHAS_REAIS = [
  'WITH PAGAMENTO_OBRA AS (',
  '    SELECT',
  '        COD_EMPRESA,',
  '        COD_REGIONAL,',
  '        NUM_OBRA,',
  '        CASE',
  "           WHEN SUM(QTD_PARCELA) - SUM(QTD_OBRA_PAGA) = 0 THEN 'SIM'",
  "           ELSE 'NÃO'",
  '        END AS PAGAMENTO_OBRA',
  '    FROM (',
];
const kids = [];
LINHAS_REAIS.forEach((l, i) => { if (i) kids.push(BR()); kids.push(T(l)); });
const real = codeText(E('PRE', [E('CODE', kids)]));
eq('SQL real mantem uma linha por linha', real.split('\n').length, LINHAS_REAIS.length);
eq('SQL real nao tem mais NBSP', / /.test(real), false);
eq('SQL real preserva a indentacao', real.split('\n')[2], '        COD_EMPRESA,');

console.log('\n' + pass + ' ok, ' + fail + ' falhou');
process.exit(fail ? 1 : 0);
