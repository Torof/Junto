// Ramer–Douglas–Peucker path simplification, on screen-space points {x,y}.
// Used by the freehand GPX draw mode: a finger stroke yields hundreds of raw
// points; we thin them (in pixels, before the screen→geo conversion) so we
// convert & store only what matters. Zero dependency.

export interface Pt {
  x: number;
  y: number;
}

// Perpendicular distance from p to the segment a→b (pixels).
function perpendicularDistance(p: Pt, a: Pt, b: Pt): number {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  if (dx === 0 && dy === 0) return Math.hypot(p.x - a.x, p.y - a.y);
  const t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy);
  const projX = a.x + t * dx;
  const projY = a.y + t * dy;
  return Math.hypot(p.x - projX, p.y - projY);
}

// Returns a thinned copy keeping the shape within `tolerance` pixels.
export function simplifyRDP(points: Pt[], tolerance = 3): Pt[] {
  if (points.length <= 2) return points;
  const first = points[0]!;
  const last = points[points.length - 1]!;

  let maxDist = 0;
  let index = 0;
  for (let i = 1; i < points.length - 1; i++) {
    const d = perpendicularDistance(points[i]!, first, last);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }

  if (maxDist > tolerance) {
    const left = simplifyRDP(points.slice(0, index + 1), tolerance);
    const right = simplifyRDP(points.slice(index), tolerance);
    // drop the duplicated join point
    return [...left.slice(0, -1), ...right];
  }
  return [first, last];
}
