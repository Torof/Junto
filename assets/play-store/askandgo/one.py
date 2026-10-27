# Play images 2 · 4 · 5 as ONE bigger screen with « exploded » details
# (Scott 2026-10-27: people don't read — each piece of information must be
# caught at a glance). The real UI fragment is lifted out of the phone at
# 1.5× on a white card with a strong shadow, and a two-word label over it.
#   python3 one.py 2 out.html   (4, 5 likewise)
import os, sys
S = os.path.dirname(os.path.abspath(__file__))
src = open(f'{S}/generate.py').read()
src = src.replace("PH=lambda k:f'photos/demo-channel-{k}.jpg'", "PH=lambda k:f'file://{S}/photos/demo-channel-{k}.jpg'")
which = sys.argv[1]
# helpers + the body of the wanted image, exactly as generate.py draws it
cut = {'2': "out['2-sortie']", '4': "out['4-canaux']", '5': "out['5-confiance']"}[which]
exec(src[:src.index(cut)])  # noqa: S102
screen_body = body

def frag(x, y, w, label, html, tilt=0):
    return (f'<div style="position:absolute;left:{x}px;top:{y}px;width:{w}px;z-index:5;transform:rotate({tilt}deg)">'
            f'<div style="font-size:26px;font-weight:800;color:{DEEP};letter-spacing:-.3px;margin:0 0 8px 6px">{label}</div>'
            f'<div style="background:#FFF;border-radius:22px;padding:16px 18px;box-shadow:0 24px 50px rgba(31,26,21,.28), 0 2px 6px rgba(31,26,21,.12);border:1.5px solid rgba(31,26,21,.08);font-size:24px">{html}</div></div>')

def exploded(title, sub, body_html, frags):
    shell = screen(title, sub, '', '')
    phone = f'<div class="phone" style="left:14px;top:640px;transform:scale(.78) rotate(-3deg);z-index:1"><div class="scr">{body_html}</div></div>'
    return shell.replace('<div class="phone"><div class="scr"></div></div>', phone + ''.join(frags))

if which == '2':
    frags = [
        frag(585, 760, 455, 'Qui conduit',
             f'<div class="row" style="margin:0"><div class="av" style="width:56px;height:56px;font-size:20px">LM</div><div class="t"><b style="font-size:24px">Léa conduit · 3 places</b><small style="font-size:18px">Briançon → Ailefroide · 7h00</small></div><span class="gp" style="font-size:20px;padding:10px 20px">Monter</span></div>', 2),
        frag(570, 1070, 470, 'Qui apporte quoi',
             f'<div style="display:flex;flex-wrap:wrap;gap:10px"><span class="chip ok" style="font-size:20px;padding:10px 16px">{li("check",20,"#1E6B45",3)}Corde 60 m · Léa</span><span class="chip ok" style="font-size:20px;padding:10px 16px">{li("check",20,"#1E6B45",3)}Casque · toi</span><span class="chip miss" style="font-size:20px;padding:10px 16px">Jeu de friends · manque 1</span></div>', -2),
        frag(555, 1390, 485, 'On se parle',
             f'<div style="display:flex;flex-direction:column;gap:8px"><div class="bub" style="font-size:21px;margin:0;max-width:92%"><span class="who" style="font-size:17px">Sam B.</span>Je serai 10 min en retard, commencez sans moi</div><div class="bub own" style="font-size:21px;margin:0;max-width:80%">Pas de souci, on t\'attend au parking</div></div>', 2),
    ]
    html = exploded("Dedans, tout<br>s'organise.", "Qui conduit, qui apporte la corde, qui est en retard : tout le monde le voit au même endroit.", screen_body, frags)
elif which == '4':
    frags = [
        frag(585, 780, 455, 'Par sport, par vallée',
             f'<div style="display:flex;flex-direction:column;gap:12px"><div style="display:flex;align-items:center;gap:12px"><span class="chip" style="font-size:19px;padding:8px 14px;gap:8px">{sp("climbing-sport",22,INK)}Escalade</span><span style="font-size:19px;color:{SEC}">· Gap</span></div><div style="font-size:24px;font-weight:800">Grimpe au soleil à Céüse</div><div style="font-size:18px;color:{SEC}">{li("users",18,SEC)} 128 membres</div></div>', 2),
        frag(570, 1110, 470, 'Ouvert à qui passe',
             f'<div style="display:flex;align-items:center;justify-content:space-between;gap:12px"><div><div style="font-size:23px;font-weight:800">Peaux de phoque &amp; poudreuse</div><div style="font-size:18px;color:{SEC}">Briançon · 87 membres</div></div><span class="gp" style="font-size:20px;padding:10px 20px">Rejoindre</span></div>', -2),
        frag(555, 1420, 485, 'Et ça finit dehors',
             f'<div style="display:flex;flex-direction:column;gap:8px"><div class="bub" style="font-size:21px;margin:0;max-width:94%"><span class="who" style="font-size:17px">Hugo P.</span>Conditions parfaites au Fournel demain, quelqu\'un ?</div><div class="bub own" style="font-size:21px;margin:0;max-width:60%">Je suis chaud, 9h ?</div></div>', 2),
    ]
    html = exploded('Des discussions qui<br>finissent dehors.', 'Conditions du jour, binômes, matos, sorties proposées : chaque vallée a ses canaux.', screen_body, frags)
else:
    frags = [
        frag(585, 760, 455, 'Présence vérifiée',
             f'<div style="display:flex;align-items:center;gap:14px"><span style="width:52px;height:52px;border-radius:50%;background:#E6F4EC;display:inline-flex;align-items:center;justify-content:center">{li("pin",28,"#1E6B45",2.6)}</span><div><div style="font-size:23px;font-weight:800">Sur place, sortie après sortie</div><div style="font-size:18px;color:{SEC}">GPS, QR ou partenaires</div></div></div>', 2),
        frag(570, 1060, 470, 'Fiabilité',
             f'<div style="display:flex;align-items:center;gap:16px"><div style="width:72px;height:72px;border-radius:50%;border:6px solid {GOOD};display:flex;align-items:center;justify-content:center;font-size:22px;font-weight:800">LM</div><div><div style="font-size:24px;font-weight:800;color:{GOOD}">Bonne · 94 %</div><div style="font-size:18px;color:{SEC}">53 sorties terminées, présente</div></div></div>', -2),
        frag(555, 1370, 485, 'Niveau confirmé',
             f'<div style="display:flex;align-items:center;gap:12px;flex-wrap:wrap"><span class="chip" style="font-size:20px;padding:9px 14px;gap:8px;background:{UNI["climbing-sport"]}1A;color:{UNI["climbing-sport"]}">{sp("climbing-sport",22,UNI["climbing-sport"])}Escalade · avancée</span><span style="font-size:18px;color:{SEC}">▲ confirmé par 3 partenaires</span></div>', 2),
    ]
    html = exploded('Des inconnus, oui.<br>Des inconnus fiables.', 'Pas de notes, pas de classement : une fiabilité qui se construit dehors.', screen_body, frags)

open(sys.argv[2], 'w').write(html)
print('ok')
