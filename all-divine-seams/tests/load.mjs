// Loads src/ modules into a fresh vm context, the way the page loads them, and returns AD.
// The simulation never touches the DOM, so Node can run it directly.
import vm from 'node:vm';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function load(files) {
  const ctx = { console };
  ctx.window = ctx;
  vm.createContext(ctx);
  for (const f of files) {
    vm.runInContext(fs.readFileSync(path.join(ROOT, 'src', f), 'utf8'), ctx, { filename: 'src/' + f });
  }
  return ctx.AD;
}

// An open 15x10 room with walls round it, for simulation tests.
export function testRoom(AD, rows) {
  rows = rows || ['###############'].concat(Array.from({ length: 8 }, () => '#.............#'), ['###############']);
  return { grid: new AD.Grid(rows), bodies: new Map(), bus: new AD.Bus(), frame: 0, nextId: 0, run: { coins: 0, coef: () => 1 } };
}
