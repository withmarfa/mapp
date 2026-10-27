import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// One self-contained page, written into the app's sources so the app builds without Node.
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
