import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Politique de confidentialité — askandgo',
  description: 'Politique de confidentialité de l\'application askandgo.',
};

const CONTACT_EMAIL = 'contact@askandgo.io';

export default function PrivacyPage() {
  return (
    <article style={{ color: 'var(--ink)', lineHeight: 1.6 }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, marginBottom: 8 }}>Politique de Confidentialité</h1>
      <p style={{ color: 'var(--muted)', fontSize: 14, marginBottom: 32 }}>
        Dernière mise à jour : novembre 2026
      </p>

      <H2>1. Responsable du traitement</H2>
      <P>
        Le responsable du traitement des données personnelles est l'éditeur d'askandgo, personne physique (voir les{' '}
      <A href="/legal/mentions">mentions légales</A>), joignable à l'adresse :{' '}
        <A href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</A>.
      </P>

      <H2>2. Données collectées</H2>
      <P><B>Données d'inscription :</B></P>
      <Ul>
        <li>Adresse email</li>
        <li>Pseudonyme (généré automatiquement, modifiable)</li>
      </Ul>
      <P><B>Données de profil (optionnelles) :</B></P>
      <Ul>
        <li>Photo de profil</li>
        <li>Présentation (bio)</li>
        <li>Sports pratiqués</li>
      </Ul>
      <P><B>Données d'activité :</B></P>
      <Ul>
        <li>Activités créées et rejointes (titre, description, lieu, date, sport, niveau)</li>
        <li>Traces GPX et leurs étapes</li>
        <li>Disponibilités indiquées pour trouver des partenaires (sports, dates, zone et rayon)</li>
        <li>Messages sur le mur d'événement, dans les canaux de discussion et messages privés ; contacts</li>
        <li>Évaluations de fiabilité et badges de réputation</li>
        <li>Signalements effectués</li>
        <li>Avis déposés sur les professionnels et leurs sorties</li>
      </Ul>
      <P><B>Données de réservation (si vous réservez une sortie encadrée) :</B></P>
      <Ul>
        <li>Sortie, date, nombre de personnes et message adressé au professionnel</li>
        <li>Fiches participants, lorsque le professionnel les demande : pointure, taille, poids, âge, niveau, réponses à ses questions</li>
      </Ul>
      <P><B>Données techniques :</B></P>
      <Ul>
        <li>Géolocalisation (pour afficher les activités à proximité et valider la présence aux activités)</li>
        <li>Données de session (token d'authentification stocké de manière sécurisée sur l'appareil)</li>
        <li>Identifiant d'appareil et token de notification push (livraison des notifications)</li>
      </Ul>
      <P><B>Données professionnelles (uniquement si vous demandez une page pro) :</B></P>
      <Ul>
        <li>Nom de la structure et coordonnées (site web, email, téléphone, réseaux sociaux), affichés publiquement sur la page pro</li>
        <li>Nom et prénom du responsable — collectés uniquement pour vérifier et valider la demande, <B>jamais affichés publiquement</B></li>
        <li>Agenda (créneaux ouverts, réservations) et, si le professionnel en connecte un, l'adresse de son agenda externe</li>
      </Ul>

      <H2>3. Finalités du traitement</H2>
      <Ul>
        <li>Permettre la création de votre compte et l'accès aux services</li>
        <li>Afficher les activités géolocalisées à proximité</li>
        <li>Permettre la communication entre utilisateurs</li>
        <li>Calculer le score de fiabilité et attribuer les badges</li>
        <li>Assurer la modération et la sécurité de la plateforme</li>
        <li>Recueillir l'attestation d'âge minimum requis (18 ans)</li>
        <li>Vérifier et valider les demandes de page pro</li>
        <li>Transmettre les réservations et les fiches participants au professionnel concerné</li>
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
      <P><B>Données transmises au professionnel quand vous réservez :</B></P>
      <Ul>
        <li>Pseudonyme et photo, réservation, message et fiches participants</li>
        <li>Le professionnel ne peut les utiliser que pour organiser la sortie réservée (voir les CGU)</li>
        <li>
          Si le professionnel abonne son agenda externe (Google, Apple, Outlook) à askandgo, vos
          réservations y apparaissent sans votre nom, sauf s'il choisit d'afficher les noms (votre pseudonyme).
          À l'inverse, quand il importe son agenda externe, askandgo n'en conserve que les créneaux
          occupés, jamais le contenu des événements.
        </li>
      </Ul>
      <P><B>Données NON visibles par les autres utilisateurs :</B></P>
      <Ul>
        <li>Adresse email</li>
        <li>Nom et prénom du responsable d'une page pro (vérification interne uniquement)</li>
      </Ul>
      <P><B>Sous-traitants :</B></P>
      <Ul>
        <li>Supabase (hébergement, base de données, authentification — serveurs UE)</li>
        <li>Mapbox (affichage cartographique — reçoit des coordonnées de requête ; États-Unis)</li>
        <li>Expo / Google Firebase Cloud Messaging (livraison des notifications push — reçoit le token d'appareil ; États-Unis)</li>
        <li>GeoJS (zone approximative à partir de l'adresse IP, seulement quand aucune position n'est disponible sur l'appareil — reçoit l'adresse IP)</li>
        <li>Photon / komoot (recherche de lieux et nom du lieu à partir d'une position — reçoit le texte recherché ou les coordonnées ; Allemagne)</li>
        <li>OpenRouteService / HeiGIT (calage d'un tracé dessiné sur les sentiers — reçoit les points du tracé, via nos serveurs ; Allemagne)</li>
        <li>IGN Géoplateforme (calcul du dénivelé d'un tracé — reçoit les points du tracé, via nos serveurs ; France)</li>
        <li>Resend (envoi des e-mails de compte : confirmation, mot de passe — reçoit l'adresse email ; et des demandes de page pro à l'équipe askandgo ; États-Unis)</li>
        <li>Vercel (hébergement du site web askandgo.io ; États-Unis)</li>
      </Ul>
      <P>
        Les transferts de données vers des sous-traitants situés hors de l'Union européenne sont
        encadrés par les Clauses Contractuelles Types de la Commission européenne et/ou le EU-US
        Data Privacy Framework, selon le sous-traitant.
      </P>
      <P>Nous ne vendons jamais vos données à des tiers.</P>

      <H2>6. Durée de conservation</H2>
      <Ul>
        <li>Données de compte : conservées tant que le compte est actif</li>
        <li>Données d'activité : conservées tant que l'activité existe</li>
        <li>Messages du mur : anonymisés en cas de suppression du compte (le contenu reste, sans lien avec vous)</li>
        <li>Signalements : conservés même après suppression du compte (obligation de modération)</li>
        <li>Notifications : effacées automatiquement après 7 jours (sauf une demande pas encore lue)</li>
        <li>Fiches participants, message de réservation et téléphone noté par le professionnel : effacés 30 jours après la date de la sortie</li>
        <li>Quand vous retirez un contact, la conversation disparaît pour vous deux ; une copie est conservée 90 jours, accessible uniquement à la modération (en cas de signalement), puis effacée</li>
        <li>Après suppression du compte : données et médias (photos de profil, galeries) supprimés immédiatement ; toute donnée résiduelle sous 30 jours maximum</li>
      </Ul>
      <P>
        La suppression de compte se fait depuis les paramètres de l'application, ou{' '}
        <A href="/legal/account-deletion">sur demande sans accès à l'application</A>.
      </P>

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
        <li>Valider automatiquement votre présence aux activités auxquelles vous participez</li>
      </Ul>
      <P>
        <B>Géolocalisation en arrière-plan :</B> si vous l'autorisez explicitement, l'Application
        peut détecter votre arrivée sur le lieu d'une activité à laquelle vous participez{' '}
        <B>même lorsqu'elle est fermée</B>. La détection est armée à partir de 24 heures avant le
        début de l'activité et s'arrête 15 minutes après le début. Seule une position relevée entre
        15 minutes avant et 15 minutes après le début sert à valider la présence. Sans connexion,
        cette validation reste sur votre téléphone et est envoyée au plus tard 24 heures après la
        fin de l'activité. Cette autorisation est optionnelle (la présence peut aussi être validée
        par QR code) et révocable à tout moment dans les paramètres de votre appareil.
      </P>
      <P>
        Votre position n'est jamais stockée de manière permanente. La dernière position connue est
        gardée sur votre téléphone, pour ouvrir la carte sur votre région. Quand aucune position
        n'est disponible, une zone approximative est déduite de l'adresse IP.
      </P>

      <H2>10. Cookies et mesure d'audience</H2>
      <P>
        L'Application et le site askandgo.io n'utilisent aucun cookie de suivi, aucun outil de mesure
        d'audience et aucune publicité.
      </P>

      <H2>11. Mineurs</H2>
      <P>
        L'Application est strictement réservée aux personnes de 18 ans et plus. Lors de l'inscription, l'utilisateur atteste sur l'honneur avoir 18 ans ou plus. Aucune date de naissance n'est collectée.
      </P>

      <H2>12. Modifications</H2>
      <P>
        Nous nous réservons le droit de modifier cette politique. Toute modification substantielle sera communiquée via l'Application.
      </P>

      <H2>13. Contact</H2>
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
  return <p style={{ color: 'var(--muted)', fontSize: 15, marginBottom: 12 }}>{children}</p>;
}
function Ul({ children }: { children: React.ReactNode }) {
  return <ul style={{ color: 'var(--muted)', fontSize: 15, marginBottom: 12, paddingLeft: 20 }}>{children}</ul>;
}
function B({ children }: { children: React.ReactNode }) {
  return <strong style={{ color: 'var(--ink)' }}>{children}</strong>;
}
function A({ href, children }: { href: string; children: React.ReactNode }) {
  return <a href={href} style={{ color: 'var(--cta)', textDecoration: 'underline' }}>{children}</a>;
}
