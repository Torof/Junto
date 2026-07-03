import { useMemo, useState } from 'react';
import { View, Text, TextInput, Pressable, Modal, StyleSheet, Alert } from 'react-native';
import { ScrollView as GHScrollView } from 'react-native-gesture-handler';
import { Image } from 'expo-image';
import Animated from 'react-native-reanimated';
import { useKeyboardDockPadding } from '@/hooks/use-keyboard-dock-padding';
import { useTranslation } from 'react-i18next';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Flag, Pencil, Trash2, CornerUpLeft, ImagePlus, X } from 'lucide-react-native';
import dayjs from 'dayjs';
import * as Burnt from 'burnt';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing, radius } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';
import { reviewService, type Review } from '@/services/review-service';
import { proCommunityPhotoService } from '@/services/pro-photo-service';
import { pickAndUploadRawPhotos } from '@/utils/pro-photo-upload';
import { getFriendlyError } from '@/utils/friendly-error';
import { UserAvatar } from './user-avatar';
import { StarRating, StarPicker } from './star-rating';
import { ReportModal } from './report-modal';

const REVIEW_PHOTO_MAX = 5;

interface ReviewSectionProps {
  targetType: 'pro' | 'offering';
  targetId: string;
  // Current user is the reviewed pro (owns the storefront) — gets the
  // reply action instead of the write-review CTA.
  isOwner: boolean;
  currentUserId: string | null;
  // Renders the reviews as a horizontal, full-width-bleed carousel of
  // fixed-width cards instead of a vertical list (summary + composer unchanged).
  horizontal?: boolean;
}

// Full "Avis" tab content for the pro page and offering pages.
// Self-contained: owns its queries and mutations, parameterized only
// by target. Rendered inside the parent tab's ScrollView.
export function ReviewSection({ targetType, targetId, isOwner, currentUserId, horizontal = false }: ReviewSectionProps) {
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
  // Community photos attached in the composer this session (uploaded to storage,
  // linked to the review on submit). Pro pages only.
  const [draftPhotos, setDraftPhotos] = useState<string[]>([]);
  const [photoBusy, setPhotoBusy] = useState(false);
  // Lifts the bottom sheets above the IME while typing (flush at rest).
  const imePadding = useKeyboardDockPadding(0);

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

  // Community photos on this pro (only pro pages have them), grouped by the
  // review they were posted with so each review renders its own thumbnails.
  const { data: communityPhotos = [] } = useQuery({
    queryKey: ['community-photos', targetId],
    queryFn: () => proCommunityPhotoService.listByPro(targetId),
    enabled: targetType === 'pro',
  });
  const photosByReview = useMemo(() => {
    const m = new Map<string, string[]>();
    for (const p of communityPhotos) {
      if (!p.review_id) continue;
      m.set(p.review_id, [...(m.get(p.review_id) ?? []), p.photo_url]);
    }
    return m;
  }, [communityPhotos]);

  const ownReview = currentUserId ? reviews.find((r) => r.reviewer_id === currentUserId) ?? null : null;
  const ownExistingPhotos = ownReview ? (photosByReview.get(ownReview.id) ?? []).length : 0;
  const photoSlotsLeft = REVIEW_PHOTO_MAX - ownExistingPhotos - draftPhotos.length;

  // Star distribution for the summary bars — counts[0] = 1★ … counts[4] = 5★,
  // computed from the loaded reviews (the headline avg + total come from stats).
  const dist = useMemo(() => {
    const counts = [0, 0, 0, 0, 0];
    for (const r of reviews) {
      const idx = Math.min(5, Math.max(1, Math.round(r.rating))) - 1;
      counts[idx] = (counts[idx] ?? 0) + 1;
    }
    return counts;
  }, [reviews]);

  const invalidate = async () => {
    await queryClient.invalidateQueries({ queryKey: ['reviews', targetType, targetId] });
    await queryClient.invalidateQueries({ queryKey: ['review-stats', targetType, targetId] });
  };

  const openComposer = () => {
    setDraftRating(ownReview?.rating ?? 0);
    setDraftBody(ownReview?.body ?? '');
    setDraftPhotos([]);
    setComposerOpen(true);
  };

  const handleAddPhotos = async () => {
    if (targetType !== 'pro' || photoSlotsLeft <= 0) return;
    setPhotoBusy(true);
    try {
      const urls = await pickAndUploadRawPhotos(targetId, photoSlotsLeft);
      if (urls.length > 0) setDraftPhotos((prev) => [...prev, ...urls]);
    } catch (err) {
      Alert.alert(t('auth.error'), getFriendlyError(err, 'generic'));
    } finally {
      setPhotoBusy(false);
    }
  };

  const handleSubmit = async () => {
    if (draftRating < 1) {
      Alert.alert(t('auth.error'), t('reviews.ratingRequired'));
      return;
    }
    setIsSubmitting(true);
    const body = draftBody.trim().length > 0 ? draftBody.trim() : null;
    try {
      let reviewId = ownReview?.id ?? null;
      if (ownReview) {
        if (targetType === 'pro') await reviewService.updateForPro(ownReview.id, draftRating, body);
        else await reviewService.updateForOffering(ownReview.id, draftRating, body);
      } else if (targetType === 'pro') {
        reviewId = await reviewService.createForPro(targetId, draftRating, body);
      } else {
        await reviewService.createForOffering(targetId, draftRating, body);
      }
      // Link the freshly-uploaded photos to the review (pro pages only).
      if (targetType === 'pro' && reviewId && draftPhotos.length > 0) {
        for (const url of draftPhotos) await proCommunityPhotoService.add(targetId, url, reviewId);
        await queryClient.invalidateQueries({ queryKey: ['community-photos', targetId] });
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

  const renderReviewCard = (review: Review) => {
    const isMine = review.reviewer_id === currentUserId;
    const reviewPhotos = targetType === 'pro' ? (photosByReview.get(review.id) ?? []) : [];
    return (
      <View key={review.id} style={[styles.reviewCard, horizontal && styles.reviewCardH]}>
        <View style={styles.reviewHeader}>
          <UserAvatar name={review.reviewer_name ?? '?'} avatarUrl={review.reviewer_avatar} size={32} />
          <View style={styles.reviewHeaderText}>
            <Text style={styles.reviewerName} numberOfLines={1}>{review.reviewer_name ?? '?'}</Text>
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
              <Pressable onPress={() => setReportTargetId(review.id)} hitSlop={8} accessibilityLabel={t('report.title')}>
                <Flag size={14} color={colors.textMuted} strokeWidth={2} />
              </Pressable>
            )}
          </View>
        </View>

        {review.body ? <Text style={styles.reviewBody} numberOfLines={horizontal ? 5 : undefined}>{review.body}</Text> : null}

        {reviewPhotos.length > 0 && (
          <View style={styles.reviewPhotos}>
            {reviewPhotos.map((url) => (
              <Image key={url} source={url} style={styles.reviewPhoto} contentFit="cover" />
            ))}
          </View>
        )}

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
  };

  return (
    <View style={styles.wrap}>
      {/* Header — aggregate summary (avg + stars + voters) with per-star bars */}
      {stats && stats.review_count > 0 && (
        <View style={styles.summary}>
          <View style={styles.summaryLeft}>
            <Text style={styles.summaryAvg}>{Number(stats.avg_rating).toFixed(1)}</Text>
            <StarRating rating={Number(stats.avg_rating)} size={15} />
            <Text style={styles.summaryCount}>{t('reviews.count', { count: stats.review_count })}</Text>
          </View>
          <View style={styles.summaryBars}>
            {[5, 4, 3, 2, 1].map((star) => {
              const pct = reviews.length > 0 ? (dist[star - 1] ?? 0) / reviews.length : 0;
              return (
                <View key={star} style={styles.barRow}>
                  <Text style={styles.barStar}>{star}</Text>
                  <View style={styles.barTrack}>
                    <View style={[styles.barFill, { width: `${Math.round(pct * 100)}%` }]} />
                  </View>
                </View>
              );
            })}
          </View>
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

      {reviews.length > 0 && (horizontal ? (
        <GHScrollView horizontal showsHorizontalScrollIndicator={false} style={styles.hBleed} contentContainerStyle={styles.hCarousel}>
          {reviews.map(renderReviewCard)}
        </GHScrollView>
      ) : (
        reviews.map(renderReviewCard)
      ))}

      {/* Composer — write / edit own review */}
      <Modal visible={composerOpen} animationType="slide" transparent onRequestClose={() => setComposerOpen(false)}>
        <Pressable style={styles.backdrop} onPress={() => setComposerOpen(false)}>
          <Animated.View style={imePadding}>
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
            {targetType === 'pro' && (
              <View style={styles.photoRow}>
                {draftPhotos.map((url) => (
                  <View key={url} style={styles.photoThumbWrap}>
                    <Image source={url} style={styles.photoThumb} contentFit="cover" />
                    <Pressable
                      style={styles.photoRemove}
                      onPress={() => setDraftPhotos((p) => p.filter((u) => u !== url))}
                      hitSlop={6}
                    >
                      <X size={11} color={colors.background} strokeWidth={3} />
                    </Pressable>
                  </View>
                ))}
                {photoSlotsLeft > 0 && (
                  <Pressable style={styles.photoAdd} onPress={handleAddPhotos} disabled={photoBusy}>
                    <ImagePlus size={22} color={colors.cta} strokeWidth={2} />
                  </Pressable>
                )}
              </View>
            )}
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
          </Animated.View>
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
          <Animated.View style={imePadding}>
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
          </Animated.View>
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
    // Google-style rating summary: big average + stars + voters on the left,
    // per-star proportion bars on the right.
    summary: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: spacing.lg,
      paddingVertical: spacing.md,
      paddingHorizontal: spacing.sm,
    },
    summaryLeft: { alignItems: 'center', gap: 3, minWidth: 92 },
    summaryAvg: { color: colors.textPrimary, fontSize: 40, fontWeight: '800', lineHeight: 44 },
    summaryCount: { color: colors.textSecondary, fontSize: fontSizes.xs },
    summaryBars: { flex: 1, gap: 4, justifyContent: 'center' },
    barRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    barStar: { color: colors.textSecondary, fontSize: fontSizes.xs, width: 10, textAlign: 'center' },
    barTrack: { flex: 1, height: 7, borderRadius: 4, backgroundColor: colors.surfaceAlt, overflow: 'hidden' },
    barFill: { height: '100%', borderRadius: 4, backgroundColor: colors.cta },
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
    // Horizontal carousel mode — fixed-width cards that bleed full width.
    reviewCardH: { width: 280 },
    hBleed: { marginHorizontal: -spacing.lg },
    hCarousel: { gap: spacing.sm, paddingHorizontal: spacing.lg, paddingBottom: spacing.xs },
    reviewHeader: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    reviewHeaderText: { flex: 1, gap: 2 },
    reviewerName: { color: colors.textPrimary, fontSize: fontSizes.sm, fontWeight: '600' },
    reviewMeta: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
    reviewDate: { color: colors.textMuted, fontSize: fontSizes.xs },
    actionsRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md },
    reviewBody: { color: colors.textPrimary, fontSize: fontSizes.sm, lineHeight: 20 },
    reviewPhotos: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.xs },
    reviewPhoto: { width: 76, height: 76, borderRadius: radius.sm, backgroundColor: colors.surfaceAlt },
    photoRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, alignItems: 'center' },
    photoThumbWrap: { position: 'relative' },
    photoThumb: { width: 60, height: 60, borderRadius: radius.sm, backgroundColor: colors.surfaceAlt },
    photoRemove: {
      position: 'absolute',
      top: -6,
      right: -6,
      width: 20,
      height: 20,
      borderRadius: 10,
      backgroundColor: colors.textPrimary,
      alignItems: 'center',
      justifyContent: 'center',
    },
    photoAdd: {
      width: 60,
      height: 60,
      borderRadius: radius.sm,
      borderWidth: 1.5,
      borderColor: colors.cta,
      borderStyle: 'dashed',
      alignItems: 'center',
      justifyContent: 'center',
    },
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
