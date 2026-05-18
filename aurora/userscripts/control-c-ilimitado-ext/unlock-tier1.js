// Tier 1 — Desbloqueio nao-invasivo aplicado em document_start em todos sites.
// Bloqueia handlers de copy/cut/paste/selectstart/contextmenu/dragstart instalados pelo site.
// Capture phase + stopImmediatePropagation = listeners do site nao recebem o evento.

(() => {
  'use strict';
  if (window.__ctrlCIlimitadoTier1) return;
  window.__ctrlCIlimitadoTier1 = true;

  const EVENTS = ['copy', 'cut', 'paste', 'selectstart', 'contextmenu', 'dragstart', 'beforecopy'];
  const stop = (e) => e.stopImmediatePropagation();

  for (const evt of EVENTS) {
    window.addEventListener(evt, stop, { capture: true, passive: true });
    document.addEventListener(evt, stop, { capture: true, passive: true });
  }

  // CSS: forca user-select: text em tudo, com selecao visivel
  const applyCSS = () => {
    if (document.getElementById('ctrl-c-ilimitado-css')) return;
    const s = document.createElement('style');
    s.id = 'ctrl-c-ilimitado-css';
    s.textContent = `
      *, *::before, *::after {
        user-select: text !important;
        -webkit-user-select: text !important;
        -moz-user-select: text !important;
        -ms-user-select: text !important;
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
})();
