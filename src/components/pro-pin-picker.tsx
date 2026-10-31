import { useMemo, useState } from 'react';
import { View, Pressable, StyleSheet } from 'react-native';
import { Image } from 'expo-image';
import { useTranslation } from 'react-i18next';
import { ImagePlus } from 'lucide-react-native';
import { AppText } from '@/components/app-text';
import { ProPin } from '@/components/pro-pin';
import { SportDropdown } from '@/components/sport-dropdown';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { PRO_PIN_ICONS } from '@/constants/pro-pin-icons';
import { PRO_GOLD } from '@/constants/pin-style';
import { isProProfession } from '@/constants/professions';

interface Props {
  displayName: string;
  profession: string | null;
  pinIcon: string | null;
  pinImageUrl: string | null;
  pinImageBusy: boolean;
  onPinIcon: (key: string | null) => void;
  onPickImage: () => void;
  onRemoveImage: () => void;
}

type Way = 'metier' | 'univers' | 'sport' | 'photo';
const UNIVERSE_KEYS = new Set(PRO_PIN_ICONS.map((o) => o.key));

// « Ton pin sur la carte » (Scott 2026-10-26, mockup « le formulaire pro »):
// the preview of the pin as the map shows it, then ONE row of four tiles —
// Métier · Univers · Sport · Photo — each drawn with the pin it would give
// this pro; the chosen tile takes the gold border. Under the row, only what
// the choice needs: nothing for the profession, the five universes, the
// chosen sport with « Changer », the photo with « Changer / Retirer ».
// Data: Métier = pin_icon NULL · Univers / Sport = the key · Photo =
// pin_image_url. The photo sits on top of the key: removing it falls back
// to the last key.
export function ProPinPicker({
  displayName, profession, pinIcon, pinImageUrl, pinImageBusy, onPinIcon, onPickImage, onRemoveImage,
}: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  // The Sport tile stays selected while the pro picks a sport (no key yet).
  const [wantSport, setWantSport] = useState(false);

  const isUniverse = !!pinIcon && UNIVERSE_KEYS.has(pinIcon);
  const way: Way = pinImageUrl ? 'photo' : isUniverse ? 'univers' : pinIcon || wantSport ? 'sport' : 'metier';
  const sportKey = pinIcon && !isUniverse ? pinIcon : null;
  const hasProfession = isProProfession(profession);
  const professionLabel = hasProfession
    ? t(`pro.profession.${profession}`, { defaultValue: profession ?? '' })
    : t('pro.pin.noProfession', { defaultValue: 'Renseigne ton métier' });
  const universeLabel = (key: string) => t(`partenaires.universe.${key}`, { defaultValue: key });
  const sportLabel = (key: string) => t(`sports.${key}`, { defaultValue: key });

  const caption =
    way === 'photo' ? t('pro.pin.photo', { defaultValue: 'Photo' })
      : way === 'univers' ? `${t('pro.pin.univers', { defaultValue: 'Univers' })} · ${universeLabel(pinIcon ?? '')}`
        : way === 'sport' && sportKey ? `${t('pro.pin.sport', { defaultValue: 'Sport' })} · ${sportLabel(sportKey)}`
          : `${t('pro.pin.metier', { defaultValue: 'Métier' })} · ${professionLabel}`;

  const chooseMetier = () => { setWantSport(false); onPinIcon(null); if (pinImageUrl) onRemoveImage(); };
  const chooseUniverse = (key: string) => { setWantSport(false); onPinIcon(key); if (pinImageUrl) onRemoveImage(); };
  const chooseSport = (key: string) => { setWantSport(false); onPinIcon(key); if (pinImageUrl) onRemoveImage(); };
  const tapUniversTile = () => chooseUniverse(isUniverse && pinIcon ? pinIcon : 'mountain');
  const tapSportTile = () => { if (sportKey) { if (pinImageUrl) onRemoveImage(); } else setWantSport(true); };

  // Each tile shows the pin that way would give THIS pro.
  const tiles: { way: Way; title: string; sub: string; pin: React.ReactNode }[] = [
    { way: 'metier', title: t('pro.pin.metier', { defaultValue: 'Métier' }),
      sub: hasProfession ? t('pro.pin.metierHint', { defaultValue: 'Le picto de ton métier' }) : professionLabel,
      pin: <ProPin displayName={displayName} profession={profession} /> },
    { way: 'univers', title: t('pro.pin.univers', { defaultValue: 'Univers' }),
      sub: t('pro.pin.universHint', { defaultValue: 'Montagne, eau…' }),
      pin: <ProPin displayName={displayName} pinIcon={isUniverse ? pinIcon : 'mountain'} /> },
    { way: 'sport', title: t('pro.pin.sport', { defaultValue: 'Sport' }),
      sub: t('pro.pin.sportHint', { defaultValue: 'Un des sports' }),
      pin: <ProPin displayName={displayName} pinIcon={sportKey ?? 'hiking'} /> },
    { way: 'photo', title: t('pro.pin.photo', { defaultValue: 'Photo' }),
      sub: pinImageBusy ? t('pro.pinLogoBusy', { defaultValue: 'Envoi…' }) : t('pro.pin.photoTileHint', { defaultValue: 'Ton logo ou une photo' }),
      pin: pinImageUrl
        ? <ProPin displayName={displayName} pinImageUrl={pinImageUrl} />
        : <View style={styles.photoPlaceholder}><ImagePlus size={18} color={colors.textSecondary} strokeWidth={2.2} /></View> },
  ];
  const onTile = (w: Way) => {
    if (w === 'metier') chooseMetier();
    else if (w === 'univers') tapUniversTile();
    else if (w === 'sport') tapSportTile();
    else onPickImage();
  };

  return (
    <View style={styles.card}>
      <AppText style={styles.label}>{t('pro.pinSection', { defaultValue: 'Ton pin sur la carte' })}</AppText>
      <AppText style={styles.intro}>
        {t('pro.pin.intro', { defaultValue: 'C’est l’icône qui te représente sur la carte. Choisis ce qu’elle montre : ton métier, un univers, un sport ou ta photo.' })}
      </AppText>
      <View style={styles.preview}>
        <ProPin displayName={displayName} pinIcon={pinIcon} profession={profession} pinImageUrl={pinImageUrl} />
        <View style={styles.captionChip}><AppText style={styles.captionText} numberOfLines={1}>{caption}</AppText></View>
      </View>

      <View style={styles.tiles}>
        {tiles.map((tile) => {
          const selected = tile.way === way;
          return (
            <Pressable
              key={tile.way}
              style={[styles.tile, selected && styles.tileSelected]}
              onPress={() => onTile(tile.way)}
              disabled={tile.way === 'photo' && pinImageBusy}
              accessibilityRole="button"
              accessibilityState={{ selected }}
            >
              <View style={styles.tilePin} pointerEvents="none">{tile.pin}</View>
              <AppText style={styles.tileTitle}>{tile.title}</AppText>
              <AppText style={styles.tileSub} numberOfLines={2}>{tile.sub}</AppText>
            </Pressable>
          );
        })}
      </View>

      {way === 'metier' && (
        <AppText style={styles.helper}>
          {hasProfession
            ? t('pro.pin.helperMetier', { defaultValue: 'Le pin montre ton métier. Choisis un univers, un sport ou une photo pour le changer.' })
            : t('pro.pin.helperNoProfession', { defaultValue: 'Renseigne ton métier ci-dessous : le pin le montrera.' })}
        </AppText>
      )}

      {way === 'univers' && (
        <View style={styles.sub}>
          <AppText style={styles.subHead}>{t('pro.pin.yourUniverse', { defaultValue: 'Ton univers' })}</AppText>
          <View style={styles.chips}>
            {PRO_PIN_ICONS.map((opt) => {
              const selected = pinIcon === opt.key;
              return (
                <Pressable
                  key={opt.key}
                  style={[styles.chip, selected && styles.chipSelected]}
                  onPress={() => chooseUniverse(opt.key)}
                  accessibilityLabel={universeLabel(opt.key)}
                  accessibilityState={{ selected }}
                >
                  <View style={styles.chipPin} pointerEvents="none"><ProPin displayName="" pinIcon={opt.key} /></View>
                </Pressable>
              );
            })}
          </View>
        </View>
      )}

      {way === 'sport' && (
        <View style={styles.sub}>
          <View style={styles.row}>
            {sportKey ? (
              <>
                <View style={styles.rowPin}><ProPin displayName="" pinIcon={sportKey} /></View>
                <View style={styles.rowText}>
                  <AppText style={styles.rowTitle}>{sportLabel(sportKey)}</AppText>
                  <AppText style={styles.rowSub}>{t('pro.pin.sportSub', { defaultValue: 'Le picto de tes sorties {{sport}}.', sport: sportLabel(sportKey).toLowerCase() })}</AppText>
                </View>
              </>
            ) : (
              <AppText style={[styles.rowSub, { flex: 1 }]}>{t('pro.pin.sportPick', { defaultValue: 'Le picto de ce sport, dans la couleur de son univers.' })}</AppText>
            )}
          </View>
          <SportDropdown selected={sportKey ?? ''} onSelect={chooseSport} label={t('pro.pin.chooseSport', { defaultValue: 'Choisir un sport' })} />
        </View>
      )}

      {way === 'photo' && pinImageUrl && (
        <View style={styles.sub}>
          <View style={styles.row}>
            <Image source={{ uri: pinImageUrl }} style={styles.thumb} contentFit="cover" />
            <View style={styles.rowText}>
              <AppText style={styles.rowTitle}>{t('pro.pin.yourPhoto', { defaultValue: 'Ta photo' })}</AppText>
              <AppText style={styles.rowSub}>{t('pro.pin.photoHint', { defaultValue: 'Cadre serré, sujet au centre : elle sera petite.' })}</AppText>
            </View>
            <Pressable onPress={onPickImage} disabled={pinImageBusy} hitSlop={6}>
              <AppText style={styles.link}>{t('pro.pin.change', { defaultValue: 'Changer' })}</AppText>
            </Pressable>
            <Pressable onPress={onRemoveImage} disabled={pinImageBusy} hitSlop={6}>
              <AppText style={styles.linkMuted}>{t('pro.pin.remove', { defaultValue: 'Retirer' })}</AppText>
            </Pressable>
          </View>
        </View>
      )}
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  card: { backgroundColor: colors.surfaceAlt, borderRadius: radius.card, padding: spacing.sm + 4, marginBottom: spacing.md },
  label: { color: colors.textPrimary, fontSize: fontSizes.sm - 1, fontWeight: '700', marginBottom: spacing.xs },
  intro: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16, marginBottom: spacing.sm },
  preview: {
    height: 128, borderRadius: radius.card - 4, backgroundColor: colors.surface,
    alignItems: 'center', justifyContent: 'center', overflow: 'hidden',
  },
  captionChip: {
    position: 'absolute', left: spacing.sm + 2, bottom: spacing.sm,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.full, paddingHorizontal: spacing.sm + 1, paddingVertical: 3,
    maxWidth: '80%',
  },
  captionText: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '600' },
  tiles: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm + 2 },
  tile: {
    flex: 1, backgroundColor: colors.surface, borderRadius: radius.card - 4,
    borderWidth: 1.5, borderColor: colors.lineStrong, paddingVertical: spacing.sm + 2, paddingHorizontal: 2, minHeight: 104,
    alignItems: 'center',
  },
  tileSelected: { borderColor: PRO_GOLD, backgroundColor: PRO_GOLD + '1F' },
  tilePin: { height: 52, alignItems: 'center', justifyContent: 'center', transform: [{ scale: 0.8 }] },
  tileTitle: { color: colors.textPrimary, fontSize: fontSizes.xs, fontWeight: '700', marginTop: 2 },
  tileSub: { color: colors.textSecondary, fontSize: 10.5, lineHeight: 13, textAlign: 'center', minHeight: 13 },
  photoPlaceholder: {
    width: 38, height: 38, borderRadius: radius.sm, borderWidth: 1.5, borderStyle: 'dashed', borderColor: colors.lineStrong,
    alignItems: 'center', justifyContent: 'center',
  },
  helper: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16, marginTop: spacing.sm },
  sub: { marginTop: spacing.sm + 2, backgroundColor: colors.surface, borderRadius: radius.card - 4, padding: spacing.sm + 2, gap: spacing.sm },
  subHead: { color: colors.textSecondary, fontSize: fontSizes.xs },
  chips: { flexDirection: 'row', gap: spacing.sm },
  chip: {
    flex: 1, height: 60, borderRadius: radius.card - 4, backgroundColor: colors.surfaceAlt,
    borderWidth: 1.5, borderColor: 'transparent', alignItems: 'center', justifyContent: 'center',
  },
  chipSelected: { borderColor: PRO_GOLD, backgroundColor: PRO_GOLD + '1F' },
  chipPin: { transform: [{ scale: 0.78 }] },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm + 2 },
  rowPin: { transform: [{ scale: 0.9 }] },
  rowText: { flex: 1, minWidth: 0 },
  rowTitle: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '700' },
  rowSub: { color: colors.textSecondary, fontSize: fontSizes.xs, lineHeight: 16 },
  thumb: { width: 52, height: 52, borderRadius: radius.sm, backgroundColor: colors.surfaceAlt },
  link: { color: colors.cta, fontSize: fontSizes.sm - 1, fontWeight: '700' },
  linkMuted: { color: colors.textSecondary, fontSize: fontSizes.sm - 1, fontWeight: '600' },
});
