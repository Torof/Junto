import { ScrollView, Text, StyleSheet } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { colors, fontSizes, spacing } from '@/constants/theme';

export default function TermsScreen() {
  const insets = useSafeAreaInsets();

  return (
    <ScrollView style={styles.container} contentContainerStyle={[styles.content, { paddingBottom: insets.bottom + spacing.xl }]}>
      <Text style={styles.title}>Conditions Générales d'Utilisation</Text>
      <Text style={styles.date}>Dernière mise à jour : avril 2026</Text>

      <Text style={styles.heading}>1. Objet</Text>
      <Text style={styles.body}>
        Junto est une application mobile de mise en relation entre personnes souhaitant pratiquer des activités sportives et de plein air ensemble. Les présentes Conditions Générales d'Utilisation (CGU) régissent l'accès et l'utilisation de l'application Junto (ci-après "l'Application") éditée par Junto (ci-après "l'Éditeur").
      </Text>

      <Text style={styles.heading}>2. Acceptation des CGU</Text>
      <Text style={styles.body}>
        L'utilisation de l'Application implique l'acceptation pleine et entière des présentes CGU. En créant un compte, l'Utilisateur reconnaît avoir lu, compris et accepté les présentes conditions.
      </Text>

      <Text style={styles.heading}>3. Inscription et Compte</Text>
      <Text style={styles.body}>
        L'inscription est réservée aux personnes physiques âgées de 18 ans ou plus. L'Utilisateur s'engage à fournir des informations exactes lors de son inscription. Chaque Utilisateur reçoit un pseudonyme généré aléatoirement qu'il peut modifier ultérieurement.{'\n\n'}
        L'Utilisateur est responsable de la confidentialité de ses identifiants de connexion et de toute activité réalisée depuis son compte.
      </Text>

      <Text style={styles.heading}>4. Services proposés</Text>
      <Text style={styles.body}>
        L'Application permet de :{'\n'}
        • Créer des activités sportives géolocalisées{'\n'}
        • Rechercher et rejoindre des activités créées par d'autres utilisateurs{'\n'}
        • Communiquer via un mur d'événement et une messagerie privée{'\n'}
        • Évaluer la fiabilité des co-participants{'\n'}
        • Partager des activités via un lien d'invitation
      </Text>

      <Text style={styles.heading}>5. Obligations de l'Utilisateur</Text>
      <Text style={styles.body}>
        L'Utilisateur s'engage à :{'\n'}
        • Utiliser l'Application de manière conforme aux lois en vigueur{'\n'}
        • Ne pas publier de contenu illicite, offensant, discriminatoire ou contraire aux bonnes mœurs{'\n'}
        • Respecter les autres utilisateurs et adopter un comportement adapté lors des activités{'\n'}
        • Ne pas créer de faux profils ni usurper l'identité d'un tiers{'\n'}
        • Ne pas utiliser l'Application à des fins commerciales sans autorisation{'\n'}
        • Signaler tout comportement inapproprié via le système de signalement
      </Text>

      <Text style={styles.heading}>6. Responsabilité</Text>
      <Text style={styles.body}>
        L'Éditeur met en relation les Utilisateurs mais n'organise pas les activités. L'Éditeur ne peut être tenu responsable :{'\n'}
        • Des dommages corporels ou matériels survenus lors d'une activité{'\n'}
        • Du comportement des Utilisateurs avant, pendant ou après une activité{'\n'}
        • De l'exactitude des informations fournies par les Utilisateurs (niveau, description){'\n'}
        • Des conditions météorologiques ou environnementales{'\n\n'}
        Chaque Utilisateur participe aux activités sous sa propre responsabilité et doit évaluer ses capacités physiques et les risques liés à l'activité.
      </Text>

      <Text style={styles.heading}>7. Modération et Sanctions</Text>
      <Text style={styles.body}>
        L'Éditeur se réserve le droit de suspendre ou supprimer tout compte en cas de violation des présentes CGU, notamment en cas de comportement inapproprié, harcèlement, contenu illicite ou usage abusif de la plateforme.{'\n\n'}
        Un Utilisateur suspendu en est informé via l'Application et peut contacter le support pour contester la décision.
      </Text>

      <Text style={styles.heading}>8. Propriété intellectuelle</Text>
      <Text style={styles.body}>
        L'ensemble des éléments de l'Application (design, code, logos, textes) est protégé par le droit de la propriété intellectuelle. Toute reproduction ou utilisation non autorisée est interdite.
      </Text>

      <Text style={styles.heading}>9. Suppression de compte</Text>
      <Text style={styles.body}>
        L'Utilisateur peut supprimer son compte à tout moment depuis les paramètres de l'Application. La suppression entraîne l'effacement définitif de ses données personnelles conformément à la Politique de Confidentialité.
      </Text>

      <Text style={styles.heading}>10. Modification des CGU</Text>
      <Text style={styles.body}>
        L'Éditeur se réserve le droit de modifier les présentes CGU. Les Utilisateurs seront informés de toute modification substantielle. La poursuite de l'utilisation de l'Application après modification vaut acceptation des nouvelles CGU.
      </Text>

      <Text style={styles.heading}>11. Droit applicable</Text>
      <Text style={styles.body}>
        Les présentes CGU sont soumises au droit français. Tout litige sera soumis aux tribunaux compétents du ressort du siège social de l'Éditeur.
      </Text>

      <Text style={styles.heading}>12. Contact</Text>
      <Text style={styles.body}>
        Pour toute question relative aux présentes CGU : support@junto.app
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
});
