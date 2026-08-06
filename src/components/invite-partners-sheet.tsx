import { useEffect, useMemo, useState } from 'react';
import { View, Text, Modal, Pressable, SectionList, StyleSheet, TextInput } from 'react-native';
import { Check } from 'lucide-react-native';
import { useTranslation } from 'react-i18next';
import { useQuery } from '@tanstack/react-query';
import * as Burnt from 'burnt';
import { fontSizes, spacing, radius } from '@/constants/theme';
import { useColors } from '@/hooks/use-theme';
import type { AppColors } from '@/constants/colors';
import { contactService } from '@/services/contact-service';
import { invitationService } from '@/services/invitation-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from './user-avatar';
import { LogoSpinner } from './logo-spinner';

interface Props {
  visible: boolean;
  activityId: string;
  onClose: () => void;
}

// Multi-select official invitation-to-join (Brique 4e): pick from your contacts
// + recent partners (+ optional message), then send real invitations via
// send_activity_invitations. Creator-only, pre-approved (accept = participant);
// the invitee sees it in their Demandes → Invitations. Eligibility is enforced
// server-side (ineligible/blocked/dup skipped silently, RETURNS VOID).
export function InvitePartnersSheet({ visible, activityId, onClose }: Props) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState('');
  const [sending, setSending] = useState(false);

  useEffect(() => { if (!visible) { setSelected(new Set()); setMessage(''); setSending(false); } }, [visible]);

  const { data: contacts, isLoading: loadingContacts } = useQuery({
    queryKey: ['contacts'], queryFn: () => contactService.getContacts(), enabled: visible,
  });
  const { data: partners, isLoading: loadingPartners } = useQuery({
    queryKey: ['recent-partners'], queryFn: () => contactService.getRecentPartners(), enabled: visible,
  });

  const toggle = (id: string) => setSelected((prev) => {
    const next = new Set(prev);
    if (next.has(id)) next.delete(id); else next.add(id);
    return next;
  });

  const sections = useMemo(() => {
    const out: { title: string; data: { id: string; display_name: string; avatar_url: string | null }[] }[] = [];
    if (contacts && contacts.length) out.push({ title: t('contacts.myContacts', { defaultValue: 'Mes contacts' }), data: contacts });
    if (partners && partners.length) out.push({ title: t('contacts.recentPartners', { defaultValue: 'Partenaires récents' }), data: partners });
    return out;
  }, [contacts, partners, t]);

  const loading = loadingContacts || loadingPartners;

  const handleInvite = async () => {
    if (selected.size === 0 || sending) return;
    setSending(true);
    try {
      await invitationService.sendInvitations(activityId, [...selected], message);
      Burnt.toast({ title: t('contacts.invitationsSent', { defaultValue: 'Invitations envoyées' }), preset: 'done' });
      onClose();
    } catch (e) {
      Burnt.toast({ title: getFriendlyError(e, 'generic') });
    } finally {
      setSending(false);
    }
  };

  return (
    <Modal visible={visible} animationType="slide" transparent onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose}>
        <Pressable style={styles.sheet} onPress={() => {}}>
          <View style={styles.handle} />
          <Text style={styles.title}>{t('contacts.inviteTitle', { defaultValue: 'Inviter des partenaires' })}</Text>

          {loading ? (
            <View style={styles.center}><LogoSpinner /></View>
          ) : sections.length === 0 ? (
            <Text style={styles.empty}>
              {t('contacts.inviteEmpty', { defaultValue: 'Ajoute des contacts, ou fais des sorties pour retrouver tes partenaires ici.' })}
            </Text>
          ) : (
            <SectionList
              sections={sections}
              keyExtractor={(item) => item.id}
              stickySectionHeadersEnabled={false}
              style={styles.list}
              renderSectionHeader={({ section }) => <Text style={styles.section}>{section.title}</Text>}
              renderItem={({ item }) => {
                const on = selected.has(item.id);
                return (
                  <Pressable style={styles.row} onPress={() => toggle(item.id)}>
                    <UserAvatar name={item.display_name} avatarUrl={item.avatar_url} size={40} />
                    <Text style={styles.name} numberOfLines={1}>{item.display_name}</Text>
                    <View style={[styles.check, on && styles.checkOn]}>
                      {on && <Check size={14} color="#FFFFFF" strokeWidth={3} />}
                    </View>
                  </Pressable>
                );
              }}
            />
          )}

          {sections.length > 0 && (
            <TextInput
              style={styles.messageInput}
              value={message}
              onChangeText={setMessage}
              placeholder={t('contacts.inviteMessagePlaceholder', { defaultValue: 'Un mot (optionnel)…' })}
              placeholderTextColor={colors.textSecondary}
              maxLength={500}
              multiline
            />
          )}

          <Pressable
            style={[styles.cta, (selected.size === 0 || sending) && styles.ctaDisabled]}
            disabled={selected.size === 0 || sending}
            onPress={handleInvite}
          >
            <Text style={styles.ctaText}>
              {sending
                ? t('contacts.inviting', { defaultValue: 'Envoi…' })
                : t('contacts.inviteCta', { defaultValue: 'Inviter ({{count}})', count: selected.size })}
            </Text>
          </Pressable>
        </Pressable>
      </Pressable>
    </Modal>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  backdrop: { flex: 1, backgroundColor: colors.overlay, justifyContent: 'flex-end' },
  sheet: {
    backgroundColor: colors.background,
    borderTopLeftRadius: radius.lg, borderTopRightRadius: radius.lg,
    padding: spacing.lg, paddingBottom: spacing.xl + 16, maxHeight: '80%',
  },
  handle: { width: 40, height: 4, borderRadius: 2, backgroundColor: colors.textSecondary, alignSelf: 'center', marginBottom: spacing.lg, opacity: 0.4 },
  title: { color: colors.textPrimary, fontSize: fontSizes.lg, fontWeight: 'bold', marginBottom: spacing.md },
  empty: { color: colors.textSecondary, fontSize: fontSizes.md, textAlign: 'center', paddingVertical: spacing.xl },
  center: { paddingVertical: spacing.xl, alignItems: 'center' },
  list: { maxHeight: 400 },
  section: {
    color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '800',
    letterSpacing: 0.8, textTransform: 'uppercase',
    marginTop: spacing.md, marginBottom: spacing.xs,
  },
  row: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.sm },
  name: { flex: 1, color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: '600' },
  check: {
    width: 24, height: 24, borderRadius: 12, borderWidth: 1.5, borderColor: colors.borderMuted,
    alignItems: 'center', justifyContent: 'center',
  },
  checkOn: { backgroundColor: colors.cta, borderColor: colors.cta },
  messageInput: {
    color: colors.textPrimary, fontSize: fontSizes.md,
    backgroundColor: colors.surfaceAlt, borderRadius: radius.md,
    paddingHorizontal: spacing.md, paddingVertical: spacing.sm,
    marginTop: spacing.md, maxHeight: 90,
  },
  cta: {
    backgroundColor: colors.cta, borderRadius: radius.md,
    paddingVertical: spacing.sm + 2, alignItems: 'center', marginTop: spacing.md,
  },
  ctaDisabled: { opacity: 0.4 },
  ctaText: { color: '#FFFFFF', fontSize: fontSizes.md, fontWeight: '800' },
});
