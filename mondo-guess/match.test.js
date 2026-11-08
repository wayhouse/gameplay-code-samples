const test = require('node:test');
const assert = require('node:assert/strict');
const { createMatch, applyMove } = require('./match.js');

// This seed gives player 1 the first pick. The two unpicked cards are 6 and 7.
function draftSix(match) {
  for (let cardId = 0; cardId < 6; cardId++) {
    applyMove(match, { sequence: cardId + 1, player: cardId % 2 + 1, type: 'pick', cardId });
  }
}

function assertRejected(match, move) {
  const before = structuredClone(match);
  assert.throws(() => applyMove(match, move));
  assert.deepEqual(match, before, 'A rejected move must leave the previous state intact');
}

test('the same seed deals the same eight cards and no type appears more than three times', () => {
  for (const seed of ['00000000', '11111111', '36938526', '01234567']) {
    const match = createMatch(seed);
    assert.deepEqual(match, createMatch(seed));
    assert.deepEqual(match.pool, [0, 1, 2, 3, 4, 5, 6, 7]);
    assert.equal(match.cards.length, 8);
    for (const type of match.cards) assert.ok(['Rock', 'Paper', 'Scissors'].includes(type));
    for (const type of ['Rock', 'Paper', 'Scissors']) {
      assert.ok(match.cards.filter(card => card === type).length <= 3, seed);
    }
    assert.equal(match.firstPlayer, Number(seed[0]) % 2 + 1);
  }
  assert.notDeepEqual(createMatch('00000000').cards, createMatch('11111111').cards);
  for (const invalid of ['', '1234567', '123456789', '0123456x', 12345678]) {
    assert.throws(() => createMatch(invalid));
  }
});

test('independent clients agree after drafting, an exchange and a swap by each player', () => {
  const left = createMatch('01234567');
  const right = createMatch('01234567');
  draftSix(left);
  assert.deepEqual(right.hands, { 1: [], 2: [] });
  assert.deepEqual(left.hands, { 1: [0, 2, 4], 2: [1, 3, 5] });
  assert.deepEqual(left.pool, [6, 7]);
  assert.equal(left.phase, 'exchange');
  draftSix(right);

  const moves = [
    { sequence: 7, player: 1, type: 'exchange', outgoingId: 2, incomingId: 6 },
    { sequence: 8, player: 2, type: 'swap', from: 1, to: 2 },
    { sequence: 9, player: 1, type: 'swap', from: 0, to: 2 },
  ];
  for (const move of moves) {
    applyMove(left, move);
    applyMove(right, move);
    assert.deepEqual(left, right);
  }
  assert.equal(left.phase, 'order');
  assert.deepEqual(left.hands, { 1: [4, 6, 0], 2: [1, 5, 3] });
  assert.deepEqual([...left.pool].sort((a, b) => a - b), [2, 7]);
  assert.equal(left.lastSequence, 9);
});

test('only the first player may exchange or keep, and only once', () => {
  const match = createMatch('01234567');
  draftSix(match);
  assertRejected(match, { sequence: 7, player: 2, type: 'keep' });
  assertRejected(match, { sequence: 7, player: 2, type: 'exchange', outgoingId: 1, incomingId: 7 });
  assertRejected(match, { sequence: 7, player: 1, type: 'exchange', outgoingId: 1, incomingId: 7 });
  assertRejected(match, { sequence: 7, player: 1, type: 'exchange', outgoingId: 2, incomingId: 3 });
  applyMove(match, { sequence: 7, player: 1, type: 'keep' });
  assert.deepEqual(match.hands, { 1: [0, 2, 4], 2: [1, 3, 5] });
  assert.equal(match.phase, 'order');
  assertRejected(match, { sequence: 8, player: 1, type: 'exchange', outgoingId: 2, incomingId: 7 });
  assertRejected(match, { sequence: 8, player: 2, type: 'swap', from: 0, to: 3 });
});

test('the draft rejects wrong turns, unavailable cards, duplicate moves and gaps', () => {
  const match = createMatch('12345678');
  const first = { sequence: 1, player: 2, type: 'pick', cardId: 0 };
  assertRejected(match, { ...first, player: 1 });
  assertRejected(match, { ...first, cardId: 8 });
  applyMove(match, first);
  assertRejected(match, first);
  assertRejected(match, { sequence: 3, player: 1, type: 'pick', cardId: 1 });
  assertRejected(match, { sequence: 2, player: 1, type: 'pick', cardId: 0 });
  applyMove(match, { sequence: 2, player: 1, type: 'pick', cardId: 1 });
  assert.deepEqual(match.hands, { 1: [1], 2: [0] });
});
