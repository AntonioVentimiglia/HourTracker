import { DateTime, Interval } from 'luxon';

// Duration is always computed from real UTC instants, never naive local
// subtraction, so DST transitions and timezone travel are handled correctly.
export function durationSeconds(startUtc, endUtc) {
  if (!endUtc) return null;
  const start = DateTime.fromISO(startUtc, { zone: 'utc' });
  const end = DateTime.fromISO(endUtc, { zone: 'utc' });
  return Math.max(0, Math.round(end.diff(start, 'seconds').seconds));
}

// The local date on which an instant falls, in a given zone. Used to bucket
// events/sessions into calendar days for the user.
export function localDate(utcIso, zone) {
  return DateTime.fromISO(utcIso, { zone: 'utc' }).setZone(zone).toISODate();
}

// Splits a session's duration across the calendar days it spans, so a session
// crossing midnight contributes the right number of hours to each day.
// Returns a map of { 'YYYY-MM-DD': seconds }.
export function allocateAcrossDays(startUtc, endUtc, zone) {
  const start = DateTime.fromISO(startUtc, { zone: 'utc' }).setZone(zone);
  const end = (endUtc ? DateTime.fromISO(endUtc, { zone: 'utc' } ) : DateTime.utc()).setZone(zone);
  const out = {};
  if (end <= start) return out;

  let cursor = start;
  while (cursor < end) {
    const dayEnd = cursor.plus({ days: 1 }).startOf('day');
    const sliceEnd = dayEnd < end ? dayEnd : end;
    const seconds = Math.round(sliceEnd.diff(cursor, 'seconds').seconds);
    const key = cursor.toISODate();
    out[key] = (out[key] || 0) + seconds;
    cursor = sliceEnd;
  }
  return out;
}

// Returns [startISO, endISO] in UTC for the week containing `dateIso`,
// respecting the user's chosen week start (0 = Sunday, 1 = Monday).
export function weekBoundsUtc(dateIso, zone, weekStartsOn) {
  let d = DateTime.fromISO(dateIso, { zone }).startOf('day');
  // Luxon weekday: 1 = Monday ... 7 = Sunday
  const weekdayIndex = d.weekday % 7; // 0 = Sunday
  const diff = (weekdayIndex - weekStartsOn + 7) % 7;
  const start = d.minus({ days: diff });
  const end = start.plus({ days: 7 });
  return [start.toUTC().toISO(), end.toUTC().toISO()];
}

export function monthBoundsUtc(monthIso, zone) {
  const start = DateTime.fromISO(`${monthIso}-01`, { zone }).startOf('month');
  const end = start.plus({ months: 1 });
  return [start.toUTC().toISO(), end.toUTC().toISO()];
}

export function dayBoundsUtc(dateIso, zone) {
  const start = DateTime.fromISO(dateIso, { zone }).startOf('day');
  const end = start.plus({ days: 1 });
  return [start.toUTC().toISO(), end.toUTC().toISO()];
}

export function humanDuration(seconds) {
  if (seconds == null) return '0m';
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  if (h && m) return `${h}h ${m}m`;
  if (h) return `${h}h`;
  return `${m}m`;
}

// Spoken form for Siri confirmations, e.g. "2 hours and 16 minutes".
export function spokenDuration(seconds) {
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds % 3600) / 60);
  const parts = [];
  if (h) parts.push(`${h} ${h === 1 ? 'hour' : 'hours'}`);
  if (m) parts.push(`${m} ${m === 1 ? 'minute' : 'minutes'}`);
  if (!parts.length) return 'less than a minute';
  return parts.join(' and ');
}

export function spokenTime(utcIso, zone) {
  return DateTime.fromISO(utcIso, { zone: 'utc' }).setZone(zone).toFormat('h:mm a');
}

export { DateTime, Interval };
