// Europe/Paris wall-clock helpers shared by the calendar functions. Half-days
// (00568): morning 08:00-13:00, afternoon 13:00-19:00, Paris time.

export const HALF_DAYS = { am: [8, 13], pm: [13, 19] } as const;

const fmt = new Intl.DateTimeFormat('en-US', {
  timeZone: 'Europe/Paris', hourCycle: 'h23',
  year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit',
});

function parts(d: Date): Record<string, number> {
  const out: Record<string, number> = {};
  for (const p of fmt.formatToParts(d)) if (p.type !== 'literal') out[p.type] = Number(p.value);
  return out;
}

// Minutes Paris is ahead of UTC at instant d.
function offsetMinutes(d: Date): number {
  const p = parts(d);
  return Math.round((Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - d.getTime()) / 60000);
}

// 'YYYY-MM-DD' + Paris hour → UTC instant.
export function parisToUtc(day: string, hour: number): Date {
  const guess = new Date(`${day}T${String(hour).padStart(2, '0')}:00:00Z`);
  return new Date(guess.getTime() - offsetMinutes(guess) * 60000);
}

// UTC instant → Paris calendar day 'YYYY-MM-DD'.
export function parisDay(d: Date): string {
  const p = parts(d);
  return `${p.year}-${String(p.month).padStart(2, '0')}-${String(p.day).padStart(2, '0')}`;
}

export function addDays(day: string, n: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
