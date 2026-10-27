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
    cells = ''.join(f'<div style="display:flex;align-items:center;gap:12px"><span style="width:52px;height:52px;border-radius:50%;background:#FFF;display:inline-flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(31,26,21,.12)">{ic}</span><span style="font-size:30px;font-weight:800;color:{DEEP};letter-spacing:-.4px;white-space:nowrap">{w}</span></div>' for ic, w in items)
    return f'<div style="position:absolute;left:0;right:0;top:586px;display:flex;justify-content:center;gap:34px;padding:0 30px">{cells}</div>'

def single(title, sub, body_html, items):
    shell = screen(title, sub, '', '')
    phone = f'<div class="phone" style="left:220px;top:690px;transform:scale(.85);box-shadow:0 36px 70px rgba(31,26,21,.26)"><div class="scr">{body_html}</div></div>'
    return shell.replace('<div class="phone"><div class="scr"></div></div>', keywords(items) + phone)

if which == '2':
    html = single("Dedans, tout<br>s'organise.", "Covoiturage, matériel, discussion de groupe, rendez-vous : tout le monde voit la même chose.", screen_body,
                  [(li('car', 28, INK), 'Qui conduit'), (li('bag', 28, INK), 'Qui apporte quoi'), (li('msg', 28, INK), 'On se parle')])
elif which == '4':
    html = single('Des discussions qui<br>finissent dehors.', 'Conditions du jour, binômes, matos, sorties proposées — chaque vallée a ses canaux.', screen_body,
                  [(sp('ski-touring', 30, INK), 'Par sport'), (li('pin', 28, INK), 'Par vallée'), (li('users', 28, INK), 'Ouvert à tous')])
else:
    html = single('Des inconnus, oui.<br>Des inconnus fiables.', 'Pas de notes, pas de classement : une fiabilité qui se construit dehors, sortie après sortie.', screen_body,
                  [(li('check', 28, INK, 3), 'Présence vérifiée'), (li('shield', 28, INK), 'Fiabilité'), (li('users', 28, INK), 'Niveau confirmé')])
open(sys.argv[2], 'w').write(html)
print('ok')
