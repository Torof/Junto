import QRCode from 'qrcode';
import { CREAM, INK, INK_SOFT, ORANGE, SectionLabel, TopoLines } from './shared';

// Latest preview APK (v0.1.3 build #11, EAS) — built from main, includes
// everything to date. The QR and the download button both point here.
// Each new build produces a fresh artifact URL: re-point this (or override
// via NEXT_PUBLIC_APK_DOWNLOAD_URL in Vercel) when you cut a new APK.
const APK_DOWNLOAD_URL =
  process.env.NEXT_PUBLIC_APK_DOWNLOAD_URL ??
  'https://expo.dev/artifacts/eas/rZrLvxbXDEIxvUW4WQ2J7fFE4lWjHCyRLfd_tXoFezQ.apk';

async function getQrDataUrl(url: string): Promise<string> {
  return QRCode.toDataURL(url, {
    width: 560,
    margin: 1,
    color: { dark: INK, light: '#FFFFFF' },
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
        padding: '120px 40px',
        background: CREAM,
        color: INK,
        position: 'relative',
        overflow: 'hidden',
        borderTop: `2px solid ${INK}`,
      }}
    >
      <TopoLines opacity={0.05} color={INK} count={10} />

      <div style={{ maxWidth: 960, margin: '0 auto', position: 'relative', textAlign: 'center' }}>
        <div style={{ display: 'inline-block' }}>
          <SectionLabel>Télécharge Junto</SectionLabel>
        </div>
        <h2
          className="display junto-cta-title"
          style={{
            fontSize: 'clamp(48px, 8vw, 84px)',
            lineHeight: 0.96,
            margin: 0,
            fontWeight: 900,
            letterSpacing: '-0.04em',
            textWrap: 'balance',
          }}
        >
          Ta prochaine sortie
          <br />
          <span style={{ color: ORANGE }}>t&apos;attend déjà.</span>
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
              className="junto-hero-cta junto-cta-button"
              href={APK_DOWNLOAD_URL}
              style={{
                display: 'inline-flex',
                alignItems: 'center',
                gap: 12,
                background: ORANGE,
                color: '#FFF',
                padding: '18px 28px',
                borderRadius: 14,
                border: `2px solid ${INK}`,
                fontSize: 16,
                fontWeight: 800,
                textDecoration: 'none',
                boxShadow: `4px 4px 0 ${INK}`,
              }}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden>
                <path d="M17.523 15.34a4 4 0 1 1-7.846-1.68L12 10l5.523 5.34zm-11.046 0L12 10l2.323 3.66a4 4 0 1 1-7.846 1.68zM12 2L8 6h8l-4-4z" />
              </svg>
              Télécharger l&apos;APK
            </a>
            <div
              className="mono"
              style={{ fontSize: 10, color: INK_SOFT, letterSpacing: '0.1em', marginTop: 12 }}
            >
              ANDROID 9+ · ~205 MO
            </div>
          </div>

          <div className="junto-cta-qrwrap" style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
            <div
              className="mono junto-cta-scan"
              style={{
                fontSize: 11,
                color: INK_SOFT,
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
                border: `2px solid ${INK}`,
                boxShadow: `4px 4px 0 ${INK}`,
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

        <div style={{ fontSize: 13, color: INK_SOFT, marginTop: 48 }}>
          Android d&apos;abord — iOS arrivera avec la communauté.{' '}
          <a
            href="mailto:contact@getjunto.app"
            style={{ color: INK, fontWeight: 700, textDecoration: 'underline' }}
          >
            Écris-nous
          </a>
        </div>
      </div>
    </section>
  );
}
