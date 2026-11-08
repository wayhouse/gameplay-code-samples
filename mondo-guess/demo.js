'use strict';

const assert = require('node:assert/strict');
const { createMatch, applyMove } = require('./match.js');

try {
  replay(process.argv[2] ?? '36938526');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}

function replay(seed) {
  const clientA = createMatch(seed);
  const clientB = createMatch(seed);
  const first = clientA.firstPlayer;
  const second = 3 - first;
  const moves = [
    { player: first,  type: 'pick', cardId: 3 },
    { player: second, type: 'pick', cardId: 7 },
    { player: first,  type: 'pick', cardId: 4 },
    { player: second, type: 'pick', cardId: 1 },
    { player: first,  type: 'pick', cardId: 0 },
    { player: second, type: 'pick', cardId: 5 },
    { player: first,  type: 'exchange', outgoingId: 4, incomingId: 6 },
    { player: first,  type: 'swap', from: 0, to: 2 },
    { player: second, type: 'swap', from: 1, to: 2 },
  ];

  assert.deepStrictEqual(clientA, clientB);
  console.log(`Room ${seed} | Player ${first} picks first`);
  console.log('Deal:', clientA.cards.map((sign, id) => `${id}=${sign}`).join(', '));
  for (const [index, move] of moves.entries()) {
    const message = JSON.stringify({ sequence: index + 1, ...move });
    // Each client receives the same message and owns its own match state.
    applyMove(clientA, JSON.parse(message));
    applyMove(clientB, JSON.parse(message));
    assert.deepStrictEqual(clientA, clientB);
    console.log(message);
  }
  for (const player of [1, 2]) {
    const cards = clientA.hands[player].map(id => `${clientA.cards[id]} (#${id})`);
    console.log(`Player ${player} hand: ${cards.join(' | ')}`);
  }
  console.log(`Verified: both clients agreed on the deal and after all ${moves.length} moves.`);
}
