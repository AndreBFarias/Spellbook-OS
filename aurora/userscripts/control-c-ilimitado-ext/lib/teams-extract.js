// lib/teams-extract.js — DOM (fragmento da selecao) -> modelo de mensagens.
// A parte Teams-aware (fragil): as funcoes de reconhecimento (is*/get*) sao
// pequenas e ajustaveis de proposito. Fallback sempre cai em paragrafo de texto
// -> nunca perde conteudo.
(function (root) {
  'use strict';
  const CCI = (root.CCI = root.CCI || {});
  const imgs = () => CCI.images;

  // ── Seletores Fuent UI (prefixo fui-* e estavel; sufixo ___hash e volatil) ──
  const MSG_SEL = '.fui-ChatMessage';
  const SYS_SEL = '.fui-ChatControlMessage, .fui-ChatControlMessageItem';
  const BODY_SEL = '.fui-ChatMessage__body';
  const AUTHOR_SEL = '.fui-ChatMessage__author';
  const GRID_SEL = '[data-tid="file-attachment-grid"], [data-tid^="file-attachment"], [data-tid*="fileAttachment" i]';

  const INLINE_TAGS = new Set(['SPAN', 'A', 'B', 'STRONG', 'I', 'EM', 'CODE', 'U', 'S',
    'SUB', 'SUP', 'MARK', 'SMALL', 'ABBR', 'TIME', 'LABEL', 'FONT']);

  // Frases que sao so acessibilidade/ruido e devem sumir do texto de saida.
  const CRUFT_RE = /(tem menu de contexto|menu de contexto|Coração reaç(ão|ões)|reaç(ão|ões)\.?$|^\s*\d+\s*$|Início da citação)/i;

  // Regex de hora/data que o Teams mostra: "22/07 11:57", "06/07/2026, 13:18", "09:58".
  const TIME_RE = /(\d{1,2}\/\d{1,2}(\/\d{2,4})?(,?\s*\d{1,2}:\d{2})?|\b\d{1,2}:\d{2}\b)/;

  // ── Entrada ──
  // liveGridAttachments: array (uma entrada por card de anexo, na ordem em que
  // aparecem no documento) com o resultado de attachmentsFromGrid rodado nos
  // elementos AINDA VIVOS, antes do clone -- ver extractLiveAttachments. E
  // consumido em fila (shift) conforme walkBlock encontra os cards equivalentes
  // no fragmento clonado, que nao tem mais os props do React pra ler sozinho.
  function extract(fragment, liveGridAttachments) {
    coalesceMentions(fragment);
    const gridQueue = (liveGridAttachments || []).slice();
    const messages = [];
    const items = topLevelItems(fragment);

    if (!items.length) {
      // Nenhum container de mensagem reconhecido: trata o fragmento inteiro como
      // um bloco unico (fallback — melhor entregar texto cru que perder tudo).
      const blocks = blocksFrom(fragment, gridQueue);
      if (blocks.length) messages.push({ kind: 'message', author: null, timestamp: null, blocks });
      return { messages };
    }

    for (const it of items) {
      if (isSystem(it)) {
        const text = cleanLine(it.innerText || '');
        if (text) messages.push({ kind: 'system', text });
        continue;
      }
      messages.push(messageFrom(it, gridQueue));
    }
    return { messages };
  }

  // Itens de nivel superior (mensagem ou sistema) em ordem, sem os aninhados
  // (uma citacao dentro do corpo NAO conta como item — vira bloco 'quote').
  function topLevelItems(rootEl) {
    const all = Array.prototype.slice.call(rootEl.querySelectorAll(MSG_SEL + ',' + SYS_SEL));
    return all.filter(el => !all.some(o => o !== el && o.contains(el)));
  }

  function isSystem(el) {
    return el.matches && el.matches(SYS_SEL);
  }

  function messageFrom(it, gridQueue) {
    const author = getAuthor(it);
    const timestamp = getTimestamp(it);
    const bodyEl = it.querySelector(BODY_SEL) || it;
    const blocks = blocksFrom(bodyEl, gridQueue);
    return { kind: 'message', author, timestamp, blocks };
  }

  function getAuthor(it) {
    const a = it.querySelector(AUTHOR_SEL);
    let raw = a ? a.innerText : '';
    if (!raw) {
      // fallback: primeira StyledText do cabecalho
      const s = it.querySelector('.fui-StyledText');
      raw = s ? s.innerText : '';
    }
    return cleanAuthor(raw);
  }

  function cleanAuthor(raw) {
    if (!raw) return null;
    let s = raw.replace(/\s+/g, ' ').trim();
    // tira a hora que as vezes cola no nome do autor
    const m = s.match(TIME_RE);
    if (m && m.index > 0) s = s.slice(0, m.index).trim();
    s = s.replace(/(Editada|Edited)\s*$/i, '').trim();
    return s || null;
  }

  function getTimestamp(it) {
    // Prefere o texto EXIBIDO ("13:37", "22/07 11:57"); ISO do atributo datetime
    // fica so como ultimo recurso (2026-07-22T17:53Z e ilegivel pro leitor/IA).
    const t = it.querySelector('time');
    if (t) {
      const disp = cleanLine(t.innerText || '');
      if (disp) return disp;
    }
    const head = (it.querySelector(AUTHOR_SEL) || it).innerText || '';
    const m = head.match(TIME_RE);
    if (m) return m[0].trim();
    if (t) {
      const dt = (t.getAttribute('datetime') || '').trim();
      if (dt) return dt;
    }
    return null;
  }

  // ── Corpo -> blocos ──
  function blocksFrom(container, gridQueue) {
    const out = [];
    // buffer de inlines do paragrafo corrente. CRITICO: limpar SEMPRE no lugar
    // (buf.length = 0), nunca reatribuir (buf = []). walkBlock recebe esta mesma
    // referencia; um `buf = []` reatribuiria so a variavel externa e a recursao
    // continuaria empurrando no array antigo -> o corpo das mensagens sumia.
    const buf = [];
    const flush = () => {
      const inl = trimInlines(buf);
      if (inl.length) out.push({ type: 'p', inlines: inl });
      buf.length = 0;
    };

    walkBlock(container, out, buf, flush, gridQueue);
    flush();
    return attachmentize(mergeAdjacent(out));
  }

  // Caminha um container em nivel de bloco. Empurra blocos especiais em `out` e
  // acumula texto inline em `buf` (via closure de flush).
  function walkBlock(container, out, buf, flush, gridQueue) {
    for (const node of Array.prototype.slice.call(container.childNodes)) {
      if (node.nodeType === Node.TEXT_NODE) {
        pushText(buf, node.nodeValue);
        continue;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) continue;
      const el = node;
      const tag = el.tagName;

      if (isPruned(el)) continue;

      // Imagem
      if (tag === 'IMG') {
        const kind = imgs() ? imgs().classify(el) : 'content';
        if (kind === 'content') {
          flush();
          out.push({ type: 'image', src: el.currentSrc || el.src || el.getAttribute('src') || '',
            alt: (el.getAttribute('alt') || '').trim() || null, dataUri: null, imgKind: 'content' });
        } else if (kind === 'emoji') {
          const a = (el.getAttribute('alt') || '').trim();
          if (a) buf.push({ t: 'text', v: a });
        }
        continue;
      }

      if (tag === 'BR') { flush(); continue; }

      // Card de anexo do Teams (data-tid estavel). O elemento AQUI e do
      // fragmento CLONADO (cloneContents() nao copia __reactProps$ -- so os
      // nos originais, ainda vivos, tem esses dados), entao NAO da pra ler
      // attachmentsFromGrid(el) neste ponto. Os dados reais ja foram extraidos
      // dos nos vivos ANTES do clone (extractLiveAttachments) e chegam aqui via
      // gridQueue, na mesma ordem de documento -- so consumimos em fila.
      if (el.matches && el.matches(GRID_SEL)) {
        flush();
        const attachments = (gridQueue && gridQueue.length) ? gridQueue.shift() : null;
        if (attachments && attachments.length) {
          out.push.apply(out, attachments);
        } else {
          const name = cleanLine(el.innerText || '');
          if (name) out.push({ type: 'attachment', name: name, href: null });
        }
        continue;
      }

      // Citacao / resposta
      if (isQuote(el)) {
        flush();
        out.push(quoteFrom(el));
        continue;
      }

      // Bloco de codigo
      if (tag === 'PRE' || (el.matches && el.matches('[class*="code" i]') && el.querySelector('code'))) {
        flush();
        out.push({ type: 'code', lang: null, text: (el.innerText || '').replace(/\n+$/, '') });
        continue;
      }

      // Lista
      if (tag === 'UL' || tag === 'OL') {
        flush();
        out.push(listFrom(el, tag === 'OL'));
        continue;
      }

      // Mencao (@Fulano) — recolhe o chip inteiro num inline so
      if (isMention(el)) {
        const v = mentionText(el);
        if (v) buf.push(mentionInline(el, v));
        continue;
      }

      // Link no nivel de bloco: capturar o href AQUI. Sem isto, cairia no
      // inlineInto abaixo, que processa os filhos do <a> como texto e perde a URL.
      if (tag === 'A' && !hasContentImage(el)) {
        const t = cleanLine(el.innerText || '');
        const href = (el.getAttribute && el.getAttribute('href')) || '';
        if (t && href) buf.push({ t: 'link', v: t, href });
        else if (t) buf.push({ t: 'text', v: t });
        else inlineInto(el, buf);
        continue;
      }

      // Inline conhecido -> acumula no paragrafo. Excecao: se embrulha uma imagem
      // de conteudo, trata como bloco pra a imagem virar bloco de verdade.
      if (INLINE_TAGS.has(tag)) {
        if (hasContentImage(el)) { flush(); walkBlock(el, out, buf, flush, gridQueue); flush(); }
        else inlineInto(el, buf);
        continue;
      }

      // Bloco generico (div/p/section...): fecha o paragrafo atual e desce.
      flush();
      walkBlock(el, out, buf, flush, gridQueue);
      flush();
    }
  }

  // Acumula o conteudo inline de um elemento em `buf`, preservando negrito/italico/
  // link/codigo/mencao.
  function inlineInto(el, buf) {
    for (const node of Array.prototype.slice.call(el.childNodes)) {
      if (node.nodeType === Node.TEXT_NODE) { pushText(buf, node.nodeValue); continue; }
      if (node.nodeType !== Node.ELEMENT_NODE) continue;
      const c = node, tag = c.tagName;
      if (isPruned(c)) continue;
      if (tag === 'IMG') {
        const kind = imgs() ? imgs().classify(c) : 'content';
        if (kind === 'emoji') { const a = (c.getAttribute('alt') || '').trim(); if (a) buf.push({ t: 'text', v: a }); }
        continue;
      }
      if (isMention(c)) { const v = mentionText(c); if (v) buf.push(mentionInline(c, v)); continue; }
      const txt = cleanLine(c.innerText || '');
      if (!txt) { inlineInto(c, buf); continue; }
      if (tag === 'A') buf.push({ t: 'link', v: txt, href: c.getAttribute('href') || '' });
      else if (tag === 'B' || tag === 'STRONG') buf.push({ t: 'bold', v: txt });
      else if (tag === 'I' || tag === 'EM') buf.push({ t: 'italic', v: txt });
      else if (tag === 'CODE') buf.push({ t: 'code', v: txt });
      else inlineInto(c, buf);
    }
  }

  function quoteFrom(el) {
    // O preview da citacao mistura autor + hora + texto citado no mesmo innerText,
    // com uma estrutura de spans que, se caminhada, repete autor/hora no corpo.
    // Mais robusto: pegar autor/hora e usar o RESTO do innerText como o texto citado.
    const author = getAuthor(el);
    const timestamp = getTimestamp(el);
    const full = cleanLine(el.innerText || '');
    let body = full;
    if (author) body = body.split(author).join(' ');
    if (timestamp) body = body.split(timestamp).join(' ');
    const truncated = /…|\.\.\.\s*$/.test(full);
    body = body.replace(/\s+/g, ' ').replace(/^[\s,;:·—-]+/, '')
      .replace(/…\s*$/, '').replace(/\.\.\.\s*$/, '').trim();
    const blocks = body ? [{ type: 'p', inlines: [{ t: 'text', v: body }] }] : [];
    return { type: 'quote', author, timestamp, truncated, blocks };
  }

  function listFrom(el, ordered) {
    const items = [];
    for (const li of Array.prototype.slice.call(el.querySelectorAll(':scope > li'))) {
      const buf = [];
      inlineInto(li, buf);
      const inl = trimInlines(buf);
      if (inl.length) items.push(inl);
    }
    return { type: 'list', ordered, items };
  }

  // ── Reconhecimento ajustavel ──
  function quoteAria(el) {
    const aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
    return /início da citação|inicio da citacao/i.test(aria);
  }

  function isQuote(el) {
    if (!el.matches) return false;
    if (el.tagName === 'BLOCKQUOTE') return true;
    // Teams marca "Início da citação" em DOIS niveis: o wrapper externo (que
    // embrulha tambem o corpo da resposta) e o preview interno. So o mais interno
    // (sem outra citacao dentro) e a citacao de fato — o externo e o corpo.
    if (quoteAria(el)) {
      const inner = Array.prototype.slice.call(el.querySelectorAll('*')).some(quoteAria);
      return !inner;
    }
    if (el.matches('[class*="quote" i], [class*="reply" i], [class*="Citation" i]')) return true;
    return false;
  }

  function isMention(el) {
    if (!el.matches) return false;
    if (el.hasAttribute && el.hasAttribute('data-cci-mention')) return true;
    const aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
    // Teams fragmenta a mencao em varios divs, cada um com aria "X mencionado".
    if (/mencionad|mentioned/i.test(aria)) return true;
    return el.matches('[class*="mention" i], [data-mention], [data-itemtype*="mention" i], [itemtype*="Person" i]');
  }

  function isMentionChip(el) {
    return el && el.nodeType === Node.ELEMENT_NODE &&
      /mencionad|mentioned/i.test((el.getAttribute && el.getAttribute('aria-label')) || '');
  }

  // Mencao e sempre texto puro @Nome: o link da pessoa no Teams (l/mentions/...) e
  // interno e inutil fora dele, entao NAO viramos a mencao em link.
  function mentionInline(el, v) {
    return { t: 'mention', v };
  }

  // Pre-passo: o Teams quebra "@Nome Sobrenome (SETOR)" em varios divs irmaos,
  // cada um com aria "X mencionado". Aqui, ANTES de caminhar o DOM, junto cada
  // sequencia de chips irmaos num unico <span data-cci-mention>@Nome Completo</span>.
  // Robusto a espacos entre chips e independe da ordem/estrutura do resto.
  function coalesceMentions(root) {
    if (!root.querySelectorAll) return;
    const chips = Array.prototype.slice.call(root.querySelectorAll('*'))
      .filter(el => isMentionChip(el) && !isMentionChip(el.parentElement));
    for (const first of chips) {
      if (!first.parentNode) continue; // ja consumido por um grupo anterior
      const names = [mentionText(first)];
      const toRemove = [];
      let pendingWs = [];
      let sib = first.nextSibling;
      while (sib) {
        if (sib.nodeType === Node.TEXT_NODE && !sib.nodeValue.trim()) { pendingWs.push(sib); sib = sib.nextSibling; continue; }
        if (isMentionChip(sib)) {
          names.push(mentionText(sib));
          // remove tambem o espaco em branco ENTRE os chips (senao vira "@A B , texto")
          for (const w of pendingWs) toRemove.push(w);
          pendingWs = [];
          toRemove.push(sib);
          sib = sib.nextSibling;
          continue;
        }
        break; // texto real: para (o espaco final separa a mencao do texto seguinte)
      }
      for (const n of toRemove) { if (n.remove) n.remove(); }
      const full = '@' + names.filter(Boolean).join(' ');
      const doc = first.ownerDocument || document;
      const marker = doc.createElement('span');
      marker.setAttribute('data-cci-mention', full); // nome no atributo (a prova de layout)
      marker.textContent = full;
      if (first.replaceWith) first.replaceWith(marker);
    }
  }

  // Texto do nome da mencao. Marcador do coalesce guarda o nome no atributo
  // (a prova de layout); senao usa innerText; senao tira "mencionado" da aria.
  function mentionText(el) {
    if (el.getAttribute) {
      const stored = el.getAttribute('data-cci-mention');
      if (stored && stored !== '1') return stored;
    }
    const t = cleanLine(el.innerText || '');
    if (t) return t;
    const aria = (el.getAttribute && el.getAttribute('aria-label')) || '';
    return aria.replace(/\s*(mencionad[oa]|mentioned)\s*$/i, '').trim();
  }

  // Extensoes de arquivo que marcam um anexo (PDF, Excel, Word, etc.).
  const FILE_RE = /\.(pdf|xlsx?|docx?|pptx?|csv|txt|zip|rar|7z|odt|ods|odp)$/i;

  // Um paragrafo que e SO um nome de arquivo vira bloco de anexo (para marcar com
  // clipe e, no modo Baixar, tentar baixar via href do link, quando houver).
  function attachmentize(blocks) {
    return blocks.map(b => {
      if (b.type !== 'p') return b;
      const text = inlineText(b.inlines).trim();
      if (text && text.length < 200 && FILE_RE.test(text) && !/\s{2,}/.test(text)) {
        const link = b.inlines.find(i => i.t === 'link' && i.href);
        return { type: 'attachment', name: text, href: link ? link.href : null };
      }
      return b;
    });
  }

  function inlineText(inlines) {
    return (inlines || []).map(i => i.v || '').join('');
  }

  // Elemento contem alguma imagem de CONTEUDO (nao avatar/emoji) na descendencia?
  // Usado pra forcar um span inline a virar bloco quando embrulha uma imagem.
  function hasContentImage(el) {
    if (!el.querySelectorAll) return false;
    const list = Array.prototype.slice.call(el.querySelectorAll('img'));
    return list.some(im => !imgs() || imgs().classify(im) === 'content');
  }

  // ── Anexos: link real via props do React ──
  // O card de anexo nao expoe href no DOM, mas o React anexa os props do
  // componente ao proprio no sob uma chave "__reactProps$<sufixo>" (sufixo
  // aleatorio por carregamento de pagina, nao por elemento -- funciona em
  // qualquer no marcado pelo React). Confirmado via harness de console em
  // 2026-07-23 (ver docs/superpowers/specs) em cards reais do Teams.
  function reactPropsOf(el) {
    if (!el) return null;
    const keys = Object.keys(el).filter(function (k) { return k.indexOf('__reactProps$') === 0; });
    return keys.length ? el[keys[0]] : null;
  }

  // Ultimo segmento do path de uma URL, decodificado -- fallback quando o
  // objeto do arquivo nao traz um campo de nome literal.
  function filenameFromUrl(url) {
    if (!url) return null;
    try {
      const clean = url.split('?')[0];
      const segs = clean.split('/').filter(Boolean);
      const last = segs[segs.length - 1];
      return last ? decodeURIComponent(last) : null;
    } catch (_) { return null; }
  }

  function attachmentNameFrom(file) {
    return file.title || file.name || file.fileName ||
      filenameFromUrl(file.objectUrl) || filenameFromUrl(file.shareUrl) || null;
  }

  // Um card "file-attachment-grid" pode agrupar 1+ arquivos (props.children).
  // Cada child carrega file.props.file com {baseUrl, objectUrl, shareUrl,
  // previewUrl}. shareUrl e o link de COMPARTILHAMENTO do SharePoint (o mesmo
  // formato que aparece quando alguem cola um hyperlink de arquivo direto na
  // mensagem) -- objectUrl e so o path cru na biblioteca (nao abre sozinho) e
  // previewUrl e um endpoint interno do Teams (asyncgw, exige sessao do app).
  function attachmentsFromGrid(el) {
    const props = reactPropsOf(el);
    const kids = props && props.children;
    if (!kids) return [];
    const list = Array.isArray(kids) ? kids : [kids];
    const out = [];
    for (let i = 0; i < list.length; i++) {
      const child = list[i];
      const file = child && child.props && child.props.file && child.props.file.props &&
        child.props.file.props.file;
      if (!file) continue;
      const href = file.shareUrl || file.objectUrl || null;
      const name = attachmentNameFrom(file);
      if (name || href) out.push({ type: 'attachment', name: name || 'arquivo', href: href });
    }
    return out;
  }

  // Le os anexos das cards AINDA VIVAS (conectadas ao React) que caem dentro
  // da selecao do usuario -- precisa rodar ANTES do cloneContents(), que nao
  // preserva os __reactProps$. Retorna um array na mesma ordem de documento em
  // que walkBlock vai encontrar os cards equivalentes no fragmento clonado
  // (cada entrada e o resultado de attachmentsFromGrid pra um card).
  function extractLiveAttachments(range) {
    if (!range || typeof document === 'undefined' || !document.querySelectorAll) return [];
    const all = Array.prototype.slice.call(document.querySelectorAll(GRID_SEL));
    const inRange = all.filter(function (el) {
      return range.intersectsNode ? range.intersectsNode(el) : false;
    });
    return inRange.map(function (el) { return attachmentsFromGrid(el); });
  }

  // ── Anexos: agrupamento por extensao (guia "Arquivos" no final da saida) ──
  const EXT_LABELS = {
    xlsx: 'Excel', xls: 'Excel', csv: 'Excel',
    pdf: 'PDF',
    docx: 'Word', doc: 'Word',
    pptx: 'PowerPoint', ppt: 'PowerPoint',
    zip: 'Compactado', rar: 'Compactado', '7z': 'Compactado'
  };

  function extOf(name) {
    const m = /\.([a-z0-9]+)$/i.exec(name || '');
    return m ? m[1].toLowerCase() : '';
  }

  function labelForExt(ext) {
    if (EXT_LABELS[ext]) return EXT_LABELS[ext];
    return ext ? ext.toUpperCase() : 'Outro';
  }

  function collectAttachments(model) {
    const out = [];
    const walk = (blocks) => {
      for (const b of (blocks || [])) {
        if (b.type === 'attachment') out.push(b);
        else if (b.type === 'quote') walk(b.blocks);
      }
    };
    for (const m of (model.messages || [])) if (m.blocks) walk(m.blocks);
    return out;
  }

  // Agrupa por extensao, preservando a ordem de 1a aparicao de cada grupo.
  function groupAttachmentsByExt(model) {
    const atts = collectAttachments(model);
    const order = [];
    const byLabel = new Map();
    for (const a of atts) {
      const label = labelForExt(extOf(a.name));
      if (!byLabel.has(label)) { byLabel.set(label, []); order.push(label); }
      byLabel.get(label).push(a);
    }
    return order.map(label => ({ label, items: byLabel.get(label) }));
  }

  // Elementos que sao puro ruido: botoes, svg, aria-hidden, barra de reacao, icones.
  function isPruned(el) {
    if (!el.matches) return false;
    if (el.tagName === 'BUTTON' || el.tagName === 'SVG' || el.tagName === 'svg') return true;
    if (el.getAttribute && el.getAttribute('aria-hidden') === 'true') return true;
    if (el.getAttribute && el.getAttribute('role') === 'button') return true;
    if (el.matches('[class*="reaction" i], [class*="ChatMessageItem__icon" i], [class*="messageActions" i]')) return true;
    // span so-leitor-de-tela com frase de cruft
    const txt = (el.innerText || '').trim();
    if (txt && el.children.length === 0 && CRUFT_RE.test(txt)) return true;
    return false;
  }

  // ── Helpers de texto ──
  function pushText(buf, v) {
    if (!v) return;
    const s = v.replace(/\s+/g, ' ');
    if (!s.trim() && buf.length === 0) return; // nao comeca paragrafo com espaco
    buf.push({ t: 'text', v: s });
  }

  function cleanLine(s) {
    return (s || '').replace(/\s+/g, ' ').trim();
  }

  // Junta inlines de texto adjacentes, funde mencoes fragmentadas, remove cruft.
  function trimInlines(buf) {
    const out = [];
    for (const inl of buf) {
      if (inl.t === 'text') {
        if (CRUFT_RE.test(inl.v.trim())) continue;
        const last = out[out.length - 1];
        if (last && last.t === 'text') { last.v += inl.v; continue; }
      }
      if (inl.t === 'mention') {
        // Teams quebra "@Nome Sobrenome" em varios chips -> funde os adjacentes,
        // absorvendo um eventual espaco em branco (text node) entre dois chips.
        let last = out[out.length - 1];
        if (last && last.t === 'text' && !last.v.trim() && out.length >= 2 && out[out.length - 2].t === 'mention') {
          out.pop();
          last = out[out.length - 1];
        }
        if (last && last.t === 'mention') { last.v += ' ' + inl.v; continue; }
      }
      out.push(Object.assign({}, inl));
    }
    // colapsa espacos multiplos (sobra da remocao de chips de mencao)
    for (const inl of out) { if (inl.t === 'text') inl.v = inl.v.replace(/ {2,}/g, ' '); }
    // apara espaco nas pontas
    if (out.length && out[0].t === 'text') out[0].v = out[0].v.replace(/^\s+/, '');
    if (out.length && out[out.length - 1].t === 'text') out[out.length - 1].v = out[out.length - 1].v.replace(/\s+$/, '');
    return out.filter(i => !(i.t === 'text' && i.v === ''));
  }

  // Remove paragrafos vazios duplicados consecutivos.
  function mergeAdjacent(blocks) {
    return blocks.filter(b => {
      if (b.type === 'p') return b.inlines && b.inlines.length;
      return true;
    });
  }

  CCI.extract = extract;
  CCI.extractLiveAttachments = extractLiveAttachments;
  CCI.collectAttachments = collectAttachments;
  CCI.groupAttachmentsByExt = groupAttachmentsByExt;
  // exporta helpers pra teste/afinacao
  CCI._teams = { topLevelItems, isQuote, isMention, isPruned, getAuthor, getTimestamp, cleanAuthor, attachmentsFromGrid };
})(self);
