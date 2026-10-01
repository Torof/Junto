/**
 * Parse a Postgres `interval` as PostgREST serialises it, into milliseconds.
 *
 * Why this exists: the same ad-hoc parser was duplicated in activity-detail and
 * the peer-review screen, and neither handled the `day` component. Postgres
 * renders an interval over 24 h as `1 day 02:00:00` (default IntervalStyle), so
 * a 26-hour outing produced NaN from `Number('1 day 02')`. NaN poisons every
 * presence comparison — `isInQrWindow`, `showPeerBackstop` and the review
 * window all silently became false, leaving an outing with NO presence UI at
 * all and no error anywhere. `activities.duration` has no upper bound in the
 * schema (only `>= 15 minutes`), so this is reachable with a multi-day trek.
 *
 * Handles, in order: `N day[s] HH:MM:SS[.ffffff]`, `N day[s]`, `HH:MM:SS`
 * (including hour counts above 24), and the verbose `N hours M mins` form.
 */
const DEFAULT_MS = 2 * 60 * 60 * 1000;

export function parsePgIntervalMs(raw: string | null | undefined): number {
  if (!raw) return DEFAULT_MS;
  const d = raw.trim();
  let total = 0;
  let matched = false;

  // `N day` / `N days`, optionally followed by a clock part.
  const days = d.match(/(-?\d+)\s+days?/i);
  if (days) {
    total += parseInt(days[1]!, 10) * 86400 * 1000;
    matched = true;
  }

  // Clock part `HH:MM[:SS[.ffffff]]` — hours may exceed 24 when there is no
  // day component (e.g. `26:00:00`).
  const clock = d.match(/(-?\d+):(\d{1,2})(?::(\d{1,2})(?:\.\d+)?)?/);
  if (clock) {
    const h = parseInt(clock[1]!, 10);
    const m = parseInt(clock[2]!, 10);
    const s = clock[3] != null ? parseInt(clock[3], 10) : 0;
    // A negative clock part applies to the whole clock group, not just hours.
    const sign = h < 0 ? -1 : 1;
    total += sign * (Math.abs(h) * 3600 + m * 60 + s) * 1000;
    matched = true;
  } else {
    // Verbose form: `2 hours 30 mins`, `90 mins`, `1 hour`.
    const hours = d.match(/(-?\d+)\s*hours?/i);
    const mins = d.match(/(-?\d+)\s*(?:mins?|minutes?)/i);
    const secs = d.match(/(-?\d+)\s*(?:secs?|seconds?)/i);
    if (hours) { total += parseInt(hours[1]!, 10) * 3600 * 1000; matched = true; }
    if (mins) { total += parseInt(mins[1]!, 10) * 60 * 1000; matched = true; }
    if (secs) { total += parseInt(secs[1]!, 10) * 1000; matched = true; }
  }

  if (!matched || !Number.isFinite(total)) return DEFAULT_MS;
  return total;
}
