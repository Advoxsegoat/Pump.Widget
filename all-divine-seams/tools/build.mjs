// Joins src/ into one offline page, in the order of src/order.txt.
//   node tools/build.mjs                 -> web/index.html
//   node tools/build.mjs --page out.html -> the artifact page (no document skeleton)
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = (f) => fs.readFileSync(path.join(ROOT, 'src', f), 'utf8');
const order = src('order.txt').split(/\s+/).filter(Boolean);
const html = src('head.html') + order.map((f) => '// ---- src/' + f + '\n' + src(f)).join('') + src('tail.html');

const at = process.argv.indexOf('--page');
if (at >= 0) {
  const out = process.argv[at + 1];
  const body = html.indexOf('<body>\n') + '<body>\n'.length;
  const end = html.lastIndexOf('\n</body></html>');
  fs.writeFileSync(out, html.slice(body, end));
  console.log('wrote', out, end - body);
} else {
  const out = path.join(ROOT, 'web/index.html');
  fs.writeFileSync(out, html);
  console.log('wrote', out, html.length);
}
