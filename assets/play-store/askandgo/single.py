# Play images 2 · 4 · 5 — one screen, straight and big (85 %), and between the
# subtitle and the phone a single row of three keywords with their icon
# (Scott 2026-10-27, option A: « lire peu, comprendre d'un coup d'œil »).
#   python3 single.py 2 out.html   (4, 5 likewise)
import os, sys
S = os.path.dirname(os.path.abspath(__file__))
src = open(f'{S}/generate.py').read()
src = src.replace("PH=lambda k:f'photos/demo-channel-{k}.jpg'", "PH=lambda k:f'file://{S}/photos/demo-channel-{k}.jpg'")
which = sys.argv[1]
cut = {'2': "out['2-sortie']", '4': "out['4-canaux']", '5': "out['5-confiance']"}[which]
exec(src[:src.index(cut)])  # noqa: S102 — helpers + `body` of that image as generate.py draws it
screen_body = body

def keywords(items):
    # items: [(icon_html, word)] — one centred row, title typography, no boxes
    cells = ''.join(f'<div style="display:flex;align-items:center;gap:12px"><span style="width:58px;height:58px;border-radius:50%;background:#FFF;display:inline-flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(31,26,21,.12)">{ic}</span><span style="font-size:32px;font-weight:800;color:{DEEP};letter-spacing:-.5px;white-space:nowrap">{w}</span></div>' for ic, w in items)
    return f'<div style="position:absolute;left:0;right:0;top:478px;display:flex;justify-content:center;gap:26px;padding:0 20px">{cells}</div>'

def single(title, sub, body_html, items):
    shell = screen(title, sub, '', '')
    phone = f'<div class="phone" style="left:220px;top:585px;transform:scale(.95);box-shadow:0 36px 70px rgba(31,26,21,.26)"><div class="scr">{body_html}</div></div>'
    return shell.replace('<div class="phone"><div class="scr"></div></div>', keywords(items) + phone)

if which == '2':
    html = single("La sortie s'organise<br>avec les participants :<br>covoiturage, matériel, discussion.", "", screen_body,
                  [(li('car', 32, INK), 'Qui conduit'), (li('bag', 32, INK), 'Qui apporte quoi'), (li('msg', 32, INK), 'On se parle')])
elif which == '4':
    html = single("Les discussions des pratiquants<br>de ta vallée,<br>sport par sport.", '', screen_body,
                  [(sp('ski-touring', 34, INK), 'Par sport'), (li('pin', 32, INK), 'Par vallée'), (li('users', 32, INK), 'Ouvert à tous')])
else:
    html = single("Des partenaires fiables :<br>présence et niveau<br>vérifiés sur le terrain.", '', screen_body,
                  [(li('check', 32, INK, 3), 'Présence vérifiée'), (li('shield', 32, INK), 'Fiabilité'), (li('users', 32, INK), 'Niveau confirmé')])
html = html.replace('font-size:82px;line-height:1.04', 'font-size:62px;line-height:1.1').replace('margin:150px 70px 0;text-align:center', 'margin:140px 60px 0;text-align:center')
open(sys.argv[2], 'w').write(html)
print('ok')
