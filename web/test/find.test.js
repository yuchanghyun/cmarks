import { describe, expect, it } from 'vitest';
import { Finder, collectText } from '../src/find.js';

function article(html) {
  const el = document.createElement('article');
  el.innerHTML = html;
  document.body.append(el);
  return el;
}

describe('collectText', () => {
  it('skips scripts and closed details bodies but keeps summaries', () => {
    const root = article('<p>Hello</p><script>x</script><details><summary>Sum</summary><p>hidden</p></details><details open><p>shown</p></details>');
    const { text } = collectText(root);
    expect(text).toBe('HelloSumshown');
  });
});

describe('Finder', () => {
  it('finds case-insensitive matches across nodes and steps through them', () => {
    const root = article('<p>Foo <em>foo</em>bar FOO</p><p>nothing</p>');
    const finder = new Finder(root);
    const result = finder.search('foo');
    expect(result.count).toBe(3);
    expect(result.index).toBe(0);
    expect(finder.ranges.map((r) => r.toString())).toEqual(['Foo', 'foo', 'FOO']);
    expect(finder.next().index).toBe(1);
    expect(finder.next().index).toBe(2);
    expect(finder.next().index).toBe(0);
    expect(finder.prev().index).toBe(2);
  });

  it('respects case sensitivity and clears', () => {
    const root = article('<p>Foo foo</p>');
    const finder = new Finder(root);
    expect(finder.search('Foo', { caseSensitive: true }).count).toBe(1);
    expect(finder.search('').count).toBe(0);
    finder.search('foo');
    finder.clear();
    expect(finder.result()).toEqual({ count: 0, index: -1 });
  });

  it('builds ranges spanning multiple text nodes', () => {
    const root = article('<p>ab<b>cd</b>ef</p>');
    const finder = new Finder(root);
    expect(finder.search('bcde').count).toBe(1);
    expect(finder.ranges[0].toString()).toBe('bcde');
  });
});
