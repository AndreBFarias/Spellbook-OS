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
