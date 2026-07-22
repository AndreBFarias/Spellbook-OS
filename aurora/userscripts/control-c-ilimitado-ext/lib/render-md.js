// lib/render-md.js — modelo -> Markdown limpo (Obsidian / legivel por IA).
(function (root) {
  'use strict';
  const CCI = (root.CCI = root.CCI || {});

  const CLIP = '\u{1F4CE}';   // clipe de anexo
  const REPLY = '\u{21A9}';   // seta de resposta

  // opts.imageMode: 'embed' | 'download' | 'link'
  function renderMd(model, opts) {
    opts = opts || {};
    const msgs = [];
    for (const msg of model.messages) {
      if (msg.kind === 'system') { msgs.push('*' + esc(msg.text) + '*'); continue; }
      const lines = [];
      const head = header(msg);
      if (head) lines.push('### ' + head);
      const body = blocks(msg.blocks, opts, 0);
      if (body) lines.push(body);
      if (lines.length) msgs.push(lines.join('\n\n'));
    }
    // divisoria entre mensagens: separa claramente quem falou o que
    return msgs.join('\n\n---\n\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
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
      else if (b.type === 'attachment') out.push(attachment(b));
      else if (b.type === 'list') out.push(listMd(b));
    }
    return out.filter(Boolean).join('\n\n');
  }

  function attachment(b) {
    const name = esc(b.name || 'arquivo');
    if (b.href) return CLIP + ' [**' + name + '**](' + b.href + ')';
    return CLIP + ' **' + name + '**';
  }

  function quote(b, opts, depth) {
    const lines = [];
    const attrib = [b.author, b.timestamp].filter(Boolean).join(' · ');
    lines.push(REPLY + ' **Em resposta a' + (attrib ? ' ' + esc(attrib) : '') + '**');
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
      case 'mention': {
        const nm = '@' + inl.v.replace(/^@/, '');
        return inl.href ? '[' + nm + '](' + inl.href + ')' : nm;
      }
      default: return esc(inl.v);
    }
  }

  // Escapa caracteres que ligariam markdown por engano (fora de code/link).
  function esc(s) {
    return String(s == null ? '' : s).replace(/([\\`*_{}\[\]#|])/g, '\\$1');
  }

  CCI.renderMd = renderMd;
})(self);
