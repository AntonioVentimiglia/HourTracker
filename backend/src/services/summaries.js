import { listSessions, allocateAcrossDays } from './sessions.js';
import {
  dayBoundsUtc, weekBoundsUtc, monthBoundsUtc, humanDuration, DateTime,
} from './time.js';

function summarize(sessions, zone) {
  const totalSeconds = sessions.reduce((s, x) => s + (x.durationSeconds || 0), 0);
  const closed = sessions.filter((s) => s.endUtc);
  const open = sessions.filter((s) => !s.endUtc);
  const starts = sessions.map((s) => s.startUtc).sort();
  const ends = closed.map((s) => s.endUtc).sort();
  const notes = sessions.map((s) => s.note).filter(Boolean);

  return {
    totalSeconds,
    totalHuman: humanDuration(totalSeconds),
    sessionCount: sessions.length,
    firstClockIn: starts[0] || null,
    lastClockOut: ends[ends.length - 1] || null,
    openSessions: open.length,
    notes,
    warnings: sessions.flatMap((s) => s.validationWarnings || []),
  };
}

export function dailySummary(userId, dateIso, zone) {
  const [startUtc, endUtc] = dayBoundsUtc(dateIso, zone);
  const sessions = listSessions({ userId, startUtc, endUtc });
  // Allocate cross-midnight time so this day gets only its own slice.
  let allocated = 0;
  for (const s of sessions) {
    const map = allocateAcrossDays(s.startUtc, s.endUtc, zone);
    allocated += map[dateIso] || 0;
  }
  const base = summarize(sessions, zone);
  return { date: dateIso, ...base, allocatedSeconds: allocated, allocatedHuman: humanDuration(allocated), sessions };
}

export function weeklySummary(userId, weekStartIso, zone, weekStartsOn = 0) {
  const [startUtc, endUtc] = weekBoundsUtc(weekStartIso, zone, weekStartsOn);
  const sessions = listSessions({ userId, startUtc, endUtc });
  const days = {};
  for (const s of sessions) {
    const map = allocateAcrossDays(s.startUtc, s.endUtc, zone);
    for (const [day, sec] of Object.entries(map)) days[day] = (days[day] || 0) + sec;
  }
  const dayList = Object.entries(days).map(([date, seconds]) => ({
    date, seconds, human: humanDuration(seconds),
  })).sort((a, b) => a.date.localeCompare(b.date));
  const total = dayList.reduce((s, d) => s + d.seconds, 0);
  const longest = dayList.reduce((m, d) => (d.seconds > (m?.seconds || 0) ? d : m), null);
  const activeDays = dayList.filter((d) => d.seconds > 0).length || 1;

  return {
    weekStart: DateTime.fromISO(startUtc, { zone: 'utc' }).setZone(zone).toISODate(),
    ...summarize(sessions, zone),
    totalSeconds: total,
    totalHuman: humanDuration(total),
    dailyBreakdown: dayList,
    averagePerDaySeconds: Math.round(total / activeDays),
    averagePerDayHuman: humanDuration(Math.round(total / activeDays)),
    longestDay: longest,
    sessions,
  };
}

export function monthlySummary(userId, monthIso, zone) {
  const [startUtc, endUtc] = monthBoundsUtc(monthIso, zone);
  const sessions = listSessions({ userId, startUtc, endUtc });
  const days = {};
  for (const s of sessions) {
    const map = allocateAcrossDays(s.startUtc, s.endUtc, zone);
    for (const [day, sec] of Object.entries(map)) days[day] = (days[day] || 0) + sec;
  }
  const heatmap = Object.entries(days).map(([date, seconds]) => ({
    date, seconds, human: humanDuration(seconds),
  })).sort((a, b) => a.date.localeCompare(b.date));
  const total = heatmap.reduce((s, d) => s + d.seconds, 0);
  return {
    month: monthIso,
    ...summarize(sessions, zone),
    totalSeconds: total,
    totalHuman: humanDuration(total),
    heatmap,
    sessions,
  };
}

export function csvExport(sessions, zone) {
  const header = ['session_id', 'start_local', 'end_local', 'duration_hours', 'note', 'status', 'source', 'warnings'];
  const rows = sessions.map((s) => {
    const startLocal = DateTime.fromISO(s.startUtc, { zone: 'utc' }).setZone(zone).toFormat('yyyy-LL-dd HH:mm');
    const endLocal = s.endUtc ? DateTime.fromISO(s.endUtc, { zone: 'utc' }).setZone(zone).toFormat('yyyy-LL-dd HH:mm') : '';
    const hours = s.durationSeconds != null ? (s.durationSeconds / 3600).toFixed(2) : '';
    const note = (s.note || '').replace(/"/g, '""');
    return [s.id, startLocal, endLocal, hours, `"${note}"`, s.status, s.source, (s.validationWarnings || []).join('|')].join(',');
  });
  return [header.join(','), ...rows].join('\n');
}
