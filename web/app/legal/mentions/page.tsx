import type { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Mentions légales — Junto',
  description: 'Mentions légales du site getjunto.app et de l’application Junto.',
};

const CONTACT_EMAIL = 'contact@getjunto.app';

// Éditeur non professionnel (personne physique) — LCEN art. 6-III-2 : identité
// détenue par l'hébergeur, non publiée. À repasser en mentions "pro" complètes
// si Junto devient commercial (offres payantes, monétisation des pros).
export default function MentionsPage() {
  return (
    <article style={{ color: 'var(--ink)', lineHeight: 1.6 }}>
      <h1 style={{ fontSize: 32, fontWeight: 800, marginBottom: 8 }}>Mentions légales</h1>
      <p style={{ color: 'var(--muted)', fontSize: 14, marginBottom: 32 }}>
        Site getjunto.app et application mobile Junto
      </p>

      <H2>Éditeur</H2>
      <P>
        Le site getjunto.app et l&apos;application Junto sont édités à titre personnel et non
        professionnel par une personne physique.
      </P>
      <P>
        Conformément à l&apos;article 6-III-2 de la loi n° 2004-575 du 21 juin 2004 (LCEN),
        l&apos;éditeur — personne physique éditant à titre non professionnel — a communiqué ses
        coordonnées d&apos;identification à l&apos;hébergeur et n&apos;est pas tenu de les rendre
        publiques.
      </P>
      <Ul>
        <li>Contact : <A href={`mailto:${CONTACT_EMAIL}`}>{CONTACT_EMAIL}</A></li>
      </Ul>

      <H2>Hébergement</H2>
      <Ul>
        <li>
          <B>Site web :</B> Vercel Inc., 440 N Barranca Ave #4133, Covina, CA 91723, États-Unis —{' '}
          <A href="https://vercel.com">vercel.com</A>
        </li>
        <li>
          <B>Données applicatives :</B> Supabase Inc. (infrastructure hébergée dans l&apos;Union
          européenne) — <A href="https://supabase.com">supabase.com</A>
        </li>
      </Ul>

      <H2>Propriété intellectuelle</H2>
      <P>
        L&apos;ensemble des éléments du site et de l&apos;application (marque, logo, textes,
        interfaces) est la propriété de l&apos;éditeur. Toute reproduction sans autorisation
        préalable est interdite.
      </P>

      <H2>Données personnelles</H2>
      <P>
        Le traitement des données personnelles est décrit dans la{' '}
        <A href="/legal/privacy">politique de confidentialité</A>. La suppression de compte est
        possible <A href="/legal/account-deletion">depuis l&apos;application ou sur demande</A>.
      </P>

      <H2>Cookies</H2>
      <P>
        Ce site n&apos;utilise pas de cookies de suivi ni d&apos;outil d&apos;analyse d&apos;audience.
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
