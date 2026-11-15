// Safe Markdown parser & renderer for CHANGELOG.md (adapted for shadowspore.com).
// All text is HTML-escaped; only explicit structural tags are emitted.

const esc = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');

export function resolveChangelogImg(src) {
  const clean = String(src || '').trim().replace(/^docs\/img\//i, './img/changelog/');
  if (clean.startsWith('./') || clean.startsWith('img/')) return clean.startsWith('./') ? clean : `./${clean}`;
  return `./img/changelog/${clean.replace(/^\/+/, '')}`;
}

/** Splits CHANGELOG.md into versions: [{ id, index, version, date, title, teaser, image, imageAlt, body }]. */
export function splitVersions(md) {
  const lines = String(md || '').replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let cur = null;
  for (const line of lines) {
    const m = /^## \[([^\]]+)\]\s*[–-]?\s*(.*)$/.exec(line);
    if (m) {
      cur = { version: m[1].trim(), date: m[2].trim(), lines: [] };
      out.push(cur);
      continue;
    }
    if (cur) cur.lines.push(line);
  }
  return out.map((v, i) => {
    const body = v.lines.join('\n').replace(/\n---\s*$/g, '').trim();
    const titleLine = v.lines.find((l) => /^###\s+/.test(l)) || '';
    const images = [...body.matchAll(/!\[([^\]]*)\]\(([^)\s]+)\)/g)];
    const img = images.find((m) => !/sheet|icons|cards|poses|before_after|frames|_qa/i.test(m[2])) || images[0];
    const quote = v.lines.find((l) => /^>\s*\*[^*]/.test(l)) || '';
    return {
      id: `v${i}`,
      index: i,
      version: v.version,
      date: v.date,
      title: stripInline(titleLine.replace(/^###\s+/, '')),
      teaser: stripInline(quote.replace(/^>\s*/, '')).slice(0, 220),
      image: img ? resolveChangelogImg(img[2]) : '',
      imageAlt: img ? img[1] : '',
      body,
    };
  });
}

export function stripInline(s) {
  return String(s || '')
    .replace(/!\[[^\]]*\]\([^)]*\)/g, '')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/[*_`]/g, '')
    .replace(/<[^>]+>/g, '')
    .trim();
}

/** Splits a leading emoji off a heading: "🏰 Hallgrat" -> ["🏰", "Hallgrat"]. */
export function splitEmoji(text) {
  const m = /^(\p{Extended_Pictographic}[\u{FE0F}\u{200D}\p{Extended_Pictographic}]*)\s*(.*)$/u.exec(String(text || ''));
  return m ? [m[1], m[2]] : ['', String(text || '')];
}

const TAGS = {
  '🟣 NEU': 'new',
  '🔵 REWORK': 'rework',
  '🟢 BUFF': 'teal',
  '🔴 NERF': 'danger',
  '🟡 FIX': 'gold',
  '🟠 FIX': 'gold',
  '⚪ TECHNIK': 'rework',
};

function tagify(html) {
  let out = html;
  for (const [label, cls] of Object.entries(TAGS)) {
    const word = label.split(' ')[1];
    out = out.replaceAll(`<code>${label}</code>`, `<span class="tag tag-${cls}">${word}</span>`);
    out = out.replaceAll(label, `<span class="tag tag-${cls}">${word}</span>`);
  }
  return out.replace(/[🟣🔵🟢🔴🟡🟠⚪]\s*(?=<span class="tag)/gu, '');
}

function inline(text) {
  const codes = [];
  let s = esc(text).replace(/`([^`]+)`/g, (_, c) => {
    codes.push(c);
    return `\u0000${codes.length - 1}\u0000`;
  });
  s = s
    .replace(/!\[([^\]]*)\]\(([^)\s]+)\)/g, (_, alt, src) => {
      const rSrc = esc(resolveChangelogImg(src));
      const rAlt = esc(alt);
      return `<button type="button" class="md-inline-shot" data-shot="${rSrc}" data-caption="${rAlt}"><img src="${rSrc}" loading="lazy" alt="${rAlt}"></button>`;
    })
    .replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, (_, label, href) => {
      const safeHref = /^https?:\/\//i.test(href) ? esc(href) : '#chronicle';
      return `<a href="${safeHref}" target="_blank" rel="noreferrer noopener">${label}</a>`;
    })
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/(^|[^*\w])\*([^*\s][^*]*?)\*(?!\*)/g, '$1<em>$2</em>')
    .replace(/&lt;(\/?)(b|i|br)\s*\/?&gt;/g, (_, slash, tag) =>
      tag === 'br' ? '<br>' : `<${slash}${tag === 'b' ? 'strong' : 'em'}>`
    );
  s = s.replace(/\u0000(\d+)\u0000/g, (_, i) => `<code>${codes[Number(i)]}</code>`);
  return tagify(s);
}

function renderTable(rows) {
  const cells = (r) => r.replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
  const head = cells(rows[0]);
  const body = rows.slice(2).map(cells);
  return (
    `<div class="md-table-wrap"><table class="md-table"><thead><tr>${head.map((h) => `<th>${inline(h)}</th>`).join('')}</tr></thead>` +
    `<tbody>${body.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join('')}</tr>`).join('')}</tbody></table></div>`
  );
}

function renderList(items) {
  let html = '';
  const stack = [];
  for (const it of items) {
    while (stack.length && stack[stack.length - 1].depth > it.depth) html += `</li></${stack.pop().tag}>`;
    const top = stack[stack.length - 1];
    if (!top || top.depth < it.depth) {
      const tag = it.ordered ? 'ol' : 'ul';
      stack.push({ depth: it.depth, tag });
      html += `<${tag} class="md-list md-list-nested">`;
    } else {
      html += '</li>';
    }
    html += `<li><div>${inline(it.text)}</div>`;
  }
  while (stack.length) html += `</li></${stack.pop().tag}>`;
  return html;
}

export function renderMarkdown(md) {
  const lines = String(md || '').replace(/\r\n/g, '\n').split('\n');
  let html = '';
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    const t = line.trim();
    if (!t) { i++; continue; }

    if (/^<details>/.test(t)) { html += '<details class="md-details">'; i++; continue; }
    if (/^<\/details>/.test(t)) { html += '</div></details>'; i++; continue; }
    const sum = /^<summary>(.*)<\/summary>$/.exec(t);
    if (sum) { html += `<summary>${inline(sum[1])}</summary><div class="md-details-body">`; i++; continue; }

    if (/^-{3,}$/.test(t)) { html += '<hr class="md-hr">'; i++; continue; }

    const h = /^(#{1,6})\s+(.*)$/.exec(t);
    if (h) {
      const level = Math.min(6, h[1].length + 1);
      const [emoji, rest] = splitEmoji(h[2]);
      html += `<h${level} class="md-h">${emoji ? `<span class="md-emoji">${emoji}</span>` : ''}<span>${inline(rest)}</span></h${level}>`;
      i++;
      continue;
    }

    const img = /^!\[([^\]]*)\]\(([^)\s]+)\)$/.exec(t);
    if (img) {
      const group = [];
      while (i < lines.length) {
        const m = /^!\[([^\]]*)\]\(([^)\s]+)\)$/.exec(lines[i].trim());
        if (!m) break;
        group.push(m);
        i++;
      }
      html += `<div class="md-gallery md-gallery-${Math.min(group.length, 3)}">${group
        .map((m) => {
          const rSrc = esc(resolveChangelogImg(m[2]));
          const rAlt = esc(m[1]);
          return `<figure class="md-figure"><button type="button" class="md-figure-btn stair" data-shot="${rSrc}" data-caption="${rAlt}"><img src="${rSrc}" loading="lazy" alt="${rAlt}"></button><figcaption>${rAlt}</figcaption></figure>`;
        })
        .join('')}</div>`;
      continue;
    }

    if (t.startsWith('>')) {
      const block = [];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        block.push(lines[i].trim().replace(/^>\s?/, ''));
        i++;
      }
      const callout = /^\[!(\w+)\]$/.exec(block[0] || '');
      if (callout) {
        const kind = callout[1].toLowerCase();
        const labels = { important: 'WICHTIG', tip: 'TIPP', warning: 'ACHTUNG', note: 'HINWEIS', caution: 'VORSICHT' };
        html += `<aside class="md-callout md-callout-${esc(kind)}"><div class="md-callout-label">${esc(labels[kind] || kind.toUpperCase())}</div>${renderMarkdown(block.slice(1).join('\n'))}</aside>`;
      } else {
        html += `<blockquote class="md-quote">${renderMarkdown(block.join('\n'))}</blockquote>`;
      }
      continue;
    }

    if (t.startsWith('|')) {
      const rows = [];
      while (i < lines.length && lines[i].trim().startsWith('|')) rows.push(lines[i++].trim());
      html += rows.length >= 2 ? renderTable(rows) : `<p>${inline(rows[0])}</p>`;
      continue;
    }

    if (/^\s*([*+-]|\d+\.)\s+/.test(line)) {
      const items = [];
      while (i < lines.length) {
        const m = /^(\s*)([*+-]|\d+\.)\s+(.*)$/.exec(lines[i]);
        if (m) {
          items.push({ depth: Math.floor(m[1].replace(/\t/g, '  ').length / 2), ordered: /\d/.test(m[2]), text: m[3] });
          i++;
        } else if (lines[i].trim() && /^\s{2,}\S/.test(lines[i]) && items.length) {
          items[items.length - 1].text += ' ' + lines[i].trim();
          i++;
        } else break;
      }
      html += renderList(items);
      continue;
    }

    const para = [];
    while (i < lines.length && lines[i].trim() && !/^(#|>|\||!\[|<|-{3,}|\s*([*+-]|\d+\.)\s)/.test(lines[i].trim())) {
      para.push(lines[i++].trim());
    }
    if (para.length) html += `<p>${inline(para.join(' '))}</p>`;
    else { html += `<p>${inline(t)}</p>`; i++; }
  }
  return html;
}
