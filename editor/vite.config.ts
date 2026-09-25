import { defineConfig } from 'vite'
import { viteSingleFile } from 'vite-plugin-singlefile'

// One self-contained page, written into the app's sources so the app builds without Node.
export default defineConfig({
  base: './',
  plugins: [viteSingleFile()],
  build: {
    target: 'safari26',
    modulePreload: false,
    cssCodeSplit: false,
    outDir: '../MAPP/Editor/Page',
    emptyOutDir: true,
    rollupOptions: { input: 'editor.html' },
  },
})
