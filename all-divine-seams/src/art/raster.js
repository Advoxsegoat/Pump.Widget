// Ras: a small pixel raster that sprites are painted into, then turned into a canvas.
// Carried over from All-Divine Tactics (sprites.js).
(function (AD) {
  'use strict';
  const G = AD.gfx;
  const S = (AD.spr = AD.spr || {});
  function Ras(w, h) { this.w = w; this.h = h; this.d = new Array(w * h).fill(null); }
  Ras.prototype.set = function (x, y, c) {
    x = Math.floor(x); y = Math.floor(y);
    if (x < 0 || y < 0 || x >= this.w || y >= this.h || !c) return;
    this.d[y * this.w + x] = c;
  };
  Ras.prototype.get = function (x, y) {
    if (x < 0 || y < 0 || x >= this.w || y >= this.h) return null;
    return this.d[y * this.w + x];
  };
  Ras.prototype.clear = function (x, y) { if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.d[y * this.w + x] = null; };
  Ras.prototype.rect = function (x, y, w, h, c) { for (let j = y; j < y + h; j++) for (let i = x; i < x + w; i++) this.set(i, j, c); };
  Ras.prototype.row = function (y, x0, x1, c) { for (let i = x0; i <= x1; i++) this.set(i, y, c); };
  Ras.prototype.col = function (x, y0, y1, c) { for (let j = y0; j <= y1; j++) this.set(x, j, c); };
  Ras.prototype.ellipse = function (cx, cy, rx, ry, c, clip) {
    for (let j = Math.floor(cy - ry - 1); j <= Math.ceil(cy + ry + 1); j++) {
      for (let i = Math.floor(cx - rx - 1); i <= Math.ceil(cx + rx + 1); i++) {
        const dx = (i + 0.5 - cx) / rx, dy = (j + 0.5 - cy) / ry;
        if (dx * dx + dy * dy <= 1 && (!clip || clip(i, j))) this.set(i, j, c);
      }
    }
  };
  Ras.prototype.poly = function (pts, c) {
    let minY = Infinity, maxY = -Infinity;
    pts.forEach((p) => { minY = Math.min(minY, p[1]); maxY = Math.max(maxY, p[1]); });
    for (let y = Math.floor(minY); y <= Math.ceil(maxY); y++) {
      const xs = [];
      const yc = y + 0.5;
      for (let i = 0; i < pts.length; i++) {
        const a = pts[i], b = pts[(i + 1) % pts.length];
        if ((a[1] <= yc && b[1] > yc) || (b[1] <= yc && a[1] > yc)) xs.push(a[0] + ((yc - a[1]) / (b[1] - a[1])) * (b[0] - a[0]));
      }
      xs.sort((p, q) => p - q);
      for (let k = 0; k + 1 < xs.length; k += 2) for (let x = Math.round(xs[k]); x < Math.round(xs[k + 1]); x++) this.set(x, y, c);
    }
  };
  Ras.prototype.line = function (x0, y0, x1, y1, c) {
    const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) || 1;
    for (let i = 0; i <= n; i++) this.set(Math.round(x0 + ((x1 - x0) * i) / n), Math.round(y0 + ((y1 - y0) * i) / n), c);
  };
  // darken edges that face down/right, light the ones facing up/left
  Ras.prototype.shade = function (amt, keep) {
    const src = this.d.slice();
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      const c = src[y * this.w + x];
      if (!c || (keep && keep[c])) continue;
      const r = src[y * this.w + x + 1], b = y + 1 < this.h ? src[(y + 1) * this.w + x] : null;
      const l = x > 0 ? src[y * this.w + x - 1] : null, t = y > 0 ? src[(y - 1) * this.w + x] : null;
      if ((x + 1 >= this.w || !r) || !b) this.d[y * this.w + x] = G.shade(c, -amt);
      else if (!l || !t) this.d[y * this.w + x] = G.shade(c, amt * 0.6);
    }
  };
  Ras.prototype.outline = function (col) {
    const src = this.d.slice();
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) {
      if (src[y * this.w + x]) continue;
      const n = [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => {
        const xx = x + dx, yy = y + dy;
        return xx >= 0 && yy >= 0 && xx < this.w && yy < this.h && src[yy * this.w + xx];
      });
      if (n) this.d[y * this.w + x] = col || OUT;
    }
  };
  Ras.prototype.flip = function () {
    const r = new Ras(this.w, this.h);
    for (let y = 0; y < this.h; y++) for (let x = 0; x < this.w; x++) r.d[y * this.w + x] = this.d[y * this.w + (this.w - 1 - x)];
    return r;
  };
  Ras.prototype.canvas = function () {
    const c = G.canvas(this.w, this.h);
    const id = c.x.createImageData(this.w, this.h);
    const cache = {};
    for (let i = 0; i < this.d.length; i++) {
      const col = this.d[i];
      if (!col) continue;
      const rgb = cache[col] || (cache[col] = G.rgb(col));
      id.data[i * 4] = rgb[0]; id.data[i * 4 + 1] = rgb[1]; id.data[i * 4 + 2] = rgb[2]; id.data[i * 4 + 3] = 255;
    }
    c.x.putImageData(id, 0, 0);
    return c;
  };
  S.Ras = Ras;
})(window.AD);
