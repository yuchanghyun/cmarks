// GitHub 헤딩 앵커 알고리즘(github-slugger와 동일). Swift의 GitHubSlugger와 같은 벡터를 통과해야 한다.
// 소문자화 → 글자(L)·숫자(N)·결합 기호(M)·공백·`-`·`_` 외 제거 → 공백을 `-`로.
const STRIP = /[^\p{L}\p{N}\p{M} _-]/gu;

export function slug(value) {
  return String(value).toLowerCase().replace(STRIP, '').replace(/ /g, '-');
}

export class Slugger {
  constructor() {
    this.occurrences = new Map();
  }

  /** 같은 문서 안의 중복 슬러그에 -1, -2… 를 붙인다. */
  slug(value) {
    const base = slug(value);
    let result = base;
    while (this.occurrences.has(result)) {
      const n = (this.occurrences.get(base) ?? 0) + 1;
      this.occurrences.set(base, n);
      result = `${base}-${n}`;
    }
    this.occurrences.set(result, 0);
    return result;
  }
}
