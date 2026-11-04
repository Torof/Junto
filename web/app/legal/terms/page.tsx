import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Conditions d\'utilisation — askandgo',
  description: 'Conditions générales d\'utilisation de l\'application askandgo.',
};

const CONTACT_EMAIL = 'contact@askandgo.io';

export default function TermsPage() {
  return (
    <article style={{ color: 'var(--ink)', lineHeight: 1.6 }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, marginBottom: 8 }}>Conditions Générales d'Utilisation</h1>
      <p style={{ color: 'var(--muted)', fontSize: 14, marginBottom: 32 }}>
        Dernière mise à jour : novembre 2026
      </p>

      <H2>1. Objet</H2>
      <P>
        askandgo est une application mobile qui met en relation des personnes souhaitant pratiquer ensemble des activités sportives et de plein air, ainsi que des pratiquants et des professionnels (guides, moniteurs, accompagnateurs, écoles) qui présentent leurs sorties encadrées. Les présentes Conditions Générales d'Utilisation (CGU) régissent l'accès et l'utilisation de l'application askandgo et du site askandgo.io (ci-après "l'Application").
      </P>
      <P>
        L'Application est éditée à titre personnel et non professionnel par une personne physique (ci-après "l'Éditeur", voir les <A href="/legal/mentions">mentions légales</A>). Elle est gratuite et ne comporte aucun paiement.
      </P>

      <H2>2. Acceptation des CGU</H2>
      <P>
        L'utilisation de l'Application implique l'acceptation pleine et entière des présentes CGU. En créant un compte, l'Utilisateur reconnaît avoir lu, compris et accepté les présentes conditions.
      </P>

      <H2>3. Inscription et Compte</H2>
      <P>
        L'inscription est réservée aux personnes physiques âgées de 18 ans ou plus. L'Utilisateur s'engage à fournir des informations exactes lors de son inscription. Chaque Utilisateur reçoit un pseudonyme généré aléatoirement qu'il peut modifier ultérieurement.
      </P>
      <P>
        L'Utilisateur est responsable de la confidentialité de ses identifiants de connexion et de toute activité réalisée depuis son compte.
      </P>

      <H2>4. Services proposés</H2>
      <P>L'Application permet notamment de :</P>
      <Ul>
        <li>Créer des sorties sportives géolocalisées, les rechercher sur une carte et les rejoindre</li>
        <li>Organiser une sortie avec les participants : covoiturage, matériel, discussion, point de rendez-vous, traces GPX</li>
        <li>Indiquer ses disponibilités pour trouver des partenaires (même sport, même zone, mêmes dates)</li>
        <li>Participer à des canaux de discussion par sport et par lieu</li>
        <li>Échanger par messagerie privée, après une demande de contact acceptée (y compris par QR code)</li>
        <li>Valider sa présence aux sorties et donner un retour sur ses co-participants (fiabilité, niveau)</li>
        <li>Consulter les pages des professionnels, réserver leurs sorties encadrées et laisser un avis</li>
        <li>Pour les professionnels : tenir une page pro, un catalogue de sorties, un agenda, gérer les réservations et échanger avec leurs clients</li>
      </Ul>

      <H2>5. Obligations de l'Utilisateur</H2>
      <P>L'Utilisateur s'engage à :</P>
      <Ul>
        <li>Utiliser l'Application de manière conforme aux lois en vigueur</li>
        <li>Ne pas publier de contenu illicite, offensant, discriminatoire ou contraire aux bonnes mœurs</li>
        <li>Respecter les autres utilisateurs et adopter un comportement adapté lors des activités</li>
        <li>Ne pas créer de faux profils ni usurper l'identité d'un tiers</li>
        <li>Ne pas utiliser l'Application à des fins commerciales, sauf au moyen d'une page pro validée</li>
        <li>Signaler tout comportement inapproprié via le système de signalement</li>
      </Ul>

      <H2>6. Professionnels</H2>
      <P>
        Un Utilisateur peut demander une page pro pour présenter son activité et ses sorties encadrées. L'Éditeur valide les demandes en vérifiant leur cohérence. <B>L'Éditeur ne vérifie ni les diplômes, ni les cartes professionnelles, ni les assurances, ni l'existence légale de l'activité.</B> Le badge « PRO » indique qu'une page a été validée de cette façon ; il ne constitue pas une certification.
      </P>
      <P>En demandant une page pro, le professionnel déclare sur l'honneur et s'engage à :</P>
      <Ul>
        <li>Exercer légalement son activité et détenir les qualifications exigées pour encadrer contre rémunération (notamment la carte professionnelle d'éducateur sportif prévue par le Code du sport)</li>
        <li>Être couvert par une assurance de responsabilité civile professionnelle adaptée</li>
        <li>Respecter ses obligations, notamment fiscales, sociales et envers les consommateurs (information sur les prix et les conditions d'annulation)</li>
        <li>Publier des informations exactes et à jour : sorties, prix, dates, places, lieux</li>
        <li>N'utiliser les informations reçues de ses clients (coordonnées, fiches participants) que pour organiser la sortie réservée, sans prospection ni cession à des tiers</li>
      </Ul>
      <P>
        L'Éditeur peut retirer une page pro en cas de manquement, de signalement fondé ou de non-respect des présentes CGU.
      </P>

      <H2>7. Réservations</H2>
      <P>
        Une réservation faite dans l'Application est une demande adressée au professionnel, qui l'accepte ou la refuse ; sur une date fixe publiée par le professionnel, l'inscription est confirmée immédiatement dans la limite des places. <B>L'Éditeur n'est pas partie au contrat</B> : celui-ci se forme directement entre le client et le professionnel, aux conditions de ce dernier.
      </P>
      <Ul>
        <li>Aucun paiement ne transite par l'Application. Le prix, le paiement, un éventuel acompte, l'annulation et le remboursement se règlent directement entre le client et le professionnel.</li>
        <li>Le professionnel peut annuler une sortie ; les clients sont prévenus dans l'Application. Lorsqu'il a fixé un nombre minimum de participants, la sortie peut être annulée automatiquement la veille si ce minimum n'est pas atteint.</li>
        <li>L'Éditeur n'est pas responsable de l'exécution de la prestation, de sa qualité ni de sa sécurité, ni des litiges entre client et professionnel. Un comportement contraire aux CGU peut être signalé.</li>
        <li>Les droits des consommateurs s'appliquent dans la relation avec un professionnel ; ils ne s'appliquent pas entre particuliers qui organisent une sortie ensemble.</li>
      </Ul>

      <H2>8. Avis</H2>
      <P>
        Les pages pro et les sorties encadrées peuvent recevoir des avis. <B>Seul un Utilisateur dont la réservation a été acceptée, et dont la date de sortie est passée, peut déposer un avis</B> sur ce professionnel ou cette sortie.
      </P>
      <Ul>
        <li>Les avis ne donnent lieu à aucune contrepartie.</li>
        <li>Ni l'Éditeur ni le professionnel ne peuvent modifier un avis. Le professionnel peut y répondre publiquement ; l'auteur peut modifier ou supprimer le sien.</li>
        <li>Un avis peut être signalé. L'Éditeur peut retirer un avis contraire aux CGU (injurieux, hors sujet, sans lien avec une expérience réelle).</li>
        <li>Les avis sont affichés du plus récent au plus ancien.</li>
      </Ul>
      <P>
        Entre pratiquants, l'Application n'utilise ni notes ni classement : la fiabilité découle des présences validées, et le niveau est confirmé par les co-participants.
      </P>

      <H2>9. Affichage des contenus</H2>
      <P>
        Les sorties et les pages pro sont affichées sur la carte selon leur position géographique, et dans les listes selon les filtres et le tri choisis par l'Utilisateur. Aucun contenu n'est mis en avant contre rémunération. Sur sa propre page, un professionnel peut choisir la sortie qu'il met en avant.
      </P>

      <H2>10. Responsabilité</H2>
      <P>L'Éditeur met en relation les Utilisateurs mais n'organise pas les activités. L'Éditeur ne peut être tenu responsable :</P>
      <Ul>
        <li>Des dommages corporels ou matériels survenus lors d'une activité</li>
        <li>Du comportement des Utilisateurs avant, pendant ou après une activité</li>
        <li>De l'exactitude des informations fournies par les Utilisateurs ou les professionnels (niveau, description, qualifications, prix)</li>
        <li>Des conditions météorologiques ou environnementales</li>
      </Ul>
      <P>
        Chaque Utilisateur participe aux activités sous sa propre responsabilité et doit évaluer ses capacités physiques et les risques liés à l'activité.
      </P>

      <H2>11. Modération et Sanctions</H2>
      <P>
        L'Éditeur se réserve le droit de suspendre ou supprimer tout compte, page pro ou contenu en cas de violation des présentes CGU, notamment en cas de comportement inapproprié, harcèlement, contenu illicite ou usage abusif de la plateforme.
      </P>
      <P>
        Un Utilisateur suspendu en est informé via l'Application et peut contacter le support pour contester la décision.
      </P>

      <H2>12. Propriété intellectuelle</H2>
      <P>
        L'ensemble des éléments de l'Application (design, code, logos, textes) est protégé par le droit de la propriété intellectuelle. Toute reproduction ou utilisation non autorisée est interdite. L'Utilisateur reste titulaire des contenus qu'il publie (textes, photos, traces) et autorise leur affichage dans l'Application.
      </P>

      <H2>13. Suppression de compte</H2>
      <P>
        L'Utilisateur peut supprimer son compte à tout moment depuis les paramètres de l'Application. La suppression entraîne l'effacement définitif de ses données personnelles conformément à la <A href="/legal/privacy">Politique de Confidentialité</A>.
      </P>

      <H2>14. Modification des CGU</H2>
      <P>
        L'Éditeur se réserve le droit de modifier les présentes CGU. Les Utilisateurs seront informés de toute modification substantielle. La poursuite de l'utilisation de l'Application après modification vaut acceptation des nouvelles CGU.
      </P>

      <H2>15. Droit applicable</H2>
      <P>
        Les présentes CGU sont soumises au droit français. Tout litige relève des juridictions françaises compétentes.
      </P>

      <H2>16. Contact</H2>
      <P>
        Pour toute question relative aux présentes CGU : <A href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</A>.
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
function A({ href, children }: { href: string; children: React.ReactNode }) {
  return <a href={href} style={{ color: 'var(--cta)', textDecoration: 'underline' }}>{children}</a>;
}

function B({ children }: { children: React.ReactNode }) {
  return <strong style={{ color: 'var(--ink)' }}>{children}</strong>;
}
