'use strict';

const SIGNS = ['Rock', 'Paper', 'Scissors'];
const HAND_SIZE = 3;

function createMatch(seed) {
  if (typeof seed !== 'string' || !/^[0-9]{8}$/.test(seed)) {
    throw new Error('The room seed must be an eight-digit string.');
  }

  // The card's original position remains its ID after it moves to a hand.
  const remaining = [3, 3, 3];
  const cards = Array.from(seed, digit => {
    let sign = Number(digit) % SIGNS.length;
    if (remaining[sign] === 0) {
      // Prefer the least-used sign. Array order breaks ties on both clients.
      sign = remaining.indexOf(Math.max(...remaining));
    }
    remaining[sign]--;
    return SIGNS[sign];
  });

  return {
    cards,
    pool: cards.map((_, id) => id),
    hands: { 1: [], 2: [] },
    firstPlayer: (Number(seed[0]) % 2) + 1,
    phase: 'draft',
    lastSequence: 0,
  };
}

function pick(match, move) {
  const picksMade = match.cards.length - match.pool.length;
  const nextPlayer = picksMade % 2 === 0 ? match.firstPlayer : 3 - match.firstPlayer;
  if (match.phase !== 'draft' || move.player !== nextPlayer) {
    throw new Error('Only the current drafter can pick a card.');
  }
  const poolSlot = match.pool.indexOf(move.cardId);
  if (poolSlot === -1) throw new Error('That card is no longer in the pool.');

  match.pool.splice(poolSlot, 1);
  match.hands[move.player].push(move.cardId);
  if (picksMade + 1 === HAND_SIZE * 2) match.phase = 'exchange';
}

function finishExchange(match, move) {
  if (match.phase !== 'exchange' || move.player !== match.firstPlayer) {
    throw new Error('Only the first drafter can exchange or keep their hand, once.');
  }
  if (move.type === 'exchange') {
    const hand = match.hands[move.player];
    const handSlot = hand.indexOf(move.outgoingId);
    const poolSlot = match.pool.indexOf(move.incomingId);
    if (handSlot === -1 || poolSlot === -1) {
      throw new Error('Exchange requires a card from your hand and a card from the pool.');
    }
    hand[handSlot] = move.incomingId;
    match.pool[poolSlot] = move.outgoingId;
  }
  match.phase = 'order';
}

function swapSlots(match, move) {
  if (match.phase !== 'order') throw new Error('Hand ordering follows the exchange.');
  const hand = match.hands[move.player];
  for (const slot of [move.from, move.to]) {
    if (!Number.isInteger(slot) || slot < 0 || slot >= hand.length) {
      throw new Error('Hand slots must be integers within your hand.');
    }
  }
  [hand[move.from], hand[move.to]] = [hand[move.to], hand[move.from]];
}

function applyMove(match, move) {
  if (move.sequence !== match.lastSequence + 1) {
    throw new Error(`Expected move ${match.lastSequence + 1}, received ${move.sequence}.`);
  }
  if (move.player !== 1 && move.player !== 2) throw new Error('Unknown player.');

  switch (move.type) {
    case 'pick':
      pick(match, move);
      break;
    case 'exchange':
    case 'keep':
      finishExchange(match, move);
      break;
    case 'swap':
      swapSlots(match, move);
      break;
    default:
      throw new Error(`Unknown move: ${move.type}`);
  }
  match.lastSequence = move.sequence;
}

module.exports = { createMatch, applyMove };
