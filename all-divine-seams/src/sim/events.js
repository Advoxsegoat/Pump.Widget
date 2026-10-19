// The event bus. Items, rooms, the Book, sounds and the HUD all listen here. Handlers run in a fixed
// order (by `order`, then by when they were added), so the same inputs always give the same result.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  let seq = 0;
  function Bus() { this.h = {}; }
  Bus.prototype.on = function (name, fn, order) {
    const list = this.h[name] || (this.h[name] = []);
    const rec = { fn, order: order === undefined ? 50 : order, seq: seq++ };
    list.push(rec);
    list.sort((a, b) => a.order - b.order || a.seq - b.seq);
    return () => { const i = list.indexOf(rec); if (i >= 0) list.splice(i, 1); };
  };
  Bus.prototype.emit = function (name, payload) {
    const list = this.h[name];
    if (!list) return payload;
    for (const rec of list.slice()) {
      try { rec.fn(payload); } catch (e) { if (AD.report) AD.report(e, 'bus ' + name); }
    }
    return payload;
  };
  Bus.prototype.clear = function () { this.h = {}; };
  AD.Bus = Bus;
})(window.AD);
