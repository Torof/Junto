# Play image 6 — « Guides et moniteurs, sur la même carte » — drawn on the pro
# page as it is since 2026-10-25 (identity on the photo, gold PRO badge,
# featured outing + « Voir les N sorties », verified reviews), with the demo
# guide Nicolas Pellissier. Reuses generate.py's frame (title, phone, callouts).
#   python3 pro6.py out.html && firefox --headless --window-size=1080,1920 --screenshot 6-pros.png file://…/out.html
import os, sys
S = os.path.dirname(os.path.abspath(__file__))
src = open(f'{S}/generate.py').read()
exec(src[:src.index('out={}')])  # noqa: S102 — the generator's helpers (li, sp, screen, callout…)

PRO = lambda f: f'file://{S}/photos/pro/{f}'
GOLD = '#F2B705'
X = {  # extra lucide-ish paths this page needs
  'heart': '<path d="M19 14c1.5-1.5 3-3.2 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.8 0-3 .5-4.5 2-1.5-1.5-2.7-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.1 3 5.5l7 7Z"/>',
  'share': '<path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><path d="m16 6-4-4-4 4"/><path d="M12 2v13"/>',
  'x': '<path d="M18 6 6 18M6 6l12 12"/>',
  'mail': '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>',
  'globe': '<circle cx="12" cy="12" r="10"/><path d="M12 2a14.5 14.5 0 0 0 0 20 14.5 14.5 0 0 0 0-20"/><path d="M2 12h20"/>',
  'insta': '<rect x="2" y="2" width="20" height="20" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.5" cy="6.5" r="1" fill="currentColor"/>',
  'nav': '<path d="M3 11 22 2l-9 19-2-8-8-2z"/>',
  'clockw': '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  'bar': '<path d="M3 3v18h18"/><path d="M18 17V9"/><path d="M13 17V5"/><path d="M8 17v-3"/>',
  'badge': '<path d="M20 13c0 5-3.5 7.5-7.7 9a.6.6 0 0 1-.6 0C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.2-2.7a1.2 1.2 0 0 1 1.6 0C14.5 3.8 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
}
def lx(k, sz=24, c=INK, w=2.2):
    return f'<svg class="li" width="{sz}" height="{sz}" viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round">{X[k]}</svg>'
def roundbtn(svg, bg='#FFF', size=44):
    return f'<span style="width:{size}px;height:{size}px;border-radius:50%;background:{bg};display:inline-flex;align-items:center;justify-content:center;box-shadow:0 2px 6px rgba(31,26,21,.14)">{svg}</span>'
def star(c='#F2B705', sz=15):
    return f'<svg width="{sz}" height="{sz}" viewBox="0 0 24 24" fill="{c}" stroke="{INK}" stroke-width="1.3" stroke-linejoin="round">{L["star"]}</svg>'
stars = ''.join(star() for _ in range(5))

body = f'''<div class="zoomwrap" style="background:#FFF">
<div style="position:relative;height:284px;background:url({PRO('cover.jpg')}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(to bottom, rgba(0,0,0,.08) 0%, rgba(0,0,0,.12) 45%, rgba(0,0,0,.62) 100%)"></div>
  <div style="position:absolute;left:14px;top:40px;background:{GOLD};color:{INK};border-radius:999px;padding:4px 10px;font-size:12px;font-weight:800;letter-spacing:1px">PRO</div>
  <div style="position:absolute;right:12px;top:36px;display:flex;gap:8px">{roundbtn(lx('heart',18,INK),'#FFF',34)}{roundbtn(lx('share',18,INK),'#FFF',34)}{roundbtn(lx('x',18,INK),'#FFF',34)}</div>
  <div style="position:absolute;left:18px;right:18px;bottom:12px;display:flex;flex-direction:column;gap:5px;color:#FFF;text-shadow:0 1px 8px rgba(0,0,0,.55)">
    <div style="width:58px;height:58px;border-radius:50%;border:3px solid #FFF;background:url({PRO('avatar.jpg')}) center/cover;box-shadow:0 2px 8px rgba(0,0,0,.3);margin-bottom:3px"></div>
    <div style="font-size:22px;font-weight:800;letter-spacing:-.4px;line-height:1.1">Nicolas Pellissier</div>
    <div style="display:flex;align-items:center;gap:5px;font-size:13px;font-weight:600;opacity:.95">{li('pin',13,'#FFF',2.4)}Guide de haute montagne · Briançon</div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin-top:2px;text-shadow:none">
      <span style="display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,.22);border-radius:999px;padding:3px 8px;font-size:11px;font-weight:700">{sp('mountaineering',12,'#FFF')}Alpinisme</span>
      <span style="display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,.22);border-radius:999px;padding:3px 8px;font-size:11px;font-weight:700">{sp('ski-touring',12,'#FFF')}Ski de rando</span>
      <span style="display:inline-flex;align-items:center;gap:4px;background:rgba(255,255,255,.22);border-radius:999px;padding:3px 8px;font-size:11px;font-weight:700">{sp('canyoning',12,'#FFF')}Canyoning</span>
    </div>
    <div style="display:flex;align-items:center;gap:6px;font-size:13px;margin-top:1px"><svg width="14" height="14" viewBox="0 0 24 24" fill="#FBBF24" stroke="#FBBF24" stroke-width="1.6" stroke-linejoin="round">{L['star']}</svg><b>4,9</b><span style="opacity:.9">· 5 avis</span></div>
  </div>
</div>
<div style="padding:0 16px">
  <div style="display:flex;gap:8px;margin-top:12px;overflow:hidden">{''.join(f'<span style="display:inline-flex;align-items:center;gap:6px;background:#F1EFEA;border-radius:999px;padding:8px 13px;font-size:13px;font-weight:700;white-space:nowrap">{svg}{lab}</span>' for svg,lab in [(li('phone',16),'Appeler'),(lx('mail',16),'E-mail'),(lx('globe',16),'Site'),(lx('nav',16),'Itinéraire'),(lx('insta',16),'Instagram')])}</div>

  <div style="display:flex;align-items:center;gap:8px;margin-top:18px;font-size:12px;font-weight:800;letter-spacing:1px;color:{SEC}">SORTIES ENCADRÉES <span style="font-weight:600;letter-spacing:0;text-transform:none">· mise en avant</span></div>
  <div style="margin-top:8px;border-radius:18px;background:#F1EFEA;padding:12px 12px 12px;display:flex;flex-direction:column;gap:8px">
    <div style="display:flex;align-items:center;gap:8px"><span class="chip" style="font-size:12px;padding:3px 8px;gap:5px;background:{UNI['ski-touring']};color:#FFF">{sp('mountaineering',14,'#FFF')}Alpinisme</span><span style="font-size:12px;color:{SEC};font-weight:600">2 jours</span></div>
    <div style="font-size:17px;font-weight:800;line-height:1.15">Dôme des Écrins · 2 jours</div>
    <div style="display:flex;gap:12px;font-size:12.5px;color:{SEC};font-weight:600"><span style="display:inline-flex;align-items:center;gap:4px">{lx('bar',13,SEC)}Intermédiaire</span><span style="display:inline-flex;align-items:center;gap:4px">{li('users',13,SEC)}jusqu'à 2 pers.</span></div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-top:2px"><span style="font-size:18px;font-weight:800">520 € <span style="font-size:12px;color:{SEC};font-weight:600">/ pers.</span></span><span style="background:{BRAND};color:#FFF;border-radius:999px;padding:8px 16px;font-size:13px;font-weight:800">Réserver</span></div>
  </div>
  <div style="margin-top:8px;border-radius:14px;border:1.5px solid rgba(31,26,21,.12);padding:11px 14px;display:flex;align-items:center;justify-content:space-between;font-size:14px;font-weight:700">Voir les 4 sorties<span>›</span></div>

  <div style="display:flex;align-items:center;justify-content:space-between;margin-top:18px"><span style="font-size:17px;font-weight:800">Avis</span><span style="font-size:12px;color:{SEC};font-weight:600">Voir les 5 avis ›</span></div>
  <div style="display:flex;align-items:center;gap:10px;margin-top:6px"><span style="font-size:30px;font-weight:800;line-height:1">4,9</span><span style="display:flex;flex-direction:column;gap:2px"><span style="display:inline-flex;gap:1px">{stars}</span><span style="font-size:11px;color:{SEC};display:inline-flex;align-items:center;gap:4px">{lx('badge',11,SEC)}Avis vérifiés · 5 avis</span></span></div>
  <div style="margin-top:8px;display:flex;gap:10px;align-items:flex-start"><span class="av" style="width:30px;height:30px;font-size:12px">LM</span><div style="flex:1;font-size:12.5px;line-height:1.3"><b>Léa M.</b> <span style="color:{SEC}">· Dôme des Écrins · sept.</span><div style="margin-top:2px">Sérieux, calme, et une vraie attention à la cordée. Sommet au lever du soleil, je ne l'oublierai pas.</div></div></div>

  <div style="display:flex;align-items:center;justify-content:space-between;margin-top:14px"><span style="font-size:17px;font-weight:800">Photos <span style="font-size:12px;color:{SEC};font-weight:600">· 6</span></span><span style="font-size:12px;color:{SEC};font-weight:600">Voir tout ›</span></div>
  <div style="display:flex;gap:6px;margin-top:8px">{''.join(f'<div style="flex:1;aspect-ratio:1;border-radius:10px;background:url({PRO(p)}) center/cover"></div>' for p in ['p1.jpg','p2.jpg','p3.jpg','p4.jpg'])}</div>
</div></div>'''

extra = (callout(26, 760, lx('badge', 50, INK), 'Métier', 'guide, moniteur, école — sur la photo', 'left', 212)
       + callout(838, 1180, li('cal', 50, INK), 'Réserver', 'ses sorties encadrées, prix et places', 'right', 212)
       + callout(26, 1420, li('star', 50, INK), 'Avis vérifiés', 'par ceux qui ont réservé et fait la sortie', 'left', 212))
html = screen('Guides et moniteurs,<br>sur la même carte.', "Leur page, leurs sorties encadrées avec tarifs et places, des avis vérifiés. Tu choisis, tu réserves.", body, extra)
open(sys.argv[1], 'w').write(html)
print('ok')
