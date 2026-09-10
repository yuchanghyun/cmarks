// 무거운 라이브러리(하이라이터 언어, KaTeX, Mermaid, 이모지 표)는 문서에 필요할 때만 앱 번들에서 불러온다.
const ASSETS = 'cmarks-local://assets/';
const pending = new Map();

export function loadScript(rel) {
  if (pending.has(rel)) return pending.get(rel);
  const promise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = ASSETS + rel;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`load failed: ${rel}`));
    document.head.append(script);
  });
  pending.set(rel, promise);
  return promise;
}

export function loadStyle(rel) {
  const href = ASSETS + rel;
  if (document.querySelector(`link[href="${href}"]`)) return;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  document.head.append(link);
}

const SPECIAL_LANGUAGES = new Set(['mermaid', 'math']);

/** GitHub처럼 언어가 명시된 블록만 칠한다. 모르는 언어는 그대로 둔다. 블록이 많으면 화면에 들어올 때 칠한다. */
export async function highlightCode(root, { enabled = true } = {}) {
  const hljs = window.hljs;
  if (!hljs || !enabled) return 0;
  const blocks = [...root.querySelectorAll('pre > code[class*="language-"]')].filter((code) => !code.classList.contains('hljs'));
  const languageOf = (code) => [...code.classList].find((c) => c.startsWith('language-'))?.slice(9).toLowerCase();

  async function highlight(code) {
    const lang = languageOf(code);
    if (!lang || SPECIAL_LANGUAGES.has(lang)) return;
    if (!hljs.getLanguage(lang)) {
      try {
        await loadScript(`vendor/hljs/languages/${lang}.min.js`);
      } catch {
        return;
      }
    }
    if (!hljs.getLanguage(lang)) return;
    hljs.highlightElement(code);
  }

  if (blocks.length <= 20) {
    for (const code of blocks) await highlight(code);
    return blocks.length;
  }
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      observer.unobserve(entry.target);
      highlight(entry.target);
    }
  }, { rootMargin: '400px 0px' });
  for (const code of blocks) observer.observe(code);
  return blocks.length;
}

const INLINE_MATH = /\$\$[\s\S]+?\$\$|\$[^\s$][^$\n]*?\$/;

/** $…$, $$…$$, 그리고 convertSpecialBlocks가 만든 .cmarks-math-block 을 KaTeX로. 수식이 없으면 아무것도 불러오지 않는다. */
export async function renderMath(root) {
  const blocks = [...root.querySelectorAll('.cmarks-math-block:not([data-rendered])')];
  if (blocks.length === 0 && !INLINE_MATH.test(root.textContent)) return false;

  loadStyle('vendor/katex/katex.min.css');
  await loadScript('vendor/katex/katex.min.js');
  await loadScript('vendor/katex/auto-render.min.js');

  for (const div of blocks) {
    window.katex.render(div.dataset.source ?? div.textContent, div, { displayMode: true, throwOnError: false });
    div.dataset.rendered = '1';
  }
  window.renderMathInElement(root, {
    delimiters: [
      { left: '$$', right: '$$', display: true },
      { left: '$', right: '$', display: false },
    ],
    ignoredTags: ['script', 'noscript', 'style', 'textarea', 'pre', 'code', 'a', 'kbd'],
    ignoredClasses: ['cmarks-math-block', 'cmarks-frontmatter', 'katex'],
    throwOnError: false,
  });
  return true;
}

/** convertSpecialBlocks가 만든 .mermaid 중 아직 안 그린 것만 그린다. rerender=true면 전부 다시(테마 전환). */
export async function renderMermaid(root, { rerender = false } = {}) {
  const nodes = [...root.querySelectorAll(rerender ? '.mermaid' : '.mermaid:not([data-processed])')];
  if (nodes.length === 0) return false;

  await loadScript('vendor/mermaid/mermaid.min.js');
  const dark = matchMedia('(prefers-color-scheme: dark)').matches;
  window.mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'strict' });
  for (const node of nodes) {
    node.removeAttribute('data-processed');
    node.textContent = node.dataset.source ?? node.textContent;
  }
  await window.mermaid.run({ nodes, suppressErrors: true });
  return true;
}

export async function ensureEmoji() {
  if (!window.cmarksEmoji) await loadScript('vendor/emoji.js');
  return window.cmarksEmoji ?? {};
}
