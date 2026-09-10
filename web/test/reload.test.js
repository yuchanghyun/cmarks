import { describe, expect, it } from 'vitest';
import { fnv1a, morphArticle, prepareArticle } from '../src/reload.js';

function article(html) {
  const el = document.createElement('article');
  el.className = 'markdown-body';
  el.innerHTML = html;
  return el;
}

describe('prepareArticle', () => {
  it('stamps top-level blocks with a fingerprint and converts special blocks', () => {
    const root = article('<h1>T</h1><p>a</p><pre><code class="language-mermaid">graph TD;A-->B</code></pre>');
    const outline = prepareArticle(root);
    expect(outline).toEqual([{ level: 1, text: 'T', id: 't' }]);
    expect([...root.children].every((c) => c.dataset.cmarksSrc)).toBe(true);
    const mermaid = root.querySelector('.mermaid');
    expect(mermaid).not.toBeNull();
    expect(mermaid.dataset.source).toBe('graph TD;A-->B');
  });

  it('produces identical fingerprints for identical source', () => {
    const a = article('<h2>Same</h2><p>text <em>x</em></p>');
    const b = article('<h2>Same</h2><p>text <em>x</em></p>');
    prepareArticle(a);
    prepareArticle(b);
    expect([...a.children].map((c) => c.dataset.cmarksSrc)).toEqual([...b.children].map((c) => c.dataset.cmarksSrc));
    expect(fnv1a('abc')).not.toBe(fnv1a('abd'));
  });
});

describe('morphArticle', () => {
  it('keeps enhanced DOM for unchanged blocks and updates changed ones', () => {
    const live = article('<h1>Title</h1><p>one</p><pre><code class="language-js">let x</code></pre>');
    prepareArticle(live);
    // 하이라이터가 손댄 것처럼 흔적을 남긴다
    const code = live.querySelector('code');
    code.classList.add('hljs');
    code.innerHTML = '<span class="hljs-keyword">let</span> x';

    const next = article('<h1>Title</h1><p>two</p><pre><code class="language-js">let x</code></pre>');
    prepareArticle(next);
    const changed = morphArticle(live, next);

    expect(live.querySelector('p').textContent).toBe('two');
    expect(live.querySelector('code').classList.contains('hljs')).toBe(true); // 코드 블록은 건너뜀
    expect(live.querySelector('code .hljs-keyword')).not.toBeNull();
    expect(changed.length).toBe(1);
    expect(changed[0].tagName).toBe('P');
    expect(live.querySelector('h1 a.anchor')).not.toBeNull();
  });

  it('reports inserted blocks and removes deleted ones', () => {
    const live = article('<h1>A</h1><p>1</p>');
    prepareArticle(live);
    const next = article('<h1>A</h1><p>0</p><p>1</p><h2>New</h2>');
    prepareArticle(next);
    const changed = morphArticle(live, next);
    expect(live.children.length).toBe(4);
    expect(changed.length).toBeGreaterThanOrEqual(2);
    expect(live.querySelector('h2').id).toBe('new');
  });
});
