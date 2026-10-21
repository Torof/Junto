// Android flags a fix produced by a mock-location app (developer option used
// by GPS spoofers). Such a fix is never evidence of presence: every path that
// would send it to confirm_presence_via_geo or the offline replay cache drops
// it (audit 2026-10, H1 — Scott: refuse spoofed positions, nothing else).
export function isMockedFix(fix: { mocked?: boolean } | null | undefined): boolean {
  return fix?.mocked === true;
}
