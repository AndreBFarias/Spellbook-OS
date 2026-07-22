// Content script universal — roda em isolated world em todos os sites.
// Tier 1 ja foi aplicado por unlock-tier1.js em document_start.
// Este script trata: ping, info, unlock-tier2, acoes de selecao/sessao via popup.

(() => {
  'use strict';

  const TAG = '[ctrl-c-ilimitado]';
  const log = (...a) => console.log('%c' + TAG, 'color:#bd93f9;font-weight:bold', ...a);
  const err = (...a) => console.error('%c' + TAG, 'color:#ff5555;font-weight:bold', ...a);

  // ─── 1. Site recognition ────────────────────────────
  function recognizeSite() {
    const host = location.hostname;
    if (/(^|\.)claude\.ai$/.test(host)) return 'claude';
    if (/(^|\.)teams\.microsoft\.com$/.test(host)) return 'teams';
    if (/(^|\.)github\.com$/.test(host)) return 'github';
    if (/(^|\.)chatgpt\.com$/.test(host) || /(^|\.)openai\.com$/.test(host)) return 'chatgpt';
    return 'generic';
  }

  // ─── 2. Tier 2 unlock (mais invasivo, sob demanda) ──
  function applyTier2() {
    if (window.__ctrlCIlimitadoTier2) return 'ja aplicado';
    window.__ctrlCIlimitadoTier2 = true;

    // Override addEventListener pra rejeitar futuros bloqueios em eventos criticos
    const BLOCKED = new Set(['copy', 'cut', 'paste', 'selectstart', 'contextmenu', 'dragstart', 'beforecopy']);
    const origAdd = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = function (type, listener, opts) {
      if (BLOCKED.has(type)) return; // silenciosamente nega
      return origAdd.call(this, type, listener, opts);
    };

    // Nuke handlers inline existentes
    const ATTRS = ['oncopy', 'oncut', 'onpaste', 'onselectstart', 'oncontextmenu', 'ondragstart'];
    document.querySelectorAll('*').forEach(el => {
      ATTRS.forEach(a => { if (el[a]) el[a] = null; });
      ATTRS.forEach(a => el.removeAttribute && el.removeAttribute(a));
    });

    // Re-habilita inputs disabled/readonly (em alguns campos isso libera o copy)
    document.querySelectorAll('input[readonly], textarea[readonly]').forEach(el => el.removeAttribute('readonly'));

    return 'tier 2 aplicado';
  }

  // ─── 3. Helpers gerais ──────────────────────────────
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  function selectionText() {
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed) throw new Error('nada selecionado');
    const t = sel.toString().trim();
    if (!t) throw new Error('selecao vazia');
    return t;
  }

  function wrapAsMd(text) {
    return `> Selecao de ${location.href}\n> Em ${new Date().toISOString()}\n\n${text}`;
  }

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
    if (!navigator.clipboard) throw new Error('clipboard API indisponivel');
    await navigator.clipboard.writeText(text);
  }

  function mdToSimpleHtml(md) {
    const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const lines = md.split('\n');
    const parts = [];
    let inCode = false, codeBuf = [];
    for (const ln of lines) {
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

  // ─── 4. PDF bridge ──────────────────────────────────
  let bridgeReady = false;
  let bridgeLoading = null;
  const pendingPdf = new Map();

  function ensureBridge() {
    if (bridgeReady) return Promise.resolve();
    if (bridgeLoading) return bridgeLoading;
    bridgeLoading = new Promise((resolve, reject) => {
      const onMsg = (e) => {
        if (e.source !== window || !e.data) return;
        if (e.data.__claudeExport === 'bridge-ready') {
          bridgeReady = true;
          resolve();
        }
        if (e.data.__claudeExport === 'pdf-result') {
          const cb = pendingPdf.get(e.data.reqId);
          if (cb) { pendingPdf.delete(e.data.reqId); cb(e.data); }
        }
      };
      window.addEventListener('message', onMsg);

      const libUrl = chrome.runtime.getURL('lib/html2pdf.bundle.min.js');
      const brUrl = chrome.runtime.getURL('main-bridge.js');
      const lib = document.createElement('script');
      lib.src = libUrl;
      lib.onload = () => {
        const br = document.createElement('script');
        br.src = brUrl;
        br.onerror = () => reject(new Error('bridge falhou'));
        document.documentElement.appendChild(br);
      };
      lib.onerror = () => reject(new Error('html2pdf falhou'));
      document.documentElement.appendChild(lib);

      setTimeout(() => { if (!bridgeReady) reject(new Error('bridge timeout (5s)')); }, 5000);
    });
    return bridgeLoading;
  }

  async function generatePdf({ kind, html, opts, snapshotSelector, filename }) {
    await ensureBridge();
    const reqId = Math.random().toString(36).slice(2);
    return new Promise((resolve, reject) => {
      pendingPdf.set(reqId, ({ ok, url, error, size }) => {
        if (!ok) return reject(new Error(error));
        const a = document.createElement('a');
        a.href = url; a.download = filename; a.style.display = 'none';
        document.body.appendChild(a); a.click();
        setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 30000);
        resolve({ size });
      });
      window.postMessage({ __claudeExport: 'pdf-request', reqId, kind, html, opts, snapshotSelector }, '*');
    });
  }

  // ─── 5. Site-specific: claude.ai conversation export ─
  async function tryApiClaude() {
    const m = location.pathname.match(/(?:session|chat|conversations?)[\/_]([a-zA-Z0-9_-]{16,})/);
    const id = m ? m[1] : null;
    if (!id) throw new Error('sem session_id na URL');
    let orgId = null;
    try {
      for (const k of Object.keys(localStorage)) {
        if (!/org/i.test(k)) continue;
        const v = localStorage.getItem(k);
        const mm = v && v.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/);
        if (mm) { orgId = mm[0]; break; }
      }
    } catch (_) {}
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
        const r = await fetch(path, { credentials: 'include', headers: { 'Accept': 'application/json' } });
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
          const ts = mm.created_at || mm.timestamp || mm.createdAt || null;
          return { role, text: String(text).trim(), ts };
        }).filter(mm => mm.text);
        if (msgs.length) return { id, source: 'api:' + path, messages: msgs };
      } catch (_) {}
    }
    throw new Error('API: nenhum endpoint funcionou');
  }

  async function scrapeChatDom() {
    const scrollerSels = ['[data-testid="conversation-turn-scroll"]', 'main [class*="overflow-y"]', 'main [class*="scroll"]', 'main'];
    let sc = null;
    for (const s of scrollerSels) {
      const el = document.querySelector(s);
      if (el && el.scrollHeight > el.clientHeight) { sc = el; break; }
    }
    sc = sc || document.scrollingElement || document.documentElement;
    sc.scrollTo({ top: 0, behavior: 'instant' });
    await sleep(800);
    const turnSel = ['[data-testid^="conversation-turn"]', 'div[class*="font-claude-message"]', 'div[class*="font-user-message"]', 'article'];
    const all = new Map();
    const ingest = () => {
      for (const s of turnSel) {
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
    }
    ingest();
    return { id: null, source: 'dom-scrape', messages: [...all.values()].sort((a, b) => a._y - b._y).map(({ _y, ...r }) => r) };
  }

  function formatConversationMd({ id, source, messages }) {
    const out = [
      `# Conversa ${id ? '- ' + id : ''}`, '',
      `- **URL:** ${location.href}`,
      `- **Site:** ${location.hostname}`,
      `- **Exportado:** ${new Date().toISOString()}`,
      `- **Fonte:** ${source}`,
      `- **Mensagens:** ${messages.length}`, '',
      '---', '',
    ];
    for (const m of messages) {
      const tag = m.role === 'user' ? '## Usuario' : m.role === 'assistant' ? '## Assistente' : `## ${m.role}`;
      out.push(tag + (m.ts ? `  \n*${m.ts}*` : ''), '', m.text, '', '---', '');
    }
    return out.join('\n');
  }

  // ─── 6. Acoes ───────────────────────────────────────
  const ACTIONS = {
    'ping': async () => ({ site: recognizeSite(), host: location.hostname, hasSelection: !!window.getSelection()?.toString().trim() }),

    'unlock-tier2': async () => applyTier2(),

    'selection-copy-md': async () => {
      const md = wrapAsMd(selectionText());
      // Tenta escrever aqui (funciona no menu de contexto, onde a pagina tem foco).
      // No popup a pagina perde o foco -> writeText lanca NotAllowedError; nesse caso
      // devolvemos o texto e o popup (que esta focado) faz a escrita.
      let wrote = false;
      try { await writeClipboard(md); wrote = true; } catch (_) {}
      return { clipboardText: md, wrote, note: `${md.length} chars (.md)` };
    },

    'selection-save-md': async () => {
      const md = wrapAsMd(selectionText());
      triggerDownload(new Blob([md], { type: 'text/markdown;charset=utf-8' }), fname('selecao', 'md'));
      return `${md.length} chars baixados`;
    },

    'selection-copy-txt': async () => {
      const t = selectionText();
      let wrote = false;
      try { await writeClipboard(t); wrote = true; } catch (_) {}
      return { clipboardText: t, wrote, note: `${t.length} chars (txt)` };
    },

    'selection-pdf-text': async () => {
      const t = selectionText();
      const r = await generatePdf({ kind: 'text', html: t, filename: fname('selecao', 'pdf') });
      return `PDF texto (${(r.size / 1024).toFixed(1)} KB)`;
    },

    'selection-pdf-md': async () => {
      const md = wrapAsMd(selectionText());
      const html = mdToSimpleHtml(md);
      const r = await generatePdf({ kind: 'html', html, filename: fname('selecao-md', 'pdf') });
      return `PDF formatado (${(r.size / 1024).toFixed(1)} KB)`;
    },

    'selection-pdf-snap': async () => {
      const sel = window.getSelection();
      if (!sel || sel.isCollapsed) throw new Error('nada selecionado');
      const ancestor = sel.getRangeAt(0).commonAncestorContainer;
      const target = ancestor.nodeType === 1 ? ancestor : ancestor.parentElement;
      if (!target) throw new Error('nao localizou o elemento');
      const tmpId = 'ctrl-c-ilim-snap-' + Math.random().toString(36).slice(2);
      const hadId = !!target.id;
      if (!hadId) target.id = tmpId;
      try {
        const r = await generatePdf({ kind: 'snapshot', snapshotSelector: '#' + target.id, filename: fname('selecao-snap', 'pdf') });
        return `PDF screenshot (${(r.size / 1024).toFixed(1)} KB)`;
      } finally {
        if (!hadId) target.removeAttribute('id');
      }
    },

    'conversation-export': async () => {
      const site = recognizeSite();
      if (site !== 'claude') throw new Error('exportar conversa so funciona em claude.ai (este: ' + site + ')');
      let result;
      try { result = await tryApiClaude(); }
      catch (e) { log('API falhou:', e.message); result = await scrapeChatDom(); }
      if (!result.messages?.length) throw new Error('nenhuma mensagem');
      const md = formatConversationMd(result);
      triggerDownload(new Blob([md], { type: 'text/markdown;charset=utf-8' }), fname('conversa', 'md'));
      try { await writeClipboard(md); } catch (_) {}
      return `${result.messages.length} msgs (${(md.length / 1024).toFixed(1)} KB)`;
    },
  };

  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    const fn = ACTIONS[msg?.action];
    if (!fn) { sendResponse({ ok: false, msg: 'acao desconhecida: ' + msg?.action }); return false; }
    Promise.resolve(fn())
      .then(r => sendResponse({ ok: true, msg: typeof r === 'string' ? r : 'ok', data: typeof r === 'object' ? r : null }))
      .catch(e => { err(msg.action, e); sendResponse({ ok: false, msg: e.message }); });
    return true;
  });

  log('content script ativo em', location.hostname, '(' + recognizeSite() + ')');
})();
