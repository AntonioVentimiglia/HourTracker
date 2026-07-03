import test from 'node:test';
import assert from 'node:assert/strict';
import { computeBilledBlocks, BLOCK_SECONDS } from '../src/services/billing.js';

// Helper: build an interval from "minutes:seconds after an arbitrary T0".
const T0 = 1_000_000_000; // arbitrary epoch anchor
const at = (min, sec = 0) => T0 + min * 60 + sec;
const interval = (startMin, endMin) => ({ startSec: at(startMin), endSec: at(endMin) });
const min = (n) => n * 60;

test('single 1-minute clock-in bills a full 15-minute block', () => {
  const r = computeBilledBlocks([interval(0, 1)]);
  assert.equal(r.blocks.length, 1);
  assert.equal(r.billedSeconds, min(15));
  assert.equal(r.rawSeconds, min(1));
});

test('a second clock-in within the 15-min window adds nothing', () => {
  // 9:00-9:01 and 9:10-9:11 both inside the first [0,15) block.
  const r = computeBilledBlocks([interval(0, 1), interval(10, 11)]);
  assert.equal(r.blocks.length, 1, 'still one block');
  assert.equal(r.billedSeconds, min(15));
  assert.equal(r.rawSeconds, min(2));
});

test('work that spills >= 1 min past the window opens a second block', () => {
  // starts inside first block, ends at 16 min = 1 min past the 15-min boundary.
  const r = computeBilledBlocks([interval(0, 1), interval(14, 16)]);
  assert.equal(r.blocks.length, 2);
  assert.equal(r.billedSeconds, min(30));
});

test('spillover of LESS than 1 min is rounded down (no new block)', () => {
  // ends 30s past the boundary -> stays a single block.
  const r = computeBilledBlocks([{ startSec: at(14), endSec: at(15, 30) }]);
  assert.equal(r.blocks.length, 1);
  assert.equal(r.billedSeconds, min(15));
});

test('exactly 1 min past the boundary DOES open a new block', () => {
  const r = computeBilledBlocks([{ startSec: at(0), endSec: at(16, 0) }]);
  assert.equal(r.blocks.length, 2);
});

test('a gap in activity anchors a fresh block', () => {
  // 9:00-9:01, then 9:20-9:21 (past the first [0,15) block) -> two blocks.
  const r = computeBilledBlocks([interval(0, 1), interval(20, 21)]);
  assert.equal(r.blocks.length, 2);
  assert.equal(r.billedSeconds, min(30));
  // Second block is anchored at the second clock-in (20), not at 15.
  assert.equal(r.blocks[1].startSec, at(20));
});

test('long continuous session chains multiple contiguous blocks', () => {
  // 40 minutes straight -> blocks [0,15) [15,30) [30,45) = 45 min billed.
  const r = computeBilledBlocks([interval(0, 40)]);
  assert.equal(r.blocks.length, 3);
  assert.equal(r.billedSeconds, min(45));
  assert.equal(r.rawSeconds, min(40));
});

test('blocks are aligned to the clock-in time, not wall-clock quarters', () => {
  // clock in at 7 min past T0, spill to 25 -> blocks anchored at 7 and 22.
  const r = computeBilledBlocks([interval(7, 25)]);
  assert.equal(r.blocks[0].startSec, at(7));
  assert.equal(r.blocks[1].startSec, at(22));
});

test('empty / zero-length intervals bill nothing', () => {
  assert.equal(computeBilledBlocks([]).billedSeconds, 0);
  assert.equal(computeBilledBlocks([{ startSec: at(0), endSec: at(0) }]).billedSeconds, 0);
});

test('BLOCK_SECONDS is 15 minutes', () => {
  assert.equal(BLOCK_SECONDS, 900);
});
