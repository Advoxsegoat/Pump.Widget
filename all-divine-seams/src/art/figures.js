// Characters: 24x32 paper-doll figures with real limbs, drawn into larger canvases so weapons and
// lunges have room. Every frame is generated from a "look" (colours and style choices) and a pose.
//   front / back views: idle (breathing, blinking) and walk cycles
//   side view: walk cycle plus attack poses per weapon style, hurt and dodge
// Mounted riders and the big things from beyond the world have their own renderers.
(function (AD) {
  'use strict';
  const G = AD.gfx, S = AD.spr, Ras = S.Ras;
  const OUT = '#120c1a';
  const rad = (d) => (d * Math.PI) / 180;
  // canvas for a standing figure: the 24x32 body sits at (12, 4) inside 48x40
  const CW = 48, CH = 40, OX = 12, OY = 4;
  // frames per idle pose, per walk pose (towns, world), per tile walked on a battle map
  AD.ANIM = { idle: 18, walk: 8, step: 12 };

  // ---------------------------------------------------------------- drawing proxy
  function view(r, ox, oy) {
    const p = {
      set: (x, y, c) => r.set(Math.round(x) + ox, Math.round(y) + oy, c),
      rect: (x, y, w, h, c) => r.rect(Math.round(x) + ox, Math.round(y) + oy, w, h, c),
      row: (y, x0, x1, c) => r.row(Math.round(y) + oy, Math.round(x0) + ox, Math.round(x1) + ox, c),
      col: (x, y0, y1, c) => r.col(Math.round(x) + ox, Math.round(y0) + oy, Math.round(y1) + oy, c),
      ellipse: (cx, cy, rx, ry, c) => r.ellipse(cx + ox, cy + oy, rx, ry, c),
      poly: (pts, c) => r.poly(pts.map(([x, y]) => [x + ox, y + oy]), c),
      thick: (x0, y0, x1, y1, w, c) => {
        const n = Math.max(1, Math.ceil(Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0)) * 2));
        for (let i = 0; i <= n; i++) {
          const x = x0 + ((x1 - x0) * i) / n, y = y0 + ((y1 - y0) * i) / n;
          r.rect(Math.round(x - (w - 1) / 2) + ox, Math.round(y - (w - 1) / 2) + oy, w, w, c);
        }
      },
    };
    return p;
  }

  const BUILD = {
    normal: { head: 10, headH: 10, tw: 8, th: 8, leg: [4, 3], arm: [4, 4], aw: 2, lw: 2 },
    big: { head: 10, headH: 10, tw: 10, th: 8, leg: [4, 3], arm: [4, 4], aw: 3, lw: 3 },
    small: { head: 10, headH: 9, tw: 7, th: 6, leg: [3, 3], arm: [3, 3], aw: 2, lw: 2 },
    tall: { head: 9, headH: 10, tw: 8, th: 9, leg: [5, 4], arm: [4, 5], aw: 2, lw: 2 },
    child: { head: 9, headH: 8, tw: 6, th: 5, leg: [3, 2], arm: [3, 2], aw: 2, lw: 2 },
  };
  function metrics(L) {
    const B = BUILD[L.build || 'normal'] || BUILD.normal;
    const foot = 30, ankle = foot - 2;
    const hip = ankle - (B.leg[0] + B.leg[1]);
    const sh = hip - B.th;
    const headB = sh + 1, headT = headB - B.headH + 1;
    return { B, foot, ankle, hip, sh, headB, headT };
  }
  const has = (L, k) => (L.extras || []).indexOf(k) >= 0;
  const darkSkin = (c) => { const [r, g, b] = G.rgb(c); return r * 0.3 + g * 0.59 + b * 0.11 < 115; };

  // ---------------------------------------------------------------- hair
  const LONG = { long: 1, platinum: 1, white: 1, wavy: 1, braids: 1 };
  function hair(t, L, f, viewName) {
    const st = L.hairStyle || 'short';
    const h = L.hair || '#2a2030', hd = G.shade(h, -0.25), hl = G.shade(h, 0.3);
    const { hx0, hx1, hT, hB, sh, hip, cx } = f;
    if (st === 'bald') { if (viewName !== 'back') t.set(cx - 2, hT + 1, G.shade(L.skin, 0.25)); return; }
    if (st === 'shaved' || st === 'shavedbraid') {
      t.row(hT, hx0 + 1, hx1 - 1, G.shade(L.skin, -0.12)); t.row(hT + 1, hx0, hx1, G.shade(L.skin, -0.08));
      if (st === 'shavedbraid') {
        const bx = viewName === 'side' ? hx0 : viewName === 'back' ? cx : hx1 + 1;
        t.col(bx, hT + 4, sh + 7, h); t.col(bx + (viewName === 'front' ? 0 : 1), hT + 5, sh + 6, hd);
        for (let y = hT + 6; y < sh + 7; y += 3) t.set(bx, y, '#d8d8e8');
      }
      return;
    }
    if (st === 'buzz') { t.row(hT - 1, hx0 + 2, hx1 - 2, h); t.row(hT, hx0 + 1, hx1 - 1, h); t.row(hT + 1, hx0, hx1, hd); return; }
    if (st === 'undercut') {
      // shaved back and sides, the length swept up off the brow
      const stub = G.mix(L.skin, h, 0.42), stubD = G.shade(stub, -0.12);
      t.row(hT - 2, hx0 + 2, hx1 - 2, h); t.row(hT - 1, hx0 + 1, hx1 - 1, h); t.row(hT, hx0 + 1, hx1 - 1, h);
      t.row(hT - 2, cx - 1, cx, hl);
      if (viewName === 'side') { t.rect(hx0, hT + 1, 4, 4, stub); t.col(hx0, hT + 1, hT + 4, stubD); t.row(hT + 1, hx1 - 3, hx1, h); t.set(hx1, hT - 2, h); t.set(hx1 + 1, hT - 1, hl); }
      else if (viewName === 'back') { t.rect(hx0, hT + 1, hx1 - hx0 + 1, Math.max(1, hB - hT - 2), stub); t.row(hB - 1, hx0 + 1, hx1 - 1, stubD); }
      else { t.col(hx0, hT + 1, hT + 4, stub); t.col(hx1, hT + 1, hT + 4, stub); t.row(hT + 1, hx0 + 2, hx1 - 2, h); t.set(hx1 - 2, hT - 3, h); t.set(hx1 - 1, hT - 3, hl); }
      return;
    }
    const cap = () => { t.row(hT - 1, hx0 + 2, hx1 - 2, h); t.row(hT, hx0 + 1, hx1 - 1, h); t.rect(hx0, hT + 1, hx1 - hx0 + 1, 2, h); };
    cap();
    if (viewName === 'back') {
      t.rect(hx0, hT + 3, hx1 - hx0 + 1, hB - hT - 4, h);
      t.row(hB - 1, hx0 + 1, hx1 - 1, hd);
      if (LONG[st]) t.rect(hx0, hB - 1, hx1 - hx0 + 1, (st === 'wavy' ? sh + 6 : hip - 1) - hB + 2, hd);
      if (st === 'bob') t.rect(hx0, hB - 2, hx1 - hx0 + 1, 2, h);
      if (st === 'ponytail' || st === 'tied') { t.col(cx, hB - 1, sh + (st === 'tied' ? 1 : 6), hd); t.col(cx - 1, hB - 1, sh + (st === 'tied' ? 1 : 5), hd); }
      if (st === 'braids') { t.col(hx0 + 1, hB, sh + 7, h); t.col(hx1 - 1, hB, sh + 7, h); }
      if (st === 'wavy') { t.col(hx0 - 1, hT + 2, sh + 4, hd); t.col(hx1 + 1, hT + 2, sh + 4, hd); }
    } else if (viewName === 'side') {
      // back of the head on the left, fringe on the right
      t.rect(hx0, hT + 3, 4, 4, h);
      if (LONG[st]) t.rect(hx0, hT + 6, 3, hip - hT - 7, hd);
      if (st === 'bob' || st === 'curly') t.rect(hx0, hT + 6, 3, 3, h);
      if (st === 'ponytail') { t.col(hx0 - 1, hT + 3, sh + 5, hd); t.col(hx0 - 2, hT + 4, sh + 3, hd); }
      if (st === 'tied') t.rect(hx0 - 2, hT + 3, 2, 2, hd);
      if (st === 'braids') { t.col(hx0 + 1, hT + 6, sh + 7, hd); }
      if (st === 'wavy') { t.rect(hx0 - 1, hT + 2, 2, sh - hT + 4, hd); t.rect(hx1 - 1, hT + 3, 2, 4, h); }
      if (st !== 'neat' && st !== 'tied') t.row(hT + 3, hx1 - 3, hx1, h);
      if (st === 'messy' || st === 'spiky' || st === 'wild' || st === 'storm') { t.set(hx0 + 2, hT - 2, h); t.set(hx0 + 5, hT - 2, h); t.set(hx1 - 1, hT - 1, h); t.set(hx1, hT + 4, h); }
      if (st === 'storm') { t.set(hx0 + 3, hT - 3, h); t.set(hx0 + 6, hT - 3, h); }
      if (st === 'curly') { t.set(hx0 - 1, hT + 2, h); t.set(hx0 + 3, hT - 2, h); t.set(hx0 + 6, hT - 2, h); }
    } else {
      // front
      const fr = (y, x0, x1) => t.row(y, x0, x1, h);
      switch (st) {
        case 'messy': case 'spiky': case 'wild':
          [hx0 + 1, cx - 1, hx1 - 2].forEach((x) => t.set(x, hT - 2, h)); t.set(cx - 1, hT - 3, h);
          fr(hT + 3, hx0 + 1, hx0 + 2); fr(hT + 3, cx - 2, cx - 1); fr(hT + 3, cx + 1, cx + 2); t.set(hx1 - 1, hT + 3, h);
          t.set(hx0 + 1, hT + 4, h); t.set(cx + 1, hT + 4, h); t.set(hx1 - 1, hT + 4, h);
          t.col(hx0, hT + 3, hT + 5, h); t.col(hx1, hT + 3, hT + 5, h);
          if (st === 'wild') { t.col(hx0 - 1, hT + 2, hT + 7, h); t.col(hx1 + 1, hT + 2, hT + 7, h); }
          break;
        case 'curly':
          [hx0 + 1, hx0 + 2, cx - 1, cx, hx1 - 2, hx1 - 1].forEach((x) => t.set(x, hT - 2, h));
          for (let x = hx0 + 1; x < hx1; x += 2) t.set(x, hT + 3, h);
          t.col(hx0 - 1, hT + 1, hT + 5, h); t.col(hx1 + 1, hT + 1, hT + 5, h); t.col(hx0, hT + 3, hT + 6, h); t.col(hx1, hT + 3, hT + 6, h);
          break;
        case 'bob':
          fr(hT + 3, hx0 + 1, hx1 - 1);
          t.rect(hx0, hT + 3, 2, 6, h); t.rect(hx1 - 1, hT + 3, 2, 6, h);
          break;
        case 'storm':
          for (let x = hx0; x <= hx1; x += 2) t.col(x, hT - 3, hT - 1, h);
          t.col(hx0, hT + 3, hT + 6, h); t.col(hx1, hT + 3, hT + 6, h); fr(hT + 3, hx0 + 1, cx - 1);
          break;
        case 'neat': case 'tied': fr(hT + 3, hx0 + 1, cx + 1); t.col(hx0, hT + 3, hT + 4, h); t.col(hx1, hT + 3, hT + 4, h); break;
        case 'parted': fr(hT + 3, hx0 + 1, cx - 2); fr(hT + 3, cx + 1, hx1 - 1); t.col(hx0, hT + 3, hT + 5, h); t.col(hx1, hT + 3, hT + 5, h); break;
        default:
          fr(hT + 3, hx0 + 1, cx - 1); fr(hT + 3, cx + 2, hx1 - 1);
          t.col(hx0, hT + 3, hT + 5, h); t.col(hx1, hT + 3, hT + 5, h);
      }
      if (LONG[st]) {
        const end = st === 'wavy' ? sh + 4 : hB + 3;
        t.rect(hx0, hT + 3, st === 'wavy' ? 2 : 1, end - hT - 2, h); t.rect(hx1 - (st === 'wavy' ? 1 : 0), hT + 3, st === 'wavy' ? 2 : 1, end - hT - 2, h);
        if (st === 'wavy') { t.col(hx0 - 1, hT + 2, sh + 3, h); t.col(hx1 + 1, hT + 2, sh + 3, h); }
        if (st === 'braids') for (let y = hT + 6; y <= end; y += 3) { t.set(hx0, y, L.acc || G.C.gold); t.set(hx1, y, L.acc || G.C.gold); }
      }
      if (st === 'ponytail') { t.set(hx1 + 1, hT + 2, hd); t.col(hx1 + 1, hT + 3, hT + 6, hd); }
    }
    // a highlight along the crown
    t.row(hT, hx0 + 2, hx0 + 4, hl);
  }

  // hair that hangs behind the shoulders, drawn before the body (front view)
  function backHair(t, L, f) {
    const st = L.hairStyle;
    if (!LONG[st]) return;
    const hd = G.shade(L.hair || '#2a2030', -0.3);
    const end = st === 'wavy' ? f.sh + 7 : f.hip - 1;
    t.rect(f.hx0 - (st === 'wavy' ? 1 : 0), f.hT + 4, f.hx1 - f.hx0 + 1 + (st === 'wavy' ? 2 : 0), end - f.hT - 3, hd);
  }

  // ---------------------------------------------------------------- outfits and extras
  function outfitFront(t, L, f, back) {
    const { tx0, tx1, sh, hip, cx } = f;
    const main = L.main, sec = L.sec || G.shade(main, 0.35), acc = L.acc || G.C.gold;
    const o = L.outfit || 'shirt';
    if (back) {
      if (o === 'apron') t.row(sh + 3, tx0, tx1, sec);
      if (o === 'coat' || o === 'longcoat' || o === 'uniform') t.col(cx, sh + 2, hip, G.shade(main, -0.2));
      return;
    }
    switch (o) {
      case 'apron':
        t.rect(tx0 + 1, sh + 2, tx1 - tx0 - 1, hip - sh + 1, sec);
        t.col(tx0 + 1, sh, sh + 1, sec); t.col(tx1 - 1, sh, sh + 1, sec);
        t.row(sh + 4, tx0, tx0, sec); t.row(sh + 4, tx1, tx1, sec);
        break;
      case 'coat': case 'longcoat': case 'uniform':
        t.col(cx - 1, sh, hip - 1, sec); t.col(cx, sh, hip - 2, sec);
        t.set(cx - 2, sh + 1, sec); t.set(cx + 1, sh + 1, sec);
        if (o === 'uniform') { t.set(cx - 1, sh + 2, acc); t.set(cx - 1, sh + 4, acc); t.row(hip - 1, tx0, tx1, acc); t.set(tx0 - 1, sh, acc); t.set(tx1 + 1, sh, acc); }
        else t.row(hip - 1, tx0, tx1, G.shade(main, -0.25));
        break;
      case 'vest': t.rect(cx - 1, sh, 2, hip - sh, sec); break;
      case 'tank': t.rect(cx - 2, sh, 4, 2, L.skin); break;
      case 'overalls':
        t.rect(tx0, sh, tx1 - tx0 + 1, 3, sec);
        t.col(tx0 + 1, sh, sh + 2, main); t.col(tx1 - 1, sh, sh + 2, main);
        t.set(tx0 + 1, sh + 3, acc); t.set(tx1 - 1, sh + 3, acc);
        break;
      case 'armor':
        t.rect(tx0 - 1, sh, 3, 2, G.shade(main, 0.2)); t.rect(tx1 - 1, sh, 3, 2, G.shade(main, 0.2));
        t.row(sh + 2, tx0 + 1, tx1 - 1, G.shade(main, 0.35));
        t.row(hip - 1, tx0, tx1, acc);
        break;
      case 'robe': case 'dress': case 'gown':
        t.rect(cx - 1, sh, 2, 2, o === 'gown' ? L.skin : sec);
        if (o === 'gown') t.row(sh + 2, tx0, tx1, acc);
        break;
      case 'wraps': t.row(sh + 3, tx0, tx1, sec); t.row(hip - 1, tx0, tx1, acc); break;
      case 'rags': t.set(tx0 + 1, sh + 3, sec); t.set(tx1 - 1, hip - 2, sec); t.set(cx, sh + 5, sec); break;
      default: t.row(hip - 1, tx0, tx1, acc); t.set(cx - 1, sh, G.shade(main, 0.3)); t.set(cx, sh, G.shade(main, 0.3));
    }
  }

  function extrasHead(t, L, f, viewName) {
    const { hx0, hx1, hT, hB, cx, sh, e0, e1 } = f;
    const side = viewName === 'side', back = viewName === 'back';
    if (L.ears) {
      // long pointed ears (goblins)
      const ec = L.skin, ed = G.shade(L.skin, -0.25);
      if (side) { t.row(e0 - 1, hx0 - 3, hx0, ec); t.row(e0, hx0 - 2, hx0, ed); t.set(hx0 - 4, e0 - 2, ec); }
      else {
        t.row(e0 - 1, hx0 - 3, hx0 - 1, ec); t.row(e0, hx0 - 2, hx0 - 1, ed); t.set(hx0 - 4, e0 - 2, ec);
        t.row(e0 - 1, hx1 + 1, hx1 + 3, ec); t.row(e0, hx1 + 1, hx1 + 2, ed); t.set(hx1 + 4, e0 - 2, ec);
      }
    }
    if (has(L, 'beard')) {
      const b = L.beard || L.hair;
      if (!back) { t.rect(hx0 + (side ? 4 : 1), e1 + 2, side ? hx1 - hx0 - 3 : hx1 - hx0 - 1, hB - e1 - 1, b); t.row(hB + 1, side ? hx0 + 5 : hx0 + 2, side ? hx1 - 1 : hx1 - 2, b); }
      if (has(L, 'bells')) { t.set(cx - 1, hB + 1, G.C.gold); t.set(cx + 1, hB, G.C.gold); }
    }
    if (has(L, 'mustache') && !back) t.row(e1 + 2, side ? cx + 1 : cx - 2, side ? hx1 : cx + 1, L.beard || L.hair);
    if (has(L, 'glasses') && !back) {
      const g = L.glassC || '#2a2a3a';
      if (side) { t.row(e0, hx1 - 3, hx1, g); t.set(hx1 - 2, e0, '#cfe8ff'); }
      else { t.row(e0, hx0 + 1, hx1 - 1, g); t.set(cx - 2, e0, '#cfe8ff'); t.set(cx + 1, e0, '#cfe8ff'); }
    }
    if (has(L, 'spectacles') && !back) { if (side) t.row(e0, hx1 - 3, hx1, '#8a5a1a'); else { t.row(e0, hx0 + 1, hx1 - 1, '#6a4a1a'); t.set(cx - 2, e0, '#d89a3a'); t.set(cx + 1, e0, '#d89a3a'); } }
    if (has(L, 'rose') && !back) { const rx = side ? hx0 + 2 : hx1; t.rect(rx, hT + 2, 2, 2, '#e8344e'); t.set(rx, hT + 2, '#ff8a9e'); t.set(rx, hT + 4, '#3a8a4a'); }
    if (has(L, 'earring') && !back) t.set(side ? hx0 + 3 : hx0, e1 + 1, L.earC || G.C.gold);
    if (has(L, 'scar') && viewName === 'front') { t.set(cx + 2, e1 + 1, '#d8b8a8'); t.set(cx + 3, e1 + 2, '#d8b8a8'); }
    if (has(L, 'patch') && viewName === 'front') { t.rect(cx + 1, e0 - 1, 3, 3, '#1a1420'); t.row(e0 - 2, hx0, hx1, '#1a1420'); }
    if (has(L, 'beret')) {
      const b = L.beret || '#e8607e';
      t.row(hT - 2, hx0 + 1, hx1 - 1, b); t.row(hT - 1, hx0, hx1 + 1, b); t.set(hx1 + 1, hT, b);
      [['#ffd36a', hx0 + 2], ['#6ad3ff', cx], ['#8af07a', hx1 - 1]].forEach(([c, x]) => t.set(x, hT - 1, c));
      t.set(cx, hT - 3, '#3a2a2a');
    }
    if (has(L, 'shako')) { const c = L.hat || L.main; t.rect(hx0 + 1, hT - 4, hx1 - hx0 - 1, 5, c); t.row(hT + 1, hx0, hx1, G.shade(c, -0.35)); if (!back) t.set(cx, hT - 3, L.acc || G.C.gold); }
    if (has(L, 'cap')) { const c = L.hat || L.main; t.row(hT - 1, hx0 + 1, hx1 - 1, c); t.rect(hx0, hT, hx1 - hx0 + 1, 2, c); if (side) t.row(hT + 2, hx1 - 2, hx1 + 2, G.shade(c, -0.35)); else if (!back) t.row(hT + 2, hx0, hx1, G.shade(c, -0.35)); }
    if (has(L, 'hood')) {
      const c = L.hood || L.main;
      t.row(hT - 1, hx0 + 1, hx1 - 1, c); t.rect(hx0 - 1, hT, hx1 - hx0 + 3, 3, c);
      if (back) t.rect(hx0 - 1, hT, hx1 - hx0 + 3, hB - hT + 2, c);
      else if (side) t.rect(hx0 - 1, hT, 6, hB - hT + 2, c);
      else { t.col(hx0 - 1, hT, hB + 1, c); t.col(hx0, hT + 3, hB, c); t.col(hx1 + 1, hT, hB + 1, c); t.col(hx1, hT + 3, hB, c); }
    }
    if (has(L, 'veil')) {
      const c = L.hood || '#8a8a96';
      t.row(hT - 1, hx0 + 1, hx1 - 1, c); t.rect(hx0 - 1, hT, hx1 - hx0 + 3, 4, c);
      if (back || side) t.rect(hx0 - 1, hT, back ? hx1 - hx0 + 3 : 7, sh - hT + 3, c);
      else { t.col(hx0 - 1, hT, sh + 2, c); t.col(hx1 + 1, hT, sh + 2, c); t.rect(hx0, e1 + 1, hx1 - hx0 + 1, hB - e1, c); t.set(cx - 2, e0 + 1, '#f4f4ff'); t.set(cx + 1, e0 + 1, '#f4f4ff'); }
    }
    if (has(L, 'helmet')) {
      const c = L.helm || '#d8dce8';
      t.row(hT - 1, hx0 + 1, hx1 - 1, c); t.rect(hx0, hT, hx1 - hx0 + 1, 4, c);
      t.row(hT, hx0 + 2, hx0 + 4, G.shade(c, 0.4));
      if (back) t.rect(hx0, hT, hx1 - hx0 + 1, hB - hT, c);
      else if (side) { t.rect(hx0, hT, 5, hB - hT, c); t.row(hT + 4, hx0 + 5, hx1, G.shade(c, -0.5)); }
      else { t.col(hx0, hT + 4, hB - 2, c); t.col(hx1, hT + 4, hB - 2, c); t.row(hT + 4, hx0 + 1, hx1 - 1, G.shade(c, -0.5)); }
      if (L.plume) { t.col(cx, hT - 4, hT - 2, L.plume); t.col(cx - 1, hT - 3, hT - 2, L.plume); }
    }
    if (has(L, 'mask') && !back) { const c = L.maskC || '#c9a35d'; const x0 = side ? hx1 - 4 : hx0 + 1; t.rect(x0, e0 - 1, side ? 5 : hx1 - hx0 - 1, 4, c); t.set(side ? hx1 - 2 : cx - 2, e0, '#120c1a'); if (!side) t.set(cx + 1, e0, '#120c1a'); }
    if (has(L, 'bonemask') && !back) { const c = '#ece6d4'; const x0 = side ? hx1 - 5 : hx0 + 1; t.rect(x0, hT + 2, side ? 6 : hx1 - hx0 - 1, hB - hT - 2, c); t.rect(side ? hx1 - 2 : cx - 2, e0, 1, 2, '#120c1a'); if (!side) t.rect(cx + 1, e0, 1, 2, '#120c1a'); }
    if (L.trinket && L.trinket.kind === 'circlet') {
      const T = L.trinket;
      if (side) { t.row(hT + 2, hx0 + 2, hx1, T.c); if (T.gem) t.set(hx1 - 1, hT + 2, T.gem); }
      else { t.row(hT + 2, hx0, hx1, T.c); if (T.gem && !back) t.set(cx - 1, hT + 2, T.gem); }
    }
    if (has(L, 'crown')) { t.row(hT - 1, hx0 + 1, hx1 - 1, G.C.gold); [hx0 + 1, cx - 1, cx + 1, hx1 - 1].forEach((x) => t.set(x, hT - 2, G.C.gold)); if (!back) t.set(cx, hT - 1, '#e8344e'); }
  }

  function extrasBody(t, L, f, viewName) {
    const { tx0, tx1, sh, cx } = f;
    if (has(L, 'scarf')) { const s = L.scarf || L.acc || G.C.gold; t.rect(tx0 - 1, sh, tx1 - tx0 + 3, 2, s); if (viewName === 'front') t.col(tx1, sh + 2, sh + 5, s); if (viewName === 'side') { t.col(tx0 - 1, sh + 2, sh + 5, s); t.col(tx0 - 2, sh + 3, sh + 6, G.shade(s, -0.2)); } if (viewName === 'back') t.col(cx, sh + 2, sh + 6, s); }
    if (has(L, 'lantern') && viewName !== 'back') { const lx = viewName === 'side' ? tx1 - 1 : cx - 1; t.rect(lx, sh + 2, 2, 3, '#fff2a8'); t.set(lx, sh + 2, '#ffffff'); }
    if (has(L, 'gear') && viewName !== 'back') { t.set(cx - 1, sh, '#c98a2a'); t.set(cx, sh, '#e8b84a'); }
  }

  // ---------------------------------------------------------------- worn gear
  // armour over the clothes: a breastplate, pauldrons, bracers and greaves; chain is checkered
  function armorCols(L) {
    const a = L.armor; if (!a) return null;
    const has = (k) => a.pieces.indexOf(k) >= 0;
    return { has, c: a.plate, d: G.shade(a.plate, -0.32), l: G.shade(a.plate, 0.3), trim: a.trim || G.shade(a.plate, -0.2), chain: a.chain, glow: a.glow, stars: a.stars };
  }
  function wearTorso(t, L, x0, x1, sh, back, side) {
    const A = armorCols(L);
    if (A && A.has('breast')) {
      t.rect(x0 + 1, sh + 1, x1 - x0 - 1, 5, back ? A.d : A.c);
      if (!back) { t.row(sh + 1, x0 + 2, x1 - 2, A.l); if (!side) t.col(x1 - 1, sh + 2, sh + 5, A.d); }
      t.row(sh + 6, x0, x1, A.trim);
      if (A.chain) for (let y = sh + 2; y <= sh + 5; y++) for (let x = x0 + 1; x < x1; x++) if ((x + y) % 2) t.set(x, y, A.d);
      if (A.glow && !back) t.set(Math.round((x0 + x1) / 2), sh + 3, A.glow);
    }
    if (A && A.has('mantle')) { t.row(sh, x0 - 1, x1 + 1, A.trim); if (!back) t.set(x1, sh + 1, A.trim); }
    if (A && A.stars && back) { t.set(x0 + 1, sh + 6, '#ffffff'); t.set(x1 - 1, sh + 10, '#bfe8ff'); t.set(x0 + 3, sh + 13, '#ffffff'); }
    const T = L.trinket;
    if (T && T.kind === 'amulet' && !back) { const cx = side ? x1 : Math.round((x0 + x1) / 2); t.set(cx - 1, sh + 1, T.c); t.set(cx + (side ? -1 : 1), sh + 1, T.c); t.set(cx, sh + 2, T.gem || T.c); }
    if (T && T.kind === 'charm') { t.set(side ? x0 : x1 - 1, sh + 9, T.c); t.set(side ? x0 : x1 - 1, sh + 10, G.shade(T.c, 0.3)); }
  }
  function wearShoulders(t, L, xs, sh) {
    const A = armorCols(L);
    if (!A || !A.has('pauldrons')) return;
    xs.forEach((x) => { t.rect(x - 1, sh - 1, 4, 3, A.c); t.row(sh - 1, x, x + 1, A.l); t.row(sh + 1, x - 1, x + 2, A.trim); });
  }

  // ---------------------------------------------------------------- weapons
  // (hx, hy) hand; a = angle (0 down, 90 forward, 180 up); x = slide along the shaft
  function weapon(t, kind, hx, hy, a, x, L) {
    const dx = Math.sin(rad(a)), dy = Math.cos(rad(a));
    const at = (d) => [hx + dx * (d + (x || 0)), hy + dy * (d + (x || 0))];
    const seg = (d0, d1, w, c) => { const [x0, y0] = at(d0), [x1, y1] = at(d1); t.thick(x0, y0, x1, y1, w, c); };
    const perp = (d, len, c) => { const [px, py] = at(d); t.thick(px - dy * len, py + dx * len, px + dy * len, py - dx * len, 1, c); };
    switch (kind) {
      case 'sword': seg(1, 10, 1, '#e6ecff'); seg(2, 9, 1, '#e6ecff'); perp(1, 2, L.hilt || G.C.gold); seg(-1, 0, 1, '#6a4a2a'); { const [a1, b1] = at(10); t.set(a1, b1, '#ffffff'); } break;
      case 'knife': seg(1, 4, 1, '#e6ecff'); perp(1, 1, '#9aa1c4'); break;
      case 'cleaver': seg(-1, 0, 1, '#5a3a2a'); seg(1, 5, 2, '#d8dce8'); { const [px, py] = at(5); t.set(px, py, '#ffffff'); } break;
      case 'sling': seg(0, 4, 1, '#8a6a4a'); { const [px, py] = at(5); t.rect(px - 1, py - 1, 2, 2, '#9a948a'); } break;
      case 'bomb': { const [px, py] = at(2); t.rect(px - 1, py - 2, 4, 4, '#2a2a30'); t.set(px, py - 2, '#5a5a66'); t.set(px + 2, py - 3, '#8a6a4a'); t.set(px + 3, py - 4, '#ffb347'); } break;
      case 'prism': seg(1, 10, 2, '#bff0ff'); seg(3, 4, 2, '#ffb0e0'); seg(6, 7, 2, '#fff0a0'); perp(1, 2, '#e8607e'); break;
      case 'skillet': seg(0, 3, 1, '#5a4a3a'); { const [px, py] = at(5); t.rect(px - 2, py - 1, 4, 3, '#3a3a44'); t.row(py - 1, px - 2, px + 1, '#5a5a66'); } break;
      case 'poker': seg(-1, 7, 1, '#5a5a66'); { const [px, py] = at(7); t.set(px + dy, py - dx, '#5a5a66'); } break;
      case 'brush': seg(-1, 5, 1, '#c9a35d'); { const [px, py] = at(6); t.rect(px - 0.5, py - 0.5, 2, 2, '#e8607e'); } break;
      case 'lance': seg(-5, 12, 1, '#8a6a4a'); seg(12, 15, 1, '#e6ecff'); { const [px, py] = at(16); t.set(px, py, '#ffffff'); } break;
      case 'staff': seg(-6, 2, 1, '#1a1a22'); seg(2, 11, 1, L.staffC || '#f4f4f4'); { const [px, py] = at(11); t.set(px, py, G.C.gold); } break;
      case 'crossbow': seg(-1, 6, 1, '#6a4a2a'); perp(5, 3, '#9a7a4a'); { const [px, py] = at(6); t.set(px, py, '#9aa1c4'); } break;
      case 'rifle': seg(-3, 9, 1, '#5a4a3a'); seg(5, 10, 1, '#7a7e8a'); break;
      case 'book': { t.rect(hx - 1, hy - 2, 3, 4, L.bookC || '#8e2f4a'); t.set(hx - 1, hy - 2, G.C.gold); } break;
      case 'orb': case 'flame': {
        const c = kind === 'flame' ? '#ffb347' : L.orbC || '#bfe0ff';
        t.rect(hx - 1, hy - 3, 3, 3, c); t.set(hx, hy - 2, '#ffffff');
        if (kind === 'flame') t.set(hx, hy - 4, '#ff6a3a');
      } break;
    }
  }
  const STYLE_WEAPON = {
    slash: ['sword', 'knife', 'knives', 'prism', 'skillet', 'poker', 'brush', 'cleaver', 'bomb'],
    thrust: ['lance', 'staff'],
    shoot: ['crossbow', 'rifle', 'sling'],
  };
  function visualWeapon(L, style) {
    const held = L.held === 'knives' ? 'knife' : L.held;
    if (!style) return held;
    if (style === 'slash') return STYLE_WEAPON.slash.indexOf(L.held) >= 0 ? held : 'sword';
    if (style === 'thrust') return STYLE_WEAPON.thrust.indexOf(L.held) >= 0 ? held : 'lance';
    if (style === 'shoot') return STYLE_WEAPON.shoot.indexOf(L.held) >= 0 ? held : 'crossbow';
    return null;
  }

  // ---------------------------------------------------------------- front and back
  function frame(L) {
    const M = metrics(L);
    return M;
  }
  function drawFront(r, L, P, back) {
    const t = view(r, OX, OY);
    const M = frame(L), B = M.B;
    const u = P.bob || 0;
    const cx = 12;
    const f = {
      cx, tx0: cx - B.tw / 2, tx1: cx + B.tw / 2 - 1, sh: M.sh + u, hip: M.hip,
      hT: M.headT + u, hB: M.headB + u, hx0: cx - Math.ceil(B.head / 2), hx1: cx - Math.ceil(B.head / 2) + B.head - 1,
    };
    f.e0 = f.hT + 5; f.e1 = f.hT + 6;
    const skin = L.skin, main = L.main, pants = L.pants || G.shade(main, -0.35), boots = L.boots || '#3a2a2a';
    const o = L.outfit || 'shirt';
    const skirt = o === 'dress' || o === 'gown' || o === 'robe';
    if (L.cape) t.rect(f.tx0 - 2, f.sh + 1, B.tw + 4, M.hip - f.sh + 6, back ? L.cape : G.shade(L.cape, -0.3));
    if (!back) backHair(t, L, f);
    // legs
    const lw = B.lw;
    const legX = [cx - 1 - lw, cx + 1];
    for (let i = 0; i < 2; i++) {
      const lift = (P.lift || [0, 0])[i];
      if (!skirt) for (let x = legX[i]; x < legX[i] + lw; x++) t.col(x, M.hip, M.ankle - lift, pants);
      t.rect(legX[i] - (i === 0 ? 1 : 0), M.ankle + 1 - lift, lw + 1, 2, boots);
      const A = armorCols(L);
      if (A && A.has('greaves') && !skirt) { t.rect(legX[i], M.ankle - 3 - lift, lw, 3, back ? A.d : A.c); t.row(M.ankle - 3 - lift, legX[i], legX[i] + lw - 1, A.l); }
    }
    if (skirt) {
      const sk = main;
      for (let y = M.hip; y <= M.ankle; y++) { const k = Math.floor((y - M.hip) / 3); t.row(y, f.tx0 - k, f.tx1 + k, sk); }
      t.row(M.ankle, f.tx0 - 3, f.tx1 + 3, o === 'gown' ? (L.acc || G.C.gold) : G.shade(main, -0.25));
      t.col(f.tx1 + 2, M.hip + 3, M.ankle - 1, G.shade(main, -0.2));
    }
    // torso
    t.rect(f.tx0, f.sh + 1, B.tw, M.hip - f.sh, main);
    t.row(f.sh, f.tx0 + 1, f.tx1 - 1, main);
    t.col(f.tx1, f.sh + 1, M.hip, G.shade(main, -0.18));
    if ((o === 'coat' || o === 'longcoat') && !skirt) { const len = o === 'longcoat' ? 4 : 2; t.rect(f.tx0, M.hip, 3, len, main); t.rect(f.tx1 - 2, M.hip, 3, len, G.shade(main, -0.1)); }
    // arms
    const aw = B.aw, alen = B.arm[0] + B.arm[1];
    const sleeve = o === 'vest' || o === 'tank' ? skin : o === 'robe' ? G.shade(main, -0.08) : main;
    const hand = L.gloves || (o === 'armor' ? G.shade(main, 0.1) : skin);
    const hands = [];
    const late = [];
    [-1, 1].forEach((side, i) => {
      const ax = side < 0 ? f.tx0 - aw : f.tx1 + 1;
      const rch = P.reach ? P.reach[i] : 0;
      if (rch || P.raise) {
        const sl = side > 0 ? G.shade(sleeve, -0.12) : sleeve;
        if (back && rch > 0) {
          // a blow thrown away from the viewer: the arm goes up past the head, the fist above it
          const top = f.hT - 1 - Math.round(2 * rch);
          t.rect(ax, top + 3, aw, f.sh + 2 - top - 3, sl);
          t.rect(ax - 1, top, aw + 1, 3, hand); t.row(top, ax - 1, ax + aw - 1, G.shade(hand, 0.15));
          hands.push([ax, top]);
        } else if (back || P.raise || rch < 0) {
          // raised to cast, or drawn back to wind up (rch < 0): the fist beside the head
          const top = f.sh - 3 - Math.round(3 * Math.abs(rch || 1));
          t.rect(ax, top, aw, f.sh + 2 - top, sl);
          t.rect(ax, top - 2, aw, 2, hand);
          hands.push([ax, top - 2]);
        } else {
          // a blow thrown toward the viewer: the arm drives down across the body and the fist,
          // bigger for being nearer, breaks the silhouette below the belt
          const fx = side < 0 ? cx - 4 : cx + 1, fy = f.hip - 1 + Math.round(2 * rch);
          t.rect(ax, f.sh + 1, aw, 3, sl);
          late.push(() => {
            t.thick(ax + (side < 0 ? 1 : 0), f.sh + 3, fx + 1, fy, aw, sl);
            t.rect(fx - 1, fy, aw + 3, 4, hand); t.row(fy, fx - 1, fx + aw + 1, G.shade(hand, 0.18)); t.row(fy + 3, fx - 1, fx + aw + 1, G.shade(hand, -0.15));
          });
          hands.push([fx + 1, fy + 3]);
        }
        return;
      }
      const sw = (P.swing || [0, 0])[i];
      const w = o === 'robe' ? aw + 1 : aw;
      const x0 = side < 0 && o === 'robe' ? ax - 1 : ax;
      t.rect(x0, f.sh + 1, w, alen - 1 + sw, side > 0 ? G.shade(sleeve, -0.12) : sleeve);
      t.rect(ax, f.sh + alen + sw, aw, 2, hand);
      const A = armorCols(L);
      if (A && A.has('bracers')) t.rect(ax, f.sh + alen - 3 + sw, aw, 2, side > 0 ? A.d : A.c);
      hands.push([ax + (side > 0 ? aw - 1 : 0), f.sh + alen + sw + 1]);
    });
    outfitFront(t, L, f, back);
    wearTorso(t, L, f.tx0, f.tx1, f.sh, back, false);
    wearShoulders(t, L, [f.tx0 - 2, f.tx1], f.sh + 1);
    late.forEach((fn) => fn());
    if (L.trinket && L.trinket.kind === 'ring' && !back) t.set(hands[1][0], hands[1][1], L.trinket.gem || L.trinket.c);
    // head
    const hw = B.head;
    t.row(f.hT, f.hx0 + 2, f.hx1 - 2, skin);
    t.row(f.hT + 1, f.hx0 + 1, f.hx1 - 1, skin);
    t.rect(f.hx0, f.hT + 2, hw, f.hB - f.hT - 3, skin);
    t.row(f.hB - 1, f.hx0 + 1, f.hx1 - 1, skin);
    t.row(f.hB, f.hx0 + 2, f.hx1 - 2, skin);
    if (!back) {
      t.col(f.hx1, f.hT + 3, f.hB - 2, G.shade(skin, -0.12));
      const eye = L.eyes || '#20182c';
      if (P.blink || P.hurt) { t.row(f.e1, cx - 3, cx - 2, G.shade(skin, -0.45)); t.row(f.e1, cx + 1, cx + 2, G.shade(skin, -0.45)); }
      else {
        t.col(cx - 2, f.e0, f.e1, eye); t.col(cx + 1, f.e0, f.e1, eye);
        if (L.eyeGlow) { t.set(cx - 2, f.e0, L.eyeGlow); t.set(cx + 1, f.e0, L.eyeGlow); }
        else if (darkSkin(skin)) { t.set(cx - 2, f.e0, '#f4eee8'); t.set(cx + 1, f.e0, '#f4eee8'); }
        else { t.set(cx - 3, f.e0, G.shade(L.hair || '#2a2030', -0.1)); t.set(cx + 2, f.e0, G.shade(L.hair || '#2a2030', -0.1)); }
      }
      if (P.hurt) t.rect(cx - 1, f.e1 + 2, 2, 1, '#5a2a2a');
      if (L.blush) { t.set(cx - 3, f.e1 + 1, L.blush); t.set(cx + 2, f.e1 + 1, L.blush); }
    }
    hair(t, L, f, back ? 'back' : 'front');
    extrasHead(t, L, f, back ? 'back' : 'front');
    extrasBody(t, L, f, back ? 'back' : 'front');
    // what they carry, at rest
    const wv = visualWeapon(L);
    const blow = !!(P.reach || P.raise);
    if (wv && (!back || blow)) {
      const [hx, hy] = hands[1];
      const restA = { sword: 165, knife: 170, prism: 165, lance: 180, staff: 180, rifle: 150, crossbow: 120, skillet: 140, poker: 170, brush: 170 }[wv];
      const a = P.wa !== undefined ? P.wa : back && blow ? 180 : restA === undefined ? 180 : restA;
      weapon(t, wv, hx + 1, hy - 1, a, wv === 'lance' || wv === 'staff' ? -2 : 0, L);
      if (L.held === 'knives') weapon(t, 'knife', hands[0][0] - 1, hands[0][1] - 1, 190, 0, L);
    }
    return f;
  }

  // ---------------------------------------------------------------- side view (facing right)
  function limb(t, x, y, a1, l1, a2, l2, w, c1, c2) {
    const ex = x + Math.sin(rad(a1)) * l1, ey = y + Math.cos(rad(a1)) * l1;
    const hx = ex + Math.sin(rad(a1 + a2)) * l2, hy = ey + Math.cos(rad(a1 + a2)) * l2;
    t.thick(x, y, ex, ey, w, c1);
    t.thick(ex, ey, hx, hy, w, c2 || c1);
    return [hx, hy, ex, ey];
  }
  function drawSide(r, L, P) {
    const t = view(r, OX, OY);
    const M = frame(L), B = M.B;
    const lean = P.lean || 0, crouch = P.crouch || 0, u = (P.bob || 0) + crouch;
    const cx = 12 + lean;
    const tw = Math.max(5, B.tw - 2);
    const f = {
      cx, tx0: cx - Math.floor(tw / 2), tx1: cx - Math.floor(tw / 2) + tw - 1, sh: M.sh + u, hip: M.hip + crouch,
      hT: M.headT + u, hB: M.headB + u, hx0: cx - 5, hx1: cx - 5 + B.head - 1,
    };
    f.e0 = f.hT + 5; f.e1 = f.hT + 6;
    const skin = L.skin, main = L.main, pants = L.pants || G.shade(main, -0.35), boots = L.boots || '#3a2a2a';
    const o = L.outfit || 'shirt';
    const skirt = o === 'dress' || o === 'gown' || o === 'robe';
    const sleeve = o === 'vest' || o === 'tank' ? skin : main;
    const hand = L.gloves || (o === 'armor' ? G.shade(main, 0.1) : skin);
    const punchy = P.style === 'punch' || P.style === 'jab' || P.style === 'palm';
    const fist = punchy ? (L.gloves || '#b8c0d8') : hand;
    const hipX = 12 + lean * 0.4;
    if (L.cape) t.poly([[f.tx0, f.sh + 1], [f.tx0 + 2, f.sh + 1], [f.tx0 - 3 - lean, M.foot - 2], [f.tx0 - 6 - lean, M.foot - 3]], G.shade(L.cape, -0.2));
    // hair that hangs behind
    if (LONG[L.hairStyle]) t.rect(f.hx0, f.hT + 6, 3, f.hip - f.hT - 7, G.shade(L.hair || '#2a2030', -0.3));
    // far arm, behind everything
    const shX = cx, shY = f.sh + 2;
    const aF = P.armF || [-8, 8];
    const farH = limb(t, shX - 1, shY, aF[0], B.arm[0], aF[1], B.arm[1], B.aw, G.shade(sleeve, -0.3), G.shade(sleeve, -0.3));
    const farFist = P.style === 'jab' || P.style === 'palm' ? 3 : 2;
    t.rect(farH[0] - 1, farH[1] - 1, farFist, farFist, G.shade(fist, -0.25));
    // legs
    const legF = P.legF || [-4, 2], legN = P.legN || [4, -2];
    const boot = (p, c) => { t.rect(p[0] - 1, p[1], 3, 2, c); t.set(p[0] + 2, p[1] + 1, c); };
    const lf = limb(t, hipX - 1, f.hip, legF[0], B.leg[0], legF[1], B.leg[1] + 1, B.lw, G.shade(pants, -0.3));
    boot(lf, G.shade(boots, -0.25));
    const ln = limb(t, hipX, f.hip, legN[0], B.leg[0], legN[1], B.leg[1] + 1, B.lw, pants);
    boot(ln, boots);
    const SA = armorCols(L);
    if (SA && SA.has('greaves') && !skirt) [[lf, SA.d], [ln, SA.c]].forEach(([l, c]) => t.thick(l[2] + (l[0] - l[2]) * 0.25, l[3] + (l[1] - l[3]) * 0.25, l[2] + (l[0] - l[2]) * 0.8, l[3] + (l[1] - l[3]) * 0.8, B.lw, c));
    if (skirt) {
      t.poly([[f.tx0 - 1, f.hip - 1], [f.tx1 + 1, f.hip - 1], [f.tx1 + 4, M.ankle], [f.tx0 - 4, M.ankle]], main);
      t.row(M.ankle, f.tx0 - 4, f.tx1 + 3, o === 'gown' ? (L.acc || G.C.gold) : G.shade(main, -0.25));
    }
    // torso
    t.rect(f.tx0, f.sh + 1, tw, f.hip - f.sh, main);
    t.row(f.sh, f.tx0 + 1, f.tx1, main);
    t.col(f.tx0, f.sh + 2, f.hip, G.shade(main, -0.2));
    if (o === 'apron') { t.rect(f.tx1 - 1, f.sh + 2, 2, f.hip - f.sh + 1, L.sec || '#e8e0d0'); t.row(f.sh + 3, f.tx0, f.tx1, L.sec || '#e8e0d0'); }
    if (o === 'coat' || o === 'longcoat' || o === 'uniform') { t.col(f.tx1, f.sh + 1, f.hip - 1, L.sec || G.shade(main, 0.35)); t.rect(f.tx0 - 1, f.hip, 3, o === 'longcoat' ? 4 : 2, main); }
    if (o === 'uniform') t.row(f.hip - 1, f.tx0, f.tx1, L.acc || G.C.gold);
    if (o === 'armor') { t.rect(f.tx0, f.sh, 4, 3, G.shade(main, 0.25)); t.row(f.hip - 1, f.tx0, f.tx1, L.acc || G.C.gold); }
    if (o === 'overalls') { t.rect(f.tx0 + 1, f.sh + 1, tw - 1, 2, L.sec || '#f4ecd8'); }
    if (o === 'vest') t.rect(f.tx1 - 1, f.sh + 1, 2, f.hip - f.sh - 1, L.sec || '#e8e0d0');
    if (o === 'gown') t.row(f.sh + 2, f.tx0, f.tx1, L.acc || G.C.gold);
    if (!skirt && o !== 'apron') t.row(f.hip - 1, f.tx0, f.tx1, o === 'shirt' ? (L.acc || G.C.gold) : G.shade(main, -0.25));
    wearTorso(t, L, f.tx0, f.tx1, f.sh, false, true);
    extrasBody(t, L, f, 'side');
    // head
    t.row(f.hT, f.hx0 + 2, f.hx1 - 1, skin);
    t.row(f.hT + 1, f.hx0 + 1, f.hx1, skin);
    t.rect(f.hx0, f.hT + 2, B.head, f.hB - f.hT - 3, skin);
    t.row(f.hB - 1, f.hx0 + 2, f.hx1, skin);
    t.row(f.hB, f.hx0 + 3, f.hx1 - 1, skin);
    t.set(f.hx1 + 1, f.e1, skin); // nose
    t.col(f.hx0 + 3, f.e0, f.e1, G.shade(skin, -0.2)); // ear
    const eye = L.eyes || '#20182c';
    if (P.blink || P.hurt) t.row(f.e1, f.hx1 - 3, f.hx1 - 2, G.shade(skin, -0.45));
    else {
      t.col(f.hx1 - 2, f.e0, f.e1, eye);
      if (L.eyeGlow) t.set(f.hx1 - 2, f.e0, L.eyeGlow);
      else if (darkSkin(skin)) t.set(f.hx1 - 2, f.e0, '#f4eee8');
    }
    if (P.hurt || P.shout) t.set(f.hx1, f.e1 + 2, '#5a2a2a');
    hair(t, L, f, 'side');
    extrasHead(t, L, f, 'side');
    // near arm, then the weapon, then the hand on top of the grip
    const aN = P.armN || [8, -8];
    const nh = limb(t, shX, shY, aN[0], B.arm[0], aN[1], B.arm[1], B.aw, sleeve, sleeve);
    if (SA && SA.has('bracers')) t.thick(nh[2] + (nh[0] - nh[2]) * 0.35, nh[3] + (nh[1] - nh[3]) * 0.35, nh[2] + (nh[0] - nh[2]) * 0.8, nh[3] + (nh[1] - nh[3]) * 0.8, B.aw, SA.c);
    wearShoulders(t, L, [shX - 1], f.sh + 1);
    const kind = P.weapon === undefined ? visualWeapon(L, P.style) : P.weapon;
    if (kind) weapon(t, kind, nh[0], nh[1], P.wa === undefined ? 30 : P.wa, P.wx || 0, L);
    t.rect(nh[0] - 1, nh[1] - 1, punchy ? 3 : 2, punchy ? 3 : 2, fist);
    if (L.trinket && L.trinket.kind === 'ring') t.set(nh[0], nh[1] - 1, L.trinket.gem || L.trinket.c);
    // magic in the hands
    if (P.glow) {
      const [gx, gy] = P.glowAt === 'far' ? farH : nh;
      const c = P.glow, big = P.glowBig;
      t.rect(gx - (big ? 2 : 1), gy - (big ? 4 : 3), big ? 5 : 3, big ? 5 : 3, c);
      t.set(gx, gy - (big ? 2 : 2), '#ffffff');
    }
    return f;
  }

  // ---------------------------------------------------------------- poses
  const WALK_SIDE = [
    { legN: [25, -12], legF: [-22, -14], armN: [-26, 14], armF: [26, 18] },
    { legN: [12, -34], legF: [0, 0], armN: [-4, 8], armF: [4, 8], bob: -1 },
    { legN: [-22, -14], legF: [25, -12], armN: [26, 18], armF: [-26, 14] },
    { legN: [0, 0], legF: [12, -34], armN: [4, 8], armF: [-4, 8], bob: -1 },
  ];
  const ELEM = { flame: '#ffb347', bloom: '#ff7a9a', tide: '#7ad8ff', all: '#ffe28a', song: '#c8ffd8' };
  const POSES = {
    slash: {
      ready: { armN: [55, 45], wa: 150, armF: [20, 30], legN: [14, -8], legF: [-14, -6], crouch: 1 },
      windup: { armN: [168, 18], wa: 205, armF: [-24, 34], legN: [8, -4], legF: [-18, -10], lean: -1 },
      strike: { armN: [96, -6], wa: 84, armF: [-38, 20], legN: [42, -34], legF: [-38, -6], lean: 2, crouch: 2 },
      follow: { armN: [46, -12], wa: 22, armF: [-22, 12], legN: [32, -28], legF: [-32, -6], lean: 1, crouch: 1 },
    },
    punch: {
      ready: { armN: [64, 100], armF: [56, 104], legN: [16, -10], legF: [-16, -6], crouch: 1 },
      windup: { armN: [-44, 118], armF: [70, 96], legN: [10, -6], legF: [-22, -10], lean: -1, crouch: 1 },
      strike: { armN: [92, 0], armF: [36, 104], legN: [36, -28], legF: [-32, -6], lean: 2, crouch: 1, shout: 1 },
      follow: { armN: [80, 22], armF: [58, 96], legN: [26, -20], legF: [-26, -6], lean: 1, crouch: 1 },
    },
    jab: {
      ready: { armN: [64, 100], armF: [56, 104], legN: [16, -10], legF: [-16, -6], crouch: 1 },
      windup: { armN: [70, 96], armF: [-30, 110], legN: [10, -6], legF: [-22, -10], lean: -1, crouch: 1 },
      strike: { armN: [40, 100], armF: [94, 0], legN: [34, -26], legF: [-30, -6], lean: 2, crouch: 1, shout: 1 },
      follow: { armN: [56, 96], armF: [80, 20], legN: [24, -18], legF: [-24, -6], lean: 1, crouch: 1 },
    },
    palm: {
      ready: { armN: [64, 100], armF: [56, 104], legN: [16, -10], legF: [-16, -6], crouch: 1 },
      windup: { armN: [-40, 120], armF: [-50, 116], legN: [6, -4], legF: [-26, -12], lean: -2, crouch: 2 },
      strike: { armN: [98, -6], armF: [92, 0], legN: [46, -36], legF: [-40, -6], lean: 3, crouch: 2, shout: 1 },
      follow: { armN: [86, 4], armF: [80, 10], legN: [34, -26], legF: [-32, -6], lean: 2, crouch: 1 },
    },
    thrust: {
      ready: { armN: [70, -8], armF: [86, -22], wa: 96, legN: [14, -8], legF: [-14, -6], crouch: 1 },
      windup: { armN: [36, 14], armF: [54, 2], wa: 100, wx: -5, legN: [8, -4], legF: [-20, -10], lean: -1 },
      strike: { armN: [96, 0], armF: [104, -6], wa: 92, wx: 7, legN: [42, -34], legF: [-38, -6], lean: 2, crouch: 2 },
      follow: { armN: [86, 2], armF: [96, -6], wa: 90, wx: 3, legN: [30, -24], legF: [-30, -6], lean: 1, crouch: 1 },
    },
    shoot: {
      ready: { armN: [84, 6], armF: [96, -10], wa: 92, legN: [10, -6], legF: [-12, -4] },
      windup: { armN: [88, 0], armF: [98, -10], wa: 90, legN: [12, -6], legF: [-14, -4], crouch: 1 },
      strike: { armN: [78, 12], armF: [90, 0], wa: 98, legN: [10, -6], legF: [-14, -4], lean: -1 },
      follow: { armN: [84, 6], armF: [96, -10], wa: 92, legN: [10, -6], legF: [-12, -4] },
    },
    cast: {
      ready: { armN: [60, 52], armF: [40, 44], legN: [10, -6], legF: [-10, -4], glow: 1 },
      windup: { armN: [166, 8], armF: [150, 14], legN: [8, -4], legF: [-14, -6], lean: -1, glow: 1, glowBig: 1 },
      strike: { armN: [96, -4], armF: [90, 2], legN: [24, -16], legF: [-22, -6], lean: 1, glow: 1, glowBig: 1, shout: 1 },
      follow: { armN: [70, 20], armF: [52, 20], legN: [16, -10], legF: [-16, -6], glow: 1 },
    },
    sing: {
      ready: { armN: [44, 102], armF: [40, 104], legN: [6, -4], legF: [-6, -2], glow: 1 },
      windup: { armN: [60, 96], armF: [56, 98], legN: [6, -4], legF: [-6, -2], glow: 1, glowBig: 1, bob: -1 },
      strike: { armN: [120, 10], armF: [110, 16], legN: [6, -4], legF: [-6, -2], glow: 1, glowBig: 1, shout: 1 },
      follow: { armN: [44, 102], armF: [40, 104], legN: [6, -4], legF: [-6, -2], glow: 1 },
    },
  };
  const HURT = { armN: [-52, 40], armF: [-62, 30], legN: [-8, 8], legF: [-22, 6], lean: -2, hurt: 1, wa: -40 };
  const DODGE = { armN: [-18, 64], armF: [-30, 60], legN: [-24, -8], legF: [-38, -12], lean: -3, crouch: 1, wa: 200 };
  const STAND = { legN: [4, -3], legF: [-4, 3], armN: [8, -6], armF: [-6, 6], wa: 30 };
  AD.attackStyle = function (wtype) {
    return { blade: 'slash', fist: 'punch', pole: 'thrust', shot: 'shoot', flame: 'cast', bloom: 'cast', tide: 'cast', all: 'cast', song: 'sing' }[wtype] || 'slash';
  };

  // ---------------------------------------------------------------- mounted (horse and rider, facing right)
  const MW = 56, MH = 44, MOX = 12, MOY = 6;
  function drawMount(r, L, P) {
    const t = view(r, MOX, MOY);
    const horse = L.mount, hd = G.shade(horse, -0.22), hdd = G.shade(horse, -0.4);
    const ph = P.step || 0, lunge = P.lunge || 0, bob = P.bob || 0;
    const ox = lunge;
    // legs (far pair darker), a four-beat walk
    const leg = (x, y, a, c) => { const ex = x + Math.sin(rad(a)) * 7, ey = y + 8; t.thick(x, y, ex, ey, 2, c); t.rect(ex - 1, ey, 3, 1, '#2a2020'); };
    const sw = [[18, -14], [-14, 18], [10, -10], [-10, 10]][ph % 4];
    leg(9 + ox, 21, sw[1], hdd); leg(22 + ox, 21, sw[0], hdd);
    // body
    t.ellipse(15.5 + ox, 18 + bob, 9, 4.5, horse);
    t.poly([[20 + ox, 15 + bob], [24 + ox, 8 + bob], [28 + ox, 9 + bob], [25 + ox, 18 + bob]], horse);
    t.rect(25 + ox, 7 + bob, 5, 5, horse); t.rect(29 + ox, 9 + bob, 2, 3, hd); t.set(26 + ox, 6 + bob, horse); t.set(27 + ox, 8 + bob, '#1a1414');
    t.row(15 + bob, 9 + ox, 20 + ox, G.shade(horse, 0.25));
    const mane = L.mane || G.shade(horse, -0.45);
    for (let i = 0; i < 5; i++) t.set(23 + ox - i * 0.4, 9 + bob + i, mane), t.set(24 + ox - i * 0.4, 8 + bob + i, mane);
    t.thick(7 + ox, 15 + bob, 4 + ox, 22, 2, mane);
    if (L.barding) { t.rect(10 + ox, 13 + bob, 10, 3, L.barding); t.row(16 + bob, 10 + ox, 19 + ox, G.shade(L.barding, -0.3)); }
    leg(11 + ox, 21, sw[2], hd); leg(24 + ox, 21, sw[3], hd);
    // rider
    const main = L.main, skin = L.skin;
    const rx = 14 + ox + (P.lean || 0), ry = 4 + bob;
    t.rect(rx - 1, ry + 4, 6, 8, main);
    t.col(rx - 1, ry + 5, ry + 11, G.shade(main, -0.2));
    if ((L.extras || []).indexOf('lantern') >= 0) { t.rect(rx + 3, ry + 6, 2, 3, '#fff2a8'); t.set(rx + 3, ry + 6, '#ffffff'); }
    t.thick(rx + 2, ry + 12, rx + 6, ry + 13, 2, G.shade(main, -0.35)); t.thick(rx + 6, ry + 13, rx + 6, ry + 17, 2, G.shade(main, -0.35)); t.rect(rx + 5, ry + 17, 3, 2, '#3a2a2a');
    // head
    t.rect(rx - 2, ry - 4, 8, 8, skin); t.row(ry - 5, rx - 1, rx + 4, skin);
    const hairC = L.hair || main;
    t.row(ry - 5, rx - 1, rx + 4, hairC); t.rect(rx - 2, ry - 4, 8, 2, hairC); t.rect(rx - 2, ry - 2, 3, 3, hairC);
    if ((L.extras || []).indexOf('helmet') >= 0) { const c = L.helm || '#e0e4ee'; t.row(ry - 5, rx - 1, rx + 4, c); t.rect(rx - 2, ry - 4, 8, 3, c); t.rect(rx - 2, ry - 1, 3, 3, c); t.row(ry - 1, rx + 1, rx + 5, G.shade(c, -0.5)); if (L.plume) t.col(rx + 1, ry - 8, ry - 6, L.plume); }
    if (!P.hurt) t.col(rx + 4, ry, ry + 1, L.eyes || '#20182c'); else t.row(ry + 1, rx + 3, rx + 4, '#5a2a2a');
    // lance arm
    const la = P.wa === undefined ? 160 : P.wa;
    const nh = limb(t, rx + 2, ry + 6, P.arm ? P.arm[0] : 60, 4, P.arm ? P.arm[1] : -30, 4, 2, main, main);
    if (L.held === 'lance' || L.held === 'sword') weapon(t, L.held, nh[0], nh[1], la, P.wx || 0, L);
    t.rect(nh[0] - 1, nh[1] - 1, 2, 2, L.gloves || skin);
  }
  const MOUNT_POSES = {
    ready: { wa: 120, arm: [70, -20] },
    windup: { wa: 104, wx: -5, arm: [40, 10], lean: -1 },
    strike: { wa: 92, wx: 8, arm: [94, 0], lunge: 3, lean: 1 },
    follow: { wa: 96, wx: 4, arm: [86, 0], lunge: 1 },
  };

  // ---------------------------------------------------------------- big things (48x48, drawn at 1.5x)
  function big(r, k) {
    return {
      set: (x, y, c) => r.rect(Math.round(x * k), Math.round(y * k), Math.ceil(k), Math.ceil(k), c),
      rect: (x, y, w, h, c) => r.rect(Math.round(x * k), Math.round(y * k), Math.round(w * k), Math.round(h * k), c),
      ellipse: (cx, cy, rx, ry, c) => r.ellipse(cx * k, cy * k, rx * k, ry * k, c),
      poly: (pts, c) => r.poly(pts.map(([x, y]) => [x * k, y * k]), c),
      line: (x0, y0, x1, y1, c) => view(r, 0, 0).thick(x0 * k, y0 * k, x1 * k, y1 * k, Math.max(1, Math.round(k)), c),
    };
  }
  const BIG = {
    concordance(r, L, t) {
      const bob = t % 2;
      r.ellipse(16, 9 + bob, 7, 7, '#5a4a5a'); r.ellipse(16, 20 + bob, 11, 9, '#4a3a4a');
      r.rect(6, 22, 5, 9, '#3a2c3a'); r.rect(21, 22, 5, 9, '#3a2c3a');
      r.rect(2, 13 + bob, 5, 11, '#5a3a4a'); r.rect(25, 13 + bob, 5, 11, '#5a3a4a');
      for (let i = 0; i < 9; i++) r.line(8 + i * 2, 12 + (i % 3) * 3, 10 + i * 2, 26, '#cfd8e8');
      r.rect(12, 7 + bob, 8, 2, '#ffe28a'); r.set(13, 7 + bob, '#ffffff'); r.set(18, 7 + bob, '#ffffff');
    },
    tide(r, L, t) {
      const w = Math.sin(t / 2);
      r.ellipse(16, 15, 13, 13, '#1a3a5a'); r.ellipse(16, 15, 11, 11, '#4a7a9a'); r.ellipse(16 + w, 14, 8, 9, '#b8d0e0');
      r.rect(11 + w, 12, 3, 1, '#1a3a5a'); r.rect(18 + w, 12, 3, 1, '#1a3a5a'); r.rect(13 + w, 19, 6, 1, '#6a8aa0');
      for (let i = 0; i < 6; i++) r.set(5 + i * 4, 28 - (i % 2), '#7ab0d8');
    },
    nul(r, L, t) {
      r.ellipse(16, 7, 4, 5, '#000000'); r.rect(12, 11, 9, 13, '#000000'); r.rect(10, 12, 2, 9, '#000000'); r.rect(21, 12, 2, 9, '#000000');
      r.rect(13, 24, 3, 7, '#000000'); r.rect(17, 24, 3, 7, '#000000');
      for (let i = 0; i < 7; i++) r.set(12 + ((i * 7 + t) % 9), 12 + ((i * 5) % 12), '#2a2a44');
    },
    tessellate(r, L, t) {
      const pts = [];
      for (let i = 0; i < 7; i++) { const a = (i / 7) * Math.PI * 2 + t * 0.4; pts.push([16 + Math.cos(a) * 12, 16 + Math.sin(a) * 12]); }
      r.poly(pts, '#7a6ab8');
      r.poly(pts.map((p, i) => [16 + (p[0] - 16) * (i % 2 ? 0.45 : 0.75), 16 + (p[1] - 16) * (i % 2 ? 0.45 : 0.75)]), '#c8b8ff');
      r.line(4, 16, 28, 16, '#ffffff'); r.line(16, 4, 16, 28, '#e8e0ff');
    },
    haar(r, L, t) {
      for (let i = 0; i < 6; i++) r.ellipse(8 + i * 3.5, 16 + Math.sin(t / 2 + i) * 3, 6, 5, i % 2 ? '#9aa0a8' : '#b8bec6');
      r.set(13, 14, '#606870'); r.set(19, 14, '#606870');
    },
    sleeper(r, L, t) {
      const bob = t % 2;
      r.ellipse(16, 18 + bob, 13, 8, '#2a3a4a'); r.ellipse(26, 12 + bob, 5, 5, '#2a3a4a');
      r.rect(5, 23, 3, 8 - bob, '#1a2a3a'); r.rect(12, 23, 3, 7 + bob, '#1a2a3a'); r.rect(19, 23, 3, 8 - bob, '#1a2a3a'); r.rect(25, 22, 3, 8 + bob, '#1a2a3a');
      r.set(28, 11 + bob, '#ff5040'); r.set(25, 11 + bob, '#ff5040');
      for (let i = 0; i < 6; i++) r.set(8 + i * 3, 11 + (i % 2) + bob, '#4a6a8a');
    },
    sun(r, L, t) { r.ellipse(16, 16, 12 + (t % 2), 12 + (t % 2), '#ffcf5a'); r.ellipse(16, 16, 8, 8, '#fff2b0'); },
  };

  // ---------------------------------------------------------------- building frame sets
  function finish(r) { r.shade(0.12); r.outline(OUT); return r.canvas(); }
  function figFrame(L, P, viewName) {
    const r = new Ras(CW, CH);
    if (viewName === 'side') drawSide(r, L, P); else drawFront(r, L, P, viewName === 'back');
    return r;
  }
  function flipCanvas(c) {
    const o = G.canvas(c.width, c.height);
    o.x.translate(c.width, 0); o.x.scale(-1, 1); o.x.drawImage(c, 0, 0);
    return o;
  }
  function upscale(r, k) {
    const o = new Ras(r.w * k, r.h * k);
    for (let y = 0; y < r.h; y++) for (let x = 0; x < r.w; x++) { const c = r.get(x, y); if (c) o.rect(x * k, y * k, k, k, c); }
    return o;
  }

  const cache = {};
  S.unit = function (L) {
    const key = L.key || JSON.stringify(L);
    if (cache[key]) return cache[key];
    let out;
    if (L.big && L.big !== 'giant') {
      const fr = [0, 1, 2, 3].map((t) => { const r = new Ras(48, 48); BIG[L.big](big(r, 1.5), L, t); return finish(r); });
      out = { kind: 'big', w: 48, h: 48, ox: -12, oy: -23, idle: fr, down: fr, up: fr, right: fr, left: fr, blink: fr[0], stand: { down: fr[0], up: fr[0], right: fr[0], left: fr[0] } };
    } else if (L.big === 'giant') {
      const mk = (P, v) => { const r = figFrame(Object.assign({}, L, { big: null, build: L.build || 'big' }), P, v); r.shade(0.12); r.outline(OUT); return upscale(r, 2).canvas(); };
      const idle = [mk({}, 'front'), mk({ bob: 1 }, 'front')];
      const side = WALK_SIDE.map((p) => mk(Object.assign({}, STAND, p), 'side'));
      const st = mk(STAND, 'side');
      out = { kind: 'giant', w: 96, h: 80, ox: -36, oy: -46, idle: [idle[0], idle[0], idle[1], idle[1]], down: side, up: side, right: side, left: side.map(flipCanvas), blink: idle[0], scale: 2, stand: { down: idle[0], up: idle[0], right: st, left: flipCanvas(st) } };
    } else if (L.mount) {
      const mk = (P) => { const r = new Ras(MW, MH); drawMount(r, L, P); return finish(r); };
      const walk = [0, 1, 2, 3].map((s) => mk({ step: s, bob: s % 2 ? -1 : 0, wa: 150 }));
      const idle = [mk({ wa: 160 }), mk({ wa: 160, bob: 1 })];
      out = { kind: 'mount', w: MW, h: MH, ox: -16, oy: -12, idle: [idle[0], idle[0], idle[1], idle[1]], down: walk, up: walk.map(flipCanvas), right: walk, left: walk.map(flipCanvas), blink: idle[0], stand: { down: idle[0], up: flipCanvas(idle[0]), right: idle[0], left: flipCanvas(idle[0]) } };
    } else {
      const mk = (P, v) => finish(figFrame(L, P, v));
      const idle = [mk({}, 'front'), mk({ bob: 1, swing: [0, 0] }, 'front')];
      const blink = mk({ blink: 1 }, 'front');
      const walkF = [{ lift: [0, 2], swing: [1, -1] }, { bob: -1 }, { lift: [2, 0], swing: [-1, 1] }, { bob: -1 }];
      const down = walkF.map((p) => mk(p, 'front'));
      const up = walkF.map((p) => mk(p, 'back'));
      const right = WALK_SIDE.map((p) => mk(Object.assign({}, STAND, p), 'side'));
      const sr = mk(STAND, 'side');
      out = { kind: 'fig', w: CW, h: CH, ox: -12, oy: -12, idle: [idle[0], idle[0], idle[1], idle[1]], down, up, right, left: right.map(flipCanvas), blink, stand: { down: idle[0], up: mk({}, 'back'), right: sr, left: flipCanvas(sr) } };
    }
    cache[key] = out;
    return out;
  };

  // an attack or reaction pose, facing right (flip for left).
  // phase: ready|breath (ready, one pixel lower)|windup|strike|follow|hurt|dodge
  const pcache = {};
  S.pose = function (L, style, phase, flip, element) {
    const key = (L.key || JSON.stringify(L)) + '|' + style + '|' + phase + '|' + (element || '') + (flip ? '|f' : '');
    if (pcache[key]) return pcache[key];
    let c;
    const u = S.unit(L);
    const breath = phase === 'breath';
    if (breath) phase = 'ready';
    if (u.kind === 'big') c = u.idle[{ ready: breath ? 2 : 0, windup: 1, strike: 2, follow: 3, hurt: 0, dodge: 1 }[phase] || 0];
    else if (u.kind === 'mount') {
      let P = phase === 'hurt' ? { hurt: 1, lean: -1, wa: 140 } : phase === 'dodge' ? { lunge: -2, lean: -1, wa: 150 } : MOUNT_POSES[phase] || MOUNT_POSES.ready;
      if (breath) P = Object.assign({}, P, { bob: 1 });
      const r = new Ras(MW, MH); drawMount(r, L, P); c = finish(r);
    } else if (u.kind === 'giant') {
      let P = phase === 'hurt' ? HURT : phase === 'dodge' ? DODGE : Object.assign({ style }, (POSES[style] || POSES.punch)[phase] || {});
      if (breath) P = Object.assign({}, P, { bob: 1 });
      const r = figFrame(Object.assign({}, L, { big: null, build: L.build || 'big' }), P, 'side'); r.shade(0.12); r.outline(OUT); c = upscale(r, 2).canvas();
    } else {
      let P = phase === 'hurt' ? Object.assign({ style }, HURT) : phase === 'dodge' ? Object.assign({ style }, DODGE) : Object.assign({ style }, (POSES[style] || POSES.slash)[phase] || STAND);
      if (breath) P.bob = 1;
      if (P.glow) P = Object.assign({}, P, { glow: ELEM[element] || ELEM[style === 'sing' ? 'song' : 'flame'] });
      if (style === 'cast' || style === 'sing') P.weapon = null;
      c = finish(figFrame(L, P, 'side'));
    }
    if (flip) c = flipCanvas(c);
    pcache[key] = c;
    return c;
  };

  // a front or back frame with an arm thrown forward or up (Between the Rooms' up and down blows)
  const fcache = {};
  S.frontPose = function (L, back, P) {
    const key = (L.key || JSON.stringify(L)) + '|' + (back ? 'b' : 'f') + '|' + JSON.stringify(P);
    if (fcache[key]) return fcache[key];
    const c = finish(figFrame(L, P, back ? 'back' : 'front'));
    fcache[key] = c;
    return c;
  };
  S.FRAME = { w: CW, h: CH, ox: OX, oy: OY };

  // draw a unit standing on the tile whose top-left is (x, y); at scale k the tile is k*TILE wide
  S.drawUnit = function (ctx, L, x, y, opt) {
    opt = opt || {};
    const u = S.unit(L);
    const fr = opt.frame || S.frameFor(L, opt.dir || 'idle', AD.frame + (opt.phase || 0));
    const k = opt.scale || 1;
    ctx.drawImage(fr, Math.round(x + u.ox * k), Math.round(y + u.oy * k), u.w * k, u.h * k);
  };
  // where a unit's frame goes for a tile at (x, y), for callers that draw the frame themselves
  S.place = function (L, x, y, k) { const u = S.unit(L); k = k || 1; return [Math.round(x + u.ox * k), Math.round(y + u.oy * k), u.w * k, u.h * k]; };
  S.frameFor = function (L, dir, t) {
    const u = S.unit(L);
    if (dir === 'idle' || !dir) { if (u.kind === 'fig' && (t % 200) < 7) return u.blink; return u.idle[Math.floor(t / AD.ANIM.idle) % u.idle.length]; }
    return u[dir][Math.floor(t / AD.ANIM.walk) % u[dir].length];
  };
})(window.AD);

