import { ScrollView, Text, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fontSizes, spacing } from '@/constants/theme';

export default function PrivacyScreen() {
  const insets = useSafeAreaInsets();

  return (
    <ScrollView style={styles.container} contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + spacing.xl }]}>
      <Text style={styles.title}>Politique de Confidentialité</Text>
      <Text style={styles.date}>Dernière mise à jour : avril 2026</Text>

      <Text style={styles.heading}>1. Responsable du traitement</Text>
      <Text style={styles.body}>
        Le responsable du traitement des données personnelles est Junto, joignable à l'adresse : support@junto.app
      </Text>

      <Text style={styles.heading}>2. Données collectées</Text>
      <Text style={styles.body}>
        Nous collectons les données suivantes :{'\n\n'}
        <Text style={styles.bold}>Données d'inscription :</Text>{'\n'}
        • Adresse email{'\n'}
        • Date de naissance (vérification de l'âge minimum de 18 ans){'\n'}
        • Pseudonyme (généré automatiquement, modifiable){'\n\n'}
        <Text style={styles.bold}>Données de profil (optionnelles) :</Text>{'\n'}
        • Photo de profil{'\n'}
        • Sports pratiqués{'\n\n'}
        <Text style={styles.bold}>Données d'activité :</Text>{'\n'}
        • Activités créées et rejointes (titre, description, lieu, date, sport, niveau){'\n'}
        • Messages sur le mur d'événement et messages privés{'\n'}
        • Évaluations de fiabilité et badges de réputation{'\n'}
        • Signalements effectués{'\n\n'}
        <Text style={styles.bold}>Données techniques :</Text>{'\n'}
        • Géolocalisation (pour afficher les activités à proximité){'\n'}
        • Données de session (token d'authentification, stocké de manière sécurisée sur l'appareil)
      </Text>

      <Text style={styles.heading}>3. Finalités du traitement</Text>
      <Text style={styles.body}>
        Vos données sont traitées pour :{'\n'}
        • Permettre la création de votre compte et l'accès aux services{'\n'}
        • Afficher les activités géolocalisées à proximité{'\n'}
        • Permettre la communication entre utilisateurs{'\n'}
        • Calculer le score de fiabilité et attribuer les badges{'\n'}
        • Assurer la modération et la sécurité de la plateforme{'\n'}
        • Vérifier l'âge minimum requis (18 ans)
      </Text>

      <Text style={styles.heading}>4. Base légale</Text>
      <Text style={styles.body}>
        Le traitement de vos données repose sur :{'\n'}
        • Votre consentement (inscription, acceptation des CGU){'\n'}
        • L'exécution du contrat (fourniture des services){'\n'}
        • L'intérêt légitime (sécurité, modération, prévention des abus){'\n'}
        • L'obligation légale (vérification de l'âge)
      </Text>

      <Text style={styles.heading}>5. Partage des données</Text>
      <Text style={styles.body}>
        <Text style={styles.bold}>Données visibles par les autres utilisateurs :</Text>{'\n'}
        • Pseudonyme, photo de profil, sports pratiqués, date d'inscription{'\n'}
        • Score de fiabilité, badges de réputation et trophées{'\n'}
        • Activités publiées (titre, lieu, date, sport, niveau){'\n\n'}
        <Text style={styles.bold}>Données NON visibles par les autres utilisateurs :</Text>{'\n'}
        • Adresse email, date de naissance, numéro de téléphone{'\n\n'}
        <Text style={styles.bold}>Sous-traitants :</Text>{'\n'}
        • Supabase (hébergement, base de données, authentification — serveurs UE){'\n'}
        • Mapbox (affichage cartographique — reçoit des coordonnées de requête){'\n'}
        • Google Places (recherche de lieux — reçoit des requêtes de recherche){'\n\n'}
        Nous ne vendons jamais vos données à des tiers.
      </Text>

      <Text style={styles.heading}>6. Durée de conservation</Text>
      <Text style={styles.body}>
        • Données de compte : conservées tant que le compte est actif{'\n'}
        • Données d'activité : conservées tant que l'activité existe{'\n'}
        • Messages du mur : anonymisés en cas de suppression du compte{'\n'}
        • Signalements : conservés même après suppression du compte (obligation de modération){'\n'}
        • Après suppression du compte : toutes les données personnelles sont supprimées sous 30 jours maximum
      </Text>

      <Text style={styles.heading}>7. Sécurité des données</Text>
      <Text style={styles.body}>
        Nous mettons en œuvre les mesures suivantes :{'\n'}
        • Chiffrement des données en transit (HTTPS/TLS){'\n'}
        • Stockage sécurisé des tokens d'authentification sur l'appareil{'\n'}
        • Row Level Security (RLS) sur toutes les tables de la base de données{'\n'}
        • Validation et assainissement de toutes les entrées utilisateur{'\n'}
        • Limitation de débit sur les opérations sensibles{'\n'}
        • Suppression des métadonnées EXIF des photos uploadées
      </Text>

      <Text style={styles.heading}>8. Vos droits (RGPD)</Text>
      <Text style={styles.body}>
        Conformément au Règlement Général sur la Protection des Données (RGPD), vous disposez des droits suivants :{'\n\n'}
        • <Text style={styles.bold}>Droit d'accès :</Text> obtenir une copie de vos données personnelles{'\n'}
        • <Text style={styles.bold}>Droit de rectification :</Text> modifier vos données depuis votre profil{'\n'}
        • <Text style={styles.bold}>Droit à l'effacement :</Text> supprimer votre compte depuis les paramètres{'\n'}
        • <Text style={styles.bold}>Droit à la portabilité :</Text> obtenir vos données dans un format structuré{'\n'}
        • <Text style={styles.bold}>Droit d'opposition :</Text> vous opposer au traitement de vos données{'\n'}
        • <Text style={styles.bold}>Droit à la limitation :</Text> demander la limitation du traitement{'\n\n'}
        Pour exercer ces droits, contactez-nous : support@junto.app{'\n\n'}
        Vous pouvez également introduire une réclamation auprès de la CNIL (www.cnil.fr).
      </Text>

      <Text style={styles.heading}>9. Géolocalisation</Text>
      <Text style={styles.body}>
        L'Application utilise votre position géographique pour :{'\n'}
        • Afficher les activités à proximité sur la carte{'\n'}
        • Calculer la distance entre vous et les activités{'\n'}
        • Centrer la carte sur votre position{'\n\n'}
        Votre position n'est jamais stockée de manière permanente. Vous pouvez désactiver la géolocalisation dans les paramètres de votre appareil. Un fallback par IP est utilisé si la géolocalisation est désactivée.
      </Text>

      <Text style={styles.heading}>10. Mineurs</Text>
      <Text style={styles.body}>
        L'Application est strictement réservée aux personnes de 18 ans et plus. La vérification de l'âge est effectuée lors de l'inscription via la date de naissance.
      </Text>

      <Text style={styles.heading}>11. Modifications</Text>
      <Text style={styles.body}>
        Nous nous réservons le droit de modifier cette politique. Toute modification substantielle sera communiquée via l'Application.
      </Text>

      <Text style={styles.heading}>12. Contact</Text>
      <Text style={styles.body}>
        Pour toute question relative à la protection de vos données : support@junto.app
      </Text>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: spacing.lg },
  title: { color: colors.textPrimary, fontSize: fontSizes.xl, fontWeight: 'bold', marginBottom: spacing.xs },
  date: { color: colors.textSecondary, fontSize: fontSizes.xs, marginBottom: spacing.xl },
  heading: { color: colors.textPrimary, fontSize: fontSizes.md, fontWeight: 'bold', marginTop: spacing.lg, marginBottom: spacing.sm },
  body: { color: colors.textSecondary, fontSize: fontSizes.sm, lineHeight: 20 },
  bold: { fontWeight: 'bold', color: colors.textPrimary },
});
