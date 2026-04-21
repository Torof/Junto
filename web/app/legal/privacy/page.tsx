import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Politique de confidentialité — Junto',
  description: 'Politique de confidentialité de l\'application Junto.',
};

const CONTACT_EMAIL = 'contact@getjunto.app';

export default function PrivacyPage() {
  return (
    <article style={{ color: 'var(--text)', lineHeight: 1.6 }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, marginBottom: 8 }}>Politique de Confidentialité</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 32 }}>
        Dernière mise à jour : avril 2026
      </p>

      <H2>1. Responsable du traitement</H2>
      <P>
        Le responsable du traitement des données personnelles est Junto, joignable à l'adresse :{' '}
        <A href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</A>.
      </P>

      <H2>2. Données collectées</H2>
      <P><B>Données d'inscription :</B></P>
      <Ul>
        <li>Adresse email</li>
        <li>Date de naissance (vérification de l'âge minimum de 18 ans)</li>
        <li>Pseudonyme (généré automatiquement, modifiable)</li>
      </Ul>
      <P><B>Données de profil (optionnelles) :</B></P>
      <Ul>
        <li>Photo de profil</li>
        <li>Sports pratiqués</li>
      </Ul>
      <P><B>Données d'activité :</B></P>
      <Ul>
        <li>Activités créées et rejointes (titre, description, lieu, date, sport, niveau)</li>
        <li>Messages sur le mur d'événement et messages privés</li>
        <li>Évaluations de fiabilité et badges de réputation</li>
        <li>Signalements effectués</li>
      </Ul>
      <P><B>Données techniques :</B></P>
      <Ul>
        <li>Géolocalisation (pour afficher les activités à proximité)</li>
        <li>Données de session (token d'authentification stocké de manière sécurisée sur l'appareil)</li>
      </Ul>

      <H2>3. Finalités du traitement</H2>
      <Ul>
        <li>Permettre la création de votre compte et l'accès aux services</li>
        <li>Afficher les activités géolocalisées à proximité</li>
        <li>Permettre la communication entre utilisateurs</li>
        <li>Calculer le score de fiabilité et attribuer les badges</li>
        <li>Assurer la modération et la sécurité de la plateforme</li>
        <li>Vérifier l'âge minimum requis (18 ans)</li>
      </Ul>

      <H2>4. Base légale</H2>
      <Ul>
        <li>Votre consentement (inscription, acceptation des CGU)</li>
        <li>L'exécution du contrat (fourniture des services)</li>
        <li>L'intérêt légitime (sécurité, modération, prévention des abus)</li>
        <li>L'obligation légale (vérification de l'âge)</li>
      </Ul>

      <H2>5. Partage des données</H2>
      <P><B>Données visibles par les autres utilisateurs :</B></P>
      <Ul>
        <li>Pseudonyme, photo de profil, sports pratiqués, date d'inscription</li>
        <li>Score de fiabilité, badges de réputation et trophées</li>
        <li>Activités publiées (titre, lieu, date, sport, niveau)</li>
      </Ul>
      <P><B>Données NON visibles par les autres utilisateurs :</B></P>
      <Ul>
        <li>Adresse email, date de naissance, numéro de téléphone</li>
      </Ul>
      <P><B>Sous-traitants :</B></P>
      <Ul>
        <li>Supabase (hébergement, base de données, authentification — serveurs UE)</li>
        <li>Mapbox (affichage cartographique — reçoit des coordonnées de requête)</li>
        <li>Google Places (recherche de lieux — reçoit des requêtes de recherche)</li>
      </Ul>
      <P>Nous ne vendons jamais vos données à des tiers.</P>

      <H2>6. Durée de conservation</H2>
      <Ul>
        <li>Données de compte : conservées tant que le compte est actif</li>
        <li>Données d'activité : conservées tant que l'activité existe</li>
        <li>Messages du mur : anonymisés en cas de suppression du compte</li>
        <li>Signalements : conservés même après suppression du compte (obligation de modération)</li>
        <li>Après suppression du compte : toutes les données personnelles sont supprimées sous 30 jours maximum</li>
      </Ul>

      <H2>7. Sécurité des données</H2>
      <Ul>
        <li>Chiffrement des données en transit (HTTPS/TLS)</li>
        <li>Stockage sécurisé des tokens d'authentification sur l'appareil</li>
        <li>Row Level Security (RLS) sur toutes les tables de la base de données</li>
        <li>Validation et assainissement de toutes les entrées utilisateur</li>
        <li>Limitation de débit sur les opérations sensibles</li>
        <li>Suppression des métadonnées EXIF des photos uploadées</li>
      </Ul>

      <H2>8. Vos droits (RGPD)</H2>
      <P>
        Conformément au Règlement Général sur la Protection des Données (RGPD), vous disposez des droits suivants :
      </P>
      <Ul>
        <li><B>Droit d'accès :</B> obtenir une copie de vos données personnelles</li>
        <li><B>Droit de rectification :</B> modifier vos données depuis votre profil</li>
        <li><B>Droit à l'effacement :</B> supprimer votre compte depuis les paramètres</li>
        <li><B>Droit à la portabilité :</B> obtenir vos données dans un format structuré</li>
        <li><B>Droit d'opposition :</B> vous opposer au traitement de vos données</li>
        <li><B>Droit à la limitation :</B> demander la limitation du traitement</li>
      </Ul>
      <P>
        Pour exercer ces droits, contactez-nous : <A href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</A>.
      </P>
      <P>
        Vous pouvez également introduire une réclamation auprès de la CNIL (<A href="https://www.cnil.fr">www.cnil.fr</A>).
      </P>

      <H2>9. Géolocalisation</H2>
      <P>L'Application utilise votre position géographique pour :</P>
      <Ul>
        <li>Afficher les activités à proximité sur la carte</li>
        <li>Calculer la distance entre vous et les activités</li>
        <li>Centrer la carte sur votre position</li>
      </Ul>
      <P>
        Votre position n'est jamais stockée de manière permanente. Vous pouvez désactiver la géolocalisation dans les paramètres de votre appareil. Un fallback par IP est utilisé si la géolocalisation est désactivée.
      </P>

      <H2>10. Mineurs</H2>
      <P>
        L'Application est strictement réservée aux personnes de 18 ans et plus. La vérification de l'âge est effectuée lors de l'inscription via la date de naissance.
      </P>

      <H2>11. Modifications</H2>
      <P>
        Nous nous réservons le droit de modifier cette politique. Toute modification substantielle sera communiquée via l'Application.
      </P>

      <H2>12. Contact</H2>
      <P>
        Pour toute question relative à la protection de vos données :{' '}
        <A href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</A>.
      </P>
    </article>
  );
}

function H2({ children }: { children: React.ReactNode }) {
  return <h2 style={{ fontSize: 18, fontWeight: 700, marginTop: 32, marginBottom: 12 }}>{children}</h2>;
}
function P({ children }: { children: React.ReactNode }) {
  return <p style={{ color: 'var(--text-secondary)', fontSize: 15, marginBottom: 12 }}>{children}</p>;
}
function Ul({ children }: { children: React.ReactNode }) {
  return <ul style={{ color: 'var(--text-secondary)', fontSize: 15, marginBottom: 12, paddingLeft: 20 }}>{children}</ul>;
}
function B({ children }: { children: React.ReactNode }) {
  return <strong style={{ color: 'var(--text)' }}>{children}</strong>;
}
function A({ href, children }: { href: string; children: React.ReactNode }) {
  return <a href={href} style={{ color: 'var(--cta)', textDecoration: 'underline' }}>{children}</a>;
}
