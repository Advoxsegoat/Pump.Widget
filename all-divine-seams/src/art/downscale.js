// The True GBA reducer (spec §9.1): every 3x3 block of the HD art becomes 2x2. Each output pixel
// reads one overlapping 2x2 quarter of its block: an outline in the quarter wins (so outlines never
// break), otherwise the commonest colour (ties to the darker). The block's rarest, most different
// pixel (an eye, a gem, a trim: what a plain vote would lose) is kept in its nearest cell.
// Transparent only if the whole quarter is.
// The core works on packed colours (0 = transparent, 0x1000000 | rgb = opaque) so a whole room
// reduces in a few milliseconds.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const A = (AD.art = AD.art || {});
  const OUT = '#120c1a';
  const ON = 0x1000000;
  const lum = (c) => ((c >> 16) & 255) * 0.3 + ((c >> 8) & 255) * 0.59 + (c & 255) * 0.11;
  const dist = (a, b) => Math.abs(((a >> 16) & 255) - ((b >> 16) & 255)) + Math.abs(((a >> 8) & 255) - ((b >> 8) & 255)) + Math.abs((a & 255) - (b & 255));
  const pack = (c) => (c ? ON | parseInt(c.slice(1), 16) : 0);
  const hex = (v) => (v ? '#' + (v & 0xffffff).toString(16).padStart(6, '0') : null);

  // px: Int32Array of packed colours, w x h; returns {w, h, d: Int32Array}
  function core(px, w, h, OL) {
    const ow = Math.ceil((w * 2) / 3), oh = Math.ceil((h * 2) / 3);
    const bw = Math.ceil(w / 3), bh = Math.ceil(h / 3);
    const d = new Int32Array(ow * oh);
    const src = (x, y) => (x < w && y < h ? px[y * w + x] : 0);
    const q = [0, 0, 0, 0], blk = new Int32Array(9), cnt = new Int8Array(9);
    for (let by = 0; by < bh; by++) for (let bx = 0; bx < bw; bx++) {
      const sx = bx * 3, sy = by * 3;
      for (let qy = 0; qy < 2; qy++) for (let qx = 0; qx < 2; qx++) {
        const ox = bx * 2 + qx, oy = by * 2 + qy;
        if (ox >= ow || oy >= oh) continue;
        q[0] = src(sx + qx, sy + qy); q[1] = src(sx + qx + 1, sy + qy); q[2] = src(sx + qx, sy + qy + 1); q[3] = src(sx + qx + 1, sy + qy + 1);
        let v = 0;
        if (q[0] === OL || q[1] === OL || q[2] === OL || q[3] === OL) v = OL;
        else {
          let bn = 0;
          for (let i = 0; i < 4; i++) {
            const c = q[i];
            if (!c) continue;
            let n = 0;
            for (let j = 0; j < 4; j++) if (q[j] === c) n++;
            if (n > bn || (n === bn && lum(c) < lum(v))) { v = c; bn = n; }
          }
        }
        d[oy * ow + ox] = v;
      }
      // keep the block's detail: a colour seen at most twice that stands out from the commonest one
      for (let i = 0; i < 9; i++) { const c = src(sx + (i % 3), sy + ((i / 3) | 0)); blk[i] = c && c !== OL ? c : 0; }
      let common = 0, cn = 0;
      for (let i = 0; i < 9; i++) {
        cnt[i] = 0;
        if (!blk[i]) continue;
        for (let j = 0; j < 9; j++) if (blk[j] === blk[i]) cnt[i]++;
        if (cnt[i] > cn) { common = blk[i]; cn = cnt[i]; }
      }
      let sc = 0, sv = 90, si = 0;
      for (let i = 0; i < 9; i++) {
        const c = blk[i];
        if (!c || c === common || cnt[i] > 2) continue;
        const s = dist(c, common);
        if (s > sv) { sv = s; sc = c; si = i; }
      }
      if (!sc) continue;
      let here = false;
      for (let qy = 0; qy < 2 && !here; qy++) for (let qx = 0; qx < 2; qx++) {
        const ox = bx * 2 + qx, oy = by * 2 + qy;
        if (ox < ow && oy < oh && d[oy * ow + ox] === sc) { here = true; break; }
      }
      if (here) continue;
      const qx = si % 3 >= 1.5 ? 1 : 0, qy = ((si / 3) | 0) >= 1.5 ? 1 : 0;
      const ox = bx * 2 + qx, oy = by * 2 + qy;
      if (ox < ow && oy < oh && d[oy * ow + ox] !== OL) d[oy * ow + ox] = sc;
      else {
        for (let k = 0; k < 4; k++) {
          const ax = bx * 2 + (k & 1), ay = by * 2 + (k >> 1);
          if (ax < ow && ay < oh && d[ay * ow + ax] && d[ay * ow + ax] !== OL) { d[ay * ow + ax] = sc; break; }
        }
      }
    }
    return { w: ow, h: oh, d };
  }

  // pixels: an array of '#rrggbb' or null, w x h; returns {w, h, d, get}
  A.reduce = function (pixels, w, h, outline) {
    const px = new Int32Array(w * h);
    for (let i = 0; i < w * h; i++) px[i] = pack(pixels[i]);
    const o = core(px, w, h, pack(outline || OUT));
    const d = Array.from(o.d, hex);
    return { w: o.w, h: o.h, d, get: (x, y) => d[y * o.w + x] };
  };

  // the same, on a canvas (browser only); cached per source canvas
  const cache = new WeakMap();
  const OLP = pack(OUT);
  A.down32 = function (cv) {
    if (!cv) return cv;
    const hit = cache.get(cv);
    if (hit) return hit;
    const w = cv.width, h = cv.height;
    const id = (cv.x || cv.getContext('2d')).getImageData(0, 0, w, h).data;
    const px = new Int32Array(w * h);
    for (let i = 0; i < w * h; i++) px[i] = id[i * 4 + 3] < 128 ? 0 : ON | (id[i * 4] << 16) | (id[i * 4 + 1] << 8) | id[i * 4 + 2];
    const o = core(px, w, h, OLP);
    const out = AD.gfx.canvas(o.w, o.h);
    const img = out.x.createImageData(o.w, o.h);
    for (let i = 0; i < o.w * o.h; i++) {
      const c = o.d[i];
      if (!c) continue;
      img.data[i * 4] = (c >> 16) & 255; img.data[i * 4 + 1] = (c >> 8) & 255; img.data[i * 4 + 2] = c & 255; img.data[i * 4 + 3] = 255;
    }
    out.x.putImageData(img, 0, 0);
    cache.set(cv, out);
    return out;
  };
})(window.AD);
