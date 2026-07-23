// Popup universal — envia mensagens pro content script de qualquer site.

const $ = sel => document.querySelector(sel);
const statusEl = $('#status');
const hostEl = $('#host');

// Versao real do manifesto (o texto do rodape era fixo e mentia).
try { $('#ver').textContent = 'v' + chrome.runtime.getManifest().version; } catch (_) {}

function setStatus(msg, cls) {
  statusEl.textContent = msg || '';
  statusEl.className = 'status' + (cls ? ' ' + cls : '');
}

function setButtonsBusy(busy) {
  document.querySelectorAll('button').forEach(b => b.disabled = busy);
}

// Traduz o erro cru do Chrome quando a aba tem um content script orfao (extension
// foi recarregada em chrome://extensions mas a aba nao foi atualizada depois).
function friendlyError(e) {
  const msg = (e && e.message) || String(e);
  if (/Could not establish connection|Receiving end does not exist/i.test(msg)) {
    return 'content script não injetou ainda — recarregue a aba (F5)';
  }
  return msg;
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

function imageMode() {
  const r = document.querySelector('input[name="imgmode"]:checked');
  return r ? r.value : 'embed';
}

async function dispatch(action) {
  setButtonsBusy(true);
  setStatus('processando...', '');
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab) throw new Error('sem aba ativa');
    const reply = await chrome.tabs.sendMessage(tab.id, { action, imageMode: imageMode() });
    if (!reply) throw new Error('sem resposta do content script (recarregue a aba)');
    if (!reply.ok) { setStatus(reply.msg || 'falhou', 'err'); return; }

    const d = reply.data;

    // Formatado (Word/Docs): escreve html + txt juntos no clipboard, a partir do
    // popup (que esta focado). Word/Docs colam o text/html; imagens embutidas vem junto.
    if (d && d.html != null) {
      const item = new ClipboardItem({
        'text/html': new Blob([d.html], { type: 'text/html' }),
        'text/plain': new Blob([d.txt || ''], { type: 'text/plain' })
      });
      await navigator.clipboard.write([item]);
    } else if (d && d.clipboardText != null && !d.wrote) {
      // Copia de texto puro/markdown: o content script nao escreve (pagina sem foco);
      // o popup focado faz a escrita.
      await navigator.clipboard.writeText(d.clipboardText);
    }

    const okMsg = (d && d.note) ? d.note + ' copiado' : (reply.msg || 'pronto');
    setStatus(okMsg, 'ok');
  } catch (e) {
    setStatus(friendlyError(e), 'err');
  } finally {
    setButtonsBusy(false);
    setTimeout(() => { if (!statusEl.classList.contains('err')) setStatus(''); }, 5000);
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
