import { DateTime } from 'luxon';

// Legal minimum-increment billing. Every engagement is billed in 15-minute
// blocks, so a 1-minute call still bills 15 minutes. Blocks chain: once you're
// clocked in, additional work inside the same 15-minute window is free, but
// work that spills past the window opens the next block.
export const BLOCK_SECONDS = 15 * 60; // 15-minute billing increment
export const GRACE_SECONDS = 60;      // spillover < 1 min past a block is rounded down

/**
 * Core algorithm. Given raw work intervals (closed clock-in/out spans), returns
 * the billed 15-minute blocks and totals.
 *
 * Rules (from the spec):
 *  1. The first moment of work anchors a 15-minute block AT its start time
 *     (blocks are aligned to the clock-in, not to wall-clock quarter hours).
 *  2. Work that falls inside an already-owned block adds nothing.
 *  3. Work that spills past current coverage by >= 1 minute opens the next
 *     contiguous 15-minute block. Repeats for longer spills.
 *  4. Spillover of LESS than 1 minute is rounded down — the block boundary
 *     holds and no new block is added ("like it never happened").
 *  5. Work that starts at/after the end of all current coverage (a gap in
 *     activity) anchors a brand-new block at that start time.
 *
 * @param intervals [{ startSec, endSec, sessionId? }] epoch seconds, closed.
 * @returns { blocks: [{startSec, endSec, sessionId?}], billedSeconds, rawSeconds }
 */
export function computeBilledBlocks(intervals, { blockSeconds = BLOCK_SECONDS, graceSeconds = GRACE_SECONDS } = {}) {
  const sorted = intervals
    .filter((i) => i.endSec != null && i.endSec > i.startSec)
    .sort((a, b) => a.startSec - b.startSec);

  const blocks = [];
  let coveredUntil = null;
  let rawSeconds = 0;

  for (const { startSec, endSec, sessionId } of sorted) {
    rawSeconds += endSec - startSec;

    // (5) / (1) Anchor a fresh block if this work begins at or after coverage.
    if (coveredUntil === null || startSec >= coveredUntil) {
      blocks.push({ startSec, endSec: startSec + blockSeconds, sessionId });
      coveredUntil = startSec + blockSeconds;
    }

    // (3) Extend coverage while work spills >= grace past the current boundary.
    // (4) A remaining spill of < grace exits the loop and is rounded down.
    while (endSec - coveredUntil >= graceSeconds) {
      blocks.push({ startSec: coveredUntil, endSec: coveredUntil + blockSeconds, sessionId });
      coveredUntil += blockSeconds;
    }
  }

  return {
    blocks,
    billedSeconds: blocks.length * blockSeconds,
    rawSeconds,
  };
}

/**
 * Applies the billing algorithm to persisted sessions, grouping by local
 * calendar day so the block chain resets at midnight in the user's zone (a
 * late-night engagement doesn't chain into the next day, and weekly/monthly
 * totals are just the sum of their days).
 *
 * Only CLOSED sessions are billed; an open (still-running) session isn't billed
 * until it's clocked out.
 *
 * @param sessions serialized WorkSession objects (camelCase, ISO strings)
 * @returns { blocks, billedSeconds, rawSeconds, billedByDay }
 */
export function billSessions(sessions, zone, opts = {}) {
  const byDay = new Map();
  for (const s of sessions) {
    if (!s.endUtc || s.status === 'deleted') continue;
    const start = DateTime.fromISO(s.startUtc, { zone: 'utc' });
    const end = DateTime.fromISO(s.endUtc, { zone: 'utc' });
    const day = start.setZone(zone).toISODate();
    if (!byDay.has(day)) byDay.set(day, []);
    byDay.get(day).push({ startSec: start.toSeconds(), endSec: end.toSeconds(), sessionId: s.id });
  }

  const blocks = [];
  const billedByDay = {};
  let billedSeconds = 0;
  let rawSeconds = 0;

  for (const [day, intervals] of byDay) {
    const res = computeBilledBlocks(intervals, opts);
    billedByDay[day] = res.billedSeconds;
    billedSeconds += res.billedSeconds;
    rawSeconds += res.rawSeconds;
    for (const b of res.blocks) {
      blocks.push({
        day,
        // "Z"-style ISO to match the timestamp format used elsewhere in the API.
        startUtc: new Date(b.startSec * 1000).toISOString(),
        endUtc: new Date(b.endSec * 1000).toISOString(),
        sessionId: b.sessionId,
      });
    }
  }

  blocks.sort((a, b) => a.startUtc.localeCompare(b.startUtc));
  return { blocks, billedSeconds, rawSeconds, billedByDay };
}
