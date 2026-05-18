// Popup universal — envia mensagens pro content script de qualquer site.

const $ = sel => document.querySelector(sel);
const statusEl = $('#status');
const hostEl = $('#host');

function setStatus(msg, cls) {
  statusEl.textContent = msg || '';
  statusEl.className = 'status' + (cls ? ' ' + cls : '');
}

function setButtonsBusy(busy) {
  document.querySelectorAll('button').forEach(b => b.disabled = busy);
}

// Configura UI baseado no site detectado
const SPECIAL = {
  claude: { label: 'Em claude.ai', btn: 'Exportar conversa completa', action: 'conversation-export' },
};

async function init() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || !tab.url) {
      hostEl.textContent = '(aba inacessivel)';
      setButtonsBusy(true);
      return;
    }
    const u = new URL(tab.url);
    hostEl.textContent = u.hostname;

    if (!/^https?:$/.test(u.protocol)) {
      hostEl.textContent += ' (nao suportado)';
      setButtonsBusy(true);
      return;
    }

    // Pinga o content script pra saber o site (e se ta vivo)
    try {
      const r = await chrome.tabs.sendMessage(tab.id, { action: 'ping' });
      if (r && r.ok && r.data) {
        const site = r.data.site;
        if (SPECIAL[site]) {
          $('#section-special').hidden = false;
          $('#special-label').textContent = SPECIAL[site].label;
          $('#special-btn').textContent = SPECIAL[site].btn;
          $('#special-btn').dataset.action = SPECIAL[site].action;
        }
      }
    } catch (_) {
      setStatus('content script nao injetou ainda — recarregue a aba (F5)', 'err');
    }
  } catch (e) {
    setStatus(e.message, 'err');
  }
}

async function dispatch(action) {
  setButtonsBusy(true);
  setStatus('processando...', '');
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab) throw new Error('sem aba ativa');
    const reply = await chrome.tabs.sendMessage(tab.id, { action });
    if (!reply) throw new Error('sem resposta do content script (recarregue a aba)');
    setStatus(reply.msg || (reply.ok ? 'pronto' : 'falhou'), reply.ok ? 'ok' : 'err');
  } catch (e) {
    setStatus(e.message, 'err');
  } finally {
    setButtonsBusy(false);
    setTimeout(() => { if (!statusEl.classList.contains('err')) setStatus(''); }, 4000);
  }
}

document.querySelectorAll('button[data-action]').forEach(b => {
  b.addEventListener('click', () => dispatch(b.dataset.action));
});

$('#help').addEventListener('click', e => {
  e.preventDefault();
  setStatus('selecione texto na pagina, depois clique a acao desejada', '');
});

init();
