import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcssV3 from 'tailwindcss-v3'
import autoprefixer from 'autoprefixer'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const here = dirname(fileURLToPath(import.meta.url))

// The phone's build of the web app.
//
// This is a separate build from the desktop app's on purpose, and it lives in
// the phone's own repository so the desktop app is never touched. Two things
// differ from the desktop build:
//
// 1. The CSS. The desktop build uses Tailwind 4, whose output is built on
//    @layer for the cascade and color-mix()/oklch() for colours. Safari
//    learned @layer in 15.4 and color-mix in 16.2, so on iOS 9 - where 85% of
//    the stylesheet was silently dropped - the page rendered unstyled. This
//    build uses Tailwind 3, which emits flat CSS that goes back to Safari 9.
//
// 2. The output. It is one classic script, not an ES module: iOS 9's WebKit
//    has no support for modules at all, and Safari only gained them in 10.3.
//    The lowering is done by scripts/legacy-bundle.mjs.
export default defineConfig({
  base: './',
  plugins: [react()],
  css: {
    postcss: {
      // Vite wants the plugins as a list. The project's own postcss.config.js
      // is for the desktop build and points at Tailwind 4, so the phone's
      // pipeline is configured here instead.
      plugins: [
        tailwindcssV3({ config: resolve(here, 'tailwind.config.mobile.js') }),
        autoprefixer(),
      ],
    },
  },
  resolve: {
    alias: [
      // The app's own entry imports the desktop stylesheet. Point that at the
      // mobile one, which is the Tailwind 3 build with the same colour tokens.
      { find: /^\.\/index\.css$/, replacement: resolve(here, 'src/mobile.css') },
    ],
  },
  build: {
    target: 'es2015',
    modulePreload: false,
    cssCodeSplit: false,
    reportCompressedSize: false,
    minify: false,
  },
})
