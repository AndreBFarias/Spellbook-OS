// ==UserScript==
// @name         Ctrl+C Ilimitado
// @namespace    aurora.andrefarias
// @version      2.0.0
// @description  Desbloqueia copy/paste/selecao em qualquer site. Salva selecao como md/pdf. Em claude.ai, exporta conversa.
// @match        *://*/*
// @run-at       document-start
// @grant        GM_setClipboard
// @grant        GM_xmlhttpRequest
// @connect      cdnjs.cloudflare.com
// @noframes
// ==/UserScript==

(() => {
  'use strict';

  const TAG = '[ctrl-c-ilimitado-us]';
  const log = (...a) => console.log('%c' + TAG, 'color:#bd93f9;font-weight:bold', ...a);
  const err = (...a) => console.error('%c' + TAG, 'color:#ff5555;font-weight:bold', ...a);

  // ─── Tier 1 — aplicado em document-start ────────────
  if (!window.__ctrlCIlimitadoTier1) {
    window.__ctrlCIlimitadoTier1 = true;
    const EVENTS = ['copy', 'cut', 'paste', 'selectstart', 'contextmenu', 'dragstart', 'beforecopy'];
    const stop = (e) => e.stopImmediatePropagation();
    for (const evt of EVENTS) {
      window.addEventListener(evt, stop, { capture: true, passive: true });
      document.addEventListener(evt, stop, { capture: true, passive: true });
    }
    const applyCSS = () => {
      if (document.getElementById('ctrl-c-ilimitado-css')) return;
      const s = document.createElement('style');
      s.id = 'ctrl-c-ilimitado-css';
      s.textContent = `
        *, *::before, *::after {
          user-select: text !important; -webkit-user-select: text !important;
          -moz-user-select: text !important; -ms-user-select: text !important;
          -webkit-touch-callout: default !important;
        }
        *::selection { background: rgba(189, 147, 249, .35) !important; color: inherit !important; }
        *::-moz-selection { background: rgba(189, 147, 249, .35) !important; color: inherit !important; }
      `;
      (document.head || document.documentElement).appendChild(s);
    };
    if (document.head) applyCSS();
    else new MutationObserver((_, obs) => { if (document.head) { applyCSS(); obs.disconnect(); } })
      .observe(document.documentElement, { childList: true });
  }

  function applyTier2() {
    if (window.__ctrlCIlimitadoTier2) return 'ja aplicado';
    window.__ctrlCIlimitadoTier2 = true;
    const BLOCKED = new Set(['copy', 'cut', 'paste', 'selectstart', 'contextmenu', 'dragstart', 'beforecopy']);
    const origAdd = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (type, listener, opts) {
      if (BLOCKED.has(type)) return;
      return origAdd.call(this, type, listener, opts);
    };
    const ATTRS = ['oncopy', 'oncut', 'onpaste', 'onselectstart', 'oncontextmenu', 'ondragstart'];
    document.querySelectorAll('*').forEach(el => {
      ATTRS.forEach(a => { if (el[a]) el[a] = null; el.removeAttribute && el.removeAttribute(a); });
    });
    document.querySelectorAll('input[readonly], textarea[readonly]').forEach(el => el.removeAttribute('readonly'));
    return 'tier 2 aplicado';
  }

  function recognizeSite() {
    const h = location.hostname;
    if (/(^|\.)claude\.ai$/.test(h)) return 'claude';
    if (/(^|\.)teams\.microsoft\.com$/.test(h)) return 'teams';
    if (/(^|\.)github\.com$/.test(h)) return 'github';
    if (/(^|\.)chatgpt\.com$/.test(h) || /(^|\.)openai\.com$/.test(h)) return 'chatgpt';
    return 'generic';
  }

  let pdfLibPromise = null;
  function loadHtml2pdf() {
    if (typeof window.html2pdf === 'function') return Promise.resolve();
    if (pdfLibPromise) return pdfLibPromise;
    pdfLibPromise = new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = 'https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js';
      s.crossOrigin = 'anonymous';
      s.onload = () => resolve();
      s.onerror = () => reject(new Error('falha ao carregar html2pdf'));
      (document.head || document.documentElement).appendChild(s);
    });
    return pdfLibPromise;
  }

  const sleep = ms => new Promise(r => setTimeout(r, ms));

  function selectionText() {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed) throw new Error('nada selecionado');
    const t = sel.toString().trim();
    if (!t) throw new Error('selecao vazia');
    return t;
  }

  const wrapAsMd = (t) => `> Selecao de ${location.href}\n> Em ${new Date().toISOString()}\n\n${t}`;

  function fname(prefix, ext) {
    const host = location.hostname.replace(/[^a-zA-Z0-9.-]/g, '_');
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    return `${prefix}_${host}_${ts}.${ext}`;
  }

  function triggerDownload(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename; a.style.display = 'none';
    document.body.appendChild(a); a.click();
    setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 1500);
  }

  async function writeClipboard(text) {
    if (typeof GM_setClipboard === 'function') { GM_setClipboard(text, 'text'); return; }
    if (navigator.clipboard) { await navigator.clipboard.writeText(text); return; }
    throw new Error('clipboard indisponivel');
  }

  function mdToSimpleHtml(md) {
    const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const parts = [];
    let inCode = false, codeBuf = [];
    for (const ln of md.split('\n')) {
      if (ln.startsWith('```')) {
        if (inCode) {
          parts.push(`<pre style="background:#f4f4f4;padding:12px;border-radius:6px;overflow:auto;font:13px ui-monospace,monospace;"><code>${esc(codeBuf.join('\n'))}</code></pre>`);
          codeBuf = []; inCode = false;
        } else inCode = true;
        continue;
      }
      if (inCode) { codeBuf.push(ln); continue; }
      if (/^#{1,6}\s/.test(ln)) {
        const lvl = ln.match(/^#+/)[0].length;
        parts.push(`<h${lvl} style="margin:18px 0 8px;">${esc(ln.replace(/^#+\s/, ''))}</h${lvl}>`);
      } else if (ln.trim() === '') parts.push('');
      else if (ln.startsWith('---')) parts.push('<hr style="border:none;border-top:1px solid #ccc;margin:18px 0;">');
      else {
        const html = esc(ln)
          .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
          .replace(/`([^`]+)`/g, '<code style="background:#f4f4f4;padding:1px 5px;border-radius:3px;font:.92em ui-monospace,monospace;">$1</code>');
        parts.push(`<p style="margin:6px 0;">${html}</p>`);
      }
    }
    return parts.filter(p => p !== '').join('\n');
  }

  async function pdfFromText(text, filename) {
    await loadHtml2pdf();
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:absolute;left:-99999px;top:0;width:794px;padding:24px;background:#fff;color:#000;';
    const pre = document.createElement('pre');
    pre.style.cssText = 'white-space:pre-wrap;font:13px/1.5 ui-monospace,monospace;margin:0;';
    pre.textContent = text;
    wrap.appendChild(pre);
    document.body.appendChild(wrap);
    try {
      const blob = await window.html2pdf().set({
        margin: 10, filename, jsPDF: { unit: 'mm', format: 'a4' },
        html2canvas: { scale: 2, backgroundColor: '#fff', logging: false },
      }).from(wrap).outputPdf('blob');
      triggerDownload(blob, filename);
      return blob.size;
    } finally { wrap.remove(); }
  }

  async function pdfFromHtml(htmlString, filename) {
    await loadHtml2pdf();
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:absolute;left:-99999px;top:0;width:794px;padding:24px;background:#fff;color:#000;font:14px/1.55 system-ui,sans-serif;';
    const doc = new DOMParser().parseFromString(htmlString, 'text/html');
    while (doc.body.firstChild) wrap.appendChild(doc.body.firstChild);
    document.body.appendChild(wrap);
    try {
      const blob = await window.html2pdf().set({
        margin: 10, filename, jsPDF: { unit: 'mm', format: 'a4' },
        html2canvas: { scale: 2, backgroundColor: '#fff', logging: false },
      }).from(wrap).outputPdf('blob');
      triggerDownload(blob, filename);
      return blob.size;
    } finally { wrap.remove(); }
  }

  async function pdfFromNode(node, filename) {
    await loadHtml2pdf();
    const blob = await window.html2pdf().set({
      margin: 10, filename, jsPDF: { unit: 'mm', format: 'a4' },
      html2canvas: { scale: 2, useCORS: true, backgroundColor: '#fff', logging: false },
    }).from(node).outputPdf('blob');
    triggerDownload(blob, filename);
    return blob.size;
  }

  async function exportClaudeConversation() {
    const m = location.pathname.match(/(?:session|chat|conversations?)[\/_]([a-zA-Z0-9_-]{16,})/);
    const id = m ? m[1] : null;
    let orgId = null;
    try {
      for (const k of Object.keys(localStorage)) {
        if (!/org/i.test(k)) continue;
        const v = localStorage.getItem(k);
        const mm = v && v.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
        if (mm) { orgId = mm[0]; break; }
      }
    } catch (_) {}

    let result = null;
    if (id) {
      const cands = [
        `/api/organizations/${orgId}/chat_conversations/${id}?tree=True&rendering_mode=raw`,
        `/api/organizations/${orgId}/sessions/${id}`,
        `/api/organizations/${orgId}/sessions/${id}/messages`,
        `/api/organizations/${orgId}/code/sessions/${id}`,
        `/api/organizations/${orgId}/code/sessions/${id}/messages`,
        `/api/sessions/${id}`,
        `/api/sessions/${id}/messages`,
      ].filter(u => !u.includes('/null/'));
      for (const path of cands) {
        try {
          const r = await fetch(path, { credentials: 'include', headers: { Accept: 'application/json' } });
          if (!r.ok) continue;
          const j = await r.json();
          const arr = [j?.chat_messages, j?.messages, j?.events, j?.conversation?.messages, j?.data?.messages].filter(Array.isArray)[0];
          if (!arr || !arr.length) continue;
          const msgs = arr.map(mm => {
            const role = mm.sender === 'human' ? 'user' :
                         mm.sender === 'assistant' ? 'assistant' :
                         mm.role || mm.author?.role || (mm.is_human ? 'user' : 'assistant');
            const text = mm.text || mm.content?.map?.(c => c.text || '').join('\n') ||
                         mm.message?.content?.parts?.join('\n') || mm.body || '';
            return { role, text: String(text).trim(), ts: mm.created_at || mm.timestamp || mm.createdAt || null };
          }).filter(mm => mm.text);
          if (msgs.length) { result = { id, source: 'api:' + path, messages: msgs }; break; }
        } catch (_) {}
      }
    }

    if (!result) {
      log('API falhou, DOM scrape');
      const sc = document.querySelector('main [class*="overflow-y"]') || document.querySelector('main') || document.scrollingElement;
      sc.scrollTo({ top: 0, behavior: 'instant' });
      await sleep(800);
      const all = new Map();
      const ingest = () => {
        for (const s of ['[data-testid^="conversation-turn"]', 'div[class*="font-claude-message"]', 'div[class*="font-user-message"]', 'article']) {
          document.querySelectorAll(s).forEach(n => {
            const c = n.cloneNode(true);
            c.querySelectorAll('button, svg, [aria-hidden="true"]').forEach(x => x.remove());
            const t = c.innerText.trim();
            if (!t || t.length < 2) return;
            const k = t.slice(0, 200);
            if (!all.has(k)) {
              const role = n.matches?.('[class*="font-user-message"]') || n.querySelector?.('[class*="font-user-message"]') ? 'user' :
                           n.matches?.('[class*="font-claude-message"]') || n.querySelector?.('[class*="font-claude-message"]') ? 'assistant' : 'unknown';
              all.set(k, { role, text: t, _y: n.getBoundingClientRect().top + window.scrollY });
            }
          });
        }
      };
      let lastH = -1, stable = 0;
      while (stable < 3) {
        ingest();
        sc.scrollBy({ top: sc.clientHeight * 0.85, behavior: 'instant' });
        await sleep(450);
        if (sc.scrollHeight === lastH && sc.scrollTop + sc.clientHeight >= sc.scrollHeight - 4) stable++;
        else stable = 0;
        lastH = sc.scrollHeight;
        setBusy(true, `scroll ${all.size} msgs`);
      }
      ingest();
      result = { id, source: 'dom-scrape', messages: [...all.values()].sort((a, b) => a._y - b._y).map(({ _y, ...r }) => r) };
    }

    if (!result.messages.length) throw new Error('nenhuma mensagem');
    const out = [
      `# Conversa ${id ? '- ' + id : ''}`, '',
      `- **URL:** ${location.href}`,
      `- **Site:** ${location.hostname}`,
      `- **Exportado:** ${new Date().toISOString()}`,
      `- **Fonte:** ${result.source}`,
      `- **Mensagens:** ${result.messages.length}`, '',
      '---', '',
    ];
    for (const mm of result.messages) {
      const tag = mm.role === 'user' ? '## Usuario' : mm.role === 'assistant' ? '## Assistente' : `## ${mm.role}`;
      out.push(tag + (mm.ts ? `  \n*${mm.ts}*` : ''), '', mm.text, '', '---', '');
    }
    const md = out.join('\n');
    triggerDownload(new Blob([md], { type: 'text/markdown;charset=utf-8' }), fname('conversa', 'md'));
    try { await writeClipboard(md); } catch (_) {}
    return `${result.messages.length} msgs (${(md.length / 1024).toFixed(1)} KB)`;
  }

  // ─── UI ─────────────────────────────────────────────
  const STYLE_ID = 'ctrl-c-ilimitado-style';
  const BTN_ID = 'ctrl-c-ilimitado-btn';
  const MENU_ID = 'ctrl-c-ilimitado-menu';

  function injectStyle() {
    if (document.getElementById(STYLE_ID)) return;
    const s = document.createElement('style');
    s.id = STYLE_ID;
    s.textContent = `
      #${BTN_ID} {
        position: fixed; bottom: 18px; right: 18px; z-index: 2147483647;
        width: 38px; height: 38px; border-radius: 50%; border: none; padding: 0;
        background: linear-gradient(135deg,#bd93f9,#ff79c6);
        color: #fff; font: 700 16px/1 ui-monospace,monospace;
        box-shadow: 0 4px 16px rgba(0,0,0,.35); cursor: pointer;
        transition: transform .15s ease, opacity .15s ease;
        display: flex; align-items: center; justify-content: center;
      }
      #${BTN_ID}:hover { transform: scale(1.1); }
      #${BTN_ID}[data-busy="1"] { opacity: .65; cursor: progress; }
      #${MENU_ID} {
        position: fixed; bottom: 64px; right: 18px; z-index: 2147483647;
        background: #282a36; color: #f8f8f2;
        border: 1px solid #44475a; border-radius: 8px;
        box-shadow: 0 8px 24px rgba(0,0,0,.5);
        font: 12px/1.4 ui-monospace,monospace;
        min-width: 230px; padding: 6px; display: none;
      }
      #${MENU_ID}[data-open="1"] { display: block; }
      #${MENU_ID} .ce-section { padding: 6px 8px 4px; color: #6272a4; font-size: 10px; text-transform: uppercase; letter-spacing: 1px; }
      #${MENU_ID} button.ce-item {
        display: block; width: 100%; padding: 8px 10px; margin: 0 0 2px;
        background: transparent; color: inherit; border: none; text-align: left;
        font: inherit; font-size: 12px; cursor: pointer; border-radius: 4px;
      }
      #${MENU_ID} button.ce-item:hover { background: #44475a; }
      #${MENU_ID} button.ce-item.primary { background: linear-gradient(135deg,#bd93f9,#ff79c6); color:#fff; font-weight: 600; }
      #${MENU_ID} .ce-pdf-row { display: flex; gap: 4px; padding: 0 8px 4px; }
      #${MENU_ID} .ce-pdf-row .ce-item { flex: 1; text-align: center; font-size: 11px; padding: 6px 4px; background: #1e1f29; border: 1px solid #44475a; }
      #${MENU_ID} .ce-pdf-row .ce-item:hover { border-color: #bd93f9; }
      #${MENU_ID} .ce-pdf-label { padding: 4px 8px 0; color: #6272a4; font-size: 10px; }
      #${MENU_ID} .ce-host { padding: 0 8px 4px; color: #6272a4; font-size: 10px; word-break: break-all; }
      .ce-toast { position: fixed; bottom: 120px; right: 18px; z-index: 2147483647;
        padding: 10px 14px; border-radius: 8px; max-width: 320px;
        font: 600 12px/1.3 ui-monospace,monospace; box-shadow: 0 4px 12px rgba(0,0,0,.4); }
      .ce-toast.ok { background: #50fa7b; color: #000; }
      .ce-toast.err { background: #ff5555; color: #000; }
    `;
    (document.head || document.documentElement).appendChild(s);
  }

  function ensureButton() {
    if (document.getElementById(BTN_ID) || !document.body) return;
    const b = document.createElement('button');
    b.id = BTN_ID;
    b.title = 'Ctrl+C Ilimitado - menu';
    b.textContent = 'C+';
    b.addEventListener('click', toggleMenu);
    document.body.appendChild(b);

    const m = document.createElement('div');
    m.id = MENU_ID;
    buildMenu(m);
    document.body.appendChild(m);

    document.addEventListener('click', (e) => {
      if (!m.contains(e.target) && e.target !== b) closeMenu();
    });
  }

  function buildMenu(root) {
    const site = recognizeSite();
    const items = [
      { type: 'host', label: location.hostname + ' (' + site + ')' },
      { type: 'section', label: 'Neste site' },
      { type: 'item', action: 'unlock-tier2', label: 'Desbloquear total' },
      { type: 'section', label: 'Selecao atual' },
      { type: 'item', action: 'selection-copy-md', label: 'Copiar como .md' },
      { type: 'item', action: 'selection-copy-txt', label: 'Copiar texto puro' },
      { type: 'item', action: 'selection-save-md', label: 'Baixar .md' },
      { type: 'pdf-label', label: 'PDF da selecao:' },
      { type: 'pdf-row', items: [
        { action: 'selection-pdf-text', label: 'texto', title: 'Texto puro' },
        { action: 'selection-pdf-md', label: 'formatado', title: 'Markdown renderizado' },
        { action: 'selection-pdf-snap', label: 'screenshot', title: 'Visual fiel' },
      ] },
    ];
    if (site === 'claude') {
      items.push(
        { type: 'section', label: 'Em claude.ai' },
        { type: 'item', action: 'conversation-export', label: 'Exportar conversa completa', primary: true },
      );
    }

    for (const it of items) {
      if (it.type === 'host') { const s = document.createElement('div'); s.className = 'ce-host'; s.textContent = it.label; root.appendChild(s); }
      else if (it.type === 'section') { const s = document.createElement('div'); s.className = 'ce-section'; s.textContent = it.label; root.appendChild(s); }
      else if (it.type === 'item') {
        const b = document.createElement('button');
        b.className = 'ce-item' + (it.primary ? ' primary' : '');
        b.textContent = it.label;
        b.dataset.action = it.action;
        b.addEventListener('click', () => runAction(it.action));
        root.appendChild(b);
      } else if (it.type === 'pdf-label') { const s = document.createElement('div'); s.className = 'ce-pdf-label'; s.textContent = it.label; root.appendChild(s); }
      else if (it.type === 'pdf-row') {
        const row = document.createElement('div');
        row.className = 'ce-pdf-row';
        for (const sub of it.items) {
          const b = document.createElement('button');
          b.className = 'ce-item';
          b.textContent = sub.label;
          b.title = sub.title || '';
          b.dataset.action = sub.action;
          b.addEventListener('click', () => runAction(sub.action));
          row.appendChild(b);
        }
        root.appendChild(row);
      }
    }
  }

  function toggleMenu(e) { e?.stopPropagation(); const m = document.getElementById(MENU_ID); if (m) m.dataset.open = m.dataset.open === '1' ? '0' : '1'; }
  function closeMenu() { const m = document.getElementById(MENU_ID); if (m) m.dataset.open = '0'; }
  function setBusy(busy, label) {
    const b = document.getElementById(BTN_ID);
    if (!b) return;
    b.dataset.busy = busy ? '1' : '0';
    b.textContent = busy ? '...' : 'C+';
    if (label) b.title = label;
  }
  function toast(msg, isErr) {
    const t = document.createElement('div');
    t.className = 'ce-toast ' + (isErr ? 'err' : 'ok');
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(() => t.remove(), 4500);
  }

  const ACTIONS = {
    'unlock-tier2': async () => applyTier2(),
    'selection-copy-md': async () => { const md = wrapAsMd(selectionText()); await writeClipboard(md); return `${md.length} chars (md) copiados`; },
    'selection-copy-txt': async () => { const t = selectionText(); await writeClipboard(t); return `${t.length} chars copiados`; },
    'selection-save-md': async () => { const md = wrapAsMd(selectionText()); triggerDownload(new Blob([md], { type: 'text/markdown;charset=utf-8' }), fname('selecao', 'md')); return `${md.length} chars baixados`; },
    'selection-pdf-text': async () => { const t = selectionText(); const size = await pdfFromText(t, fname('selecao', 'pdf')); return `PDF texto (${(size/1024).toFixed(1)} KB)`; },
    'selection-pdf-md': async () => { const md = wrapAsMd(selectionText()); const html = mdToSimpleHtml(md); const size = await pdfFromHtml(html, fname('selecao-md', 'pdf')); return `PDF formatado (${(size/1024).toFixed(1)} KB)`; },
    'selection-pdf-snap': async () => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed) throw new Error('nada selecionado');
      const ancestor = sel.getRangeAt(0).commonAncestorContainer;
      const target = ancestor.nodeType === 1 ? ancestor : ancestor.parentElement;
      if (!target) throw new Error('nao localizou o elemento');
      const size = await pdfFromNode(target, fname('selecao-snap', 'pdf'));
      return `PDF snapshot (${(size/1024).toFixed(1)} KB)`;
    },
    'conversation-export': exportClaudeConversation,
  };

  async function runAction(action) {
    closeMenu();
    const fn = ACTIONS[action];
    if (!fn) { toast('acao desconhecida: ' + action, true); return; }
    setBusy(true, action);
    try {
      const msg = await fn();
      toast('OK: ' + msg);
    } catch (e) {
      err(action, e);
      toast('ERRO: ' + e.message, true);
    } finally {
      setBusy(false);
    }
  }

  function boot() {
    injectStyle();
    ensureButton();
    new MutationObserver(() => ensureButton())
      .observe(document.body || document.documentElement, { childList: true, subtree: false });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  log('Ctrl+C Ilimitado ativo em', location.hostname);
})();
