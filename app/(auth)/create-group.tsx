import { useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, SectionList, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { Check, X } from 'lucide-react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { contactService } from '@/services/contact-service';
import { groupService } from '@/services/group-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from '@/components/user-avatar';
import { LogoSpinner } from '@/components/logo-spinner';
import { haptic } from '@/lib/haptics';

export default function CreateGroupScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const { t } = useTranslation();
  const router = useRouter();
  const queryClient = useQueryClient();
  const insets = useSafeAreaInsets();

  const [name, setName] = useState('');
  const [icon, setIcon] = useState('');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [creating, setCreating] = useState(false);

  const { data: contacts, isLoading: l1 } = useQuery({ queryKey: ['contacts'], queryFn: () => contactService.getContacts() });
  const { data: partners, isLoading: l2 } = useQuery({ queryKey: ['recent-partners'], queryFn: () => contactService.getRecentPartners() });

  const sections = useMemo(() => {
    const out: { title: string; data: { id: string; display_name: string; avatar_url: string | null }[] }[] = [];
    const contactIds = new Set((contacts ?? []).map((c) => c.id));
    const freshPartners = (partners ?? []).filter((p) => !contactIds.has(p.id));
    if (contacts && contacts.length) out.push({ title: t('contacts.myContacts', { defaultValue: 'Mes contacts' }), data: contacts });
    if (freshPartners.length) out.push({ title: t('contacts.recentPartners', { defaultValue: 'Partenaires récents' }), data: freshPartners });
    return out;
  }, [contacts, partners, t]);

  const toggle = (id: string) => setSelected((prev) => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });

  // Min 3 total (creator + 2), server-enforced; mirror it in the CTA gate.
  const canCreate = name.trim().length > 0 && selected.size >= 2 && !creating;

  const handleCreate = async () => {
    if (!canCreate) return;
    setCreating(true);
    try {
      haptic.success();
      const convId = await groupService.create(name.trim(), icon.trim() || null, [...selected]);
      await queryClient.invalidateQueries({ queryKey: ['conversations'] });
      router.replace(`/(auth)/conversation/${convId}`);
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
      setCreating(false);
    }
  };

  return (
    <View style={[styles.container, { paddingTop: insets.top }]}>
      <View style={styles.header}>
        <Pressable onPress={() => router.back()} hitSlop={8}>
          <X size={24} color={colors.textPrimary} strokeWidth={2.2} />
        </Pressable>
        <Text style={styles.headerTitle}>{t('group.createTitle', { defaultValue: 'Nouveau groupe' })}</Text>
        <View style={{ width: 24 }} />
      </View>

      <View style={styles.nameRow}>
        <TextInput
          style={styles.iconInput}
          value={icon}
          onChangeText={setIcon}
          placeholder="🏔️"
          placeholderTextColor={colors.textSecondary}
          maxLength={8}
        />
        <TextInput
          style={styles.nameInput}
          value={name}
          onChangeText={setName}
          placeholder={t('group.namePlaceholder', { defaultValue: 'Nom du groupe' })}
          placeholderTextColor={colors.textSecondary}
          maxLength={60}
        />
      </View>

      <Text style={styles.hint}>{t('group.pickHint', { defaultValue: 'Choisis au moins 2 partenaires (contacts + partenaires récents).' })}</Text>

      {l1 || l2 ? (
        <View style={styles.center}><LogoSpinner /></View>
      ) : sections.length === 0 ? (
        <Text style={styles.empty}>{t('contacts.inviteEmpty', { defaultValue: 'Ajoute des contacts, ou fais des sorties pour retrouver tes partenaires ici.' })}</Text>
      ) : (
        <SectionList
          sections={sections}
          keyExtractor={(item) => item.id}
          stickySectionHeadersEnabled={false}
          contentContainerStyle={styles.list}
          renderSectionHeader={({ section }) => <Text style={styles.section}>{section.title}</Text>}
          renderItem={({ item }) => {
            const on = selected.has(item.id);
            return (
              <Pressable style={styles.row} onPress={() => toggle(item.id)}>
                <UserAvatar name={item.display_name} avatarUrl={item.avatar_url} size={40} />
                <Text style={styles.rowName} numberOfLines={1}>{item.display_name}</Text>
                <View style={[styles.check, on && styles.checkOn]}>
                  {on && <Check size={14} color="#FFFFFF" strokeWidth={3} />}
                </View>
              </Pressable>
            );
          }}
        />
      )}

      <Pressable
        style={[styles.cta, !canCreate && styles.ctaDisabled, { marginBottom: insets.bottom + spacing.sm }]}
        disabled={!canCreate}
        onPress={handleCreate}
      >
        <Text style={styles.ctaText}>
          {creating
            ? t('group.creating', { defaultValue: 'Création…' })
            : t('group.createCta', { defaultValue: 'Créer le groupe ({{count}})', count: selected.size })}
        </Text>
      </Pressable>
    </View>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background, paddingHorizontal: spacing.md },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingVertical: spacing.md },
  headerTitle: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: '800' },
  nameRow: { flexDirection: 'row', gap: spacing.sm, marginTop: spacing.sm },
  iconInput: {
    width: 56, textAlign: 'center', color: colors.textPrimary, fontSize: fontSizes.lg,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm, paddingVertical: spacing.sm,
  },
  nameInput: {
    flex: 1, color: colors.textPrimary, fontSize: fontSizes.md,
    borderWidth: 1, borderColor: colors.borderMuted, borderRadius: radius.sm,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
  },
  hint: { color: colors.textSecondary, fontSize: fontSizes.xs, marginTop: spacing.sm, marginBottom: spacing.xs },
  center: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl },
  list: { paddingBottom: spacing.md },
  section: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800',
    letterSpacing: 0.8, textTransform: 'uppercase', marginTop: spacing.md, marginBottom: spacing.xs,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
  rowName: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  check: {
    width: 24, height: 24, borderRadius: 12, borderWidth: 1.5, borderColor: colors.borderMuted,
    alignItems: 'center', justifyContent: 'center',
  },
  checkOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  cta: { backgroundColor: colors.cta, borderRadius: radius.md, paddingVertical: spacing.sm + 2, alignItems: 'center' },
  ctaDisabled: { opacity: 0.4 },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
