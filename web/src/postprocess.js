// cmark-gfm이 만든 DOM을 GitHub 마크업에 맞춘다(PLAN.md §4.3 후처리 1~4).
// 모두 멱등이어야 한다: 라이브 리로드(morph) 후 같은 루트에 다시 실행된다.
import { Slugger } from './slugger.js';
import octicons from './generated/octicons.js';

const HEADINGS = 'h1, h2, h3, h4, h5, h6';

/** 헤딩에 GitHub 슬러그 id와 hover 앵커를 붙이고 아웃라인을 돌려준다. */
export function addHeadingAnchors(root) {
  root.querySelectorAll('a.anchor').forEach((a) => a.remove());
  const slugger = new Slugger();
  const outline = [];
  for (const heading of root.querySelectorAll(HEADINGS)) {
    const text = heading.textContent.trim();
    const id = slugger.slug(text);
    heading.id = id;
    const anchor = root.ownerDocument.createElement('a');
    anchor.className = 'anchor';
    anchor.setAttribute('aria-hidden', 'true');
    anchor.href = `#${id}`;
    const icon = root.ownerDocument.createElement('span');
    icon.className = 'octicon octicon-link';
    anchor.append(icon);
    heading.prepend(anchor);
    outline.push({ level: Number(heading.tagName[1]), text, id });
  }
  return outline;
}

const ALERTS = {
  NOTE: { title: 'Note', icon: 'info' },
  TIP: { title: 'Tip', icon: 'light-bulb' },
  IMPORTANT: { title: 'Important', icon: 'report' },
  WARNING: { title: 'Warning', icon: 'alert' },
  CAUTION: { title: 'Caution', icon: 'stop' },
};
const ALERT_MARKER = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\n|$)/;

/** `> [!NOTE]` 인용을 .markdown-alert로 바꾼다. 마커는 첫 단락 첫 줄에 단독으로 있어야 한다(GitHub 규칙). */
export function transformAlerts(root) {
  const doc = root.ownerDocument;
  for (const quote of root.querySelectorAll('blockquote')) {
    const first = quote.firstElementChild;
    if (!first || first.tagName !== 'P') continue;
    const textNode = first.firstChild;
    if (!textNode || textNode.nodeType !== 3) continue;
    const match = ALERT_MARKER.exec(textNode.nodeValue);
    if (!match) continue;

    const { title, icon } = ALERTS[match[1]];
    const alert = doc.createElement('div');
    alert.className = `markdown-alert markdown-alert-${match[1].toLowerCase()}`;
    alert.setAttribute('dir', 'auto');

    const titleEl = doc.createElement('p');
    titleEl.className = 'markdown-alert-title';
    titleEl.setAttribute('dir', 'auto');
    titleEl.innerHTML = `<svg class="octicon octicon-${icon} mr-2" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true">${octicons[icon] ?? ''}</svg>`;
    titleEl.append(doc.createTextNode(title));
    alert.append(titleEl);

    textNode.nodeValue = textNode.nodeValue.slice(match[0].length);
    if (!first.textContent.trim() && !first.querySelector('*')) first.remove();
    while (quote.firstChild) alert.append(quote.firstChild);
    quote.replaceWith(alert);
  }
}

/** cmark-gfm의 태스크 리스트 출력에 GitHub 클래스를 붙인다. */
export function markTaskLists(root) {
  for (const input of root.querySelectorAll('li > input[type="checkbox"]')) {
    const li = input.parentElement;
    if (li.firstElementChild !== input) continue;
    li.classList.add('task-list-item');
    input.classList.add('task-list-item-checkbox');
    li.parentElement?.classList.add('contains-task-list');
  }
}

const SHORTCODE = /:([a-z0-9_+-]+):/gi;
const SKIP_EMOJI_IN = new Set(['PRE', 'CODE', 'SCRIPT', 'STYLE', 'TEXTAREA', 'KBD']);

/** 텍스트 노드의 :shortcode: 를 이모지로. 코드 안은 건너뛴다. */
export function replaceEmoji(root, map) {
  if (!map) return 0;
  const doc = root.ownerDocument;
  const walker = doc.createTreeWalker(root, 4 /* SHOW_TEXT */, {
    acceptNode(node) {
      if (!node.nodeValue.includes(':')) return 2; // REJECT
      for (let el = node.parentElement; el && el !== root; el = el.parentElement) {
        if (SKIP_EMOJI_IN.has(el.tagName)) return 2;
      }
      return 1; // ACCEPT
    },
  });
  let replaced = 0;
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const node of nodes) {
    const next = node.nodeValue.replace(SHORTCODE, (whole, name) => {
      const emoji = map[name];
      if (!emoji) return whole;
      replaced += 1;
      return emoji;
    });
    if (next !== node.nodeValue) node.nodeValue = next;
  }
  return replaced;
}

/** ```mermaid / ```math 코드 블록을 렌더 전 자리 표시 div로 바꾼다. 렌더링(loaders.js)과 분리해 morph 지문 계산에 쓴다. */
export function convertSpecialBlocks(root) {
  const doc = root.ownerDocument;
  for (const code of root.querySelectorAll('pre > code.language-mermaid')) {
    const div = doc.createElement('div');
    div.className = 'mermaid';
    div.dataset.source = code.textContent;
    div.textContent = code.textContent;
    code.parentElement.replaceWith(div);
  }
  for (const code of root.querySelectorAll('pre > code.language-math')) {
    const div = doc.createElement('div');
    div.className = 'cmarks-math-block';
    div.dataset.source = code.textContent;
    div.textContent = code.textContent;
    code.parentElement.replaceWith(div);
  }
}

export function collectStats(root) {
  return {
    codeBlocks: root.querySelectorAll('pre > code').length,
    images: root.querySelectorAll('img').length,
    headings: root.querySelectorAll(HEADINGS).length,
  };
}
