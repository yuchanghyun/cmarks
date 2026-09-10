// 문서 안 찾기(⌘F). CSS Custom Highlight API로 DOM을 바꾸지 않고 표시한다.
const HIGHLIGHT_ALL = 'cmarks-find';
const HIGHLIGHT_CURRENT = 'cmarks-find-current';
const SKIP = new Set(['SCRIPT', 'STYLE', 'NOSCRIPT', 'TEXTAREA']);

/** 텍스트 노드를 이어 붙인 문자열과 각 노드의 구간. 닫힌 <details>의 본문(summary 제외)은 건너뛴다. */
export function collectText(root) {
  const doc = root.ownerDocument;
  const walker = doc.createTreeWalker(root, 4 /* SHOW_TEXT */, {
    acceptNode(node) {
      for (let el = node.parentElement; el && el !== root; el = el.parentElement) {
        if (SKIP.has(el.tagName)) return 2;
        if (el.tagName === 'DETAILS' && !el.open && !node.parentElement.closest('summary')) return 2;
      }
      return 1;
    },
  });
  const nodes = [];
  let text = '';
  while (walker.nextNode()) {
    const node = walker.currentNode;
    nodes.push({ node, start: text.length, end: text.length + node.nodeValue.length });
    text += node.nodeValue;
  }
  return { text, nodes };
}

function locate(nodes, offset) {
  let lo = 0;
  let hi = nodes.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (nodes[mid].end <= offset) lo = mid + 1;
    else hi = mid;
  }
  return nodes[lo];
}

export function makeRange(doc, nodes, start, end) {
  const from = locate(nodes, start);
  const to = locate(nodes, Math.max(start, end - 1));
  const range = doc.createRange();
  range.setStart(from.node, start - from.start);
  range.setEnd(to.node, end - to.start);
  return range;
}

export class Finder {
  constructor(root) {
    this.root = root;
    this.ranges = [];
    this.index = -1;
    this.query = '';
    this.options = {};
    // Highlight 객체를 한 번 등록해 두고 Range만 갈아 끼운다. 등록/삭제를 반복하면 WebKit이 이전 표시를 남기는 경우가 있다.
    const highlights = globalThis.CSS?.highlights;
    if (highlights && typeof globalThis.Highlight === 'function') {
      this.all = new Highlight();
      this.current = new Highlight();
      this.current.priority = 1;
      highlights.set(HIGHLIGHT_ALL, this.all);
      highlights.set(HIGHLIGHT_CURRENT, this.current);
    }
  }

  search(query, options = {}) {
    this.clear(true);
    this.query = query;
    this.options = options;
    if (!query) return this.result();

    const { text, nodes } = collectText(this.root);
    let haystack = options.caseSensitive ? text : text.toLowerCase();
    let needle = options.caseSensitive ? query : query.toLowerCase();
    if (haystack.length !== text.length) {
      // 소문자화로 길이가 달라지는 문자(İ 등)가 있으면 위치가 어긋나므로 대소문자 구분 검색으로 물러난다.
      haystack = text;
      needle = query;
    }
    const doc = this.root.ownerDocument;
    let from = 0;
    while (needle && (from = haystack.indexOf(needle, from)) !== -1) {
      this.ranges.push(makeRange(doc, nodes, from, from + needle.length));
      from += needle.length;
    }
    this.index = this.ranges.length ? this.firstVisibleIndex() : -1;
    this.apply();
    this.reveal();
    return this.result();
  }

  next() {
    return this.step(1);
  }

  prev() {
    return this.step(-1);
  }

  step(delta) {
    if (!this.ranges.length) return this.result();
    this.index = (this.index + delta + this.ranges.length) % this.ranges.length;
    this.apply();
    this.reveal();
    return this.result();
  }

  clear(reset = true) {
    this.all?.clear();
    this.current?.clear();
    if (reset) {
      this.ranges = [];
      this.index = -1;
      this.query = '';
    }
  }

  result() {
    return { count: this.ranges.length, index: this.index };
  }

  firstVisibleIndex() {
    // jsdom의 Range에는 getBoundingClientRect가 없다.
    if (typeof this.ranges[0]?.getBoundingClientRect !== 'function') return 0;
    const i = this.ranges.findIndex((r) => r.getBoundingClientRect().bottom >= 0);
    return i === -1 ? 0 : i;
  }

  apply() {
    if (!this.all) return;
    this.all.clear();
    for (const range of this.ranges) this.all.add(range);
    this.current.clear();
    if (this.index >= 0) this.current.add(this.ranges[this.index]);
  }

  reveal() {
    const range = this.ranges[this.index];
    if (!range || typeof range.getBoundingClientRect !== 'function' || typeof globalThis.innerHeight !== 'number') return;
    const rect = range.getBoundingClientRect();
    if (rect.top < 0 || rect.bottom > innerHeight) {
      scrollBy({ top: rect.top - innerHeight / 3, behavior: 'instant' });
    }
  }
}
