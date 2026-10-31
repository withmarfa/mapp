import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// One self-contained page, written into the app's sources so the app builds without Node. Vite keeps the inlined
// chunks in `dist/` until license collection finishes (`deleteInlinedFiles: false`); `scripts/copy-page.mjs` ships
// only the offline page and the notices. The host-generated notice follows this app's lockfile, and Inkkit's own
// notices cover the dependencies it bundles, Pele among them.
export default defineConfig({
  base: './',
  plugins: [viteSingleFile({ deleteInlinedFiles: false })],
  build: {
    target: 'safari26',
    modulePreload: false,
    cssCodeSplit: false,
    license: { fileName: 'EDITOR-THIRD-PARTY-NOTICES.md' },
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: { input: 'editor.html' },
  },
})
