// 라이브 리로드(PLAN.md §4.7). 새 HTML을 처리한 뒤 morphdom으로 제자리 패치한다.
// 최상위 블록마다 "처리했지만 아직 하이라이팅/수식/다이어그램은 안 한" 상태의 지문을 남겨,
// 지문이 같은 블록은 통째로 건너뛰고 렌더 결과를 보존한다.
import morphdom from 'morphdom';
import { addHeadingAnchors, convertSpecialBlocks, markTaskLists, replaceEmoji, transformAlerts } from './postprocess.js';

export function fnv1a(text) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i += 1) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash.toString(16);
}

/**
 * 동기 후처리 + 특수 블록 변환 + 최상위 블록 지문.
 * 라이브 루트와 새 DOM 양쪽에 같은 순서로 적용해야 지문을 비교할 수 있다. 아웃라인을 돌려준다.
 */
export function prepareArticle(article, { emoji = null } = {}) {
  const outline = addHeadingAnchors(article);
  transformAlerts(article);
  markTaskLists(article);
  if (emoji) replaceEmoji(article, emoji);
  convertSpecialBlocks(article);
  for (const child of article.children) child.dataset.cmarksSrc = fnv1a(child.outerHTML);
  return outline;
}

/** next의 내용을 root에 제자리 반영하고, 바뀌거나 추가된 최상위 블록을 돌려준다. */
export function morphArticle(root, next) {
  const changed = new Set();
  morphdom(root, next, {
    childrenOnly: true,
    onBeforeElUpdated(from, to) {
      if (from.parentNode === root) {
        if (from.dataset.cmarksSrc && from.dataset.cmarksSrc === to.dataset.cmarksSrc) return false;
        changed.add(from);
      }
      return true;
    },
    onNodeAdded(node) {
      if (node.parentNode === root && node.nodeType === 1) changed.add(node);
      return node;
    },
  });
  return [...changed];
}

/** 뷰포트 상단에 걸친 헤딩(없으면 최상위 블록)을 기억한다. morph 뒤 같은 자리에 맞춰 스크롤을 되돌린다. */
export function viewportAnchor(root) {
  for (const heading of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
    const rect = heading.getBoundingClientRect();
    if (rect.bottom > 0) return { id: heading.id, top: rect.top };
  }
  for (const block of root.children) {
    const rect = block.getBoundingClientRect();
    if (rect.bottom > 0) return { src: block.dataset.cmarksSrc, top: rect.top };
  }
  return null;
}

export function restoreAnchor(root, anchor, scrollBy = window.scrollBy.bind(window)) {
  if (!anchor) return false;
  let el = null;
  if (anchor.id) el = root.ownerDocument.getElementById(anchor.id);
  else if (anchor.src) el = [...root.children].find((b) => b.dataset.cmarksSrc === anchor.src) ?? null;
  if (!el) return false;
  const delta = el.getBoundingClientRect().top - anchor.top;
  if (Math.abs(delta) > 1) scrollBy(0, delta);
  return true;
}
