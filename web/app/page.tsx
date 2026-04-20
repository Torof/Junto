import Image from 'next/image';
import QRCode from 'qrcode';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? 'https://junto.app';
const CONTACT_EMAIL = 'scottpanam@protonmail.com';

async function getQrCode(url: string): Promise<string> {
  return QRCode.toDataURL(url, {
    width: 400,
    margin: 2,
    color: { dark: '#0D1B2A', light: '#F5F5F0' },
    errorCorrectionLevel: 'H',
  });
}

export default async function Home() {
  const qrDataUrl = await getQrCode(APK_DOWNLOAD_URL);

  return (
    <main style={{ minHeight: '100vh', padding: '24px 16px', maxWidth: 960, margin: '0 auto' }}>
      {/* Hero */}
      <section style={{ textAlign: 'center', paddingTop: 40, paddingBottom: 48 }}>
        <Image
          src="/junto-logo.png"
          alt="Junto"
          width={96}
          height={96}
          style={{ borderRadius: 20, marginBottom: 24 }}
          priority
        />
        <h1 style={{ fontSize: 'clamp(32px, 7vw, 52px)', fontWeight: 800, marginBottom: 12, letterSpacing: '-0.02em' }}>
          Junto
        </h1>
        <p style={{ fontSize: 'clamp(17px, 3vw, 22px)', color: 'var(--text-secondary)', maxWidth: 520, margin: '0 auto 40px', lineHeight: 1.5 }}>
          Rejoins des sorties outdoor près de chez toi.
          <br />
          Escalade, rando, parapente, canyon, ski de rando…
        </p>

        {/* QR + Button side by side on desktop, stacked on mobile */}
        <div style={{
          display: 'flex',
          flexWrap: 'wrap',
          gap: 32,
          justifyContent: 'center',
          alignItems: 'center',
        }}>
          <div style={{
            background: 'var(--text)',
            padding: 16,
            borderRadius: 20,
            display: 'inline-block',
          }}>
            <img src={qrDataUrl} alt="Scanner pour télécharger" width={220} height={220} style={{ display: 'block' }} />
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
            <p style={{ color: 'var(--text-secondary)', fontSize: 14, maxWidth: 200, textAlign: 'center' }}>
              Scanne ce QR code avec ton téléphone
            </p>
            <p style={{ color: 'var(--text-secondary)', fontSize: 14 }}>— ou —</p>
            <a
              href={APK_DOWNLOAD_URL}
              style={{
                display: 'inline-block',
                background: 'var(--cta)',
                color: 'var(--text)',
                padding: '14px 28px',
                borderRadius: 999,
                fontSize: 17,
                fontWeight: 700,
              }}
            >
              Télécharger (Android)
            </a>
          </div>
        </div>
      </section>

      {/* Screenshots — horizontal scroll on mobile, centered row on desktop */}
      <section style={{ padding: '32px 0 48px' }}>
        <div style={{
          display: 'flex',
          gap: 16,
          overflowX: 'auto',
          paddingBottom: 8,
          scrollSnapType: 'x mandatory',
          WebkitOverflowScrolling: 'touch',
          justifyContent: 'flex-start',
        }}>
          {[1, 2, 3, 4, 5, 6, 7].map((n) => (
            <div key={n} style={{
              flex: '0 0 auto',
              width: 240,
              background: 'var(--surface-2)',
              borderRadius: 24,
              padding: 8,
              scrollSnapAlign: 'center',
              overflow: 'hidden',
            }}>
              <img
                src={`/screenshots/screen-${n}.jpeg`}
                alt={`Junto screenshot ${n}`}
                style={{ width: '100%', height: 'auto', display: 'block', borderRadius: 16 }}
              />
            </div>
          ))}
        </div>
      </section>

      {/* Features */}
      <section style={{ padding: '32px 0' }}>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
          gap: 16,
        }}>
          <Feature icon="📍" title="Géolocalisé" body="Les activités autour de toi, en un coup d'œil." />
          <Feature icon="🚗" title="Transport" body="Organise le covoiturage avec les autres participants." />
          <Feature icon="🤝" title="Confiance" body="Score de fiabilité, présence vérifiée, badges." />
        </div>
      </section>

      {/* How it works */}
      <section style={{ padding: '48px 0' }}>
        <h2 style={{ fontSize: 28, fontWeight: 800, marginBottom: 32, textAlign: 'center' }}>Comment ça marche</h2>
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))',
          gap: 24,
        }}>
          <Step number="1" title="Trouve une sortie" body="Parcours la carte des activités près de chez toi." />
          <Step number="2" title="Rejoins" body="Demande à participer ou rejoins directement." />
          <Step number="3" title="Coordonne" body="Chat, transport, matériel — tout au même endroit." />
        </div>
      </section>

      {/* Footer */}
      <footer style={{ padding: '48px 0 32px', textAlign: 'center', color: 'var(--text-secondary)', fontSize: 14 }}>
        <p style={{ marginBottom: 12 }}>
          Une idée, un bug, un retour ?{' '}
          <a href={`mailto:${CONTACT_EMAIL}`} style={{ color: 'var(--cta)', textDecoration: 'underline' }}>
            {CONTACT_EMAIL}
          </a>
        </p>
        <p style={{ fontSize: 12, opacity: 0.6 }}>© Junto 2026</p>
      </footer>
    </main>
  );
}

function Feature({ icon, title, body }: { icon: string; title: string; body: string }) {
  return (
    <div style={{ background: 'var(--surface-2)', borderRadius: 16, padding: 24 }}>
      <div style={{ fontSize: 32, marginBottom: 12 }}>{icon}</div>
      <div style={{ fontSize: 17, fontWeight: 700, marginBottom: 6 }}>{title}</div>
      <div style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.5 }}>{body}</div>
    </div>
  );
}

function Step({ number, title, body }: { number: string; title: string; body: string }) {
  return (
    <div style={{ textAlign: 'center' }}>
      <div style={{
        width: 48, height: 48, borderRadius: '50%',
        background: 'var(--cta)', color: 'var(--text)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        fontSize: 20, fontWeight: 800,
        marginBottom: 16,
      }}>
        {number}
      </div>
      <div style={{ fontSize: 17, fontWeight: 700, marginBottom: 6 }}>{title}</div>
      <div style={{ fontSize: 14, color: 'var(--text-secondary)', lineHeight: 1.5, maxWidth: 240, margin: '0 auto' }}>{body}</div>
    </div>
  );
}

