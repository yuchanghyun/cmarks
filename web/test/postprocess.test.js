import { describe, expect, it } from 'vitest';
import { addHeadingAnchors, collectStats, markTaskLists, replaceEmoji, transformAlerts } from '../src/postprocess.js';

function article(html) {
  const el = document.createElement('article');
  el.className = 'markdown-body';
  el.innerHTML = html;
  return el;
}

describe('addHeadingAnchors', () => {
  it('sets ids, prepends anchors, returns outline, and is idempotent', () => {
    const root = article('<h1>Hello World</h1><h2>헤딩</h2><h2>헤딩</h2><h3>C# &amp; F#</h3>');
    const outline = addHeadingAnchors(root);
    expect(outline).toEqual([
      { level: 1, text: 'Hello World', id: 'hello-world' },
      { level: 2, text: '헤딩', id: '헤딩' },
      { level: 2, text: '헤딩', id: '헤딩-1' },
      { level: 3, text: 'C# & F#', id: 'c--f' },
    ]);
    expect(root.querySelector('h1 > a.anchor[href="#hello-world"] > span.octicon.octicon-link')).not.toBeNull();

    addHeadingAnchors(root);
    expect(root.querySelectorAll('a.anchor').length).toBe(4);
    expect(root.querySelector('h1').id).toBe('hello-world');
  });
});

describe('transformAlerts', () => {
  it('converts the five GitHub alert types and keeps content', () => {
    const root = article('<blockquote>\n<p>[!NOTE]\nBody <strong>bold</strong></p>\n<p>Second</p>\n</blockquote>');
    transformAlerts(root);
    const alert = root.querySelector('.markdown-alert.markdown-alert-note');
    expect(alert).not.toBeNull();
    expect(root.querySelector('blockquote')).toBeNull();
    const title = alert.querySelector('p.markdown-alert-title');
    expect(title.textContent).toBe('Note');
    expect(title.querySelector('svg.octicon.octicon-info.mr-2 path')).not.toBeNull();
    const paragraphs = alert.querySelectorAll('p:not(.markdown-alert-title)');
    expect(paragraphs.length).toBe(2);
    expect(paragraphs[0].innerHTML).toBe('Body <strong>bold</strong>');
  });

  it('drops the marker paragraph when it was the only content on its line', () => {
    const root = article('<blockquote><p>[!WARNING]</p><p>Text</p></blockquote>');
    transformAlerts(root);
    const alert = root.querySelector('.markdown-alert-warning');
    expect(alert.querySelectorAll('p').length).toBe(2); // title + Text
  });

  it('leaves ordinary quotes and lowercase markers alone', () => {
    const root = article('<blockquote><p>plain</p></blockquote><blockquote><p>[!note] nope</p></blockquote><blockquote><p>see [!TIP] later</p></blockquote>');
    transformAlerts(root);
    expect(root.querySelectorAll('blockquote').length).toBe(3);
    expect(root.querySelector('.markdown-alert')).toBeNull();
  });
});

describe('markTaskLists', () => {
  it('adds GitHub classes to cmark-gfm output', () => {
    const root = article('<ul>\n<li><input type="checkbox" checked="" disabled="" /> done</li>\n<li>plain</li>\n</ul>');
    markTaskLists(root);
    expect(root.querySelector('ul').classList.contains('contains-task-list')).toBe(true);
    const items = root.querySelectorAll('li');
    expect(items[0].classList.contains('task-list-item')).toBe(true);
    expect(items[0].querySelector('input').classList.contains('task-list-item-checkbox')).toBe(true);
    expect(items[1].classList.contains('task-list-item')).toBe(false);
  });
});

describe('replaceEmoji', () => {
  const map = { rocket: '🚀', '+1': '👍' };
  it('replaces shortcodes in text but not in code', () => {
    const root = article('<p>Go :rocket: :+1: :unknown:</p><pre><code>:rocket:</code></pre><p>inline <code>:rocket:</code> ok :rocket:</p>');
    const n = replaceEmoji(root, map);
    expect(n).toBe(3);
    expect(root.querySelector('p').textContent).toBe('Go 🚀 👍 :unknown:');
    expect(root.querySelector('pre code').textContent).toBe(':rocket:');
    expect(root.querySelectorAll('p')[1].innerHTML).toBe('inline <code>:rocket:</code> ok 🚀');
  });
});

describe('collectStats', () => {
  it('counts code blocks, images, headings', () => {
    const root = article('<h1>a</h1><pre><code>x</code></pre><p><img src="a.png"></p><code>inline</code>');
    expect(collectStats(root)).toEqual({ codeBlocks: 1, images: 1, headings: 1 });
  });
});
