// Words: the first-run hints (spec 8), Lucien's Book (the bestiary and the item log), the page of
// the Book each depth's rest room keeps, and what the Garden's folk say.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const L = (AD.LORE = {});

  // shown once each, at the moment they apply
  L.hints = {
    attack: 'A: strike. Hold A and let go to spin.',
    skill: 'B: a Gift - flame, bloom, tide, in turn.',
    roll: 'Red tiles are coming. R: roll through them.',
    gate: 'The Seam Gate: stay near it while it fills.',
    quick: 'Use what you found from a quickslot (tap it, or 1 and 2).',
  };

  // the Book: what Lucien wrote down about each thing met between the rooms
  L.monsters = {
    rat: 'Sewer rats. Bilibara feeds them better than it feeds its children.',
    grunt: 'Goblins came through the Seams with the cold. They lunge two steps at once.',
    slinger: 'A goblin with a sling keeps its distance. Close it.',
    bomber: 'It lobs, then the fuse is yours to count. Ninety frames.',
    shaman: 'The bone staff heals its kin and hurries them. Kill it first.',
    pickpocket: 'It wants your coins, not your life. Catch it and it pays back more.',
    whelp: 'A wyvern whelp, one gold eye. It flies over what you must walk around.',
    tough: 'The Hand hires them by the dozen in Rue Caillou. Three blows, then a breath.',
    hound: 'Gray Hounds run in threes. They are faster than you; be where they are not.',
    fusilier: 'The Crown aims along a line and takes its time. Leave the line.',
    brassmask: 'The Brass Mask turns its blade to whatever is in front of it. Be behind it.',
    knuckle: 'A Knuckle of the Hand: three blows in a row, then open.',
    goldtooth: 'Gold Tooth collects for the Hand. Knives in a fan, then the charge.',
    fixer: "Yaska's Fixer settles what the Hand will not put in writing.",
    marais: 'Lieutenant Marais keeps the Crown\'s order with a sword and a line of muskets.',
    firstknuckle: 'The First Knuckle. Every debt in Bilibara is paid to him in the end.',
  };
  L.monster = (id) => L.monsters[id] || 'Something from between the rooms.';

  // the page of the Book each rest room keeps, one a depth
  L.pages = [
    { title: 'Rue Caillou', text: 'A week after his brother left, Abarax still set two bowls on the counter of the Lazyman\'s. The street outside had started to come apart at the seams.' },
    { title: 'The Harbor', text: 'Behind the sardine cannery the tide runs the wrong way at night. The fishermen say the sea is looking for something it lost.' },
    { title: 'Under Bilibara', text: 'The old sewers remember every room the city ever built over them. Some of those rooms were never on any map.' },
    { title: 'The Tanneries', text: 'Tuesday, eleven forty in the morning, and the vats were already full of things that were not hides.' },
    { title: 'The Tanneries Yard', text: 'Where the Hand collects. Nobody owes the First Knuckle once; they owe him every week after.' },
  ];
  L.page = (depth) => L.pages[Math.max(0, Math.min(L.pages.length - 1, (depth || 1) - 1))];

  // the Garden's folk
  L.selenne = [
    'The Seams open between rooms. Walk through enough of them and you walk out of the world.',
    'Every minute down there the city notices you a little more. Do not stand still for long.',
    'A room that seals will not let you go until it is quiet again.',
    'Pots and crates hide coins. Tall grass hides more than that.',
    'Elites glow. Their coins are worth it; their tricks are not.',
    'A gate charges only while you stand near it. The guardian will not wait for you to be ready.',
    'Draughts and pages are unknown until you use them. Each run hides which is which.',
    'Petals are what the Seams leave behind. Midas knows what they are worth.',
  ];
  L.lucien = 'The Book keeps what you have met and what you have carried. Read it before you go down.';
  L.midas = 'Petals for favours. I do not haggle and I do not give credit.';
  L.tear = 'The tear in the wall. Beyond it, Bilibara, and between the rooms.';
})(window.AD);
