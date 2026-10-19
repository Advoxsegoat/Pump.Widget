// Boot: a placeholder title until the menus arrive.
(function (AD) {
  'use strict';
  if (!AD.Title) {
    AD.Title = function () { this.opaque = true; };
    AD.Title.prototype.draw = function (ctx) {
      const G = AD.gfx, W = AD.display.W, H = AD.display.H;
      ctx.fillStyle = '#07080f'; ctx.fillRect(0, 0, W, H);
      G.text(ctx, 'BETWEEN THE ROOMS', W / 2, H / 2 - 6, G.C.gold, { align: 'center' });
    };
  }
  window.addEventListener('DOMContentLoaded', () => AD.boot(() => AD.push(new AD.Title())));
})(window.AD);
