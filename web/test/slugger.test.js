import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { Slugger, slug } from '../src/slugger.js';

// Swift 테스트와 같은 벡터 파일을 쓴다. (new URL(..., import.meta.url)은 Vite가 자산 경로로 바꿔 버리므로 path로 푼다.)
const here = dirname(fileURLToPath(import.meta.url));
const vectors = JSON.parse(readFileSync(resolve(here, '../../Packages/MarkdownCore/Tests/MarkdownCoreTests/Fixtures/slugger-vectors.json'), 'utf8'));

describe('slug', () => {
  for (const v of vectors.single) {
    it(`slug(${JSON.stringify(v.in)}) === ${JSON.stringify(v.out)}`, () => {
      expect(slug(v.in)).toBe(v.out);
    });
  }
});

describe('Slugger dedupe', () => {
  for (const v of vectors.sequence) {
    it(JSON.stringify(v.in), () => {
      const s = new Slugger();
      expect(v.in.map((x) => s.slug(x))).toEqual(v.out);
    });
  }
});
