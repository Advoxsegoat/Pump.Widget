// Contact sheet of a live duel; see duel-sheet.mjs. window.DUEL = { a, d, wa, wd, dist, ev: [{who,hit,crit}], every, cols, crop, biome }
window.SCENE = function () {
  const o = Object.assign({ a: 'abarax', d: 'thug', wa: 'skillet', wd: 'ironsword', dist: 1, ev: [{ who: 'a', hit: 1 }], every: 3, cols: 5, crop: [30, 132], biome: 'city', scale: 2 }, window.DUEL || {});
  const mk = (spec, team, uid) => {
    const [id, lk] = spec.split(':');
    const U = AD.UNITS[id];
    const look = U ? (lk && U.looks[lk]) || Object.values(U.looks)[0] : AD.LOOKS[id];
    if (!look) throw new Error('no unit or look called ' + spec);
    return { uid, id, team, name: U ? U.name : id, look, port: U ? AD.PORTS[id] || U.port : null, hp: 30, mhp: 30, items: [], skills: [], mod: {}, stats: {}, eq: 0 };
  };
  const a = mk(o.a, 'p', 1), d = mk(o.d, 'e', 2);
  const side = (w) => w ? { w: AD.ITEMS[w], wo: { d: AD.ITEMS[w], i: 0 }, dmg: 9, hit: 80, crit: 10, mag: !!AD.ITEMS[w].mag } : null;
  const fc = { a, d, A: side(o.wa), D: side(o.wd), dist: o.dist, boost: 0 };
  let ah = 30, dh = 30;
  const tl = o.ev.map((e) => {
    const att = e.who === 'a' ? 'a' : 'd';
    const dmg = e.hit ? (e.dmg || (e.crit ? 27 : 9)) : 0;
    const before = att === 'a' ? dh : ah;
    if (att === 'a') dh = Math.max(0, dh - dmg); else ah = Math.max(0, ah - dmg);
    const S = att === 'a' ? fc.A : fc.D;
    return { who: att, hit: !!e.hit, crit: !!e.crit, dmg, before, after: att === 'a' ? dh : ah, mag: S.mag, type: S.w.t, aHp: ah, dHp: dh };
  });
  const bt = { map: { biome: o.biome, night: !!o.night } };
  const duel = new AD.Duel(bt, fc, { tl });
  let finished = false; duel.done = () => { finished = true; };
  const cv = document.createElement('canvas'); cv.width = 320; cv.height = 180;
  const ctx = cv.getContext('2d'); ctx.imageSmoothingEnabled = false;
  const frames = [];
  for (let f = 0; f < 1600 && !finished; f++) {
    duel.update(); AD.fx.update && AD.fx.update();
    if (f >= (o.from || 16) && f % o.every === 0) { ctx.clearRect(0, 0, 320, 180); duel.draw(ctx); const g = document.createElement('canvas'); g.width = 320; g.height = o.crop[1] - o.crop[0]; g.getContext('2d').drawImage(cv, 0, -o.crop[0]); frames.push([f, g]); }
  }
  const fw = 320, fh = o.crop[1] - o.crop[0], cols = o.cols, rows = Math.ceil(frames.length / cols), k = o.scale;
  const out = document.createElement('canvas'); out.width = cols * fw * k; out.height = rows * fh * k;
  const x = out.getContext('2d'); x.imageSmoothingEnabled = false;
  frames.forEach(([f, g], i) => { x.drawImage(g, (i % cols) * fw * k, Math.floor(i / cols) * fh * k, fw * k, fh * k); x.fillStyle = '#000'; x.fillRect((i % cols) * fw * k, Math.floor(i / cols) * fh * k, 22 * k, 9 * k); AD.gfx.text(x, String(f), (i % cols) * fw * k + 2, Math.floor(i / cols) * fh * k + 1, '#ffffff'); });
  window.FRAMES = frames.length;
  return out;
};
