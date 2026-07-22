// lib/render-txt.js — modelo -> texto puro organizado (sem simbolos markdown,
// mas diferenciando citacao/codigo/imagem).
(function (root) {
  'use strict';
  const CCI = (root.CCI = root.CCI || {});

  const CLIP = '\u{1F4CE}';
  const DIV = '─'.repeat(40);   // linha divisoria entre mensagens

  function renderTxt(model, opts) {
    opts = opts || {};
    const msgs = [];
    for (const msg of model.messages) {
      if (msg.kind === 'system') { msgs.push('— ' + msg.text + ' —'); continue; }
      const lines = [];
      const head = header(msg);
      if (head) lines.push(head);
      const body = blocks(msg.blocks, opts);
      if (body) lines.push(body);
      if (lines.length) msgs.push(lines.join('\n\n'));
    }
    return msgs.join('\n\n' + DIV + '\n\n').replace(/\n{3,}/g, '\n\n').trim() + '\n';
  }

  function header(msg) {
    const a = msg.author || '';
    const t = msg.timestamp || '';
    if (a && t) return a + '  (' + t + ')';
    return a || t;
  }

  function blocks(list, opts) {
    const out = [];
    for (const b of list) {
      if (b.type === 'p') out.push(inlines(b.inlines));
      else if (b.type === 'quote') out.push(quote(b, opts));
      else if (b.type === 'code') out.push(indent(b.text, '    '));
      else if (b.type === 'image') out.push('[imagem: ' + (b.alt || (b.src || '').slice(0, 60) || 'sem legenda') + ']');
      else if (b.type === 'attachment') out.push(CLIP + ' ' + (b.name || 'arquivo') + (b.href ? ' (' + b.href + ')' : ''));
      else if (b.type === 'list') out.push(b.items.map(it => '  - ' + inlines(it)).join('\n'));
    }
    return out.filter(Boolean).join('\n\n');
  }

  function quote(b, opts) {
    const attrib = [b.author, b.timestamp].filter(Boolean).join(' · ');
    const lines = [];
    if (attrib) lines.push('Em resposta a ' + attrib + ':');
    const inner = blocks(b.blocks, opts);
    if (inner) lines.push(inner);
    if (b.truncated) lines.push('[…truncado pelo Teams]');
    return lines.join('\n').split('\n').map(l => '> ' + l).join('\n');
  }

  function indent(s, pad) {
    return String(s || '').split('\n').map(l => pad + l).join('\n');
  }

  function inlines(list) {
    return (list || []).map(inl => {
      if (inl.t === 'mention') return '@' + inl.v.replace(/^@/, '') + (inl.href ? ' (' + inl.href + ')' : '');
      if (inl.t === 'link') return inl.v + (inl.href && inl.href !== inl.v ? ' (' + inl.href + ')' : '');
      return inl.v;
    }).join('');
  }

  CCI.renderTxt = renderTxt;
})(self);
