# Feature graphic 1024×500 for Google Play (askandgo, 2026-10-26). Same
# language as the six Play images (Outfit, pale green ground, white arcs):
# mark + name, the headline, and a slice of the Écrins map with today's pins —
# three outings and a gold pro shield. Render: see the command in the README
# block at the end (Firefox headless, window 1024×500).
import json, os, sys
S = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(f'{S}/../../..')
MAP = f'file://{ROOT}/web/public/hero-map-ecrins.jpg'
MARK = open(f'{ROOT}/assets/brand/askandgo-mark.svg').read().replace('#000000', 'currentColor')
ICONS = json.load(open(sys.argv[1]))  # sport key → svg xml (currentColor)
INK = '#1F1A15'; GREEN = '#246342'; DEEP = '#246342'; GOLD = '#F2B705'; BRAND = '#1E7FD8'  # askandgo identity 2026-10-30
UNI = {'ski-touring': '#4A7C59', 'trail-running': '#E11D48', 'paragliding': '#8B5CF6', 'canyoning': '#2563EB'}
DROP = 'M 27 3 C 15.4 3 6 12.2 6 23.5 C 6 33.5 18.5 43.5 24.6 50.2 C 25.9 51.6 28.1 51.6 29.4 50.2 C 35.5 43.5 48 33.5 48 23.5 C 48 12.2 38.6 3 27 3 Z'
SHIELD = 'M 27 3 C 34 6 41 7.5 47 7.5 C 47 22 44 36 29.6 50.2 C 28.2 51.6 25.8 51.6 24.4 50.2 C 10 36 7 22 7 7.5 C 13 7.5 20 6 27 3 Z'

def picto(key, color, size=24, cx=27, cy=23):
    xml = ICONS[key]
    vb = xml.split('viewBox="')[1].split('"')[0]
    inner = xml.split('>', 1)[1].rsplit('</svg>', 1)[0]
    return f'<svg x="{cx - size/2}" y="{cy - size/2}" width="{size}" height="{size}" viewBox="{vb}" style="color:{color}">{inner}</svg>'

def shadow(path, w):
    return (f'<path d="{path}" fill="#0A0F1A" stroke="#0A0F1A" stroke-width="{w}" stroke-linejoin="round" opacity=".28" transform="translate(0 5)" filter="url(#blur4)"/>'
            f'<path d="{path}" fill="#0A0F1A" stroke="#0A0F1A" stroke-width="{w}" stroke-linejoin="round" opacity=".4" transform="translate(0 2)" filter="url(#blur1)"/>')

def drop(key, px):
    c = UNI[key]
    return f'''<svg width="{px}" height="{px*82/78}" viewBox="-12 -14 78 82"><defs><filter id="blur4" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter><filter id="blur1" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.2"/></filter></defs>
{shadow(DROP, 4)}<path d="{DROP}" fill="#FFF" stroke="#FFF" stroke-width="4" stroke-linejoin="round"/><path d="{DROP}" fill="{c}"/>{picto(key, '#FFF', 26)}</svg>'''

def shield(key, tint, px):
    cap = f'<rect x="16" y="50.5" width="22" height="12" rx="6" fill="{GOLD}"/><text x="27" y="59.6" font-size="8" font-weight="700" letter-spacing=".5" fill="{INK}" text-anchor="middle" font-family="Outfit, Helvetica, Arial, sans-serif">PRO</text>'
    return f'''<svg width="{px}" height="{px*92/78}" viewBox="-12 -14 78 92"><defs><filter id="blur4" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="4"/></filter><filter id="blur1" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="1.2"/></filter></defs>
{shadow(SHIELD, 6)}<path d="{SHIELD}" fill="{INK}" stroke="{INK}" stroke-width="6" stroke-linejoin="round"/><path d="{SHIELD}" fill="{GOLD}" stroke="{GOLD}" stroke-width="4" stroke-linejoin="round"/><path d="{SHIELD}" fill="{tint}"/>{picto(key, INK, 24, 27, 24)}{cap}</svg>'''

def pin(x, y, svg, label, color):
    return f'<div class="pin" style="left:{x}px;top:{y}px">{svg}<span style="color:{color}">{label}</span></div>'

html = f'''<!doctype html><html lang="fr"><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Outfit:wght@500;600;700;800&display=swap">
<style>
*{{box-sizing:border-box}}html,body{{margin:0;width:1024px;height:500px;overflow:hidden}}
body{{font-family:Outfit,system-ui,sans-serif;color:{INK};background:#E4EDDF;position:relative}}
.arcs{{position:absolute;inset:0}}
.brand{{position:absolute;left:64px;top:58px;display:flex;align-items:center;gap:14px;font-size:36px;font-weight:800;letter-spacing:-.5px}}
.brand .sp{{width:54px;height:54px;border-radius:13px;background:{BRAND};color:#FFF;padding:8px;display:inline-flex}}.brand .sp svg{{width:100%;height:100%}}
.brand .a{{color:{BRAND}}}.brand .n{{color:{GREEN}}}
h1{{position:absolute;left:64px;top:138px;margin:0;width:470px;font-size:60px;line-height:1.02;font-weight:800;color:{DEEP};letter-spacing:-1.2px}}
.bar{{position:absolute;left:64px;top:292px;width:72px;height:6px;border-radius:3px;background:{GREEN}}}
.sub{{position:absolute;left:64px;top:322px;width:460px;font-size:23px;line-height:1.3;color:#4B584D;font-weight:500}}
.map{{position:absolute;left:574px;top:34px;width:416px;height:432px;border-radius:30px;overflow:hidden;background:url({MAP}) 62% 48%/190% auto;box-shadow:0 30px 60px rgba(31,26,21,.26);border:10px solid #FFF}}
.pin{{position:absolute;display:flex;align-items:center;gap:6px}}
.pin span{{font-weight:800;font-size:15px;white-space:nowrap;text-shadow:0 0 5px #FFF,0 0 5px #FFF,0 0 8px #FFF}}
</style></head><body>
<svg class="arcs" viewBox="0 0 1024 500" fill="none" stroke="#FFF" stroke-opacity=".55" stroke-width="3"><circle cx="150" cy="520" r="220"/><circle cx="150" cy="520" r="330"/><circle cx="150" cy="520" r="450"/></svg>
<div class="brand"><span class="sp">{MARK}</span><span><span class="a">ask</span><span class="n">and</span><span class="a">go</span></span></div>
<h1>Où que tu ailles,<br>vois qui part.</h1>
<div class="bar"></div>
<div class="sub">Sorties outdoor, entre passionnés ou encadrées par un pro.</div>
<div class="map">
{pin(36, 54, drop('ski-touring', 50), 'Col de Buffère', UNI['ski-touring'])}
{pin(196, 128, drop('paragliding', 50), 'Déco du Chalvet', UNI['paragliding'])}
{pin(62, 236, shield('canyoning', '#BDD0F8', 52), 'Vertige Canyon', INK)}
{pin(214, 318, drop('trail-running', 50), 'Trail à la frontale', UNI['trail-running'])}
</div>
</body></html>'''
open(sys.argv[2], 'w').write(html)
