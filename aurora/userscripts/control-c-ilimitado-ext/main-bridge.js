// Bridge no MAIN world — escuta postMessage do content script e executa html2pdf.
// Existe porque html2pdf (e jsPDF, html2canvas) carregam globals em window, e o
// content script roda em isolated world (sem acesso aos globals da pagina).

(function () {
  if (window.__cciExportBridgeLoaded) return;
  window.__cciExportBridgeLoaded = true;

  // Trusted Types policy: Chrome 95+ em sites com strict CSP (Teams, GMail,
  // claude.ai mais novo) bloqueia DOMParser.parseFromString sem TrustedHTML.
  // Cria uma policy unica desta extensao (silencia "Refused to create policy"
  // em sites que ja tem CSP trusted-types definido).
  let __ttPolicy = null;
  try {
    if (window.trustedTypes && window.trustedTypes.createPolicy) {
      __ttPolicy = window.trustedTypes.createPolicy('ctrl-c-ilimitado-bridge', {
        createHTML: (s) => s,
      });
    }
  } catch (_) { /* outra policy ja existe ou site bloqueia; vamos no fallback */ }

  // DOMParser nao executa scripts; e a forma segura de transformar string HTML em nodes.
  function htmlToFragment(htmlString) {
    const input = __ttPolicy ? __ttPolicy.createHTML(htmlString) : htmlString;
    try {
      const doc = new DOMParser().parseFromString(input, 'text/html');
      const frag = document.createDocumentFragment();
      while (doc.body.firstChild) frag.appendChild(doc.body.firstChild);
      return frag;
    } catch (e) {
      // Fallback ultimo recurso: texto cru
      const frag = document.createDocumentFragment();
      const pre = document.createElement('pre');
      pre.style.cssText = 'white-space:pre-wrap;font:13px/1.5 ui-monospace,monospace;';
      pre.textContent = String(htmlString);
      frag.appendChild(pre);
      return frag;
    }
  }

  window.addEventListener('message', async (e) => {
    if (e.source !== window || !e.data || e.data.__cciExport !== 'pdf-request') return;
    const { reqId, kind, html, opts, snapshotSelector } = e.data;

    const reply = (data) => window.postMessage(Object.assign({ __cciExport: 'pdf-result', reqId }, data), '*');

    try {
      if (typeof window.html2pdf !== 'function') {
        throw new Error('html2pdf nao carregou ainda');
      }

      let source;
      let wrap = null;

      if (kind === 'snapshot' && snapshotSelector) {
        const node = document.querySelector(snapshotSelector);
        if (!node) throw new Error('elemento para snapshot nao encontrado');
        source = node;
      } else {
        wrap = document.createElement('div');
        wrap.style.cssText = 'position:absolute;left:-99999px;top:0;width:794px;padding:24px;background:#fff;color:#000;font:14px/1.55 system-ui,sans-serif;';
        if (kind === 'html') {
          wrap.appendChild(htmlToFragment(html));
        } else {
          const pre = document.createElement('pre');
          pre.style.cssText = 'white-space:pre-wrap;font:13px/1.5 ui-monospace,monospace;margin:0;';
          pre.textContent = html;
          wrap.appendChild(pre);
        }
        document.body.appendChild(wrap);
        source = wrap;
      }

      const blob = await window.html2pdf().set(opts || {
        margin: 10,
        filename: 'ctrl-c-ilimitado-export.pdf',
        image: { type: 'jpeg', quality: 0.95 },
        html2canvas: { scale: 2, useCORS: true, logging: false, backgroundColor: '#ffffff' },
        jsPDF: { unit: 'mm', format: 'a4', orientation: 'portrait' }
      }).from(source).outputPdf('blob');

      if (wrap && wrap.parentNode) wrap.parentNode.removeChild(wrap);

      const url = URL.createObjectURL(blob);
      reply({ ok: true, url, size: blob.size });
    } catch (err) {
      reply({ ok: false, error: err.message });
    }
  });

  window.postMessage({ __cciExport: 'bridge-ready' }, '*');
})();
