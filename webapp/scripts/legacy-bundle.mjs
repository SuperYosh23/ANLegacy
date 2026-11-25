// Builds the phone's web app: two themes, one classic script.
//
// WHY A SECOND PASS: the phone runs iOS 9, whose WebKit cannot parse two
// things the app relies on.
//
//   * Generators. Safari gained them in iOS 10, and iOS 9's parser rejects
//     `function*` outright, so the whole script fails with a syntax error and
//     the page stays blank.
//   * async/await. Safari gained those in iOS 10.1.
//
// The bundler lowers async/await into generators, which puts the first problem
// back even though the app's own source has no generators. Neither esbuild nor
// a lower build target fixes it: esbuild has no switch for generators, and
// lowering to ES5 would also mean lowering let, const, destructuring and
// spread, which Safari 9 handles perfectly well.
//
// Babel is the tool that can do exactly what is needed. Its regenerator
// transform rewrites generators and async functions into a plain state machine
// with no generator syntax at all, while leaving let, const, destructuring and
// spread alone because Safari 9 understands them.
//
// The order matters:
//
//   1. esbuild bundles Vite's ES module output into one classic script. Vite
//      8's bundler ignores output.format, so the output is still ES modules
//      and esbuild does the wrapping.
//   2. Babel lowers it for iOS 9.
//   3. esbuild minifies. Minifying has to come last: Babel's generators
//      transform trips over a template literal in minified output.
//
// Two stylesheets are built, one per theme, because the colours cannot be CSS
// custom properties: Safari on iOS has no support for them at all before 9.3
// (partial) and 10 (full), and the phone runs 9.2. A var() in a colour is not
// ignored there - the whole declaration is dropped, leaving the element with no
// colour at all.
//
// The desktop build is untouched: this only runs for the phone.

import { transformSync } from '@babel/core';
import { build, transform } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, readdirSync, rmSync, existsSync, mkdirSync, copyFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const dist = join(root, 'dist');
const distLight = join(root, 'dist-light');

// --- 1. Build the app, once per theme -----------------------------------------
function viteBuild(theme, outDir) {
  console.log(`==> building the web app (${theme})`);
  execFileSync('npx', ['vite', 'build', '--config', 'vite.config.mobile.js', '--outDir', outDir], {
    cwd: root,
    stdio: 'inherit',
    env: { ...process.env, AN_THEME: theme },
  });
}

viteBuild('dark', 'dist');
viteBuild('light', 'dist-light');

const assets = join(dist, 'assets');
const lightAssets = join(distLight, 'assets');

const entry = readdirSync(assets).find((f) => f.startsWith('index-') && f.endsWith('.js'));
if (!entry) {
  console.error('no built bundle found in dist/assets');
  process.exit(1);
}

// --- 2. Bundle to one classic script -----------------------------------------
const tmp = join(assets, 'bundled-iife.js');
await build({
  entryPoints: [join(assets, entry)],
  outfile: tmp,
  bundle: true,
  format: 'iife',
  target: 'esnext',
  legalComments: 'none',
  logLevel: 'warning',
});

const bundled = readFileSync(tmp, 'utf8');
rmSync(tmp);

// --- 3. Lower it for iOS 9 ----------------------------------------------------
//
// The first pass rewrites template literals into string concatenation. Babel 8's
// regenerator transform throws on a template literal inside a generator, and the
// app's generators are its async functions. Safari 9 supports template literals
// perfectly well, so converting them costs nothing - it is only to get past
// the transform's limitation.
const preprocessed = transformSync(bundled, {
  babelrc: false,
  configFile: false,
  comments: false,
  plugins: [['@babel/plugin-transform-template-literals', { loose: true }]],
}).code;

const lowered = transformSync(preprocessed, {
  babelrc: false,
  configFile: false,
  comments: false,
  presets: [
    ['@babel/preset-env', {
      // Safari 9 is the floor. Everything it already understands is left alone;
      // only what it lacks is rewritten.
      targets: { safari: '9' },
      modules: false,
    }],
  ],
  plugins: [
    // No runtime plugin on purpose. It would emit the helpers as ES module
    // imports, and the bundle is already a classic script by this point. Babel
    // 8's generators transform also no longer needs a regeneratorRuntime
    // global, so nothing is missing by leaving it out.
  ],
});

// --- 4. Minify ----------------------------------------------------------------
const minified = await transform(lowered.code, {
  minify: true,
  loader: 'js',
  target: 'es2015',
  legalComments: 'none',
});

writeFileSync(join(assets, 'index-legacy.js'), minified.code);

// --- 5. Patch the stylesheets for iOS 9 --------------------------------------
//
//   * `inset: 0` - the shorthand arrived in Safari 14.1, and the app uses
//     inset-0 on absolutely positioned overlays.
//   * `:where(...)` - Safari 14. The selector is dropped whole, taking the
//     rule with it.
//   * flexbox `gap` - Safari 14.1. The app uses gap on well over a hundred
//     elements, and without it everything is crammed together.
//
// What is left over - aspect-ratio, display:grid, backdrop-filter - either has
// no effect the app depends on, or degrades to something harmless.
function patchStylesheet(path) {
  let css = readFileSync(path, 'utf8');

  css = css.replace(/(\s)inset\s*:\s*([^;{}]+);/g,
    (match, space, value) =>
      `${space}top:${value};${space}right:${value};${space}bottom:${value};${space}left:${value};`);

  css = css.replace(/:where\(([^()]*(?:\([^()]*\)[^()]*)*)\)/g, '$1');

  // Transforms.
  //
  // Tailwind builds every transform out of CSS custom properties:
  //   transform: translate(var(--tw-translate-x), var(--tw-translate-y)) ...
  // A browser without custom property support drops the whole declaration, so
  // on the phone no transform ran at all: the settings switches' knobs could
  // not move, the entrance animations lost their movement, and artwork zoom
  // did nothing. The fallback syntax cannot save it either - var() itself is
  // what is unsupported, not just the value.
  //
  // So each rule's transform is rebuilt with literal numbers, taken from the
  // --tw-* values that rule itself sets and the defaults for the rest.
  const TRANSFORM_TEMPLATE =
    /transform:\s*translate\(var\(--tw-translate-x\),\s*var\(--tw-translate-y\)\)\s*rotate\(var\(--tw-rotate\)\)\s*skewX\(var\(--tw-skew-x\)\)\s*skewY\(var\(--tw-skew-y\)\)\s*scaleX\(var\(--tw-scale-x\)\)\s*scaleY\(var\(--tw-scale-y\)\);/g;

  css = css.replace(/([^{}]+)\{([^{}]*)\}/g, (match, selector, body) => {
    if (!body.includes('transform:') || !body.includes('var(--tw-translate-x)')) return match;
    const values = { 'tw-translate-x': '0', 'tw-translate-y': '0', 'tw-rotate': '0', 'tw-skew-x': '0', 'tw-skew-y': '0', 'tw-scale-x': '1', 'tw-scale-y': '1' };
    for (const [name, value] of Object.entries(values)) {
      const found = new RegExp(`--${name}\\s*:\\s*([^;]+);`).exec(body);
      if (found) values[name] = found[1].trim();
    }
    const concrete =
      `transform: translate(${values['tw-translate-x']}, ${values['tw-translate-y']}) ` +
      `rotate(${values['tw-rotate']}) skewX(${values['tw-skew-x']}) skewY(${values['tw-skew-y']}) ` +
      `scaleX(${values['tw-scale-x']}) scaleY(${values['tw-scale-y']});`;
    const replaced = body.replace(TRANSFORM_TEMPLATE, concrete);
    return `${selector}{${replaced}}`;
  });

  // Colours.
  //
  // Tailwind writes a colour as rgb(R G B / var(--tw-bg-opacity, 1)). Two
  // things there are past iOS 9: the space-separated rgb() with a slash is
  // Safari 12.1, and the var() inside is meaningless without custom property
  // support - and because the declaration is invalid, the element ends up with
  // no colour at all rather than a slightly wrong one. So every colour is
  // rewritten to the old comma-separated rgba(), which iOS 9 understands.
  const toRgba = (r, g, b, a) => `rgba(${r}, ${g}, ${b}, ${a})`;
  css = css.replace(/rgb\((\d+)\s+(\d+)\s+(\d+)\s*\/\s*var\(--tw-[\w-]+-opacity,\s*([\d.]+)\)\)/g,
    (m, r, g, b, a) => toRgba(r, g, b, a));
  css = css.replace(/rgb\((\d+)\s+(\d+)\s+(\d+)\s*\/\s*([\d.]+)\)/g,
    (m, r, g, b, a) => toRgba(r, g, b, a));
  css = css.replace(/rgba\(#([0-9a-fA-F]{6}),\s*([\d.]+)\)/g, (m, hex, a) => {
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    return toRgba(r, g, b, a);
  });

  // gap on a flex container -> margins on the children, for the same spacing.
  // Only the children after the first, so there is no trailing gap.
  const gapClasses = [...css.matchAll(/\.(gap-[0-9]+)\s*\{\s*gap\s*:\s*([^;{}]+);/g)];
  for (const [, name, value] of gapClasses) {
    css += `\n.${name} > * + * { margin-left: ${value}; }`;
  }

  writeFileSync(path, css);
  return gapClasses.length;
}

const darkCss = readdirSync(assets).find((f) => f.endsWith('.css'));
const lightCss = readdirSync(lightAssets).find((f) => f.endsWith('.css'));
if (!darkCss || !lightCss) {
  console.error('could not find the built stylesheets');
  process.exit(1);
}

const darkCssPath = join(assets, 'theme-dark.css');
const lightCssPath = join(assets, 'theme-light.css');
copyFileSync(join(assets, darkCss), darkCssPath);
copyFileSync(join(lightAssets, lightCss), lightCssPath);
rmSync(join(assets, darkCss));

const gaps = patchStylesheet(darkCssPath) + patchStylesheet(lightCssPath);
console.log(`patched both stylesheets for iOS 9 (${gaps} gap rules given a margin fallback)`);

// --- 6. Point the page at them ------------------------------------------------
//
// Both stylesheets are linked and one is disabled. A disabled stylesheet is
// ignored entirely, which works in every browser - unlike a custom property
// override, which iOS 9 does not have.
//
// The defer on the script matters: Vite puts the script in the document head,
// which is safe for a module because modules are deferred by default. A classic
// script is not, so without defer it would run before the body had been parsed
// and React would find no #root to mount into.
//
// The theme is read from the query string without URLSearchParams, which iOS 9
// does not have either - the polyfills are a deferred script and so have not run
// yet at this point.
const indexPath = join(dist, 'index.html');
let html = readFileSync(indexPath, 'utf8');

html = html.replace(
  /<link rel="stylesheet"[^>]*href="\.\/assets\/[^"]*\.css"[^>]*>/,
  `<link rel="stylesheet" href="./assets/theme-light.css" id="theme-light">
    <link rel="stylesheet" href="./assets/theme-dark.css" id="theme-dark">
    <script>
      (function () {
        var theme = 'dark';
        var match = /[?&]theme=([^&]*)/.exec(window.location.search);
        if (match && match[1] === 'light') theme = 'light';
        var light = document.getElementById('theme-light');
        var dark = document.getElementById('theme-dark');
        if (light) light.disabled = (theme !== 'light');
        if (dark) dark.disabled = (theme === 'light');
        document.documentElement.setAttribute('data-theme', theme);
      })();
    </script>`
);

html = html.replace(
  /<script[^>]*src="[^"]*index-[^"]*\.js"[^>]*><\/script>/,
  '<script defer src="./assets/index-legacy.js"></script>'
);

writeFileSync(indexPath, html);

// The light build's JavaScript is the same as the dark one's, so only the
// stylesheet is taken from it.
rmSync(distLight, { recursive: true, force: true });

const generators = (minified.code.match(/function\s*\*/g) || []).length;
console.log(`lowered bundle -> assets/index-legacy.js (generators left: ${generators})`);
