// Service worker minimo. Mantido para extensibilidade futura (auto-reload, badge, etc).
// Tambem garante que o popup tenha contexto de extensao valido.

chrome.runtime.onInstalled.addListener(({ reason }) => {
  console.log('[ctrl-c-ilimitado] installed, reason=' + reason);
});

// Re-injeta content script em abas claude.ai que ja estavam abertas no momento do install
chrome.runtime.onInstalled.addListener(async () => {
  try {
    const tabs = await chrome.tabs.query({ url: 'https://claude.ai/*' });
    for (const t of tabs) {
      try {
        await chrome.scripting.executeScript({ target: { tabId: t.id }, files: ['content.js'] });
      } catch (_) { /* aba pode estar protegida (about:blank etc) */ }
    }
  } catch (e) {
    console.error('[ctrl-c-ilimitado] re-inject falhou', e);
  }
});

// =============================================================================
// Context menu (botao direito) — replica as acoes do popup quando ha selecao
// =============================================================================

// Map menu id -> action name aceito pelo listener em content.js
const MENU_ACTIONS = {
  'cci-copy-md':         'selection-copy-md',
  'cci-copy-txt':        'selection-copy-txt',
  'cci-save-md':         'selection-save-md',
  // PDF desabilitado temporariamente: bloqueado no Teams (Trusted Types / ERR_BLOCKED_BY_CLIENT).
  // 'cci-pdf-text':        'selection-pdf-text',
  // 'cci-pdf-formatted':   'selection-pdf-md',
  // 'cci-pdf-screenshot':  'selection-pdf-snap',
  'cci-unlock':          'unlock-tier2',
};

const MENU_ITEMS = [
  { id: 'cci-copy-md',       title: 'Ctrl+C Ilimitado: Copiar como .md (markdown)', contexts: ['selection'] },
  { id: 'cci-copy-txt',      title: 'Ctrl+C Ilimitado: Copiar texto puro',          contexts: ['selection'] },
  { id: 'cci-save-md',       title: 'Ctrl+C Ilimitado: Baixar arquivo .md',         contexts: ['selection'] },
  // PDF desabilitado temporariamente (ver MENU_ACTIONS acima).
  // { id: 'cci-pdf-text',      title: 'Ctrl+C Ilimitado: PDF (apenas texto)',         contexts: ['selection'] },
  // { id: 'cci-pdf-formatted', title: 'Ctrl+C Ilimitado: PDF (formatado/HTML)',       contexts: ['selection'] },
  // { id: 'cci-pdf-screenshot',title: 'Ctrl+C Ilimitado: PDF (screenshot/imagem)',    contexts: ['selection'] },
  { id: 'cci-unlock',        title: 'Ctrl+C Ilimitado: Desbloquear total (Tier 2)', contexts: ['page'] },
];

function createMenus() {
  chrome.contextMenus.removeAll(() => {
    for (const item of MENU_ITEMS) {
      chrome.contextMenus.create(item);
    }
  });
}

chrome.runtime.onInstalled.addListener(createMenus);
chrome.runtime.onStartup.addListener(createMenus);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (!tab || !tab.id) return;
  const action = MENU_ACTIONS[info.menuItemId];
  if (!action) return;
  try {
    await chrome.tabs.sendMessage(tab.id, { action });
  } catch (e) {
    console.error('[ctrl-c-ilimitado] context-menu sendMessage falhou', e);
  }
});

// =============================================================================
// Leitura de anexos do Teams no MAIN WORLD (ponte pro content script)
// =============================================================================
// Content scripts rodam em isolated world: veem o mesmo DOM da pagina, mas
// NAO enxergam expando properties que o React (main world) anexa aos nos,
// como __reactProps$... -- e uma barreira de seguranca do Chrome, nao um
// detalhe de timing. Por isso a leitura roda aqui, via chrome.scripting com
// world:'MAIN', sobre os cards que o content script marcou com um atributo
// DOM real (data-cci-grid-tmp) antes de mandar esta mensagem.
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg?.action !== 'read-live-grid-attachments') return false;
  const tabId = sender.tab && sender.tab.id;
  if (!tabId) { sendResponse({ ok: false, data: [] }); return false; }
  chrome.scripting.executeScript({
    target: { tabId },
    world: 'MAIN',
    func: readGridAttachmentsInMainWorld,
  }).then((results) => {
    const data = (results && results[0] && results[0].result) || [];
    sendResponse({ ok: true, data });
  }).catch((e) => {
    console.error('[ctrl-c-ilimitado] read-live-grid-attachments falhou', e);
    sendResponse({ ok: false, data: [] });
  });
  return true; // resposta assincrona
});

// Roda no MAIN WORLD da pagina via chrome.scripting.executeScript -- por isso
// precisa ser autocontida (a API serializa a funcao e a reexecuta isolada,
// sem closures deste arquivo). Duplica a logica de attachmentsFromGrid de
// lib/teams-extract.js por essa razao; manter as duas em sincronia.
function readGridAttachmentsInMainWorld() {
  function reactPropsOf(el) {
    const keys = Object.keys(el);
    for (const k of keys) {
      if (k.indexOf('__reactProps$') === 0) return el[k];
    }
    return null;
  }
  function filenameFromUrl(url) {
    if (!url) return null;
    try {
      const clean = url.split('?')[0];
      const segs = clean.split('/').filter(Boolean);
      const last = segs[segs.length - 1];
      return last ? decodeURIComponent(last) : null;
    } catch (e) { return null; }
  }
  function attachmentNameFrom(file) {
    return file.title || file.name || file.fileName ||
      filenameFromUrl(file.objectUrl) || filenameFromUrl(file.shareUrl) || null;
  }
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
  const els = Array.prototype.slice.call(document.querySelectorAll('[data-cci-grid-tmp]'))
    .sort(function (a, b) {
      return Number(a.getAttribute('data-cci-grid-tmp')) - Number(b.getAttribute('data-cci-grid-tmp'));
    });
  return els.map(function (el) { return attachmentsFromGrid(el); });
}
