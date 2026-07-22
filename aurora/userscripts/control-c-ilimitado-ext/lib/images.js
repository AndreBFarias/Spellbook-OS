// lib/images.js — classificacao e busca de imagens do Teams.
// Anexa em self.CCI. Sem dependencias.
(function (root) {
  'use strict';
  const CCI = (root.CCI = root.CCI || {});

  // Limite de bytes de imagem embutida (data-URI). Acima disso cai pra link,
  // pra nao estourar o clipboard/.md com um base64 gigante.
  const MAX_EMBED_BYTES = 5 * 1024 * 1024;

  // Classifica um <img> do Teams: avatar (foto de pessoa), emoji (reacao/emoji
  // inline) ou content (imagem de verdade que a pessoa colou no chat).
  function classify(img) {
    const cls = (typeof img.className === 'string' ? img.className : '') + ' ' +
      (img.getAttribute('class') || '');
    const alt = (img.getAttribute('alt') || '').trim();
    const w = img.naturalWidth || img.width || parseInt(img.getAttribute('width') || '0', 10);
    const h = img.naturalHeight || img.height || parseInt(img.getAttribute('height') || '0', 10);

    // Avatar: Fluent usa fui-Avatar; tambem fica dentro de containers de autor.
    if (/fui-Avatar|avatar/i.test(cls)) return 'avatar';
    if (img.closest && img.closest('[class*="Avatar" i], [class*="author" i]')) return 'avatar';

    // Emoji/reacao: alt curtinho que e so emoji, ou dentro de barra de reacao.
    if (isEmojiOnly(alt)) return 'emoji';
    if (img.closest && img.closest('[class*="reaction" i], [class*="Emoji" i]')) return 'emoji';

    // Icone pequeno (<= 28px) sem alt util: trata como emoji/decorativo.
    if (w && h && w <= 28 && h <= 28 && alt.length <= 2) return 'emoji';

    return 'content';
  }

  // alt e composto so por emoji/simbolos (sem letras/numeros latinos)?
  function isEmojiOnly(s) {
    if (!s) return false;
    if (/[a-zA-Z0-9]/.test(s)) return false;
    return /\p{Extended_Pictographic}/u.test(s);
  }

  // src -> data-URI (base64). Usa credenciais da pagina (cookies do Teams).
  // Retorna null se falhar ou passar do limite de tamanho.
  async function toDataUri(src) {
    try {
      const resp = await fetch(src, { credentials: 'include' });
      if (!resp.ok) return null;
      const blob = await resp.blob();
      if (blob.size > MAX_EMBED_BYTES) return null;
      return await blobToDataUri(blob);
    } catch (_) {
      return null;
    }
  }

  // src -> Blob (pra download). null se falhar.
  async function toBlob(src) {
    try {
      const resp = await fetch(src, { credentials: 'include' });
      if (!resp.ok) return null;
      return await resp.blob();
    } catch (_) {
      return null;
    }
  }

  function blobToDataUri(blob) {
    return new Promise((resolve, reject) => {
      const r = new FileReader();
      r.onload = () => resolve(r.result);
      r.onerror = () => reject(r.error);
      r.readAsDataURL(blob);
    });
  }

  // Dispara download de um Blob no navegador (contexto da pagina).
  function download(blob, filename) {
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = filename; a.style.display = 'none';
    document.body.appendChild(a); a.click();
    setTimeout(() => { a.remove(); URL.revokeObjectURL(url); }, 2000);
  }

  // Extensao de arquivo a partir do MIME do blob (fallback .png).
  function extFor(blob) {
    const m = (blob && blob.type) || '';
    if (/png/.test(m)) return 'png';
    if (/jpe?g/.test(m)) return 'jpg';
    if (/gif/.test(m)) return 'gif';
    if (/webp/.test(m)) return 'webp';
    if (/svg/.test(m)) return 'svg';
    return 'png';
  }

  CCI.images = { classify, isEmojiOnly, toDataUri, toBlob, download, extFor, MAX_EMBED_BYTES };
})(self);
