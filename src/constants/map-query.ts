// Row cap for every map viewport fetch (sorties, pros, offres). Three times
// what a phone screen can show declustered, and well under PostgREST's silent
// 1000-row cut. When a response hits the cap the map says so once (toast),
// so the user zooms in instead of trusting an incomplete field. Sorties are
// ordered by start date, so the ones furthest in time fade out first.
export const MAP_FETCH_CAP = 300;
