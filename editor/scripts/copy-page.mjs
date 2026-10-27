import { copyFile, mkdir, readFile } from 'node:fs/promises'

const destination = '../MAPP/Editor/Page'
const packageDist = new URL('.', import.meta.resolve('@aicayzer/inkkit/core'))
const hostNotices = await readFile('dist/EDITOR-THIRD-PARTY-NOTICES.md', 'utf8')
if (!hostNotices.includes('mermaid') || !hostNotices.includes('elkjs'))
  throw new Error('The editor build did not retain its dependency notices')

await mkdir(destination, { recursive: true })
for (const file of ['editor.html', 'EDITOR-THIRD-PARTY-NOTICES.md'])
  await copyFile(`dist/${file}`, `${destination}/${file}`)
for (const [source, file] of [
  ['../LICENSE', 'INKKIT-LICENSE.txt'],
  ['../NOTICE', 'INKKIT-NOTICE.txt'],
  ['THIRD-PARTY-NOTICES.txt', 'INKKIT-THIRD-PARTY-NOTICES.txt'],
  ['THIRD-PARTY-NOTICES-FULL.txt', 'INKKIT-FULL-ENTRY-NOTICES.txt'],
])
  await copyFile(new URL(source, packageDist), `${destination}/${file}`)
