import QRCode from 'qrcode';
import { CREAM, NAVY, ORANGE, ORANGE_SOFT, SKY, SectionLabel, TopoLines } from './shared';

const APK_DOWNLOAD_URL = process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ?? 'https://getjunto.app';

async function getQrDataUrl(url: string): Promise<string> {
  return QRCode.toDataURL(url, {
    width: 560,
    margin: 1,
    color: { dark: NAVY, light: '#FFFFFF' },
    errorCorrectionLevel: 'H',
  });
}

export default async function FinalCTA() {
  const qrDataUrl = await getQrDataUrl(APK_DOWNLOAD_URL);

  return (
    <section
      id="beta"
      className="junto-cta"
      style={{
        padding: '140px 40px',
        background: NAVY,
        color: '#FFF',
        position: 'relative',
        overflow: 'hidden',
      }}
    >
      <div
        style={{
          position: 'absolute',
          inset: 0,
          background: `radial-gradient(circle at 80% 20%, ${ORANGE}22 0%, transparent 50%),
                       radial-gradient(circle at 20% 80%, ${SKY}22 0%, transparent 50%)`,
        }}
      />
      <TopoLines opacity={0.06} color={CREAM} count={10} />

      <div style={{ maxWidth: 960, margin: '0 auto', position: 'relative', textAlign: 'center' }}>
        <div style={{ display: 'inline-block' }}>
          <SectionLabel color={ORANGE_SOFT}>Rejoins la bêta</SectionLabel>
        </div>
        <h2
          className="display junto-cta-title"
          style={{
            fontSize: 'clamp(48px, 8vw, 84px)',
            lineHeight: 0.96,
            margin: 0,
            fontWeight: 800,
            letterSpacing: '-0.04em',
            textWrap: 'balance',
          }}
        >
          Ta prochaine sortie
          <br />
          <span style={{ color: ORANGE_SOFT }}>t&apos;attend déjà.</span>
        </h2>

        <div
          className="junto-cta-row"
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 40,
            flexWrap: 'wrap',
            marginTop: 56,
          }}
        >
          <div className="junto-cta-download" style={{ textAlign: 'right' }}>
            <a
              className="junto-cta-button"
              href={APK_DOWNLOAD_URL}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 12,
                background: ORANGE,
                color: '#FFF',
                padding: '18px 28px',
                borderRadius: 12,
                fontSize: 16,
                fontWeight: 700,
                textDecoration: 'none',
                boxShadow: '0 10px 30px -8px rgba(242,107,46,0.5)',
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                <path d="M17.523 15.34a4 4 0 1 1-7.846-1.68L12 10l5.523 5.34zm-11.046 0L12 10l2.323 3.66a4 4 0 1 1-7.846 1.68zM12 2L8 6h8l-4-4z" />
              </svg>
              Télécharger l&apos;APK
            </a>
            <div
              className="mono"
              style={{ fontSize: 10, opacity: 0.4, letterSpacing: '0.1em', marginTop: 12 }}
            >
              ANDROID 9+ · ~24 MO
            </div>
          </div>

          <div className="junto-cta-qrwrap" style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <div
              className="mono junto-cta-scan"
              style={{
                fontSize: 11,
                opacity: 0.5,
                letterSpacing: '0.15em',
                writingMode: 'vertical-rl',
                transform: 'rotate(180deg)',
              }}
            >
              OU SCANNE →
            </div>
            <div
              className="junto-cta-qr"
              style={{
                width: 140,
                height: 140,
                borderRadius: 16,
                background: '#FFF',
                padding: 12,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              }}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={qrDataUrl}
                alt="QR code de téléchargement de l'APK Junto"
                width={116}
                height={116}
                style={{ display: 'block', width: '100%', height: '100%' }}
              />
            </div>
          </div>
        </div>

        <div style={{ fontSize: 13, opacity: 0.55, marginTop: 48 }}>
          iOS bientôt —{' '}
          <a
            href="mailto:contact@getjunto.app"
            style={{ color: ORANGE_SOFT, textDecoration: 'underline' }}
          >
            demande TestFlight
          </a>
        </div>
      </div>
    </section>
  );
}
