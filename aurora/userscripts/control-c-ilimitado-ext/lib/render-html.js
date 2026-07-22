// lib/render-html.js — modelo -> HTML rico e limpo (clipboard text/html).
// Sempre gera STRING (nunca injeta no DOM do Teams) -> imune a Trusted Types.
// Colado no Word/Docs vem formatado; imagens embutidas (data-URI) aparecem.
(function (root) {
  'use strict';
  const CCI = (root.CCI = root.CCI || {});

  function renderHtml(model, opts) {
    opts = opts || {};
    const parts = ['<div style="font-family:Segoe UI,system-ui,sans-serif;font-size:14px;line-height:1.5;color:#111;">'];
    for (const msg of model.messages) {
      if (msg.kind === 'system') {
        parts.push('<p style="color:#666;font-style:italic;margin:6px 0;">' + esc(msg.text) + '</p>');
        continue;
      }
      const head = header(msg);
      if (head) parts.push('<p style="margin:14px 0 2px;"><strong>' + head + '</strong></p>');
      parts.push(blocks(msg.blocks, opts));
    }
    parts.push('</div>');
    return parts.join('\n');
  }

  function header(msg) {
    const a = msg.author ? esc(msg.author) : '';
    const t = msg.timestamp ? esc(msg.timestamp) : '';
    if (a && t) return a + ' <span style="color:#888;font-weight:normal;">— ' + t + '</span>';
    return a || t;
  }

  function blocks(list, opts) {
    const out = [];
    for (const b of list) {
      if (b.type === 'p') out.push('<p style="margin:4px 0;">' + inlines(b.inlines) + '</p>');
      else if (b.type === 'quote') out.push(quote(b, opts));
      else if (b.type === 'code') out.push('<pre style="background:#f4f4f4;padding:8px;border-radius:4px;overflow:auto;"><code>' + esc(b.text) + '</code></pre>');
      else if (b.type === 'image') out.push(image(b, opts));
      else if (b.type === 'list') out.push(listHtml(b));
    }
    return out.join('\n');
  }

  function quote(b, opts) {
    const attrib = [b.author, b.timestamp].filter(Boolean).join(', ');
    let inner = '';
    if (attrib) inner += '<p style="margin:0 0 4px;color:#555;font-weight:600;">Citação — ' + esc(attrib) + '</p>';
    inner += blocks(b.blocks, opts);
    if (b.truncated) inner += '<p style="color:#999;font-style:italic;margin:4px 0 0;">[…truncado pelo Teams]</p>';
    return '<blockquote style="border-left:3px solid #ccc;margin:6px 0;padding:2px 0 2px 12px;color:#444;">' + inner + '</blockquote>';
  }

  function image(b, opts) {
    const alt = esc(b.alt || 'imagem');
    const mode = opts.imageMode || 'embed';
    const src = (mode === 'embed' && b.dataUri) ? b.dataUri
      : (mode === 'download' && b.file) ? b.file
        : (b.src || '');
    if (!src) return '<p style="color:#999;">[imagem indisponível: ' + alt + ']</p>';
    return '<p style="margin:6px 0;"><img alt="' + alt + '" src="' + src + '" style="max-width:100%;height:auto;"></p>';
  }

  function listHtml(b) {
    const tag = b.ordered ? 'ol' : 'ul';
    return '<' + tag + '>' + b.items.map(it => '<li>' + inlines(it) + '</li>').join('') + '</' + tag + '>';
  }

  function inlines(list) {
    return (list || []).map(inl => {
      switch (inl.t) {
        case 'bold': return '<strong>' + esc(inl.v) + '</strong>';
        case 'italic': return '<em>' + esc(inl.v) + '</em>';
        case 'code': return '<code style="background:#f4f4f4;padding:1px 4px;border-radius:3px;">' + esc(inl.v) + '</code>';
        case 'link': return '<a href="' + esc(inl.href) + '">' + esc(inl.v) + '</a>';
        case 'mention': return '<strong style="color:#4b53bc;">@' + esc(inl.v.replace(/^@/, '')) + '</strong>';
        default: return esc(inl.v);
      }
    }).join('');
  }

  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  CCI.renderHtml = renderHtml;
})(self);
