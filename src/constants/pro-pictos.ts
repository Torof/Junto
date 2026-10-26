// Pictos of the pro pin that are not sports (Scott 2026-10-26, planche
// « Les treize métiers »): drawn for Junto as flat 24-box shapes, in the
// currentColor format of the sport set so the same renderer paints them.
//   lotus      — wellness professions (the simple lotus, not a yoga posture)
//   school     — school / office (a building with a pennant, not a house)
//   briefcase  — « other »
export const PRO_PICTO_XML: Record<string, string> = {
  lotus: '<svg viewBox="0 0 24 24"><g fill="currentColor"><path d="M12 3 C 9.5 6 9 9.5 12 13.5 C 15 9.5 14.5 6 12 3 Z"/><path d="M5.5 7 C 8.5 7.5 10.5 10 11 14.5 C 7.5 13.5 5.5 11 5.5 7 Z"/><path d="M18.5 7 C 15.5 7.5 13.5 10 13 14.5 C 16.5 13.5 18.5 11 18.5 7 Z"/><path d="M2 12 C 4 16.5 7.5 19.5 12 19.5 C 16.5 19.5 20 16.5 22 12 C 18.5 13 15.5 14.5 12 17.5 C 8.5 14.5 5.5 13 2 12 Z"/></g></svg>',
  school: '<svg viewBox="0 0 24 24"><g fill="currentColor"><path d="M3 20 V 11 L 12 5 L 21 11 V 20 H 15 V 15 H 9 V 20 Z"/><rect x="11" y="1.5" width="2" height="4"/><path d="M13 1.5 H 16.5 L 15.5 3 L 16.5 4.5 H 13 Z"/></g></svg>',
  briefcase: '<svg viewBox="0 0 24 24"><g fill="currentColor"><path d="M9 7 V 5.5 A 2 2 0 0 1 11 3.5 H 13 A 2 2 0 0 1 15 5.5 V 7 H 19 A 2 2 0 0 1 21 9 V 12 H 3 V 9 A 2 2 0 0 1 5 7 Z M 10.6 7 H 13.4 V 5.6 A 0.6 0.6 0 0 0 12.8 5 H 11.2 A 0.6 0.6 0 0 0 10.6 5.6 Z"/><path d="M3 13.5 H 10 V 15.5 H 14 V 13.5 H 21 V 19 A 2 2 0 0 1 19 21 H 5 A 2 2 0 0 1 3 19 Z"/></g></svg>',
};
