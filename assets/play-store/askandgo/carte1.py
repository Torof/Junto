# Play image 1 — « Où que tu ailles, vois qui part. » — redrawn 2026-10-27 with
# the app's real pins (rounded drop, white outline, two-layer shadow, sport
# picto), the real labels (title in the universe colour · 📅 when · 📊 level)
# and the list drawer's tab handle instead of a « Voir la liste » pill.
#   python3 carte1.py out.html && firefox --headless --window-size=1080,1920 --screenshot 1-carte.png file://…/out.html
import os, sys
S = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(f'{S}/../../..')
src = open(f'{S}/generate.py').read()
exec(src[:src.index('out={}')])  # noqa: S102 — the generator's helpers (li, sp, screen, callout, tabbar…)

DROP = 'M 27 3 C 15.4 3 6 12.2 6 23.5 C 6 33.5 18.5 43.5 24.6 50.2 C 25.9 51.6 28.1 51.6 29.4 50.2 C 35.5 43.5 48 33.5 48 23.5 C 48 12.2 38.6 3 27 3 Z'
CAL = f'file://{ROOT}/assets/label-cal.png'
LVL = f'file://{ROOT}/assets/label-level.png'
PIN_PX = 64  # the 40-px drop of a 390-wide phone, in this 640-wide screen

def drop(k):
    c = UNI[k]
    inner = IC[k].split('>', 1)[1].rsplit('</svg>', 1)[0]
    vb = IC[k].split('viewBox="')[1].split('"')[0]
    w = PIN_PX * 78 / 54
    return f'''<svg width="{w:.0f}" height="{w * 82 / 78:.0f}" viewBox="-12 -14 78 82" style="display:block;overflow:visible">
<defs><filter id="bf" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter><filter id="bn" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.2"/></filter></defs>
<path d="{DROP}" fill="#0A0F1A" stroke="#0A0F1A" stroke-width="4" stroke-linejoin="round" opacity=".3" transform="translate(0 5)" filter="url(#bf)"/>
<path d="{DROP}" fill="#0A0F1A" stroke="#0A0F1A" stroke-width="4" stroke-linejoin="round" opacity=".45" transform="translate(0 2)" filter="url(#bn)"/>
<path d="{DROP}" fill="#FFF" stroke="#FFF" stroke-width="4" stroke-linejoin="round"/><path d="{DROP}" fill="{c}"/>
<svg x="14" y="10" width="26" height="26" viewBox="{vb}" style="color:#FFF">{inner}</svg></svg>'''

def realpin(k, x, y, title, when, lvl=None):
    c = UNI[k]
    halo = 'text-shadow:0 0 5px #FFF,0 0 5px #FFF,0 0 8px #FFF,0 0 10px #FFF'
    lines = f'<div style="display:flex;align-items:center;gap:5px;font-size:17px;font-weight:700;color:{SEC};{halo}"><img src="{CAL}" style="width:17px;height:17px">{when}</div>'
    if lvl:
        lines += f'<div style="display:flex;align-items:center;gap:5px;font-size:17px;font-weight:700;color:{SEC};{halo}"><img src="{LVL}" style="width:17px;height:17px">{lvl}</div>'
    return f'''<div style="position:absolute;left:{x}px;top:{y}px;display:flex;align-items:center;gap:0">{drop(k)}
<div style="display:flex;flex-direction:column;gap:1px;white-space:nowrap;margin-left:-10px;margin-top:-18px"><div style="font-size:21px;font-weight:800;line-height:1.1;color:{c};{halo}">{title}</div>{lines}</div></div>'''

# The list drawer's handle (activities-bottom-sheet TabHandle): the sheet's
# top line with a rounded tab rising from it — grip, chevron, « Sorties · 7 ».
def drawer_handle(bottom):
    return f'''<div style="position:absolute;left:0;right:0;bottom:{bottom}px;height:16px;background:#FFF;border-top:1.5px solid {INK}"></div>
<div style="position:absolute;left:12px;bottom:{bottom + 14}px;height:52px;padding:6px 22px 0;background:#FFF;border:1.5px solid {INK};border-bottom:none;border-radius:20px 20px 0 0;display:flex;flex-direction:column;align-items:center;gap:6px">
 <div style="width:52px;height:5px;border-radius:3px;background:#B9B3A8"></div>
 <div style="display:flex;align-items:center;gap:8px;font-size:17px;font-weight:800"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="{INK}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m8 14 4-4 4 4"/></svg>Sorties · 7</div></div>'''

body = f'''<div style="position:absolute;inset:0;background:url({MAP}) center/cover"></div>
<div style="position:absolute;left:22px;right:22px;top:66px;display:flex;gap:12px;align-items:center">
 <div style="flex:1;display:flex;align-items:center;gap:12px;background:#FFF;border-radius:999px;padding:14px 20px;font-size:21px;color:{SEC};box-shadow:0 4px 12px rgba(0,0,0,.14)">{li('search',24,SEC)}Chercher un lieu…</div>
 <div style="width:54px;height:54px;border-radius:50%;background:#FFF;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,.14)">{li('sliders',26)}</div>
 <div style="width:54px;height:54px;border-radius:50%;background:#FFF;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,.14)">{li('layers',26)}</div></div>
{realpin('hiking', 300, 180, "Lac de l'Eychauda", 'sam. 8h30', '900 m D+ · 12 km')}
{realpin('climbing-sport', 60, 330, 'Grande voie à Ailefroide', 'sam. 9h', '5c → 6a')}
{realpin('ski-touring', 290, 500, 'Col de Buffère', 'dim. 7h30', '800 m D+')}
{realpin('trail-running', 40, 690, 'Trail à la frontale', 'ven. 19h', '12 km')}
{realpin('paragliding', 300, 820, 'Déco du Chalvet', 'sam. 14h')}
{realpin('canyoning', 110, 950, 'Canyon du Fournel', 'dim. 10h', 'Tous niveaux')}
<div style="position:absolute;right:24px;bottom:150px"><div style="width:68px;height:68px;border-radius:50%;background:{GREEN};display:flex;align-items:center;justify-content:center;box-shadow:0 8px 20px rgba(47,164,106,.45)">{li('plus',34,'#FFF',2.8)}</div></div>
{drawer_handle(104)}
<div style="position:absolute;left:0;right:0;bottom:0">{tabbar(0)}</div>'''

# Same language as images 2, 4, 5: one row of three keywords above a big straight phone.
def keywords(items):
    cells = ''.join(f'<div style="display:flex;align-items:center;gap:12px"><span style="width:58px;height:58px;border-radius:50%;background:#FFF;display:inline-flex;align-items:center;justify-content:center;box-shadow:0 6px 16px rgba(31,26,21,.12)">{ic}</span><span style="font-size:32px;font-weight:800;color:{DEEP};letter-spacing:-.5px;white-space:nowrap">{w}</span></div>' for ic, w in items)
    return f'<div style="position:absolute;left:0;right:0;top:478px;display:flex;justify-content:center;gap:26px;padding:0 20px">{cells}</div>'
# Two sides of the same screen (Scott 2026-10-27): join an outing around you, or post
# yours for others to join — the « proposer » icon is the map's green + button.
items = [(li('search', 32, INK), 'Trouver une sortie'),
         (f'<span style="width:58px;height:58px;border-radius:50%;background:{GREEN};display:inline-flex;align-items:center;justify-content:center;margin:-0px">{li("plus", 30, "#FFF", 2.8)}</span>', 'Proposer la tienne'),
         (li('cal', 32, INK), 'Sport, lieu, date')]
shell = screen("Des sorties outdoor là où tu es :<br>rejoins-en une,<br>ou propose la tienne.", '', '', '')
phone = f'<div class="phone" style="left:220px;top:600px;transform:scale(.93) rotate(-3deg);box-shadow:0 36px 70px rgba(31,26,21,.26)"><div class="scr">{body}</div></div>'
html = shell.replace('<div class="phone"><div class="scr"></div></div>', keywords(items) + phone)
html = html.replace('font-size:82px;line-height:1.04', 'font-size:62px;line-height:1.1').replace('margin:150px 70px 0;text-align:center', 'margin:140px 60px 0;text-align:center')
open(sys.argv[1], 'w').write(html)
print('ok')
