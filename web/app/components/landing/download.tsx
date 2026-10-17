import QRCode from 'qrcode';
import IosWaitlistForm from './ios-waitlist-form';

async function qrFor(url: string): Promise<string> {
  return QRCode.toDataURL(url, { margin: 1, width: 360, color: { dark: '#0F1A14', light: '#FFFFFF' } });
}

// « Télécharger » — the closing band, map echo behind. Play link when the
// listing is public, the direct Android build meanwhile; iOS = waitlist.
export default async function Download({ playUrl, isPlayStore }: { playUrl: string; isPlayStore: boolean }) {
  const qr = await qrFor(playUrl);
  return (
    <section id="telecharger" className="l-dl">
      <img className="l-dl-img" src="/hero-map-ecrins.jpg" alt="" />
      <div className="l-dl-wrap">
        <div style={{ flex: '1 1 420px', minWidth: 0, display: 'flex', flexDirection: 'column', gap: 18 }}>
          <h2 className="l-dl-h2">Fini le sport solo.<br /><em>Va sur Junto.</em></h2>
          <p style={{ margin: 0, fontSize: 16, lineHeight: 1.6, color: 'rgba(255,255,255,0.8)', maxWidth: '48ch' }}>Gratuit, sans publicité, sans revente de données. Pensé dans les Hautes-Alpes, pour partout.</p>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 12, alignItems: 'center' }}>
            <a href={playUrl} className="l-btn-play">{isPlayStore ? 'Télécharger sur Google Play' : 'Télécharger l’app Android'}</a>
            <span style={{ fontSize: 13, color: 'rgba(255,255,255,0.7)' }}>Android 9 et plus</span>
          </div>
          <IosWaitlistForm />
        </div>
        <div className="l-qr">
          <img src={qr} alt="QR code vers le téléchargement Android" />
          <div style={{ fontSize: 12, color: 'rgba(255,255,255,0.7)' }}>Scanne depuis ton téléphone</div>
        </div>
      </div>
      <footer className="l-footer">
        <div className="l-footer-wrap">
          <span>© Junto 2026 · Fait dans les Hautes-Alpes</span>
          <div style={{ display: 'flex', gap: 18, flexWrap: 'wrap' }}>
            <a href="/legal/privacy">Confidentialité</a>
            <a href="/legal/terms">Conditions</a>
            <a href="/legal/mentions">Mentions légales</a>
            <a href="/legal/account-deletion">Supprimer mon compte</a>
            <a href="mailto:contact@getjunto.app">contact@getjunto.app</a>
          </div>
        </div>
      </footer>
    </section>
  );
}
