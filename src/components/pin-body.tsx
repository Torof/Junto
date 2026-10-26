import { Path, Defs, Filter, FeGaussianBlur } from 'react-native-svg';
import { PIN_DROP_PATH, PIN_OUTLINE, PIN_SHADOW_FAR, PIN_SHADOW_NEAR } from '@/constants/pin-style';

// The pin silhouette as every map pin draws it (Scott 2026-10-23, « A » with
// the « B » shadow): a white outline that detaches the pin from any ground,
// then a two-layer shadow — a short sharp one that sets it on the map and a
// wide light one. Only FeGaussianBlur exists natively in react-native-svg,
// so each shadow is a blurred dark copy of the outlined shape, offset down.
// `outline` — white for every pin, gold for the pro pins (2026-10-25).
// `path` — the drop by default; the pro page pin passes its shield (2026-10-26).
// `edge` — an extra thin ring OUTSIDE the outline (the pro shield's ink edge).
// Must be rendered inside an <Svg>.
export function PinBody({
  fill, outline = PIN_OUTLINE.color, path = PIN_DROP_PATH, edge,
}: { fill: string; outline?: string; path?: string; edge?: { color: string; width: number } }) {
  const shadowWidth = edge ? edge.width : PIN_OUTLINE.width;
  return (
    <>
      <Defs>
        <Filter id="pinShadowFar" x="-50%" y="-50%" width="200%" height="200%">
          <FeGaussianBlur stdDeviation={PIN_SHADOW_FAR.blur} />
        </Filter>
        <Filter id="pinShadowNear" x="-50%" y="-50%" width="200%" height="200%">
          <FeGaussianBlur stdDeviation={PIN_SHADOW_NEAR.blur} />
        </Filter>
      </Defs>
      {[PIN_SHADOW_FAR, PIN_SHADOW_NEAR].map((s, i) => (
        <Path
          key={i}
          d={path}
          fill={s.color}
          stroke={s.color}
          strokeWidth={shadowWidth}
          strokeLinejoin="round"
          opacity={s.opacity}
          transform={`translate(${s.dx} ${s.dy})`}
          filter={`url(#${i === 0 ? 'pinShadowFar' : 'pinShadowNear'})`}
        />
      ))}
      {edge && <Path d={path} fill={edge.color} stroke={edge.color} strokeWidth={edge.width} strokeLinejoin="round" />}
      <Path d={path} fill={outline} stroke={outline} strokeWidth={PIN_OUTLINE.width} strokeLinejoin="round" />
      <Path d={path} fill={fill} />
    </>
  );
}
