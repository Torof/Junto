import Link from 'next/link';

export default function LegalLayout({ children }: { children: React.ReactNode }) {
  return (
    <main style={{ maxWidth: 760, margin: '0 auto', padding: '48px 20px' }}>
      <Link href="/" style={{ color: 'var(--cta)', fontSize: 14, textDecoration: 'underline' }}>
        ← Retour
      </Link>
      <div style={{ marginTop: 32 }}>{children}</div>
    </main>
  );
}
