import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Suppression de compte — Junto',
  description: 'Comment supprimer votre compte Junto et demander la suppression de vos données.',
};

const CONTACT_EMAIL = 'contact@getjunto.app';
const MAILTO = `mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent('Demande de suppression de compte Junto')}&body=${encodeURIComponent(
  'Bonjour,\n\nJe souhaite supprimer mon compte Junto et l’ensemble de mes données personnelles.\n\nAdresse email du compte : [votre email]\n\nMerci.',
)}`;

// Web-accessible account-deletion request page — required by Google
// Play's account deletion policy (a deletion path must exist outside
// the app) and linked from the Play Store listing.
export default function AccountDeletionPage() {
  return (
    <article style={{ color: 'var(--ink)', lineHeight: 1.6 }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, marginBottom: 8 }}>Suppression de compte</h1>
      <p style={{ color: 'var(--muted)', fontSize: 14, marginBottom: 32 }}>
        Application Junto (app.getjunto)
      </p>

      <H2>Supprimer votre compte depuis l&apos;application (immédiat)</H2>
      <P>
        Le moyen le plus rapide de supprimer votre compte et l&apos;ensemble de vos données :
      </P>
      <Ol>
        <li>Ouvrez Junto et connectez-vous</li>
        <li>Allez dans <B>Profil → Paramètres</B></li>
        <li>Tout en bas, choisissez <B>Supprimer mon compte</B> et confirmez</li>
      </Ol>
      <P>
        La suppression est <B>immédiate et irréversible</B> : profil, photos, activités créées,
        participations, messages privés, notifications et tokens de notification sont supprimés.
        Les messages publiés sur les murs d&apos;activités sont anonymisés. Les signalements de
        modération sont conservés (obligation de modération).
      </P>

      <H2>Demander la suppression sans accès à l&apos;application</H2>
      <P>
        Si vous ne pouvez plus accéder à l&apos;application (téléphone perdu, mot de passe oublié,
        application désinstallée), envoyez votre demande par email — aucune connexion requise :
      </P>
      <P>
        <A href={MAILTO}>{CONTACT_EMAIL}</A> — objet : « Demande de suppression de compte Junto »,
        en précisant l&apos;adresse email associée au compte.
      </P>
      <P>
        Votre demande est traitée sous <B>30 jours maximum</B> (en pratique, généralement sous
        quelques jours). Une confirmation vous est envoyée à l&apos;adresse du compte avant
        suppression, afin de vérifier que la demande provient bien du titulaire.
      </P>

      <H2>Ce qui est supprimé, ce qui est conservé</H2>
      <Ul>
        <li><B>Supprimé :</B> compte, profil, photos (avatar et galeries pro), activités créées, participations, messages privés, avis publiés, notifications, tokens de notification</li>
        <li><B>Anonymisé :</B> messages publiés sur les murs d&apos;activités (le contenu reste, sans lien avec vous)</li>
        <li><B>Conservé :</B> signalements de modération (base légale : intérêt légitime de modération)</li>
      </Ul>
      <P>
        Détails complets dans notre <A href="/legal/privacy">politique de confidentialité</A>.
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
function Ol({ children }: { children: React.ReactNode }) {
  return <ol style={{ color: 'var(--muted)', fontSize: 15, marginBottom: 12, paddingLeft: 20 }}>{children}</ol>;
}
function B({ children }: { children: React.ReactNode }) {
  return <strong style={{ color: 'var(--ink)' }}>{children}</strong>;
}
function A({ href, children }: { href: string; children: React.ReactNode }) {
  return <a href={href} style={{ color: 'var(--cta)', textDecoration: 'underline' }}>{children}</a>;
}
