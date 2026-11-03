# Play image 7 — for the pros themselves (Scott 2026-11-03): the Espace pro
# (app/(auth)/pro/espace.tsx: today, a request to accept, the four tiles) next
# to a booking's sheet in the agenda (app/(auth)/pro/agenda.tsx: client,
# message, participant forms). No photo — initials only. Same frame as image 4
# (two straight phones under the keyword row).
#   python3 pro7.py out.html
import os, sys
S = os.path.dirname(os.path.abspath(__file__))
src = open(f'{S}/generate.py').read()
exec(src[:src.index('out={}')])  # noqa: S102 — the generator's helpers (li, sp, screen…)

CTA = GREEN; MUTED = '#A0968A'; WARN = '#F39C12'; LINE = 'rgba(31,26,21,.16)'; ALT = '#F1EFEA'
MOUNTAIN = '#4A7C59'
X = {
  'eye': L['eye'],
  'mtn': L['mountain'],
  'msgs': '<path d="M14 9a2 2 0 0 1-2 2H6l-4 4V4a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2z"/><path d="M18 9h2a2 2 0 0 1 2 2v11l-4-4h-6a2 2 0 0 1-2-2v-1"/>',
  'calday': '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01"/>',
}
def lx(k, sz=24, c=INK, w=2.2):
    return f'<svg class="li" width="{sz}" height="{sz}" viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round">{X[k]}</svg>'
def av(ini, sz, bg='#DCE5D3', fg='#3F7A56'):
    return f'<span class="av" style="width:{sz}px;height:{sz}px;font-size:{round(sz*.38)}px;background:{bg};color:{fg}">{ini}</span>'
def sport_tile(sz, solid):
    return (f'<span style="width:{sz}px;height:{sz}px;border-radius:{sz*.28}px;display:inline-flex;align-items:center;justify-content:center;flex-shrink:0;'
            f'background:{MOUNTAIN if solid else MOUNTAIN + "1F"}">{sp("via-ferrata" if not solid else "climbing-sport", sz*.5, "#FFF" if solid else MOUNTAIN)}</span>')
EYEBROW = f'font-size:12px;font-weight:800;letter-spacing:.8px;text-transform:uppercase;color:{MUTED}'
CARD = f'background:#FFF;border-radius:16px;border:1px solid {LINE};box-shadow:0 2px 8px rgba(31,26,21,.10)'

def tile(icon, title, sub, badge=None):
    b = f'<span style="min-width:20px;height:20px;border-radius:10px;background:#E74C3C;color:#FFF;font-size:11px;font-weight:800;display:inline-flex;align-items:center;justify-content:center;padding:0 6px">{badge}</span>' if badge else ''
    return (f'<div style="width:calc(50% - 5px);{CARD};padding:13px">'
            f'<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px"><span style="width:32px;height:32px;border-radius:10px;background:{CTA}18;display:inline-flex;align-items:center;justify-content:center">{icon}</span>{b}</div>'
            f'<div style="font-size:15px;font-weight:800;line-height:1.2">{title}</div><div style="font-size:13px;color:{SEC};margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">{sub}</div></div>')

espace_body = f'''<div class="zoomwrap" style="background:#FFF">
<div style="display:flex;align-items:center;gap:14px;padding:42px 16px 12px;font-size:20px;font-weight:800"><span style="font-size:24px;font-weight:600">‹</span>Espace pro</div>
<div style="padding:0 16px;display:flex;flex-direction:column">
  <div style="display:flex;align-items:center;gap:12px;margin-bottom:12px">{av('LA', 48)}
    <div style="flex:1;min-width:0"><div style="font-size:17px;font-weight:800">Lise Arnaud · Escalade Écrins</div><div style="font-size:13px;font-weight:600;color:{CTA};margin-top:1px">Page publique active</div></div></div>
  <div style="background:{BRAND};border-radius:999px;padding:14px 0;display:flex;align-items:center;justify-content:center;gap:8px;color:#FFF;font-size:16px;font-weight:700;box-shadow:0 6px 16px rgba(30,127,216,.35)">{li('plus',18,'#FFF',2.6)}Nouvelle sortie</div>

  <div style="{EYEBROW};margin:18px 0 8px">Aujourd’hui · sam. 14 nov.</div>
  <div style="{CARD};padding:14px;display:flex;align-items:center;gap:10px">
    <span style="min-width:52px;text-align:center;border-radius:9px;padding:5px 7px;background:{MOUNTAIN}1F;color:{MOUNTAIN};font-size:11px;font-weight:800">MATIN</span>
    {av('CM', 32, '#E7DCEB', '#6B4E8B')}
    <div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:700">Camille M. · 3 pers.</div><div style="font-size:13px;color:{SEC};margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">Initiation falaise · via l’app</div></div>
    <span style="width:32px;height:32px;border-radius:16px;background:{ALT};border:1px solid {LINE};display:inline-flex;align-items:center;justify-content:center">{li('msg',15,SEC)}</span>
  </div>

  <div style="{EYEBROW};margin:18px 0 8px">Demandes · 2 en attente</div>
  <div style="{CARD};border:1.5px dashed {MOUNTAIN}88;padding:12px;display:flex;flex-direction:column;gap:10px">
    <div style="display:flex;align-items:center;gap:10px">{sport_tile(44, False)}
      <div style="flex:1;min-width:0"><div style="font-size:15px;font-weight:800">Via ferrata des Vigneaux</div><div style="font-size:13px;font-weight:600;color:{MOUNTAIN};margin-top:2px">Dim. 15 nov. · Après-midi</div></div>
      <span style="background:{WARN}22;color:{WARN};border-radius:999px;padding:4px 9px;font-size:11px;font-weight:800">En attente</span></div>
    <div style="display:flex;align-items:center;gap:8px">{av('HB', 26)}<b style="font-size:14px">Hugo B.</b><span style="font-size:13px;color:{SEC}">· 2 personnes</span></div>
    <div style="background:{ALT};border-radius:8px;padding:10px 12px;font-size:13px;line-height:1.4">« On est deux débutants, c’est faisable pour nous ? »</div>
    <div style="display:flex;align-items:center;gap:8px">
      <span style="display:inline-flex;align-items:center;gap:6px;border:1px solid {LINE};border-radius:999px;padding:10px 14px;font-size:14px;font-weight:700">{li('msg',16,INK)}Écrire</span>
      <span style="padding:10px;font-size:14px;font-weight:600;color:{SEC}">Refuser</span>
      <span style="flex:1;text-align:center;background:{CTA};color:#FFF;border-radius:999px;padding:11px 0;font-size:14px;font-weight:700">Accepter</span></div>
  </div>
  <div style="text-align:center;padding:8px 0 0;font-size:14px;font-weight:700;color:{CTA}">Voir les 2 demandes ›</div>

  <div style="{EYEBROW};margin:14px 0 8px">Gérer</div>
  <div style="display:flex;flex-wrap:wrap;gap:10px">
    {tile(lx('calday',18,CTA), 'Agenda', '7 j : 4 résas · 11 pers.', 2)}
    {tile(lx('mtn',18,CTA), 'Mon catalogue de sorties', '4 au catalogue')}
    {tile(lx('msgs',18,CTA), 'Messages', '1 non lu', 1)}
    <div style="width:calc(50% - 5px);{CARD};padding:13px"><div style="margin-bottom:8px"><span style="width:32px;height:32px;border-radius:10px;background:{CTA}18;display:inline-flex;align-items:center;justify-content:center">{lx('eye',18,CTA)}</span></div>
      <div style="font-size:15px;font-weight:800;line-height:1.2">Ma page professionnelle</div>
      <div style="display:flex;gap:6px;margin-top:8px">{''.join(f'<span style="flex:1;text-align:center;border-radius:999px;background:{CTA}18;color:{CTA};padding:7px 0;font-size:13px;font-weight:700">{w}</span>' for w in ['Voir','Modifier'])}</div></div>
  </div>
</div></div>'''

def form_row(i, text):
    sep = f'border-top:1px solid rgba(31,26,21,.08);' if i > 1 else ''
    return f'<div style="display:flex;gap:10px;padding:9px 12px;{sep}"><b style="width:14px;font-size:13px;color:{MUTED}">{i}</b><span style="flex:1;font-size:13px">{text}</span></div>'

# The agenda behind the sheet, dimmed (components/availability-calendar.tsx):
# the month card, half-day cells — booked solid, request dashed, open tinted.
def half(state):
    st = {'booked': f'background:{MOUNTAIN}', 'open': f'background:{CTA}29', 'req': f'border:1.5px dashed {MOUNTAIN}', 'none': ''}[state]
    return f'<div style="flex:1;border-radius:6px;{st}"></div>'
def cell(n, am='none', pm='none', today=False):
    if n is None:
        return '<div style="width:14.28%;height:108px"></div>'
    return (f'<div style="width:14.28%;padding:.5px"><div style="height:107px;border-radius:8px;background:{ALT};padding:2px;display:flex;flex-direction:column;gap:2px;border:1px solid {CTA if today else LINE}">'
            f'<div style="height:14px;line-height:14px;text-align:center;font-size:10px;font-weight:700;opacity:.8">{n}</div>{half(am)}{half(pm)}</div></div>')
weeks = [
  [cell(9,'open','open'), cell(10,'none','none'), cell(11,'booked','open'), cell(12,'open','open'), cell(13,'open','booked'), cell(14,'booked','open',True), cell(15,'open','req')],
  [cell(16), cell(17,'open','open'), cell(18,'open','open'), cell(19), cell(20,'open','open'), cell(21,'booked','booked'), cell(22,'open','open')],
]
agenda_peek = f'''<div style="padding:42px 16px 0"><div style="display:flex;align-items:center;gap:14px;font-size:20px;font-weight:800"><span style="font-size:24px;font-weight:600">‹</span>Agenda</div>
  <div style="margin-top:14px;{CARD};border-radius:18px;padding:14px 10px">
    <div style="display:flex;align-items:center;justify-content:space-between;padding:0 4px 8px"><span style="font-size:18px">‹</span><b style="font-size:16px">Novembre 2026</b><span style="font-size:18px">›</span></div>
    <div style="display:flex;margin-bottom:4px">{''.join(f'<span style="flex:1;text-align:center;font-size:11px;font-weight:700;color:{MUTED}">{d}</span>' for d in ['L','M','M','J','V','S','D'])}</div>
    {''.join(f'<div style="display:flex">{"".join(w)}</div>' for w in weeks)}
  </div></div>'''

sheet_body = f'''<div class="zoomwrap" style="background:#FFF;position:relative">
{agenda_peek}
<div style="position:absolute;inset:0;background:rgba(15,12,9,.45)"></div>
<div style="position:absolute;left:0;right:0;bottom:0;background:#FFF;border-radius:24px 24px 0 0;padding:10px 16px 30px;display:flex;flex-direction:column;gap:16px">
  <div style="width:38px;height:4px;border-radius:2px;background:{MUTED};opacity:.5;align-self:center;margin-bottom:-6px"></div>
  <div style="display:flex;align-items:center;gap:12px">{sport_tile(48, True)}
    <div style="flex:1;min-width:0"><div style="font-size:18px;font-weight:800;line-height:1.2">Initiation falaise à Ailefroide</div><div style="font-size:14px;font-weight:600;color:{MOUNTAIN};margin-top:2px">Sam. 14 nov. · Matin</div></div>
    <span style="background:{CTA}1F;color:{CTA};border-radius:999px;padding:4px 10px;font-size:12px;font-weight:800">Confirmée</span></div>
  <div style="display:flex;align-items:center;gap:12px;background:{ALT};border-radius:14px;padding:10px 12px">{av('CM', 40, '#E7DCEB', '#6B4E8B')}
    <div style="flex:1;min-width:0"><div style="font-size:16px;font-weight:800">Camille M.</div><div style="font-size:13px;color:{SEC};margin-top:1px">Réservée dans l’app · 3 personnes</div></div>
    <span style="font-size:13px;font-weight:700;color:{CTA}">Profil ›</span></div>
  <div style="display:flex;flex-direction:column;gap:6px"><div style="{EYEBROW}">Message du client</div>
    <div style="font-size:14px;line-height:1.43">« On sera trois, avec mes deux ados de 12 et 14 ans. Première fois en falaise pour eux ! »</div></div>
  <div style="display:flex;flex-direction:column;gap:6px"><div style="{EYEBROW}">Fiches participants · 3 sur 3</div>
    <div style="border:1px solid {LINE};border-radius:14px;overflow:hidden">
      {form_row(1, 'P. 39 · 168 cm · 61 kg')}{form_row(2, 'P. 37 · 158 cm · 47 kg · 14 ans')}{form_row(3, 'P. 35 · 149 cm · 39 kg · 12 ans')}</div></div>
  <div style="background:{CTA};border-radius:999px;padding:13px 0;display:flex;align-items:center;justify-content:center;gap:6px;color:#FFF;font-size:14px;font-weight:700">{li('msg',16,'#FFF')}Écrire à Camille M.</div>
  <div style="align-self:center;font-size:14px;font-weight:700;color:#E74C3C;margin-top:-6px">Annuler la réservation</div>
</div></div>'''

def keywords(items):
    cells = ''.join(f'<div style="display:flex;align-items:center;gap:12px"><span style="width:58px;height:58px;border-radius:50%;background:#FFF;display:inline-flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(31,26,21,.12)">{ic}</span><span style="font-size:32px;font-weight:800;color:{DEEP};letter-spacing:-.5px;white-space:nowrap">{w}</span></div>' for ic, w in items)
    return f'<div style="position:absolute;left:0;right:0;top:478px;display:flex;justify-content:center;gap:26px;padding:0 20px">{cells}</div>'

shell = screen("Tu es guide ou moniteur ?<br>Tes sorties, tes réservations<br>et tes clients, au même endroit.", '', '', '')
phones = (f'<div class="phone" style="left:-27px;top:615px;transform:scale(.74);box-shadow:0 30px 60px rgba(31,26,21,.24)"><div class="scr">{espace_body}</div></div>'
          f'<div class="phone" style="left:467px;top:615px;transform:scale(.74);box-shadow:0 30px 60px rgba(31,26,21,.24)"><div class="scr">{sheet_body}</div></div>')
html = shell.replace('<div class="phone"><div class="scr"></div></div>', keywords(
    [(lx('eye', 32, INK), 'Ta vitrine'), (li('cal', 32, INK), 'Ton agenda'), (li('users', 32, INK), 'Tes clients')]) + phones)
html = html.replace('font-size:82px;line-height:1.04', 'font-size:62px;line-height:1.1').replace('margin:150px 70px 0;text-align:center', 'margin:140px 60px 0;text-align:center')
open(sys.argv[1], 'w').write(html)
print('ok')
