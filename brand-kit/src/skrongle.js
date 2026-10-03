// Shared drawing code for the END OF FEED brand: Skrongle, backgrounds, effects.
// Everything draws onto a 2D canvas so stills (avatar, banner) and the teaser
// video come from one source of truth.

(() => {
const PALETTE = {
  void: '#050806',
  toxic: '#39ff14',
  toxicDim: '#1f8f0b',
  screen: '#bff6ff',
  crustLight: '#f6c25a',
  crustMid: '#e09a2e',
  crustDark: '#a8581a',
  outline: '#3a1a06',
  mouth: '#4a0710',
  tongue: '#e05a6a',
};

function ellipsePath(ctx, x, y, rx, ry, rot) {
  ctx.beginPath();
  ctx.ellipse(x, y, rx, ry, rot, 0, Math.PI * 2);
}

// Skrongle: crude croissant, googly eyes, human teeth.
// opts: mouth 0..1, pupilL/pupilR [dx,dy] in eye radii, squash, glow, tilt
function drawSkrongle(ctx, cx, cy, size, opts = {}) {
  const o = Object.assign({ mouth: 0.6, pupilL: [0.3, 0.2], pupilR: [-0.35, 0.3], squash: 1, glow: 1, tilt: 0 }, opts);
  const u = size; // 1 unit = size px (croissant is ~1.2u wide)
  ctx.save();
  ctx.translate(cx, cy);
  ctx.rotate(o.tilt);
  ctx.scale(1 / Math.sqrt(o.squash), o.squash);

  // segments: [x, y, rx, ry, rot], drawn tips first so the center sits on top
  const segs = [
    [-0.52, 0.2, 0.11, 0.15, -0.85],
    [0.52, 0.2, 0.11, 0.15, 0.85],
    [-0.31, 0.06, 0.18, 0.23, -0.38],
    [0.31, 0.06, 0.18, 0.23, 0.38],
    [0, 0, 0.27, 0.31, 0],
  ];

  if (o.glow > 0) {
    ctx.save();
    ctx.shadowColor = PALETTE.toxic;
    ctx.shadowBlur = 0.35 * u * o.glow;
    for (const [x, y, rx, ry, r] of segs) {
      ellipsePath(ctx, x * u, y * u, rx * u, ry * u, r);
      ctx.fillStyle = PALETTE.crustMid;
      ctx.fill();
    }
    ctx.restore();
  }

  for (const [x, y, rx, ry, r] of segs) {
    const g = ctx.createRadialGradient((x - rx * 0.3) * u, (y - ry * 0.4) * u, 0, x * u, y * u, Math.max(rx, ry) * u * 1.1);
    g.addColorStop(0, PALETTE.crustLight);
    g.addColorStop(0.55, PALETTE.crustMid);
    g.addColorStop(1, PALETTE.crustDark);
    ellipsePath(ctx, x * u, y * u, rx * u, ry * u, r);
    ctx.fillStyle = g;
    ctx.fill();
    ctx.lineWidth = 0.022 * u;
    ctx.strokeStyle = PALETTE.outline;
    ctx.stroke();

    // flaky layer lines
    ctx.save();
    ctx.translate(x * u, y * u);
    ctx.rotate(r);
    ctx.strokeStyle = 'rgba(58,26,6,0.55)';
    ctx.lineWidth = 0.011 * u;
    for (const k of [-0.45, 0.45]) {
      ctx.beginPath();
      ctx.ellipse(k * rx * u, 0, rx * 0.35 * u, ry * 0.85 * u, 0, -Math.PI / 2.4, Math.PI / 2.4, k > 0);
      ctx.stroke();
    }
    ctx.restore();
  }

  // glare
  ctx.fillStyle = 'rgba(255,248,220,0.55)';
  ellipsePath(ctx, -0.12 * u, -0.2 * u, 0.07 * u, 0.035 * u, -0.5);
  ctx.fill();

  // mouth
  const mw = 0.2 * u;
  const mh = (0.025 + 0.13 * o.mouth) * u;
  const my = 0.12 * u;
  ellipsePath(ctx, 0, my, mw, mh, 0);
  ctx.fillStyle = PALETTE.mouth;
  ctx.fill();
  ctx.save();
  ctx.clip();
  // tongue
  ellipsePath(ctx, 0.02 * u, my + mh * 0.85, mw * 0.55, mh * 0.5, 0);
  ctx.fillStyle = PALETTE.tongue;
  ctx.fill();
  // upper teeth: flat, square, unsettlingly human
  const teethTop = 6;
  const tw = (mw * 2) / teethTop;
  for (let i = 0; i < teethTop; i++) {
    const tx = -mw + i * tw;
    ctx.fillStyle = '#fbf6e8';
    ctx.strokeStyle = '#9b8f78';
    ctx.lineWidth = 0.006 * u;
    ctx.beginPath();
    ctx.roundRect(tx + tw * 0.06, my - mh - 0.01 * u, tw * 0.88, Math.min(0.075 * u, mh * 0.9) + 0.01 * u, 0.012 * u);
    ctx.fill();
    ctx.stroke();
  }
  if (o.mouth > 0.25) {
    const teethBot = 5;
    const bw = (mw * 1.6) / teethBot;
    for (let i = 0; i < teethBot; i++) {
      const tx = -mw * 0.8 + i * bw;
      const th = Math.min(0.05 * u, mh * 0.5);
      ctx.beginPath();
      ctx.roundRect(tx + bw * 0.08, my + mh - th, bw * 0.84, th + 0.01 * u, 0.01 * u);
      ctx.fillStyle = '#efe7d2';
      ctx.fill();
      ctx.stroke();
    }
  }
  ctx.restore();
  ellipsePath(ctx, 0, my, mw, mh, 0);
  ctx.lineWidth = 0.018 * u;
  ctx.strokeStyle = PALETTE.outline;
  ctx.stroke();

  // googly eyes (mismatched on purpose)
  const eyes = [
    [-0.115, -0.07, 0.1, o.pupilL],
    [0.11, -0.085, 0.082, o.pupilR],
  ];
  for (const [ex, ey, er, [px, py]] of eyes) {
    ellipsePath(ctx, ex * u, ey * u, er * u, er * u, 0);
    ctx.fillStyle = '#ffffff';
    ctx.fill();
    ctx.lineWidth = 0.014 * u;
    ctx.strokeStyle = '#111';
    ctx.stroke();
    const pr = er * 0.48;
    const lim = er - pr - 0.008;
    const len = Math.hypot(px, py) || 1;
    const k = Math.min(1, len) * lim / len;
    ellipsePath(ctx, (ex + px * k) * u, (ey + py * k) * u, pr * u, pr * u, 0);
    ctx.fillStyle = '#0a0a0a';
    ctx.fill();
    ellipsePath(ctx, (ex + px * k - pr * 0.3) * u, (ey + py * k - pr * 0.35) * u, pr * 0.25 * u, pr * 0.25 * u, 0);
    ctx.fillStyle = '#fff';
    ctx.fill();
  }

  ctx.restore();
}

function drawVoid(ctx, w, h, t = 0) {
  ctx.fillStyle = PALETTE.void;
  ctx.fillRect(0, 0, w, h);
  // toxic fog rising from the bottom
  const g = ctx.createLinearGradient(0, h, 0, h * 0.35);
  g.addColorStop(0, 'rgba(57,255,20,0.32)');
  g.addColorStop(0.5, 'rgba(31,143,11,0.12)');
  g.addColorStop(1, 'rgba(0,0,0,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  // drifting fog blobs
  for (let i = 0; i < 6; i++) {
    const x = ((i * 0.23 + t * 0.015 * (i % 2 ? 1 : -1)) % 1.2 - 0.1) * w;
    const y = h * (0.78 + 0.05 * Math.sin(t * 0.7 + i));
    const r = w * (0.25 + 0.05 * i);
    const fg = ctx.createRadialGradient(x, y, 0, x, y, r);
    fg.addColorStop(0, 'rgba(57,255,20,0.09)');
    fg.addColorStop(1, 'rgba(57,255,20,0)');
    ctx.fillStyle = fg;
    ctx.fillRect(0, 0, w, h);
  }
}

function drawSkyline(ctx, w, h, baseY, scale = 1) {
  ctx.save();
  ctx.fillStyle = '#020302';
  let x = 0;
  let i = 0;
  while (x < w) {
    const bw = (60 + ((i * 37) % 90)) * scale;
    const bh = (120 + ((i * 53) % 260)) * scale;
    ctx.fillRect(x, baseY - bh, bw, bh + 4);
    if (i % 4 === 1) {
      // smokestack
      ctx.fillRect(x + bw * 0.3, baseY - bh - 140 * scale, 22 * scale, 140 * scale);
    }
    x += bw + 6 * scale;
    i++;
  }
  ctx.restore();
}

function drawScanlines(ctx, w, h, alpha = 0.12) {
  ctx.fillStyle = `rgba(0,0,0,${alpha})`;
  for (let y = 0; y < h; y += 4) ctx.fillRect(0, y, w, 2);
  const v = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * 0.3, w / 2, h / 2, Math.max(w, h) * 0.75);
  v.addColorStop(0, 'rgba(0,0,0,0)');
  v.addColorStop(1, 'rgba(0,0,0,0.6)');
  ctx.fillStyle = v;
  ctx.fillRect(0, 0, w, h);
}

// RGB-split glitch text
function glitchText(ctx, text, x, y, opts = {}) {
  // jx: horizontal jitter in px, passed in so video frames stay deterministic
  const o = Object.assign({ font: '160px Anton', color: '#ffffff', split: 6, align: 'center', jx: 0 }, opts);
  ctx.save();
  ctx.font = o.font;
  ctx.textAlign = o.align;
  ctx.textBaseline = 'middle';
  const jx = o.jx;
  ctx.globalCompositeOperation = 'lighter';
  ctx.fillStyle = 'rgba(255,0,80,0.8)';
  ctx.fillText(text, x - o.split + jx, y);
  ctx.fillStyle = 'rgba(0,220,255,0.8)';
  ctx.fillText(text, x + o.split + jx, y);
  ctx.globalCompositeOperation = 'source-over';
  ctx.fillStyle = o.color;
  ctx.fillText(text, x + jx, y);
  ctx.restore();
}

function drawPhone(ctx, cx, cy, w, h, glow = 1) {
  ctx.save();
  ctx.shadowColor = PALETTE.screen;
  ctx.shadowBlur = 90 * glow;
  ctx.fillStyle = '#0d1114';
  ctx.beginPath();
  ctx.roundRect(cx - w / 2, cy - h / 2, w, h, w * 0.12);
  ctx.fill();
  ctx.restore();
  const pad = w * 0.045;
  ctx.fillStyle = '#071216';
  ctx.beginPath();
  ctx.roundRect(cx - w / 2 + pad, cy - h / 2 + pad, w - pad * 2, h - pad * 2, w * 0.09);
  ctx.fill();
  return { x: cx - w / 2 + pad, y: cy - h / 2 + pad, w: w - pad * 2, h: h - pad * 2, r: w * 0.09 };
}

window.EOF = { PALETTE, drawSkrongle, drawVoid, drawSkyline, drawScanlines, glitchText, drawPhone };
})();
