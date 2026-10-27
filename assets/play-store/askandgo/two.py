# Play images 3 and 6 as TWO screens each (Scott 2026-10-27): the screen and
# the page that opens from it, no floating callouts.
#   3 — Partenaires → the page of one « dispo »
#   6 — the pro page → the page of one of their guided outings
#   python3 two.py 3 out.html   /   python3 two.py 6 out.html
import os, sys
S = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(f'{S}/../../..')
src = open(f'{S}/generate.py').read()
# helpers + the Partenaires body (image 3's first screen) as generate.py draws it
src = src.replace("PH=lambda k:f'photos/demo-channel-{k}.jpg'", "PH=lambda k:f'file://{S}/photos/demo-channel-{k}.jpg'")  # absolute: the html lives elsewhere
exec(src[:src.index("out['3-partenaires']")])  # noqa: S102
partenaires_body = body
# the pro page body as pro6.py draws it (image 6's first screen)
p6 = open(f'{S}/pro6.py').read()
exec(p6[p6.index("PRO = lambda"):p6.index('extra = (')])  # noqa: S102
pro_body = body

which = sys.argv[1]

def two_screens(title, sub, body_a, body_b):
    shell = screen(title, sub, '', '')
    phones = (f'<div class="phone" style="left:-6px;top:600px;transform:scale(.72) rotate(-4deg);z-index:1"><div class="scr">{body_a}</div></div>'
              f'<div class="phone" style="left:446px;top:900px;transform:scale(.72) rotate(3deg);z-index:2;box-shadow:0 46px 90px rgba(31,26,21,.34)"><div class="scr">{body_b}</div></div>')
    return shell.replace('<div class="phone"><div class="scr"></div></div>', phones)

# ---------- 3 · the page of a dispo (app/(auth)/partners/dispo.tsx) ----------
def chip(icon_html, text, bg='#F1EFEA', fg=INK):
    return f'<span class="chip" style="background:{bg};color:{fg};font-size:13px;padding:6px 11px;gap:6px">{icon_html}{text}</span>'
def block(label, value):
    return f'<div style="flex:1;background:#F1EFEA;border-radius:14px;padding:10px 12px"><div style="font-size:11px;font-weight:800;letter-spacing:.8px;color:{SEC}">{label}</div><div style="font-size:14px;font-weight:700;margin-top:3px;line-height:1.2">{value}</div></div>'
dispo_body = f'''<div class="zoomwrap" style="background:#FFF">
<div style="position:relative;background:#1F2A22;padding:72px 22px 22px;overflow:hidden">
  <svg style="position:absolute;inset:0;width:100%;height:100%" viewBox="0 0 405 230" preserveAspectRatio="none"><path d="M -20 40 C 80 10 160 70 260 30 S 380 60 440 20" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 66 C 80 44 160 86 260 56 S 380 86 440 46" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 92 C 80 78 160 122 260 82 S 380 112 440 72" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 118 C 80 88 160 138 260 108 S 380 138 440 98" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 144 C 80 122 160 174 260 134 S 380 164 440 124" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 170 C 80 156 160 190 260 160 S 380 190 440 150" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 196 C 80 166 160 226 260 186 S 380 216 440 176" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 222 C 80 200 160 242 260 212 S 380 242 440 202" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/><path d="M -20 248 C 80 234 160 278 260 238 S 380 268 440 228" fill="none" stroke="#FFF" stroke-opacity=".08" stroke-width="1.3"/></svg>
  <div style="position:absolute;right:14px;top:36px;width:36px;height:36px;border-radius:50%;background:rgba(255,255,255,.14);display:flex;align-items:center;justify-content:center"><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#FFF" stroke-width="2.4" stroke-linecap="round"><path d="M18 6 6 18M6 6l12 12"/></svg></div>
  <div style="position:relative;display:flex;align-items:center;gap:16px">
    <div style="width:92px;height:92px;border-radius:50%;border:4px solid {GOOD};padding:3px;flex-shrink:0"><div class="av" style="width:100%;height:100%;background:#E7DCEB;color:#6B4E8B;font-size:30px">JR</div></div>
    <div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px">
      <div style="font-size:26px;font-weight:800;color:#FFF;letter-spacing:-.3px;line-height:1.05">Julie R.</div>
      <span style="align-self:flex-start;background:{GOOD};color:#FFF;border-radius:999px;padding:4px 10px;font-size:12px;font-weight:700">Bonne</span>
      <div style="font-size:14px;color:rgba(255,255,255,.8)">à 24 km de ta zone · 11 sorties</div>
    </div>
  </div>
</div>
<div style="display:flex;gap:8px;padding:16px 16px 0">{block('QUAND', '9 – 12 nov.')}{block('SE DÉPLACE', 'Covoit ou solo')}{block('SA ZONE', 'Rayon de 40 km')}</div>
<div style="padding:0 16px"><div style="font-size:13px;color:{GREEN};font-weight:700;margin-top:8px;display:flex;align-items:center;gap:4px">{li('pin',13,GREEN)}Voir la zone</div></div>
<div style="padding:18px 16px 0"><div style="font-size:12px;font-weight:800;letter-spacing:1px;color:{SEC}">SES SPORTS</div>
  <div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:8px">
    {chip(sp('ski-touring',14,'#FFF'), 'Ski de rando · <span style="font-weight:600;opacity:.9">débutante</span>', UNI['ski-touring'], '#FFF')}
    {chip(sp('climbing-sport',14,'#FFF'), 'Escalade · <span style="font-weight:600;opacity:.9">intermédiaire</span>', UNI['climbing-sport'], '#FFF')}
    {chip(sp('hiking',14,'#FFF'), 'Randonnée · <span style="font-weight:600;opacity:.9">avancée</span>', UNI['hiking'], '#FFF')}
  </div></div>
<div style="padding:18px 16px 0"><div style="font-size:12px;font-weight:800;letter-spacing:1px;color:{SEC}">VIBES</div>
  <div style="display:flex;flex-wrap:wrap;gap:8px;margin-top:8px">{chip('🧭', 'Découverte')}{chip('🤝', 'Convivialité')}{chip('📈', 'Progresser')}</div></div>
<div style="padding:18px 16px 0"><div style="font-size:12px;font-weight:800;letter-spacing:1px;color:{SEC}">EN QUELQUES MOTS</div>
  <div style="font-size:15px;line-height:1.45;margin-top:8px">Débutante en peaux de phoque, motivée et bien équipée. Je cherche des gens patients pour mes premières sorties en Clarée, et des partenaires de falaise le reste de l'année.</div></div>
<div style="padding:14px 16px 0;font-size:14px;font-weight:700;color:{GREEN}">Voir son profil ›</div>
<div style="margin-top:auto;padding:14px 16px 28px;display:flex;gap:10px;border-top:1px solid rgba(31,26,21,.08)">
  <span style="flex:1;border:1.5px solid {INK};border-radius:999px;padding:13px 0;text-align:center;font-size:15px;font-weight:800">Inviter à une sortie</span>
  <span style="flex:1;background:{GREEN};color:#FFF;border-radius:999px;padding:13px 0;text-align:center;font-size:15px;font-weight:800;box-shadow:0 6px 16px rgba(47,164,106,.35)">Contacter</span>
</div></div>'''

# ---------- 6 · the guided-outing page (components/offering-page.tsx) ----------
def fact(icon_html, label, value):
    return f'<div style="flex:1;min-width:46%;background:#F1EFEA;border-radius:14px;padding:10px 12px;display:flex;gap:9px;align-items:center">{icon_html}<div><div style="font-size:11px;font-weight:800;letter-spacing:.6px;color:{SEC}">{label}</div><div style="font-size:14px;font-weight:700;margin-top:2px">{value}</div></div></div>'
offering_body = f'''<div class="zoomwrap" style="background:#FFF">
<div style="position:relative;height:250px;background:url({PRO('p3.jpg')}) center/cover">
  <div style="position:absolute;inset:0;background:linear-gradient(to bottom, rgba(0,0,0,.10) 0%, rgba(0,0,0,.10) 40%, rgba(0,0,0,.62) 100%)"></div>
  <div style="position:absolute;left:12px;top:38px;display:flex;align-items:center;gap:6px;background:{UNI['ski-touring']};color:#FFF;border-radius:999px;padding:5px 11px;font-size:12px;font-weight:800">{sp('mountaineering',14,'#FFF')}Alpinisme</div>
  <div style="position:absolute;right:12px;top:34px;display:flex;gap:8px">{roundbtn(lx('heart',18,INK),'#FFF',34)}{roundbtn(lx('share',18,INK),'#FFF',34)}{roundbtn(lx('x',18,INK),'#FFF',34)}</div>
  <div style="position:absolute;left:16px;right:140px;bottom:14px;color:#FFF;text-shadow:0 1px 8px rgba(0,0,0,.55)">
    <div style="font-size:22px;font-weight:800;line-height:1.1;letter-spacing:-.3px">Dôme des Écrins · 2 jours</div>
    <div style="display:flex;align-items:center;gap:5px;font-size:13px;margin-top:5px"><svg width="14" height="14" viewBox="0 0 24 24" fill="#FBBF24" stroke="#FBBF24" stroke-width="1.6" stroke-linejoin="round">{L['star']}</svg><b>4,5</b><span style="opacity:.9">· 2 avis</span></div>
  </div>
  <div style="position:absolute;right:12px;bottom:14px;display:flex;flex-direction:column;align-items:flex-end;gap:6px">
    <span style="background:{GOLD};color:{INK};border-radius:999px;padding:4px 10px;font-size:10.5px;font-weight:800;letter-spacing:.8px">SORTIE ENCADRÉE</span>
    <span style="background:#FFF;color:{INK};border-radius:12px;padding:6px 11px;font-size:17px;font-weight:800;box-shadow:0 2px 8px rgba(0,0,0,.2)">520 € <span style="font-size:11px;font-weight:600;color:{SEC}">/ pers.</span></span>
  </div>
</div>
<div style="display:flex;align-items:center;gap:10px;padding:12px 16px;border-bottom:1px solid rgba(31,26,21,.08)">
  <div style="width:34px;height:34px;border-radius:50%;background:url({PRO('avatar.jpg')}) center/cover"></div>
  <div style="flex:1;font-size:13px"><span style="color:{SEC}">par</span> <b>Nicolas Pellissier</b><div style="font-size:12px;color:{SEC}">Guide de haute montagne · Briançon</div></div><span style="color:{SEC}">›</span>
</div>
<div style="display:flex;flex-wrap:wrap;gap:8px;padding:14px 16px 0">
  {fact(li('clock',18,INK), 'DURÉE', '2 jours')}{fact(lx('bar',18,INK), 'NIVEAU', 'Intermédiaire')}
  {fact(li('pin',18,INK), 'LIEU', 'Pré de Mme Carle')}{fact(li('users',18,INK), 'GROUPE', "jusqu'à 2 pers.")}
</div>
<div style="padding:16px 16px 0"><div style="font-size:16px;font-weight:800">À propos</div>
  <div style="font-size:13.5px;line-height:1.45;margin-top:6px;color:#2E2A25">Le 4 000 des Écrins en deux jours : montée au refuge par le Glacier Blanc, départ nocturne, arête sommitale au lever du soleil. Bonne condition physique et une première expérience de cramponnage.</div></div>
<div style="padding:14px 16px 0"><div style="font-size:16px;font-weight:800">Matériel</div>
  <div style="font-size:11px;font-weight:800;letter-spacing:.8px;color:{SEC};margin-top:8px">FOURNI</div>
  <div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:6px"><span class="chip ok" style="font-size:12px;padding:5px 10px">{li('check',13,'#1E6B45',3)}Corde</span><span class="chip ok" style="font-size:12px;padding:5px 10px">{li('check',13,'#1E6B45',3)}Matériel glacier</span><span class="chip ok" style="font-size:12px;padding:5px 10px">{li('check',13,'#1E6B45',3)}Crampons, piolet</span></div>
  <div style="font-size:11px;font-weight:800;letter-spacing:.8px;color:{SEC};margin-top:10px">À PRÉVOIR</div>
  <div style="display:flex;flex-wrap:wrap;gap:6px;margin-top:6px"><span class="chip" style="font-size:12px;padding:5px 10px">Chaussures cramponnables</span><span class="chip" style="font-size:12px;padding:5px 10px">Baudrier et casque</span><span class="chip" style="font-size:12px;padding:5px 10px">Sac 35 L</span></div></div>
<div style="margin-top:auto;display:flex;align-items:center;justify-content:space-between;padding:12px 16px 26px;border-top:1px solid rgba(31,26,21,.08);background:#FFF">
  <div><div style="font-size:19px;font-weight:800">520 € <span style="font-size:12px;color:{SEC};font-weight:600">/ pers.</span></div><div style="font-size:11.5px;color:{SEC}">Juin à septembre · nuit au refuge</div></div>
  <span style="background:{GREEN};color:#FFF;border-radius:999px;padding:12px 26px;font-size:15px;font-weight:800;box-shadow:0 6px 16px rgba(47,164,106,.35)">Réserver</span>
</div></div>'''

if which == '3':
    html = two_screens('Dis quand<br>tu es dispo.', 'Pour quels sports, dans quelle zone — et vois qui cherche la même chose. Un message, et vous partez ensemble.', partenaires_body, dispo_body)
else:
    html = two_screens('Guides et moniteurs,<br>sur la même carte.', "Leur page, leurs sorties encadrées avec tarifs et places, des avis vérifiés. Tu choisis, tu réserves.", pro_body, offering_body)
open(sys.argv[2], 'w').write(html)
print('ok')
