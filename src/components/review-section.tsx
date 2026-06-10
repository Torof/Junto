import { useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, Modal, StyleSheet, Alert } from 'react-native';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Flag, Pencil, Trash2, CornerUpLeft } from 'lucide-react-native';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { reviewService, type Review } from '@/services/review-service';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from './user-avatar';
import { StarRating, StarPicker } from './star-rating';
import { ReportModal } from './report-modal';

interface ReviewSectionProps {
  targetType: 'pro' | 'offering';
  targetId: string;
  // Current user is the reviewed pro (owns the storefront) — gets the
  // reply action instead of the write-review CTA.
  isOwner: boolean;
  currentUserId: string | null;
}

// Full "Avis" tab content for the pro page and offering pages.
// Self-contained: owns its queries and mutations, parameterized only
// by target. Rendered inside the parent tab's ScrollView.
export function ReviewSection({ targetType, targetId, isOwner, currentUserId }: ReviewSectionProps) {
  const { t } = useTranslation();
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const queryClient = useQueryClient();

  const [composerOpen, setComposerOpen] = useState(false);
  const [draftRating, setDraftRating] = useState(0);
  const [draftBody, setDraftBody] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [replyTarget, setReplyTarget] = useState<Review | null>(null);
  const [draftReply, setDraftReply] = useState('');
  const [reportTargetId, setReportTargetId] = useState<string | null>(null);

  const { data: reviews = [] } = useQuery({
    queryKey: ['reviews', targetType, targetId],
    queryFn: () =>
      targetType === 'pro' ? reviewService.getForPro(targetId) : reviewService.getForOffering(targetId),
  });

  const { data: stats } = useQuery({
    queryKey: ['review-stats', targetType, targetId],
    queryFn: () =>
      targetType === 'pro' ? reviewService.getProStats(targetId) : reviewService.getOfferingStats(targetId),
  });

  const ownReview = currentUserId ? reviews.find((r) => r.reviewer_id === currentUserId) ?? null : null;

  const invalidate = async () => {
    await queryClient.invalidateQueries({ queryKey: ['reviews', targetType, targetId] });
    await queryClient.invalidateQueries({ queryKey: ['review-stats', targetType, targetId] });
  };

  const openComposer = () => {
    setDraftRating(ownReview?.rating ?? 0);
    setDraftBody(ownReview?.body ?? '');
    setComposerOpen(true);
  };

  const handleSubmit = async () => {
    if (draftRating < 1) {
      Alert.alert(t('auth.error'), t('reviews.ratingRequired'));
      return;
    }
    setIsSubmitting(true);
    const body = draftBody.trim().length > 0 ? draftBody.trim() : null;
    try {
      if (ownReview) {
        if (targetType === 'pro') await reviewService.updateForPro(ownReview.id, draftRating, body);
        else await reviewService.updateForOffering(ownReview.id, draftRating, body);
      } else {
        if (targetType === 'pro') await reviewService.createForPro(targetId, draftRating, body);
        else await reviewService.createForOffering(targetId, draftRating, body);
      }
      await invalidate();
      setComposerOpen(false);
      Burnt.toast({ title: t('reviews.saved'), preset: 'done' });
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setIsSubmitting(false);
    }
  };

  const handleDelete = () => {
    if (!ownReview) return;
    Alert.alert(t('reviews.deleteTitle'), t('reviews.deleteMessage'), [
      { text: t('activity.no'), style: 'cancel' },
      {
        text: t('activity.yes'),
        style: 'destructive',
        onPress: async () => {
          try {
            if (targetType === 'pro') await reviewService.deleteForPro(ownReview.id);
            else await reviewService.deleteForOffering(ownReview.id);
            await invalidate();
          } catch (err) {
            Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
          }
        },
      },
    ]);
  };

  const openReply = (review: Review) => {
    setDraftReply(review.pro_reply ?? '');
    setReplyTarget(review);
  };

  const handleReplySubmit = async (clear: boolean) => {
    if (!replyTarget) return;
    const reply = clear ? null : draftReply.trim().length > 0 ? draftReply.trim() : null;
    setIsSubmitting(true);
    try {
      if (targetType === 'pro') await reviewService.replyForPro(replyTarget.id, reply);
      else await reviewService.replyForOffering(replyTarget.id, reply);
      await invalidate();
      setReplyTarget(null);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <View style={styles.wrap}>
      {/* Header — aggregate + CTA */}
      {stats && stats.review_count > 0 && (
        <View style={styles.statsRow}>
          <Text style={styles.statsAvg}>{Number(stats.avg_rating).toFixed(1)}</Text>
          <StarRating rating={Number(stats.avg_rating)} size={16} />
          <Text style={styles.statsCount}>
            {t('reviews.count', { count: stats.review_count })}
          </Text>
        </View>
      )}

      {!isOwner && currentUserId && (
        <Pressable style={styles.ctaButton} onPress={openComposer}>
          <Text style={styles.ctaText}>
            {ownReview ? t('reviews.editMine') : t('reviews.writeOne')}
          </Text>
        </Pressable>
      )}

      {reviews.length === 0 && (
        <View style={styles.emptyCard}>
          <Text style={styles.emptyText}>{t('reviews.empty')}</Text>
        </View>
      )}

      {reviews.map((review) => {
        const isMine = review.reviewer_id === currentUserId;
        return (
          <View key={review.id} style={styles.reviewCard}>
            <View style={styles.reviewHeader}>
              <UserAvatar name={review.reviewer_name ?? '?'} avatarUrl={review.reviewer_avatar} size={32} />
              <View style={styles.reviewHeaderText}>
                <Text style={styles.reviewerName} numberOfLines={1}>
                  {review.reviewer_name ?? '?'}
                </Text>
                <View style={styles.reviewMeta}>
                  <StarRating rating={review.rating} size={12} />
                  <Text style={styles.reviewDate}>{dayjs(review.created_at).format('D MMM YYYY')}</Text>
                </View>
              </View>
              <View style={styles.actionsRow}>
                {isMine && (
                  <>
                    <Pressable onPress={openComposer} hitSlop={8} accessibilityLabel={t('reviews.editMine')}>
                      <Pencil size={16} color={colors.textSecondary} strokeWidth={2} />
                    </Pressable>
                    <Pressable onPress={handleDelete} hitSlop={8} accessibilityLabel={t('reviews.deleteTitle')}>
                      <Trash2 size={16} color={colors.error} strokeWidth={2} />
                    </Pressable>
                  </>
                )}
                {isOwner && (
                  <Pressable onPress={() => openReply(review)} hitSlop={8} accessibilityLabel={t('reviews.reply')}>
                    <CornerUpLeft size={16} color={colors.cta} strokeWidth={2} />
                  </Pressable>
                )}
                {!isMine && !isOwner && (
                  <Pressable
                    onPress={() => setReportTargetId(review.id)}
                    hitSlop={8}
                    accessibilityLabel={t('report.title')}
                  >
                    <Flag size={14} color={colors.textMuted} strokeWidth={2} />
                  </Pressable>
                )}
              </View>
            </View>

            {review.body && <Text style={styles.reviewBody}>{review.body}</Text>}

            {review.pro_reply && (
              <View style={styles.replyBlock}>
                <Text style={styles.replyLabel}>
                  {t('reviews.proReply')}
                  {review.pro_reply_at ? ` — ${dayjs(review.pro_reply_at).format('D MMM YYYY')}` : ''}
                </Text>
                <Text style={styles.replyBody}>{review.pro_reply}</Text>
              </View>
            )}
          </View>
        );
      })}

      {/* Composer — write / edit own review */}
      <Modal visible={composerOpen} animationType="slide" transparent onRequestClose={() => setComposerOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setComposerOpen(false)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.handle} />
            <Text style={styles.sheetTitle}>
              {ownReview ? t('reviews.editMine') : t('reviews.writeOne')}
            </Text>
            <StarPicker value={draftRating} onChange={setDraftRating} />
            <TextInput
              style={styles.input}
              value={draftBody}
              onChangeText={setDraftBody}
              placeholder={t('reviews.bodyPlaceholder')}
              placeholderTextColor={colors.textSecondary}
              multiline
              maxLength={1000}
            />
            <View style={styles.sheetButtons}>
              <Pressable style={styles.cancelButton} onPress={() => setComposerOpen(false)}>
                <Text style={styles.cancelButtonText}>{t('reviews.cancel')}</Text>
              </Pressable>
              <Pressable
                style={[styles.submitButton, isSubmitting && styles.buttonDisabled]}
                onPress={handleSubmit}
                disabled={isSubmitting}
              >
                <Text style={styles.submitButtonText}>{t('reviews.submit')}</Text>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>

      {/* Reply composer — pro only */}
      <Modal
        visible={replyTarget !== null}
        animationType="slide"
        transparent
        onRequestClose={() => setReplyTarget(null)}
      >
        <Pressable style={styles.backdrop} onPress={() => setReplyTarget(null)}>
          <Pressable style={styles.sheet} onPress={() => {}}>
            <View style={styles.handle} />
            <Text style={styles.sheetTitle}>{t('reviews.reply')}</Text>
            <TextInput
              style={styles.input}
              value={draftReply}
              onChangeText={setDraftReply}
              placeholder={t('reviews.replyPlaceholder')}
              placeholderTextColor={colors.textSecondary}
              multiline
              maxLength={1000}
            />
            <View style={styles.sheetButtons}>
              {replyTarget?.pro_reply ? (
                <Pressable style={styles.cancelButton} onPress={() => handleReplySubmit(true)} disabled={isSubmitting}>
                  <Text style={[styles.cancelButtonText, { color: colors.error }]}>
                    {t('reviews.removeReply')}
                  </Text>
                </Pressable>
              ) : (
                <Pressable style={styles.cancelButton} onPress={() => setReplyTarget(null)}>
                  <Text style={styles.cancelButtonText}>{t('reviews.cancel')}</Text>
                </Pressable>
              )}
              <Pressable
                style={[styles.submitButton, isSubmitting && styles.buttonDisabled]}
                onPress={() => handleReplySubmit(false)}
                disabled={isSubmitting}
              >
                <Text style={styles.submitButtonText}>{t('reviews.submit')}</Text>
              </Pressable>
            </View>
          </Pressable>
        </Pressable>
      </Modal>

      <ReportModal
        visible={reportTargetId !== null}
        targetType={targetType === 'pro' ? 'pro_review' : 'offering_review'}
        targetId={reportTargetId ?? ''}
        onClose={() => setReportTargetId(null)}
      />
    </View>
  );
}

const createStyles = (colors: AppColors) =>
  StyleSheet.create({
    wrap: { paddingHorizontal: spacing.lg, paddingTop: spacing.lg, gap: spacing.md },
    statsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    statsAvg: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: '700' },
    statsCount: { color: colors.textSecondary, fontSize: fontSizes.sm },
    ctaButton: {
      borderWidth: 1,
      borderColor: colors.cta,
      borderRadius: radius.md,
      paddingVertical: spacing.sm,
      alignItems: 'center',
    },
    ctaText: { color: colors.cta, fontSize: fontSizes.md, fontWeight: '600' },
    emptyCard: {
      backgroundColor: colors.surface,
      borderRadius: radius.md,
      borderWidth: 1,
      borderColor: colors.line,
      padding: spacing.lg,
      alignItems: 'center',
    },
    emptyText: { color: colors.textSecondary, fontSize: fontSizes.sm, textAlign: 'center' },
    reviewCard: {
      backgroundColor: colors.surface,
      borderRadius: radius.md,
      borderWidth: 1,
      borderColor: colors.line,
      padding: spacing.md,
      gap: spacing.sm,
    },
    reviewHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    reviewHeaderText: { flex: 1, gap: 2 },
    reviewerName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
    reviewMeta: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    reviewDate: { color: colors.textMuted, fontSize: fontSizes.xs },
    actionsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
    reviewBody: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
    replyBlock: {
      borderLeftWidth: 2,
      borderLeftColor: colors.cta,
      paddingLeft: spacing.sm,
      marginLeft: spacing.xs,
      gap: 2,
    },
    replyLabel: { color: colors.textSecondary, fontSize: fontSizes.xs, fontWeight: '600' },
    replyBody: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 19 },
    backdrop: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', justifyContent: 'flex-end' },
    sheet: {
      backgroundColor: colors.background,
      borderTopLeftRadius: radius.lg,
      borderTopRightRadius: radius.lg,
      padding: spacing.lg,
      paddingBottom: spacing.xl + 16,
      gap: spacing.md,
    },
    handle: {
      width: 36,
      height: 4,
      borderRadius: 2,
      backgroundColor: colors.line,
      alignSelf: 'center',
    },
    sheetTitle: {
      color: colors.textPrimary,
      fontSize: fontSizes.lg,
      fontWeight: '700',
      textAlign: 'center',
    },
    input: {
      backgroundColor: colors.surface,
      borderWidth: 1,
      borderColor: colors.line,
      borderRadius: radius.md,
      color: colors.textPrimary,
      fontSize: fontSizes.sm,
      padding: spacing.md,
      minHeight: 96,
      textAlignVertical: 'top',
    },
    sheetButtons: { flexDirection: 'row', gap: spacing.md },
    cancelButton: {
      flex: 1,
      borderWidth: 1,
      borderColor: colors.line,
      borderRadius: radius.md,
      paddingVertical: spacing.sm + 2,
      alignItems: 'center',
    },
    cancelButtonText: { color: colors.textSecondary, fontSize: fontSizes.md, fontWeight: '600' },
    submitButton: {
      flex: 1,
      backgroundColor: colors.cta,
      borderRadius: radius.md,
      paddingVertical: spacing.sm + 2,
      alignItems: 'center',
    },
    submitButtonText: { color: colors.background, fontSize: fontSizes.md, fontWeight: '700' },
    buttonDisabled: { opacity: 0.5 },
  });
