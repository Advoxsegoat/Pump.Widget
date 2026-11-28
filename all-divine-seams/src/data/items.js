// The M1 item catalogue (spec §5.3). Behaviour lives in sim/items.js; this is what the player reads.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const I = (AD.ITEMS = {});
  const add = (id, n, tier, desc, more) => { I[id] = Object.assign({ id, n, tier, desc, icon: id }, more || {}); };
  // common
  add('lazyman', 'Lazyman Stack', 'common', '+25 max HP.');
  add('coffeeflask', 'Coffee Flask', 'common', '+14% move speed.');
  add('silkscarf', 'Silk Scarf', 'common', '+15% attack speed.');
  add('gamblerschip', 'Gambler\'s Chip', 'common', '+10% crit chance.');
  add('tinring', 'Tin Ring', 'common', '15% chance to block a hit entirely.');
  add('rosethorn', 'Rose Thorn', 'common', '10% chance on hit to Bleed for 240% over 3 s.');
  add('bouillabaisse', 'Bouillabaisse', 'common', 'Kills heal 8 HP and 2% of max HP.');
  add('warmmitts', 'Warm Mitts', 'common', '+75% damage to enemies above 90% HP.');
  add('taffy', 'Taffy', 'common', '+3 HP a second after 7 s unhurt.');
  add('crowfeather', 'Crow Feather', 'common', '+1 roll charge.');
  add('bellchime', 'Bell Chime', 'common', 'Kills ring a chime: 100% to everything around the body.');
  add('throwingknives', 'Throwing Knives', 'common', '10% chance on hit to throw a knife at another foe for 200%.');
  add('brassbuttons', 'Brass Buttons', 'common', 'Every hit you take is 5 less (never below 1).');
  add('lucienswatch', 'Lucien\'s Watch', 'common', 'Your skill recharges 10% faster.');
  add('sardinetin', 'Sardine Tin', 'common', 'Heal 8% of max HP when a room clears.');
  // uncommon
  add('sparkcoil', 'Spark Coil', 'uncommon', '25% chance on hit: lightning leaps to 3 foes for 80%.');
  add('harpoon', 'Harpoon', 'uncommon', 'Kills give +125% move speed, fading over 2 s.');
  add('petalstorm', 'Petal Storm', 'uncommon', '10% chance on hit: 3 seeking petals, 100% each.');
  add('ivoryshard', 'Ivory Shard', 'uncommon', '8% chance on hit: a freezing burst for 150% that Chills.');
  add('bandolier', 'Bandolier', 'uncommon', 'Kills may refill your rolls and reset your skill.');
  add('kaelsbuckler', 'Kael\'s Buckler', 'uncommon', '+30 armour while attacking.');
  add('bloodroot', 'Bloodroot', 'uncommon', 'Heal 1 HP per hit.');
  // legendary
  add('roseheart', 'Rose Divine Heart', 'legendary', 'Once, when you would die, rise at full HP. The heart wilts.');
  add('brassmoon', 'Brass Moon', 'legendary', 'Every third hit crits and throws a spark to 2 foes.');
  // boss
  add('knucklebrass', 'Knuckle Brass', 'boss', 'Your charged spin strikes twice; every hit wears a boss\'s shield.');
  // equipment (cooldown in seconds)
  add('anchor', 'Tidebreaker\'s Anchor', 'equipment', 'Slam for 400% around you and drag foes in.', { cd: 30 });
  add('powderbarrel', 'Powder Barrel', 'equipment', 'Throw a barrel 4 tiles: 600% in a wide blast. Opens cracked walls.', { cd: 25 });
  add('pocketbell', 'Pocket Bell', 'equipment', 'Reveal the floor; stun foes within 4 tiles.', { cd: 40 });
  add('skillet', 'Henri\'s Skillet', 'equipment', 'For 3 s, block everything from the front and send shots back.', { cd: 20 });
  // what a spent heart becomes
  add('wiltedrose', 'Wilted Rose', 'spent', 'It did its work.');
})(window.AD);
