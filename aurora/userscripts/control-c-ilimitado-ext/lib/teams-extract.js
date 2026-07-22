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

  const INLINE_TAGS = new Set(['SPAN', 'A', 'B', 'STRONG', 'I', 'EM', 'CODE', 'U', 'S',
    'SUB', 'SUP', 'MARK', 'SMALL', 'ABBR', 'TIME', 'LABEL', 'FONT']);

  // Frases que sao so acessibilidade/ruido e devem sumir do texto de saida.
  const CRUFT_RE = /(tem menu de contexto|menu de contexto|Coração reaç(ão|ões)|reaç(ão|ões)\.?$|^\s*\d+\s*$|Início da citação)/i;

  // Regex de hora/data que o Teams mostra: "22/07 11:57", "06/07/2026, 13:18", "09:58".
  const TIME_RE = /(\d{1,2}\/\d{1,2}(\/\d{2,4})?(,?\s*\d{1,2}:\d{2})?|\b\d{1,2}:\d{2}\b)/;

  // ── Entrada ──
  function extract(fragment) {
    const messages = [];
    const items = topLevelItems(fragment);

    if (!items.length) {
      // Nenhum container de mensagem reconhecido: trata o fragmento inteiro como
      // um bloco unico (fallback — melhor entregar texto cru que perder tudo).
      const blocks = blocksFrom(fragment);
      if (blocks.length) messages.push({ kind: 'message', author: null, timestamp: null, blocks });
      return { messages };
    }

    for (const it of items) {
      if (isSystem(it)) {
        const text = cleanLine(it.innerText || '');
        if (text) messages.push({ kind: 'system', text });
        continue;
      }
      messages.push(messageFrom(it));
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

  function messageFrom(it) {
    const author = getAuthor(it);
    const timestamp = getTimestamp(it);
    const bodyEl = it.querySelector(BODY_SEL) || it;
    const blocks = blocksFrom(bodyEl);
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
    const t = it.querySelector('time');
    if (t) {
      const tt = (t.getAttribute('datetime') || t.innerText || '').trim();
      if (tt) return tt;
    }
    const head = (it.querySelector(AUTHOR_SEL) || it).innerText || '';
    const m = head.match(TIME_RE);
    return m ? m[0].trim() : null;
  }

  // ── Corpo -> blocos ──
  function blocksFrom(container) {
    const out = [];
    let buf = []; // buffer de inlines do paragrafo corrente
    const flush = () => {
      const inl = trimInlines(buf);
      if (inl.length) out.push({ type: 'p', inlines: inl });
      buf = [];
    };

    walkBlock(container, out, buf, flush);
    flush();
    return mergeAdjacent(out);
  }

  // Caminha um container em nivel de bloco. Empurra blocos especiais em `out` e
  // acumula texto inline em `buf` (via closure de flush).
  function walkBlock(container, out, buf, flush) {
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
        buf.push({ t: 'mention', v: cleanLine(el.innerText || '') });
        continue;
      }

      // Inline conhecido -> acumula no paragrafo
      if (INLINE_TAGS.has(tag)) {
        inlineInto(el, buf);
        continue;
      }

      // Bloco generico (div/p/section...): fecha o paragrafo atual e desce.
      flush();
      walkBlock(el, out, buf, flush);
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
      if (isMention(c)) { buf.push({ t: 'mention', v: cleanLine(c.innerText || '') }); continue; }
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
    // autor/hora do preview da citacao, quando presentes
    const qAuthorEl = el.querySelector(AUTHOR_SEL) || el.querySelector('.fui-StyledText');
    const author = qAuthorEl ? cleanAuthor(qAuthorEl.innerText) : null;
    const timestamp = getTimestamp(el);
    const bodyEl = el.querySelector(BODY_SEL) || el;
    const blocks = blocksFrom(bodyEl);
    const truncated = /…|\.\.\.$/.test((el.innerText || '').trim());
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

  // ── Reconhecimento ajustavel (o que o harness vai calibrar) ──
  function isQuote(el) {
    if (!el.matches) return false;
    if (el.tagName === 'BLOCKQUOTE') return true;
    if (el.matches('[class*="quote" i], [class*="reply" i], [class*="Citation" i]')) return true;
    // Sinal forte do Teams: aria/texto "Início da citação"
    const aria = (el.getAttribute && (el.getAttribute('aria-label') || '')) || '';
    if (/início da citação|inicio da citacao/i.test(aria)) return true;
    return false;
  }

  function isMention(el) {
    if (!el.matches) return false;
    return el.matches('[class*="mention" i], [data-mention], [itemtype*="Person" i]');
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

  // Junta inlines de texto adjacentes, remove cruft, apara pontas.
  function trimInlines(buf) {
    const out = [];
    for (const inl of buf) {
      if (inl.t === 'text') {
        if (CRUFT_RE.test(inl.v.trim())) continue;
        const last = out[out.length - 1];
        if (last && last.t === 'text') { last.v += inl.v; continue; }
      }
      out.push(Object.assign({}, inl));
    }
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
  // exporta helpers pra teste/afinacao
  CCI._teams = { topLevelItems, isQuote, isMention, isPruned, getAuthor, getTimestamp, cleanAuthor };
})(self);
