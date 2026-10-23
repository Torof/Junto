import { useMemo } from 'react';
import { ScrollView, StyleSheet } from 'react-native';
import { AppText } from '@/components/app-text';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useColors } from '@/hooks/use-theme';
import { fontSizes, spacing } from '@/constants/theme';
import type { AppColors } from '@/constants/colors';

export default function PrivacyScreen() {
  const colors = useColors();
  const styles = useMemo(() => createStyles(colors), [colors]);
  const insets = useSafeAreaInsets();

  return (
    <ScrollView style={styles.container} contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + spacing.xl }]}>
      <AppText style={styles.title}>Politique de Confidentialité</AppText>
      <AppText style={styles.date}>Dernière mise à jour : avril 2026</AppText>

      <AppText style={styles.heading}>1. Responsable du traitement</AppText>
      <AppText style={styles.body}>
        Le responsable du traitement des données personnelles est Junto, joignable à l'adresse : support@junto.app
      </AppText>

      <AppText style={styles.heading}>2. Données collectées</AppText>
      <AppText style={styles.body}>
        Nous collectons les données suivantes :{'\n\n'}
        <AppText style={styles.bold}>Données d'inscription :</AppText>{'\n'}
        • Adresse email{'\n'}
        • Pseudonyme (généré automatiquement, modifiable){'\n\n'}
        <AppText style={styles.bold}>Données de profil (optionnelles) :</AppText>{'\n'}
        • Photo de profil{'\n'}
        • Sports pratiqués{'\n\n'}
        <AppText style={styles.bold}>Données d'activité :</AppText>{'\n'}
        • Activités créées et rejointes (titre, description, lieu, date, sport, niveau){'\n'}
        • Messages sur le mur d'événement et messages privés{'\n'}
        • Évaluations de fiabilité et badges de réputation{'\n'}
        • Signalements effectués{'\n\n'}
        <AppText style={styles.bold}>Données techniques :</AppText>{'\n'}
        • Géolocalisation (pour afficher les activités à proximité){'\n'}
        • Données de session (token d'authentification, stocké de manière sécurisée sur l'appareil){'\n\n'}
        <AppText style={styles.bold}>Données professionnelles (uniquement pour les pages pro) :</AppText>{'\n'}
        • Nom de la structure et coordonnées, affichés publiquement sur la page pro{'\n'}
        • Nom et prénom du responsable — collectés pour vérifier la demande, jamais publics
      </AppText>

      <AppText style={styles.heading}>3. Finalités du traitement</AppText>
      <AppText style={styles.body}>
        Vos données sont traitées pour :{'\n'}
        • Permettre la création de votre compte et l'accès aux services{'\n'}
        • Afficher les activités géolocalisées à proximité{'\n'}
        • Permettre la communication entre utilisateurs{'\n'}
        • Calculer le score de fiabilité et attribuer les badges{'\n'}
        • Assurer la modération et la sécurité de la plateforme{'\n'}
        • Recueillir l'attestation d'âge minimum requis (18 ans)
      </AppText>

      <AppText style={styles.heading}>4. Base légale</AppText>
      <AppText style={styles.body}>
        Le traitement de vos données repose sur :{'\n'}
        • Votre consentement (inscription, acceptation des CGU){'\n'}
        • L'exécution du contrat (fourniture des services){'\n'}
        • L'intérêt légitime (sécurité, modération, prévention des abus){'\n'}
        • L'obligation légale (vérification de l'âge)
      </AppText>

      <AppText style={styles.heading}>5. Partage des données</AppText>
      <AppText style={styles.body}>
        <AppText style={styles.bold}>Données visibles par les autres utilisateurs :</AppText>{'\n'}
        • Pseudonyme, photo de profil, sports pratiqués, date d'inscription{'\n'}
        • Score de fiabilité, badges de réputation et trophées{'\n'}
        • Activités publiées (titre, lieu, date, sport, niveau){'\n\n'}
        <AppText style={styles.bold}>Données NON visibles par les autres utilisateurs :</AppText>{'\n'}
        • Adresse email{'\n'}
        • Nom et prénom du responsable d'une page pro (vérification interne){'\n\n'}
        <AppText style={styles.bold}>Sous-traitants :</AppText>{'\n'}
        • Supabase (hébergement, base de données, authentification — serveurs UE){'\n'}
        • Mapbox (affichage cartographique — reçoit des coordonnées de requête){'\n'}
        • Expo / Google Firebase Cloud Messaging (notifications push — reçoit le token d'appareil){'\n'}
        • GeoJS (zone approximative à partir de l'adresse IP, seulement si la localisation n'est pas autorisée — reçoit l'adresse IP){'\n'}
        • Photon / komoot (recherche de lieux et nom du lieu à partir d'une position — reçoit le texte recherché ou les coordonnées ; Allemagne){'\n'}
        • OpenRouteService / HeiGIT (calage d'un tracé dessiné sur les sentiers — reçoit les points du tracé, via nos serveurs ; Allemagne){'\n'}
        • IGN Géoplateforme (calcul du dénivelé d'un tracé — reçoit les points du tracé, via nos serveurs ; France){'\n'}
        • Resend (envoi des e-mails de compte : confirmation, mot de passe — reçoit l'adresse email ; États-Unis){'\n\n'}
        Nous ne vendons jamais vos données à des tiers.
      </AppText>

      <AppText style={styles.heading}>6. Durée de conservation</AppText>
      <AppText style={styles.body}>
        • Données de compte : conservées tant que le compte est actif{'\n'}
        • Données d'activité : conservées tant que l'activité existe{'\n'}
        • Messages du mur : anonymisés en cas de suppression du compte{'\n'}
        • Signalements : conservés même après suppression du compte (obligation de modération){'\n'}
        • Après suppression du compte : toutes les données personnelles sont supprimées sous 30 jours maximum
      </AppText>

      <AppText style={styles.heading}>7. Sécurité des données</AppText>
      <AppText style={styles.body}>
        Nous mettons en œuvre les mesures suivantes :{'\n'}
        • Chiffrement des données en transit (HTTPS/TLS){'\n'}
        • Stockage sécurisé des tokens d'authentification sur l'appareil{'\n'}
        • Row Level Security (RLS) sur toutes les tables de la base de données{'\n'}
        • Validation et assainissement de toutes les entrées utilisateur{'\n'}
        • Limitation de débit sur les opérations sensibles{'\n'}
        • Suppression des métadonnées EXIF des photos uploadées
      </AppText>

      <AppText style={styles.heading}>8. Vos droits (RGPD)</AppText>
      <AppText style={styles.body}>
        Conformément au Règlement Général sur la Protection des Données (RGPD), vous disposez des droits suivants :{'\n\n'}
        • <AppText style={styles.bold}>Droit d'accès :</AppText> obtenir une copie de vos données personnelles{'\n'}
        • <AppText style={styles.bold}>Droit de rectification :</AppText> modifier vos données depuis votre profil{'\n'}
        • <AppText style={styles.bold}>Droit à l'effacement :</AppText> supprimer votre compte depuis les paramètres{'\n'}
        • <AppText style={styles.bold}>Droit à la portabilité :</AppText> obtenir vos données dans un format structuré{'\n'}
        • <AppText style={styles.bold}>Droit d'opposition :</AppText> vous opposer au traitement de vos données{'\n'}
        • <AppText style={styles.bold}>Droit à la limitation :</AppText> demander la limitation du traitement{'\n\n'}
        Pour exercer ces droits, contactez-nous : support@junto.app{'\n\n'}
        Vous pouvez également introduire une réclamation auprès de la CNIL (www.cnil.fr).
      </AppText>

      <AppText style={styles.heading}>9. Géolocalisation</AppText>
      <AppText style={styles.body}>
        L'Application utilise votre position géographique pour :{'\n'}
        • Afficher les activités à proximité sur la carte{'\n'}
        • Calculer la distance entre vous et les activités{'\n'}
        • Centrer la carte sur votre position{'\n\n'}
        Votre position n'est jamais stockée de manière permanente. Vous pouvez désactiver la géolocalisation dans les paramètres de votre appareil. Un fallback par IP est utilisé si la géolocalisation est désactivée.
      </AppText>

      <AppText style={styles.heading}>10. Mineurs</AppText>
      <AppText style={styles.body}>
        L'Application est strictement réservée aux personnes de 18 ans et plus. Lors de l'inscription, l'utilisateur atteste sur l'honneur avoir 18 ans ou plus. Aucune date de naissance n'est collectée.
      </AppText>

      <AppText style={styles.heading}>11. Modifications</AppText>
      <AppText style={styles.body}>
        Nous nous réservons le droit de modifier cette politique. Toute modification substantielle sera communiquée via l'Application.
      </AppText>

      <AppText style={styles.heading}>12. Contact</AppText>
      <AppText style={styles.body}>
        Pour toute question relative à la protection de vos données : support@junto.app
      </AppText>
    </ScrollView>
  );
}

const createStyles = (colors: AppColors) => StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.xs },
  date: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xl },
  heading: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold', marginTop: spacing.lg, marginBottom: spacing.sm },
  body: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  bold: { fontWeight: 'bold', color: colors.textPrimary },
});
