#!/usr/bin/env node
// web/node_modules → App/Resources/web/vendor 복사. 실행: make assets (또는 cd web && pnpm vendor)
// 번들 대상과 이유는 docs/PLAN.md §4.3, §6 참고.
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '..');
const nm = join(root, 'web', 'node_modules');
const out = join(root, 'App', 'Resources', 'web', 'vendor');

// highlight.min.js(common 언어)에 더해 따로 싣는 언어. toml은 hljs에서 ini의 별칭이다.
// highlight.min.js(common: bash c cpp csharp css diff go graphql ini java javascript json kotlin less lua makefile
// markdown objectivec perl php plaintext python r ruby rust scss shell sql swift typescript vbnet wasm xml yaml)에
// 없는 언어만 따로 싣는다. app.js가 필요할 때 지연 로드한다.
const HLJS_EXTRA_LANGUAGES = [
  'dart', 'dockerfile', 'latex', 'nginx', 'protobuf', 'powershell', 'scala', 'haskell', 'elixir', 'erlang',
  'cmake', 'gradle', 'groovy', 'julia', 'ocaml', 'clojure', 'vim', 'applescript', 'nix', 'elm', 'fsharp',
  'x86asm', 'verilog', 'vhdl', 'matlab', 'fortran', 'prolog', 'scheme', 'lisp', 'haxe', 'crystal',
];

const versions = {};
const licenses = [];

const pkgDir = (name) => join(nm, name);
const readPkg = (name) => JSON.parse(readFileSync(join(pkgDir(name), 'package.json'), 'utf8'));

function record(name) {
  const pkg = readPkg(name);
  versions[name] = pkg.version;
  const licenseFile = readdirSync(pkgDir(name)).find((f) => /^licen[cs]e/i.test(f));
  const text = licenseFile
    ? readFileSync(join(pkgDir(name), licenseFile), 'utf8').trim()
    : `(license: ${pkg.license ?? 'unknown'}; LICENSE 파일 없음)`;
  licenses.push(`## ${name} ${pkg.version}\n\n\`\`\`\n${text}\n\`\`\`\n`);
}

function copy(name, from, to, filter) {
  const src = join(pkgDir(name), from);
  if (!existsSync(src)) throw new Error(`${name}: ${from} 없음. 패키지 구조가 바뀌었는지 확인`);
  const dst = join(out, to);
  mkdirSync(dirname(dst), { recursive: true });
  cpSync(src, dst, { recursive: true, filter });
}

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

record('github-markdown-css');
copy('github-markdown-css', 'github-markdown.css', 'github-markdown.css');

record('@highlightjs/cdn-assets');
copy('@highlightjs/cdn-assets', 'highlight.min.js', 'hljs/highlight.min.js');
copy('@highlightjs/cdn-assets', 'styles/github.min.css', 'hljs/github.min.css');
copy('@highlightjs/cdn-assets', 'styles/github-dark.min.css', 'hljs/github-dark.min.css');
for (const lang of HLJS_EXTRA_LANGUAGES) {
  const rel = `languages/${lang}.min.js`;
  if (existsSync(join(pkgDir('@highlightjs/cdn-assets'), rel))) copy('@highlightjs/cdn-assets', rel, `hljs/${rel}`);
  else console.warn(`hljs: 언어 파일 없음: ${lang}`);
}

record('katex');
copy('katex', 'dist/katex.min.css', 'katex/katex.min.css');
copy('katex', 'dist/katex.min.js', 'katex/katex.min.js');
copy('katex', 'dist/contrib/auto-render.min.js', 'katex/auto-render.min.js');
// 폰트는 woff2만 싣는다. CSS의 woff/ttf 폴백은 무시된다.
copy('katex', 'dist/fonts', 'katex/fonts', (src) => statSync(src).isDirectory() || src.endsWith('.woff2'));

record('mermaid');
copy('mermaid', 'dist/mermaid.min.js', 'mermaid/mermaid.min.js');

record('morphdom'); // app.js에 esbuild로 번들된다(라이선스 기록만)

// gemoji → emoji.js (window.cmarksEmoji = { "smile": "😄", ... }). app.js가 숏코드가 있을 때만 불러온다.
record('gemoji');
{
  const pkg = readPkg('gemoji');
  let entry = pkg.exports?.['.'] ?? pkg.exports ?? pkg.module ?? pkg.main ?? 'index.js';
  if (typeof entry === 'object') entry = entry.import ?? entry.default;
  const mod = await import(pathToFileURL(join(pkgDir('gemoji'), entry)).href);
  const map = mod.nameToEmoji ?? Object.fromEntries(mod.gemoji.flatMap((g) => g.names.map((n) => [n, g.emoji])));
  writeFileSync(join(out, 'emoji.js'), `window.cmarksEmoji=${JSON.stringify(map)};\n`);
}

// @primer/octicons → web/src/generated/octicons.js (앵커/알림 아이콘 path). esbuild가 app.js에 포함한다.
record('@primer/octicons');
{
  const data = JSON.parse(readFileSync(join(pkgDir('@primer/octicons'), 'build', 'data.json'), 'utf8'));
  const wanted = ['link', 'info', 'light-bulb', 'report', 'alert', 'stop'];
  const icons = Object.fromEntries(wanted.map((name) => [name, data[name].heights['16'].path]));
  const generated = join(root, 'web', 'src', 'generated');
  mkdirSync(generated, { recursive: true });
  writeFileSync(join(generated, 'octicons.js'), `// scripts/vendor-web.mjs 가 @primer/octicons ${versions['@primer/octicons']} 에서 생성. 직접 고치지 말 것.\nexport default ${JSON.stringify(icons, null, 2)};\n`);
}

writeFileSync(join(out, 'VERSIONS.json'), JSON.stringify(versions, null, 2) + '\n');
writeFileSync(
  join(root, 'THIRD_PARTY_LICENSES.md'),
  '# Third-party licenses\n\n' +
    '`App/Resources/web/vendor`에 번들된 웹 라이브러리의 라이선스 전문. `make assets`가 생성한다.\n' +
    'Swift 의존성(cmark-gfm: BSD-2-Clause/MIT)은 Packages/MarkdownCore/Package.swift 참고.\n\n' +
    licenses.join('\n'),
);
console.log('vendored:', versions);
