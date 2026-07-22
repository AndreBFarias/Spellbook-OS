// lib/render-md.js — modelo -> Markdown limpo (Obsidian / legivel por IA).
(function (root) {
  'use strict';
  const CCI = (root.CCI = root.CCI || {});

  // opts.imageMode: 'embed' | 'download' | 'link'
  function renderMd(model, opts) {
    opts = opts || {};
    const parts = [];
    for (const msg of model.messages) {
      if (msg.kind === 'system') { parts.push('*' + esc(msg.text) + '*'); continue; }
      const head = header(msg);
      if (head) parts.push('### ' + head);
      const body = blocks(msg.blocks, opts, 0);
      if (body) parts.push(body);
    }
    return parts.join('\n\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
  }

  function header(msg) {
    const a = msg.author || '';
    const t = msg.timestamp || '';
    if (a && t) return esc(a) + ' — ' + esc(t);
    return esc(a || t);
  }

  function blocks(list, opts, depth) {
    const out = [];
    for (const b of list) {
      if (b.type === 'p') out.push(inlines(b.inlines));
      else if (b.type === 'quote') out.push(quote(b, opts, depth));
      else if (b.type === 'code') out.push('```' + (b.lang || '') + '\n' + b.text + '\n```');
      else if (b.type === 'image') out.push(image(b, opts));
      else if (b.type === 'list') out.push(listMd(b));
    }
    return out.filter(Boolean).join('\n\n');
  }

  function quote(b, opts, depth) {
    const lines = [];
    const attrib = [b.author, b.timestamp].filter(Boolean).join(', ');
    lines.push('**Citação' + (attrib ? ' — ' + esc(attrib) : '') + '**');
    const inner = blocks(b.blocks, opts, depth + 1);
    if (inner) lines.push(inner);
    let text = lines.join('\n\n');
    if (b.truncated) text += '\n\n[…truncado pelo Teams]';
    // prefixa cada linha com "> "
    return text.split('\n').map(l => '> ' + l).join('\n');
  }

  function image(b, opts) {
    const alt = esc(b.alt || 'imagem');
    const mode = opts.imageMode || 'embed';
    if (mode === 'embed' && b.dataUri) return '![' + alt + '](' + b.dataUri + ')';
    if (mode === 'download' && b.file) return '![' + alt + '](' + b.file + ')';
    // link (ou fallback quando embed/download falharam)
    return '![' + alt + '](' + (b.src || '') + ')';
  }

  function listMd(b) {
    return b.items.map((it, i) => (b.ordered ? (i + 1) + '. ' : '- ') + inlines(it)).join('\n');
  }

  function inlines(list) {
    return (list || []).map(one).join('');
  }

  function one(inl) {
    switch (inl.t) {
      case 'bold': return '**' + esc(inl.v) + '**';
      case 'italic': return '*' + esc(inl.v) + '*';
      case 'code': return '`' + inl.v.replace(/`/g, '​`') + '`';
      case 'link': return '[' + esc(inl.v) + '](' + inl.href + ')';
      case 'mention': return '@' + inl.v.replace(/^@/, '');
      default: return esc(inl.v);
    }
  }

  // Escapa caracteres que ligariam markdown por engano (fora de code/link).
  function esc(s) {
    return String(s == null ? '' : s).replace(/([\\`*_{}\[\]#|])/g, '\\$1');
  }

  CCI.renderMd = renderMd;
})(self);
