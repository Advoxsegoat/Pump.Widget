// Sound and music (spec §3): the Tactics chiptune synth (two pulse voices, a triangle bass, a noise
// kit, scheduled ahead on WebAudio) with Between the Rooms' sound table and tracks. Every move has
// its own sound on its own frames; footsteps follow the floor; the music follows the fight and
// changes on the next bar. Sound starts only after the first key or tap.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const A = (AD.audio = { ctx: null, song: null, next: null, musicVol: 0.5, sfxVol: 0.6, muted: false });
  let master, musicGain, sfxGain, noiseBuf, waves = {};

  const NOTE = { C: 0, 'C#': 1, D: 2, 'D#': 3, E: 4, F: 5, 'F#': 6, G: 7, 'G#': 8, A: 9, 'A#': 10, B: 11 };
  function freq(n) {
    const m = /^([A-G]#?)(\d)$/.exec(n);
    if (!m) return 0;
    const semi = NOTE[m[1]] + (parseInt(m[2], 10) + 1) * 12;
    return 440 * Math.pow(2, (semi - 69) / 12);
  }

  A.unlock = function () {
    if (A.ctx) { if (A.ctx.state === 'suspended') A.ctx.resume(); return; }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    try { A.ctx = new AC(); } catch (e) { return; }
    const c = A.ctx;
    master = c.createGain(); master.gain.value = 0.9; master.connect(c.destination);
    musicGain = c.createGain(); musicGain.gain.value = A.musicVol * 0.5; musicGain.connect(master);
    sfxGain = c.createGain(); sfxGain.gain.value = A.sfxVol * 0.5; sfxGain.connect(master);
    noiseBuf = c.createBuffer(1, c.sampleRate, c.sampleRate);
    const d = noiseBuf.getChannelData(0);
    for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
    [0.125, 0.25, 0.5].forEach((duty) => {
      const n = 32, re = new Float32Array(n), im = new Float32Array(n);
      for (let k = 1; k < n; k++) im[k] = (2 / (k * Math.PI)) * Math.sin(k * Math.PI * duty);
      waves[duty] = c.createPeriodicWave(re, im);
    });
    if (A.pending) { const p = A.pending; A.pending = null; A.play(p); }
  };
  A.setVolumes = function (m, s) {
    A.musicVol = m; A.sfxVol = s;
    if (musicGain) musicGain.gain.value = A.muted ? 0 : m * 0.5;
    if (sfxGain) sfxGain.gain.value = A.muted ? 0 : s * 0.5;
  };

  function tone(dest, type, f, t0, dur, vol, opt) {
    const c = A.ctx;
    const o = c.createOscillator();
    const g = c.createGain();
    if (type === 'tri') o.type = 'triangle';
    else if (type === 'sine') o.type = 'sine';
    else o.setPeriodicWave(waves[type] || waves[0.5]);
    o.frequency.setValueAtTime(f, t0);
    if (opt && opt.slide) o.frequency.exponentialRampToValueAtTime(Math.max(20, opt.slide), t0 + dur);
    if (opt && opt.vib) {
      const lfo = c.createOscillator(), lg = c.createGain();
      lfo.frequency.value = 5.5; lg.gain.value = f * 0.006;
      lfo.connect(lg); lg.connect(o.frequency);
      lfo.start(t0 + 0.12); lfo.stop(t0 + dur + 0.05);
    }
    const sus = type === 'tri' ? 1 : 0.62;
    g.gain.setValueAtTime(0, t0);
    g.gain.linearRampToValueAtTime(vol, t0 + 0.006);
    g.gain.linearRampToValueAtTime(vol * sus, t0 + 0.08);
    g.gain.setValueAtTime(vol * sus, Math.max(t0 + 0.08, t0 + dur - 0.03));
    g.gain.linearRampToValueAtTime(0, t0 + dur);
    o.connect(g); g.connect(dest);
    o.start(t0); o.stop(t0 + dur + 0.02);
  }
  function noise(dest, t0, dur, vol, hp, lp) {
    const c = A.ctx;
    const s = c.createBufferSource();
    s.buffer = noiseBuf;
    const f = c.createBiquadFilter();
    f.type = hp ? 'highpass' : 'lowpass';
    f.frequency.value = hp || lp || 1200;
    const g = c.createGain();
    g.gain.setValueAtTime(vol, t0);
    g.gain.exponentialRampToValueAtTime(0.001, t0 + dur);
    s.connect(f); f.connect(g); g.connect(dest);
    s.start(t0, Math.random() * 0.5); s.stop(t0 + dur + 0.02);
  }
  function drum(kind, t0, vol) {
    if (kind === 'k') tone(musicGain, 'sine', 140, t0, 0.14, vol * 1.6, { slide: 40 });
    else if (kind === 's') { noise(musicGain, t0, 0.12, vol * 0.7, 1500); tone(musicGain, 'tri', 190, t0, 0.06, vol * 0.5, { slide: 120 }); }
    else if (kind === 'h') noise(musicGain, t0, 0.035, vol * 0.35, 7000);
    else if (kind === 'o') noise(musicGain, t0, 0.18, vol * 0.3, 6000);
  }

  // ---------------------------------------------------------------- tracks
  // Each channel: "NOTE:steps" tokens ("_" rests; k/s/h/o drums). A step is a sixteenth, a bar 16.
  // title, boss, garden and the two stings are the Tactics songs; bilibara and fight are new.
  const S = {};
  const rep = (s, n) => Array(n).fill(s).join(' ');
  const bars = (list, f) => list.map(f).join(' ');
  // Bilibara at night: A minor, a slow walk under the lamps
  S.bilibara = {
    bpm: 100,
    ch: [
      { v: 0.4, w: 0.25, vib: 1, n: 'A4:4 C5:2 E5:2 D5:4 C5:2 B4:2 C5:6 A4:2 E4:8 F4:4 A4:2 C5:2 B4:4 A4:2 G4:2 A4:12 _:4 E5:4 G5:2 E5:2 D5:4 C5:2 D5:2 E5:6 C5:2 A4:8 F5:4 E5:2 D5:2 C5:4 B4:2 G#4:2 A4:16' },
      { v: 0.12, w: 0.125, n: bars([['A3', 'C4', 'E4'], ['A3', 'C4', 'E4'], ['F3', 'A3', 'C4'], ['E3', 'G#3', 'B3'], ['C4', 'E4', 'G4'], ['A3', 'C4', 'E4'], ['D3', 'F3', 'A3'], ['A3', 'C4', 'E4']], ([a, b, c]) => rep(`${a}:2 ${b}:2 ${c}:2 ${b}:2`, 2)) },
      { v: 0.5, w: 'tri', n: bars(['A2', 'A2', 'F2', 'E2', 'C3', 'A2', 'D2', 'A2'], (x) => rep(x + ':2 _:2', 4)) },
      { v: 0.32, w: 'drum', n: rep('k:4 h:4 s:4 h:4', 8) },
    ],
  };
  // a sealed room or a charging gate: E minor, driving
  S.fight = {
    bpm: 140,
    ch: [
      { v: 0.42, w: 0.5, vib: 1, n: 'E5:2 E5:2 G5:2 E5:2 B5:4 A5:2 G5:2 F#5:2 D5:2 F#5:2 A5:2 G5:4 F#5:4 E5:2 E5:2 G5:2 B5:2 E6:4 D6:2 B5:2 C6:4 B5:4 A5:4 F#5:4 G5:2 G5:2 B5:2 G5:2 D6:4 C6:2 B5:2 A5:2 F#5:2 D5:2 F#5:2 A5:4 B5:4 C6:2 B5:2 A5:2 G5:2 F#5:2 E5:2 D#5:4 E5:8 B4:4 D#5:4' },
      { v: 0.12, w: 0.125, n: bars([['E4', 'G4', 'B4'], ['D4', 'F#4', 'A4'], ['E4', 'G4', 'B4'], ['C4', 'E4', 'A4'], ['G4', 'B4', 'D5'], ['D4', 'F#4', 'A4'], ['A3', 'C4', 'E4'], ['B3', 'D#4', 'F#4']], ([a, b, c]) => rep(`${a}:1 ${b}:1 ${c}:1 ${b}:1`, 4)) },
      { v: 0.5, w: 'tri', n: bars(['E', 'D', 'E', 'C', 'G', 'D', 'A', 'B'], (x) => rep(x + '2:2 ' + x + '3:2', 4)) },
      { v: 0.48, w: 'drum', n: rep('k:2 h:2 s:2 h:2 k:2 k:2 s:2 h:2', 8) },
    ],
  };
  S.title = {
    bpm: 84,
    ch: [
      { v: 0.5, w: 0.5, vib: 1, n: 'E5:4 A5:4 C6:3 B5:1 A5:4 C6:6 B5:2 A5:4 F5:4 G5:4 E5:4 G5:3 A5:1 G5:4 D5:8 _:4 B4:4 E5:4 A5:4 C6:3 D6:1 E6:4 F6:6 E6:2 C6:4 A5:4 B5:4 C6:2 B5:2 G5:4 D5:4 E5:12 _:4' },
      { v: 0.18, w: 0.25, n: rep('A4:2 C5:2 E5:2 C5:2', 2) + ' ' + rep('F4:2 A4:2 C5:2 A4:2', 2) + ' ' + rep('E4:2 G4:2 C5:2 G4:2', 2) + ' ' + rep('D4:2 G4:2 B4:2 G4:2', 2) + ' ' + rep('A4:2 C5:2 E5:2 C5:2', 2) + ' ' + rep('F4:2 A4:2 C5:2 A4:2', 2) + ' ' + rep('D4:2 G4:2 B4:2 G4:2', 2) + ' ' + rep('E4:2 G#4:2 B4:2 G#4:2', 2) },
      { v: 0.5, w: 'tri', n: 'A2:8 A2:8 F2:8 F2:8 C3:8 C3:8 G2:8 G2:8 A2:8 E2:8 F2:8 C3:8 G2:8 D3:8 E2:8 E2:8' },
    ],
  };
  S.boss = {
    bpm: 150,
    ch: [
      { v: 0.42, w: 0.5, vib: 1, n: 'D5:2 F5:2 A5:2 D6:2 C6:2 A5:2 F5:2 A5:2 A#5:4 F5:2 D5:2 A#5:4 D6:4 C6:2 E6:2 G6:2 E6:2 C6:4 G5:4 A5:4 C#6:4 E6:8 D6:2 C6:2 A5:2 F5:2 D5:4 F5:2 A5:2 A#5:2 D6:2 F6:4 D6:2 A#5:2 F5:4 G5:2 A#5:2 D6:2 G6:2 F6:4 D6:4 E6:4 C#6:4 A5:4 E5:4' },
      { v: 0.12, w: 0.125, n: 'F4:16 D4:16 E4:16 C#4:16 F4:16 D4:16 D4:16 C#4:16' },
      { v: 0.5, w: 'tri', n: [ 'D', 'A#', 'C', 'A', 'D', 'A#', 'G', 'A' ].map((x) => rep(x + '2:2 ' + x + '3:2', 4)).join(' ') },
      { v: 0.5, w: 'drum', n: rep('k:2 h:2 s:2 h:2 k:2 k:2 s:2 o:2', 8) },
    ],
  };
  S.garden = {
    bpm: 80,
    ch: [
      { v: 0.36, w: 0.125, vib: 1, n: 'E5:4 G5:4 B5:4 F#5:4 A5:6 F#5:2 D5:8 D5:4 F#5:4 B5:4 A5:4 G5:12 _:4 E5:4 G5:4 B5:4 D6:4 C6:6 A5:2 F#5:8 F#5:4 A5:4 D6:4 C#6:4 D#6:12 _:4' },
      { v: 0.14, w: 0.25, n: [ ['C4', 'E4', 'G4', 'B4'], ['D4', 'F#4', 'A4', 'F#4'], ['B3', 'D4', 'F#4', 'D4'], ['E4', 'G4', 'B4', 'G4'], ['C4', 'E4', 'G4', 'B4'], ['D4', 'F#4', 'A4', 'F#4'], ['B3', 'D4', 'F#4', 'D4'], ['B3', 'D#4', 'F#4', 'D#4'] ].map((c) => rep(c.map((x) => x + ':2').join(' '), 2)).join(' ') },
      { v: 0.4, w: 'tri', n: 'C3:16 D3:16 B2:16 E2:16 C3:16 D3:16 B2:16 B2:16' },
    ],
  };
  S.victory = { bpm: 140, once: true, ch: [
    { v: 0.45, w: 0.5, n: 'C5:2 E5:2 G5:2 C6:6 _:2 A5:2 B5:2 C6:10' },
    { v: 0.2, w: 0.25, n: 'E4:2 G4:2 C5:2 E5:6 _:2 F5:2 G5:2 G5:10' },
    { v: 0.5, w: 'tri', n: 'C3:8 _:2 F2:2 G2:2 C3:16' },
  ] };
  S.gameover = { bpm: 60, once: true, ch: [
    { v: 0.4, w: 0.25, vib: 1, n: 'A4:4 G4:4 F4:4 E4:12' },
    { v: 0.45, w: 'tri', n: 'A2:8 D2:8 A1:8' },
  ] };
  A.SONGS = S;

  function parse(n) {
    const ev = []; let t = 0;
    n.trim().split(/\s+/).forEach((tok) => {
      const [k, d] = tok.split(':');
      const steps = parseFloat(d) || 1;
      if (k !== '_') ev.push({ t, d: steps, k });
      t += steps;
    });
    return { ev, len: t };
  }
  Object.values(S).forEach((s) => s.ch.forEach((c) => { const p = parse(c.n); c.ev = p.ev; c.len = p.len; }));

  // when the next bar of a song begins, after the part already scheduled (horizon seconds ahead)
  A.nextBar = function (now, start, step, horizon) {
    const bar = 16 * step;
    return start + Math.ceil((now + horizon - start) / bar - 1e-9) * bar;
  };
  const HORIZON = 0.15;
  const songAt = (s, start) => ({ s, start, step: 60 / s.bpm / 4, chs: s.ch.map(() => ({ i: 0, loop: 0 })), until: Infinity });
  // a track; a change waits for the next bar of the one playing (o.now: start at once, for stings)
  A.play = function (name, o) {
    if (A.current === name) return;
    A.current = name;
    if (!A.ctx) { A.pending = name; return; }
    const s = S[name], now = A.ctx.currentTime;
    if (!A.song || (o && o.now) || A.song.s.once) { A.song = s ? songAt(s, now + 0.06) : null; A.next = null; return; }
    const at = A.nextBar(now, A.song.start, A.song.step, HORIZON);
    A.song.until = at;
    A.next = s ? songAt(s, at) : null;
    if (!s) A.next = { s: { ch: [], once: true }, start: at, chs: [], until: at };
  };
  A.stop = function () { A.song = null; A.next = null; A.current = null; };

  function schedule(sg, horizon) {
    sg.s.ch.forEach((c, ci) => {
      const st = sg.chs[ci];
      for (;;) {
        if (st.i >= c.ev.length) {
          if (sg.s.once) return;
          st.i = 0; st.loop++;
        }
        const e = c.ev[st.i];
        const t0 = sg.start + (st.loop * c.len + e.t) * sg.step;
        if (t0 > horizon || t0 >= sg.until) break;
        if (t0 >= A.ctx.currentTime - 0.05) {
          const dur = e.d * sg.step * 0.95;
          if (c.w === 'drum') drum(e.k, t0, c.v);
          else tone(musicGain, c.w === 'tri' ? 'tri' : c.w, freq(e.k), t0, dur, c.v * (c.w === 'tri' ? 0.9 : 0.55), { vib: c.vib && e.d >= 4 });
        }
        st.i++;
      }
    });
  }
  A.tick = function () {
    if (!A.ctx || A.muted) return;
    const now = A.ctx.currentTime, horizon = now + HORIZON;
    if (A.song) schedule(A.song, horizon);
    if (A.next && horizon >= A.next.start) {
      if (A.next.s.ch.length) schedule(A.next, horizon);
      if (now >= A.next.start) { A.song = A.next.s.ch.length ? A.next : null; A.next = null; }
    }
  };

  // ---------------------------------------------------------------- the sound table
  // each: (gain node, time, pitch, volume)
  const T = (g, w, f, t, d, v, o) => tone(g, w, f, t, d, v, o);
  const SFX = {
    // the Open Hand: a slap, a second slap, then the heavy palm
    whoosh: (g, t, p, v) => noise(g, t, 0.08, 0.13 * v, 1800 * p),
    palm1: (g, t, p, v) => { noise(g, t, 0.07, 0.34 * v, null, 1400 * p); T(g, 0.5, 170 * p, t, 0.06, 0.24 * v, { slide: 70 * p }); },
    palm2: (g, t, p, v) => { noise(g, t, 0.07, 0.34 * v, null, 1600 * p); T(g, 0.5, 205 * p, t, 0.06, 0.24 * v, { slide: 80 * p }); },
    palm3: (g, t, p, v) => { noise(g, t, 0.15, 0.48 * v, null, 900 * p); T(g, 'tri', 120 * p, t, 0.15, 0.42 * v, { slide: 40 * p }); noise(g, t, 0.04, 0.2 * v, 3000 * p); },
    spinCharge: (g, t, p, v) => { T(g, 0.25, 1760 * p, t, 0.04, 0.15 * v); T(g, 0.25, 2637 * p, t + 0.04, 0.16, 0.13 * v); },
    spin: (g, t, p, v) => { noise(g, t, 0.24, 0.3 * v, 1200 * p); T(g, 'sine', 400 * p, t, 0.22, 0.12 * v, { slide: 1300 * p }); },
    // the Three Gifts
    flame: (g, t, p, v) => { noise(g, t, 0.38, 0.38 * v, null, 1800 * p); T(g, 0.5, 220 * p, t, 0.25, 0.18 * v, { slide: 70 * p }); },
    bloom: (g, t, p, v) => [0, 3, 7, 10, 14].forEach((s, i) => T(g, 'tri', 392 * p * Math.pow(2, s / 12), t + i * 0.05, 0.2, 0.22 * v)),
    tide: (g, t, p, v) => { noise(g, t, 0.65, 0.45 * v, null, 700 * p); T(g, 'sine', 180 * p, t, 0.4, 0.14 * v, { slide: 90 * p }); },
    roll: (g, t, p, v) => { noise(g, t, 0.12, 0.2 * v, null, 900 * p); T(g, 'tri', 140 * p, t, 0.08, 0.1 * v, { slide: 90 * p }); },
    // landing blows
    hit: (g, t, p, v) => { noise(g, t, 0.12, 0.5 * v, null, 2200 * p); T(g, 0.5, 180 * p, t, 0.09, 0.3 * v, { slide: 60 * p }); },
    crit: (g, t, p, v) => { noise(g, t, 0.3, 0.6 * v, null, 4000 * p); T(g, 0.25, 520 * p, t, 0.25, 0.3 * v, { slide: 80 * p }); },
    block: (g, t, p, v) => { T(g, 0.5, 1200 * p, t, 0.03, 0.18 * v); T(g, 0.5, 900 * p, t + 0.03, 0.06, 0.16 * v); noise(g, t, 0.05, 0.12 * v, 4000); },
    hurt: (g, t, p, v) => { T(g, 0.5, 300 * p, t, 0.15, 0.3 * v, { slide: 120 * p }); noise(g, t, 0.1, 0.35 * v, null, 1500); },
    // monsters
    goblinSwing: (g, t, p, v) => { noise(g, t, 0.1, 0.2 * v, 1400 * p); T(g, 0.25, 500 * p, t, 0.06, 0.07 * v, { slide: 300 * p }); },
    sling: (g, t, p, v) => { T(g, 'tri', 300 * p, t, 0.12, 0.15 * v, { slide: 640 * p }); noise(g, t, 0.06, 0.12 * v, 2500); },
    fuse: (g, t, p, v) => noise(g, t, 0.5, 0.12 * v, 5000 * p),
    boom: (g, t, p, v) => { noise(g, t, 0.6, 0.8 * v, null, 900 * p); T(g, 0.5, 90 * p, t, 0.4, 0.5 * v, { slide: 30 }); },
    bite: (g, t, p, v) => { noise(g, t, 0.05, 0.25 * v, 2000 * p); T(g, 0.5, 600 * p, t, 0.04, 0.15 * v, { slide: 300 * p }); },
    musket: (g, t, p, v) => { noise(g, t, 0.28, 0.7 * v, null, 2600 * p); T(g, 0.5, 130 * p, t, 0.14, 0.4 * v, { slide: 40 }); },
    clang: (g, t, p, v) => { T(g, 0.5, 320 * p, t, 0.02, 0.18 * v); T(g, 0.5, 240 * p, t + 0.07, 0.03, 0.18 * v); },
    // the bosses' blows: Gold Tooth's knife fan and charge, the Fixer's sword, the First Knuckle
    knives: (g, t, p, v) => [0, 0.05, 0.1].forEach((d) => { noise(g, t + d, 0.06, 0.16 * v, 2600 * p); T(g, 0.25, 1100 * p, t + d, 0.04, 0.05 * v, { slide: 600 * p }); }),
    slash: (g, t, p, v) => { noise(g, t, 0.12, 0.22 * v, 1600 * p); T(g, 0.25, 900 * p, t, 0.08, 0.08 * v, { slide: 400 * p }); },
    dash: (g, t, p, v) => { noise(g, t, 0.18, 0.24 * v, null, 1300 * p); T(g, 'tri', 160 * p, t, 0.16, 0.14 * v, { slide: 90 * p }); },
    thud: (g, t, p, v) => { noise(g, t, 0.2, 0.55 * v, null, 500 * p); T(g, 'tri', 100 * p, t, 0.18, 0.45 * v, { slide: 45 }); },
    // rooms and the Seam Gate
    doorSlam: (g, t, p, v) => { noise(g, t, 0.3, 0.7 * v, null, 400 * p); T(g, 0.5, 80 * p, t, 0.2, 0.5 * v, { slide: 40 }); },
    doorOpen: (g, t, p, v) => { noise(g, t, 0.2, 0.3 * v, null, 700 * p); T(g, 'tri', 200 * p, t, 0.15, 0.15 * v, { slide: 300 * p }); },
    chime: (g, t, p, v) => [0, 4, 7, 12].forEach((s, i) => T(g, 'tri', 784 * p * Math.pow(2, s / 12), t + i * 0.07, 0.18, 0.28 * v)),
    gateHum: (g, t, p, v) => { T(g, 'sine', 110 * p, t, 0.5, 0.14 * v, { vib: 1 }); T(g, 0.125, 220 * p, t, 0.45, 0.05 * v); },
    gateDone: (g, t, p, v) => [0, 7, 12, 16, 19].forEach((s, i) => T(g, 0.5, 523 * p * Math.pow(2, s / 12), t + i * 0.08, 0.14, 0.2 * v)),
    // what is picked up
    coin: (g, t, p, v) => { T(g, 0.5, 1568 * p, t, 0.05, 0.14 * v); T(g, 0.5, 2093 * p, t + 0.05, 0.12, 0.14 * v); },
    heart: (g, t, p, v) => { T(g, 'tri', 659 * p, t, 0.08, 0.25 * v); T(g, 'tri', 988 * p, t + 0.08, 0.14, 0.25 * v); },
    key: (g, t, p, v) => { T(g, 0.5, 1046 * p, t, 0.06, 0.16 * v); T(g, 0.5, 2093 * p, t + 0.06, 0.1, 0.14 * v); },
    item: (g, t, p, v) => [0, 4, 7, 12, 16].forEach((s, i) => T(g, 0.25, 784 * p * Math.pow(2, s / 12), t + i * 0.05, 0.09, 0.17 * v)),
    potion: (g, t, p, v) => { T(g, 'sine', 400 * p, t, 0.1, 0.16 * v, { slide: 800 * p }); T(g, 'sine', 500 * p, t + 0.09, 0.1, 0.14 * v, { slide: 950 * p }); },
    scroll: (g, t, p, v) => { noise(g, t, 0.15, 0.15 * v, 3000 * p); T(g, 'sine', 1200 * p, t + 0.05, 0.08, 0.08 * v); },
    // Get Up, the bosses
    getup: (g, t, p, v) => { [0, 3, 7, 12].forEach((s, i) => T(g, 'tri', 392 * p * Math.pow(2, s / 12), t + i * 0.09, 0.2, 0.25 * v)); T(g, 'sine', 300 * p, t, 0.4, 0.12 * v, { slide: 1500 * p }); },
    bossIn: (g, t, p, v) => { noise(g, t, 0.6, 0.5 * v, null, 500 * p); T(g, 0.5, 110 * p, t, 0.6, 0.32 * v, { slide: 55 * p }); T(g, 'tri', 55 * p, t, 0.6, 0.4 * v); },
    pip: (g, t, p, v) => { T(g, 0.25, 880 * p, t, 0.04, 0.16 * v); noise(g, t, 0.08, 0.2 * v, 6000); },
    break: (g, t, p, v) => { noise(g, t, 0.4, 0.5 * v, 5000); [1568, 1175, 880, 659].forEach((f, i) => T(g, 'sine', f * p, t + i * 0.04, 0.1, 0.22 * v)); },
    // footsteps, by floor
    step_stone: (g, t, p, v) => noise(g, t, 0.03, 0.07 * v, 2500 * p),
    step_wood: (g, t, p, v) => { T(g, 'tri', 180 * p, t, 0.03, 0.1 * v, { slide: 120 * p }); noise(g, t, 0.03, 0.05 * v, null, 1200); },
    step_water: (g, t, p, v) => { noise(g, t, 0.08, 0.1 * v, null, 1000 * p); T(g, 'sine', 300 * p, t, 0.05, 0.03 * v, { slide: 500 * p }); },
    step_grass: (g, t, p, v) => noise(g, t, 0.04, 0.05 * v, 4000 * p),
    // and the rest of what the bus says
    levelUp: (g, t, p, v) => [0, 4, 7, 12, 16, 19].forEach((s, i) => T(g, 0.5, 523 * p * Math.pow(2, s / 12), t + i * 0.07, 0.1, 0.2 * v)),
    cantAfford: (g, t, p, v) => { T(g, 0.5, 200 * p, t, 0.08, 0.16 * v); T(g, 0.5, 150 * p, t + 0.09, 0.1, 0.16 * v); },
    trap: (g, t, p, v) => { T(g, 0.5, 1500 * p, t, 0.03, 0.16 * v); noise(g, t, 0.1, 0.3 * v, 2500); },
    fall: (g, t, p, v) => T(g, 'sine', 600 * p, t, 0.4, 0.22 * v, { slide: 80 }),
  };
  A.NAMES = Object.keys(SFX);
  const lastAt = {};
  // a sound now; the same one at most every 35 ms, so a crowd's hits don't stack into noise
  A.sfx = function (name, o) {
    if (!A.ctx || A.muted) return;
    const t = A.ctx.currentTime;
    if (lastAt[name] && t - lastAt[name] < 0.035) return;
    lastAt[name] = t;
    const p = (o && o.pitch) || 1, v = o && o.vol !== undefined ? o.vol : 1;
    (SFX[name] || ((g, tt) => T(g, 0.5, 880, tt, 0.03, 0.1)))(sfxGain, t, p, v);
  };

  // which footstep a floor makes
  A.stepSound = function (ch, biome) {
    if (ch === ',' || ch === '"') return 'step_grass';
    if (ch === '-' || ch === '~') return 'step_water';
    if (ch === 'w' || (ch === '.' && biome === 'interior')) return 'step_wood';
    return 'step_stone';
  };

  // ---------------------------------------------------------------- the bus
  const WIND = { musket: 'clang' };
  A.bind = function (bus) {
    const on = (n, f) => bus.on(n, f, 98);
    let region = 'bilibara', biome = 'city';
    const s = (n, o) => A.sfx(n, o), play = (t) => A.play(t);
    const offs = [
      on('depthStart', (p) => {
        const r = AD.regionAt ? AD.regionAt(p.depth) : null;
        if (r) { region = r.id; biome = r.d.biome; }
        play(region);
      }),
      on('hit', (p) => {
        if (!p.amount || !p.tgt || p.tgt.kind === 'hero') return;
        const share = Math.min(1, p.amount / Math.max(1, p.tgt.mhp || 1));
        const tick = p.rec && p.rec.fixed;
        s(p.crit ? 'crit' : 'hit', { vol: tick ? 0.3 : Math.min(1, 0.45 + share * 1.2), pitch: 1.1 - share * 0.5 });
      }),
      on('hurt', () => s('hurt')),
      on('blocked', () => s('block')),
      on('attackStart', (p) => {
        const a = p.attack, d = a && a.def;
        if (!d) return;
        if (d.bomb) { s('fuse'); return; }
        if (WIND[d.sfx]) { s(WIND[d.sfx]); return; }
        if (d.shape && (d.shape.k === 'shot' || d.shape.k === 'lob')) return;
        s('whoosh', { pitch: a.owner && a.owner.kind === 'hero' ? 1 : 0.8, vol: a.owner && a.owner.kind === 'hero' ? 1 : 0.7 });
      }),
      on('strike', (p) => { const d = p.attack && p.attack.def; if (d && !d.bomb && d.sfx) s(d.sfx); }),
      on('explode', () => s('boom')),
      on('roll', () => s('roll')),
      on('charged', () => s('spinCharge')),
      on('arrive', (p) => { if (p.e && p.e.kind === 'hero') s(A.stepSound(p.tile, biome), { vol: 0.8 }); }),
      on('enterRoom', (p) => { if (p.sealed) { s('doorSlam'); play('fight'); } }),
      on('roomClear', () => { s('chime'); play(region); }),
      on('opened', () => s('doorOpen')),
      on('unlock', () => s('doorOpen', { pitch: 1.2 })),
      on('gateStart', () => { s('gateHum'); play('fight'); }),
      on('gateCharging', (p) => s('gateHum', { pitch: 1 + (p.gate.charge || 0), vol: 0.6 + 0.4 * (p.gate.charge || 0) })),
      on('gateCharged', () => { s('gateDone'); play(region); }),
      on('bossIn', () => { s('bossIn'); play('boss'); }),
      on('bossPhase', () => s('bossIn', { pitch: 1.3 })),
      on('pip', () => s('pip')),
      on('break', () => s('break')),
      on('getup', () => s('getup')),
      on('levelUp', () => s('levelUp')),
      on('pickup', (p) => {
        const q = p.p || {};
        const scroll = q.scroll || (AD.SCROLLS && AD.SCROLLS[q.id]);
        const name = { coins: 'coin', heart: 'heart', key: 'key', item: 'item', armour: 'item', lore: 'scroll', petal: 'coin' }[q.kind] || (q.kind === 'cons' ? (q.id === 'bomb' ? 'item' : scroll ? 'scroll' : 'potion') : 'item');
        s(name, { pitch: q.kind === 'petal' ? 1.5 : q.kind === 'coins' ? 0.95 + Math.random() * 0.1 : 1 });
      }),
      on('consume', (p) => s(AD.SCROLLS && AD.SCROLLS[p.id] ? 'scroll' : p.id === 'bomb' ? 'clang' : 'potion', { pitch: 0.9 })),
      on('chest', () => s('item', { pitch: 0.8 })),
      on('cantAfford', () => s('cantAfford')),
      on('trap', () => s('trap')),
      on('fall', () => s('fall')),
      on('summon', () => s('clang', { pitch: 0.6 })),
      on('useEquipment', () => s('item', { pitch: 1.2 })),
      on('death', () => A.play('gameover', { now: true })),
      on('victory', () => A.play('victory', { now: true })),
    ];
    return () => offs.forEach((f) => f && f());
  };
})(window.AD);
