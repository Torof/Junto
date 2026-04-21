import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Conditions d\'utilisation — Junto',
  description: 'Conditions générales d\'utilisation de l\'application Junto.',
};

const CONTACT_EMAIL = 'contact@getjunto.app';

export default function TermsPage() {
  return (
    <article style={{ color: 'var(--text)', lineHeight: 1.6 }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, marginBottom: 8 }}>Conditions Générales d'Utilisation</h1>
      <p style={{ color: 'var(--text-secondary)', fontSize: 14, marginBottom: 32 }}>
        Dernière mise à jour : avril 2026
      </p>

      <H2>1. Objet</H2>
      <P>
        Junto est une application mobile de mise en relation entre personnes souhaitant pratiquer des activités sportives et de plein air ensemble. Les présentes Conditions Générales d'Utilisation (CGU) régissent l'accès et l'utilisation de l'application Junto (ci-après "l'Application") éditée par Junto (ci-après "l'Éditeur").
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
      <P>L'Application permet de :</P>
      <Ul>
        <li>Créer des activités sportives géolocalisées</li>
        <li>Rechercher et rejoindre des activités créées par d'autres utilisateurs</li>
        <li>Communiquer via un mur d'événement et une messagerie privée</li>
        <li>Évaluer la fiabilité des co-participants</li>
        <li>Partager des activités via un lien d'invitation</li>
      </Ul>

      <H2>5. Obligations de l'Utilisateur</H2>
      <P>L'Utilisateur s'engage à :</P>
      <Ul>
        <li>Utiliser l'Application de manière conforme aux lois en vigueur</li>
        <li>Ne pas publier de contenu illicite, offensant, discriminatoire ou contraire aux bonnes mœurs</li>
        <li>Respecter les autres utilisateurs et adopter un comportement adapté lors des activités</li>
        <li>Ne pas créer de faux profils ni usurper l'identité d'un tiers</li>
        <li>Ne pas utiliser l'Application à des fins commerciales sans autorisation</li>
        <li>Signaler tout comportement inapproprié via le système de signalement</li>
      </Ul>

      <H2>6. Responsabilité</H2>
      <P>L'Éditeur met en relation les Utilisateurs mais n'organise pas les activités. L'Éditeur ne peut être tenu responsable :</P>
      <Ul>
        <li>Des dommages corporels ou matériels survenus lors d'une activité</li>
        <li>Du comportement des Utilisateurs avant, pendant ou après une activité</li>
        <li>De l'exactitude des informations fournies par les Utilisateurs (niveau, description)</li>
        <li>Des conditions météorologiques ou environnementales</li>
      </Ul>
      <P>
        Chaque Utilisateur participe aux activités sous sa propre responsabilité et doit évaluer ses capacités physiques et les risques liés à l'activité.
      </P>

      <H2>7. Modération et Sanctions</H2>
      <P>
        L'Éditeur se réserve le droit de suspendre ou supprimer tout compte en cas de violation des présentes CGU, notamment en cas de comportement inapproprié, harcèlement, contenu illicite ou usage abusif de la plateforme.
      </P>
      <P>
        Un Utilisateur suspendu en est informé via l'Application et peut contacter le support pour contester la décision.
      </P>

      <H2>8. Propriété intellectuelle</H2>
      <P>
        L'ensemble des éléments de l'Application (design, code, logos, textes) est protégé par le droit de la propriété intellectuelle. Toute reproduction ou utilisation non autorisée est interdite.
      </P>

      <H2>9. Suppression de compte</H2>
      <P>
        L'Utilisateur peut supprimer son compte à tout moment depuis les paramètres de l'Application. La suppression entraîne l'effacement définitif de ses données personnelles conformément à la Politique de Confidentialité.
      </P>

      <H2>10. Modification des CGU</H2>
      <P>
        L'Éditeur se réserve le droit de modifier les présentes CGU. Les Utilisateurs seront informés de toute modification substantielle. La poursuite de l'utilisation de l'Application après modification vaut acceptation des nouvelles CGU.
      </P>

      <H2>11. Droit applicable</H2>
      <P>
        Les présentes CGU sont soumises au droit français. Tout litige sera soumis aux tribunaux compétents du ressort du siège social de l'Éditeur.
      </P>

      <H2>12. Contact</H2>
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
  return <p style={{ color: 'var(--text-secondary)', fontSize: 15, marginBottom: 12 }}>{children}</p>;
}
function Ul({ children }: { children: React.ReactNode }) {
  return <ul style={{ color: 'var(--text-secondary)', fontSize: 15, marginBottom: 12, paddingLeft: 20 }}>{children}</ul>;
}
function A({ href, children }: { href: string; children: React.ReactNode }) {
  return <a href={href} style={{ color: 'var(--cta)', textDecoration: 'underline' }}>{children}</a>;
}
