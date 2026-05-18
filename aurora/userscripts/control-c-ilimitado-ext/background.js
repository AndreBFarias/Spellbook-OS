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
