// Looks: the paper-doll recipes (from All-Divine Tactics) for everyone in the Seams. The goblins are
// new: small builds, green skin, long ears.
window.AD = window.AD || {};
(function (AD) {
  'use strict';
  const shade = (c, k) => (AD.gfx ? AD.gfx.shade(c, k) : c);
  const folk = (skin, hair, style, main, outfit, extra) => Object.assign({ skin, hair, hairStyle: style, main, outfit: outfit || 'shirt', sec: shade(main, 0.35) }, extra || {});
  const gob = (main, extra) => Object.assign({ skin: '#7aa04a', hair: '#2a3a1a', hairStyle: 'buzz', eyes: '#ffd84a', build: 'small', outfit: 'rags', main, sec: shade(main, 0.3), pants: '#3a3020', boots: '#2a2018', ears: 1 }, extra || {});
  AD.LOOKS = {
    // the hero: Abarax as a cook of the Lazyman's, fists bare for the Open Hand
    abarax: { skin: '#c98a5a', hair: '#4a2e1e', hairStyle: 'undercut', eyes: '#5a2e14', main: '#efe6d6', sec: '#3a4a7a', pants: '#3a3a4a', boots: '#5a3a2a', outfit: 'apron' },
    // goblins
    grunt: gob('#6a4a2a', { held: 'cleaver' }),
    slinger: gob('#5a5a3a', { held: 'sling', extras: ['cap'], hat: '#4a3a2a' }),
    bomber: gob('#4a3a3a', { held: 'bomb' }),
    shaman: gob('#4a2a5a', { held: 'staff', staffC: '#e8e0c8', extras: ['hood'], hood: '#3a1a4a', eyes: '#8affc8', eyeGlow: '#8affc8' }),
    pickpocket: gob('#2a2a3a', { extras: ['hood'], hood: '#1a1a2a' }),
    // the book's enemies (Tactics' class looks)
    tough: { skin: '#c89a74', hair: '#2a2420', hairStyle: 'buzz', main: '#5a4a3e', sec: '#8a7a6a', outfit: 'longcoat', held: 'knife', build: 'normal' },
    fusilier: { skin: '#e0b894', hair: '#3a2a20', main: '#2a4a9a', sec: '#d8d0b8', acc: '#e8c170', outfit: 'uniform', extras: ['shako'], hat: '#1a2a5a', held: 'rifle' },
    knuckle: { skin: '#b07a54', hair: '#1a1418', hairStyle: 'buzz', main: '#d8d4cc', sec: '#8a8a96', acc: '#8a8a96', outfit: 'wraps', gloves: '#e8e4dc' },
    hound: { skin: '#6a6a76', hair: '#4a4a56', main: '#5a5a66', build: 'child', outfit: 'rags', eyes: '#ff6a5a', eyeGlow: '#ff6a5a', hairStyle: 'spiky' },
    brassmask: { skin: '#c89a74', hair: '#2a2420', main: '#8a6a2a', sec: '#c9a35d', acc: '#e8c170', outfit: 'longcoat', extras: ['mask'], maskC: '#c9a35d', held: 'sword' },
    // Bilibara's mini-bosses and boss (their looks from the book's chapters)
    goldtooth: { skin: '#c89a74', hair: '#2a2420', hairStyle: 'bald', main: '#8a2e2a', sec: '#e8c170', acc: '#e8c170', outfit: 'longcoat', held: 'knife', extras: ['scar', 'earring', 'mustache'], build: 'big' },
    fixer: { skin: '#b08a6a', hair: '#2a2420', hairStyle: 'bald', main: '#24242e', sec: '#b8303a', acc: '#b8303a', outfit: 'coat', held: 'sword', gloves: '#c9a35d', extras: ['scar', 'spectacles'], build: 'big' },
    marais: { skin: '#e8c4a0', hair: '#c8c8d0', main: '#24408a', sec: '#e8c170', acc: '#e8c170', outfit: 'longcoat', extras: ['mustache', 'shako'], hat: '#1a2a5a', held: 'sword', build: 'tall' },
    firstknuckle: { skin: '#f4e8e0', hair: '#f4f4ff', hairStyle: 'short', main: '#c8d0e8', sec: '#ffffff', outfit: 'robe', held: 'orb', orbC: '#ffffff', eyeGlow: '#ffffff', build: 'tall' },
    // the Garden's folk
    selenne: { skin: '#5a3a2a', hair: '#1a1418', hairStyle: 'braids', eyes: '#c8d0e0', main: '#4a4a6a', sec: '#8a8aa8', outfit: 'robe', held: 'sword', build: 'tall' },
    lucien: folk('#f2dcd0', '#141018', 'short', '#3a3a5a', 'shirt', { build: 'small', held: 'book', eyes: '#a8b8c8' }),
    midas: folk('#f2dcd0', '#e8d088', 'messy', '#4a6a3a', 'shirt', { eyes: '#d8304a', build: 'small' }),
    // the training yard's straw man
    dummy: { skin: '#c8a860', hair: '#a88a40', hairStyle: 'messy', eyes: '#3a2a1a', main: '#8a6a3a', sec: '#c8a860', pants: '#6a5030', boots: '#4a3a20', outfit: 'rags', build: 'big' },
  };
  // armour as it shows on the body (Tactics 1.4's armour pieces)
  AD.ARMOUR_LOOK = {
    jerkin: { pieces: ['breast', 'bracers'], plate: '#6a4a30', trim: '#a87a4a' },
    hauberk: { pieces: ['breast', 'pauldrons'], plate: '#8a8e9a', trim: '#5a5e6a', chain: 1 },
    plate: { pieces: ['breast', 'pauldrons', 'bracers', 'greaves'], plate: '#c0c8d8', trim: '#e8c170' },
  };
  // a look with its armour on, cached so the figure painter's cache keys stay stable
  const dressed = {};
  AD.lookFor = function (base, armourId) {
    const key = base + '|' + (armourId || '');
    if (dressed[key]) return dressed[key];
    const L = Object.assign({}, AD.LOOKS[base]);
    if (armourId && AD.ARMOUR_LOOK[armourId]) L.armor = AD.ARMOUR_LOOK[armourId];
    L.key = key;
    dressed[key] = L;
    return L;
  };
})(window.AD);
