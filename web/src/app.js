// 렌더된 문서 안에서 도는 진입점. Swift와의 브릿지는 설계 문서 §4.5.
import { collectStats } from './postprocess.js';
import { ensureEmoji, highlightCode, renderMath, renderMermaid } from './loaders.js';
import { morphArticle, prepareArticle, restoreAnchor, viewportAnchor } from './reload.js';
import { Finder } from './find.js';

const bridge = window.webkit?.messageHandlers?.cmarks;
const post = (message) => {
  try {
    bridge?.postMessage(message);
  } catch {
    // 브라우저에서 직접 열었을 때는 브릿지가 없다.
  }
};

const config = (() => {
  try {
    return JSON.parse(document.documentElement.dataset.config || '{}');
  } catch {
    return {};
  }
})();

const root = document.getElementById('doc');
const finder = new Finder(root);
const SHORTCODE_PRESENT = /:[a-z0-9_+-]+:/i;

async function emojiTableFor(article) {
  if (config.emoji === false || !SHORTCODE_PRESENT.test(article.textContent)) return null;
  return ensureEmoji();
}

async function enhance(reason) {
  const t0 = performance.now();
  const jobs = [highlightCode(root, { enabled: config.highlight !== false })];
  if (config.math !== false) jobs.push(renderMath(root).catch((e) => post({ type: 'error', where: 'math', message: String(e) })));
  if (config.mermaid !== false) jobs.push(renderMermaid(root).catch((e) => post({ type: 'error', where: 'mermaid', message: String(e) })));
  await Promise.all(jobs);
  post({ type: 'enhanced', reason, ms: performance.now() - t0 });
}

/**
 * ⌘클릭(새 탭)·⌥클릭(분할) 링크는 WebKit이 새 창/다운로드로 처리하려 하므로 여기서 가로채 Swift에 넘긴다.
 * 일반 클릭은 그대로 두어 내비게이션 정책이 처리한다.
 */
root.addEventListener('click', (event) => {
  const anchor = event.target.closest('a[href]');
  if (!anchor || !(event.metaKey || event.altKey)) return;
  if (anchor.getAttribute('href')?.startsWith('#')) return;
  event.preventDefault();
  event.stopPropagation();
  post({ type: 'link', href: anchor.href, newTab: event.metaKey && !event.altKey, newSplit: event.altKey });
}, true);

/** 대용량 문서 배너의 "전체 표시" 버튼. CSP 때문에 인라인 핸들러를 쓸 수 없어 여기서 붙인다. */
function wireBanner() {
  root.querySelector('#cmarks-load-full')?.addEventListener('click', () => post({ type: 'loadFull' }), { once: true });
}

async function initialLoad() {
  const t0 = performance.now();
  wireBanner();
  const outline = prepareArticle(root, { emoji: await emojiTableFor(root) });
  post({ type: 'outline', items: outline });
  post({ type: 'ready', reason: 'load', ms: performance.now() - t0, ...collectStats(root) });
  scrollToFragment();
  await enhance('load');
}

/** 파일이 바뀌었을 때. 새 본문을 처리해 제자리 패치하고 스크롤 기준점을 유지한다. */
async function morph(html) {
  const t0 = performance.now();
  const anchor = viewportAnchor(root);
  const next = document.createElement('article');
  next.className = root.className;
  next.innerHTML = html;
  const outline = prepareArticle(next, { emoji: await emojiTableFor(next) });
  const changed = morphArticle(root, next);
  wireBanner();
  post({ type: 'outline', items: outline });
  post({ type: 'ready', reason: 'reload', ms: performance.now() - t0, changedBlocks: changed.length, ...collectStats(root) });
  await enhance('reload');
  restoreAnchor(root, anchor);
  if (finder.query) finder.search(finder.query, finder.options);
  return { changedBlocks: changed.length };
}

function scrollToFragment() {
  const id = decodeURIComponent(location.hash.slice(1));
  if (!id) return;
  document.getElementById(id)?.scrollIntoView({ block: 'start' });
}

function scrollInfo() {
  const max = Math.max(1, document.documentElement.scrollHeight - innerHeight);
  return { y: scrollY, ratio: Math.min(1, scrollY / max), heading: activeHeadingID() };
}

/** 뷰포트 상단(8px 여유) 바로 위 또는 걸친 마지막 헤딩. 아웃라인 하이라이트 동기화에 쓴다. */
function activeHeadingID() {
  let active = null;
  for (const heading of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    if (heading.getBoundingClientRect().top <= 8) active = heading.id;
    else break;
  }
  return active;
}

// Swift가 프로그램으로 스크롤한 직후의 scroll 이벤트는 사용자 스크롤로 보고하지 않는다.
let suppressScrollUntil = 0;

window.cmarks = {
  config,
  post,
  morph,
  scrollTo({ y }) {
    suppressScrollUntil = performance.now() + 400;
    window.scrollTo(0, y);
  },
  scrollToAnchor(id) {
    suppressScrollUntil = performance.now() + 400;
    document.getElementById(id)?.scrollIntoView({ block: 'start' });
  },
  getScroll: scrollInfo,
  /** 설정 변경 즉시 반영. 본문 폭은 다시 렌더하지 않고 스타일만 바꾼다. */
  setConfig(next) {
    Object.assign(config, next);
    if ('contentMaxWidth' in next) {
      root.style.maxWidth = next.contentMaxWidth ? `${next.contentMaxWidth}px` : 'none';
    }
  },
  find: {
    search: (query, options) => finder.search(query, options),
    next: () => finder.next(),
    prev: () => finder.prev(),
    goTo: (index) => finder.goTo(index),
    clear: () => finder.clear(),
  },
};

let scrollTimer = 0;
addEventListener('scroll', () => {
  if (performance.now() < suppressScrollUntil) return;
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(() => post({ type: 'scroll', ...scrollInfo() }), 150);
}, { passive: true });

matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
  if (config.mermaid !== false) renderMermaid(root, { rerender: true }).catch(() => {});
});

initialLoad();
