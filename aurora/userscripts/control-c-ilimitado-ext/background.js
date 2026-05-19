// Service worker minimo. Mantido para extensibilidade futura (auto-reload, badge, etc).
// Tambem garante que o popup tenha contexto de extensao valido.

chrome.runtime.onInstalled.addListener(({ reason }) => {
  console.log('[claude-export] installed, reason=' + reason);
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
    console.error('[claude-export] re-inject falhou', e);
  }
});

// =============================================================================
// Context menu (botao direito) — replica as acoes do popup quando ha selecao
// =============================================================================

const MENU_ITEMS = [
  { id: 'cci-copy-md',     title: 'Ctrl+C Ilimitado: Copiar como .md',        contexts: ['selection'] },
  { id: 'cci-copy-txt',    title: 'Ctrl+C Ilimitado: Copiar texto puro',      contexts: ['selection'] },
  { id: 'cci-save-md',     title: 'Ctrl+C Ilimitado: Baixar .md',             contexts: ['selection'] },
  { id: 'cci-pdf-text',    title: 'Ctrl+C Ilimitado: PDF (texto)',            contexts: ['selection'] },
  { id: 'cci-pdf-formatted', title: 'Ctrl+C Ilimitado: PDF (formatado)',     contexts: ['selection'] },
  { id: 'cci-pdf-screenshot', title: 'Ctrl+C Ilimitado: PDF (screenshot)',   contexts: ['selection'] },
  { id: 'cci-unlock',      title: 'Ctrl+C Ilimitado: Desbloquear total (Tier 2)', contexts: ['page'] },
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
  const action = info.menuItemId.replace(/^cci-/, '');
  // Encaminha pro content script via chrome.tabs.sendMessage
  try {
    await chrome.tabs.sendMessage(tab.id, { __cciContextMenu: true, action });
  } catch (e) {
    console.error('[claude-export] context-menu sendMessage falhou', e);
  }
});
