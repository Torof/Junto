// « 12,4 km · D+ 830 m » — the one way a trace's figures are written, in the
// creation form, the GPX library, the pickers. Either part is dropped when
// missing; null when there is nothing to say.
export function formatTraceStats(
  distanceKm: number | string | null | undefined,
  elevationGainM: number | null | undefined,
  locale: string,
): string | null {
  const parts: string[] = [];
  const km = distanceKm != null ? Number(distanceKm) : null;
  if (km != null && Number.isFinite(km) && km > 0) {
    parts.push(`${km.toLocaleString(locale, { maximumFractionDigits: 1 })} km`);
  }
  if (elevationGainM != null && elevationGainM > 0) {
    parts.push(`D+ ${elevationGainM.toLocaleString(locale)} m`);
  }
  return parts.length > 0 ? parts.join(' · ') : null;
}
