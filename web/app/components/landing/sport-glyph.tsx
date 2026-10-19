import { SPORT_ICON_XML } from './sport-icon-svgs';

// The app's sport glyph, on the web. The SVG strings are our own static
// assets (copied from the app), rendered inline so `color` drives the fill
// through currentColor — universe colour on cards, white on a coloured pin.
export function hasSportGlyph(sportKey: string | null | undefined): boolean {
  return !!sportKey && sportKey in SPORT_ICON_XML;
}

export default function SportGlyph({ sportKey, size = 16, color = 'currentColor' }: { sportKey: string | null | undefined; size?: number; color?: string }) {
  const xml = sportKey ? SPORT_ICON_XML[sportKey] : undefined;
  if (!xml) return null;
  return (
    <span
      className="l-glyph"
      style={{ width: size, height: size, color }}
      aria-hidden
      dangerouslySetInnerHTML={{ __html: xml }}
    />
  );
}

// French labels used in the demo form and the illustrative cards → app keys.
export const LABEL_TO_KEY: Record<string, string> = {
  Escalade: 'climbing-sport', 'Grande voie': 'climbing-multipitch', Alpinisme: 'mountaineering', Alpi: 'mountaineering',
  'Via ferrata': 'via-ferrata', 'Ski de rando': 'ski-touring', Canyoning: 'canyoning', Kayak: 'kayaking',
  'Planche à voile': 'windsurfing', Natation: 'swimming', Parapente: 'paragliding', Gravel: 'gravel',
  'VTT enduro': 'mtb-enduro', Enduro: 'mtb-enduro', Route: 'cycling', Randonnée: 'hiking', Rando: 'hiking',
  Trail: 'trail-running', Trek: 'trekking', Yoga: 'yoga', 'Marche nordique': 'nordic-walking',
  Kitesurf: 'kitesurfing', Wingfoil: 'wingfoil',
};
