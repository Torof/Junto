# Builds the Nicolas variants of image 6 for comparison (Scott 2026-10-28).
import sys, subprocess, os
S = os.path.dirname(os.path.abspath(__file__))
P6 = open(f'{S}/_n_pro6.py').read(); TW = open(f'{S}/_n_two.py').read()
V = {
 'glacier': dict(cover="p1.jpg", sport_icon='mountaineering', sport='Alpinisme', uni="ski-touring", dur_card='1 journée',
     title='Initiation glacier · Glacier Blanc', level='Débutant', group="jusqu'à 4 pers.", price='160 €', place='Glacier Blanc',
     rating='5,0', count='2 avis', dur='1 journée',
     about="Une journée pour apprendre à marcher en crampons, s'encorder et évoluer sur un glacier, au pied de la Barre des Écrins. Le meilleur premier pas avant une course de neige.",
     prov=['Crampons, piolet','Baudrier, casque','Corde'], req=['Chaussures rigides','Gants, bonnet','Pique-nique'], season='Juin à septembre · départ 6h30',
     rev=('HP','Hugo P.','Initiation glacier · juil.',"Initiation glacier parfaite, j'ai appris plus en une journée qu'en trois ans de lecture.")),
 'skirando': dict(cover="p2.jpg", sport_icon='ski-touring', sport='Ski de rando', uni="ski-touring", dur_card='1 journée',
     title='Ski de rando à la journée · Clarée', level='Intermédiaire', group="jusqu'à 5 pers.", price='95 €', place='Névache',
     rating='4,0', count='1 avis', dur='1 journée',
     about="Une journée de ski de randonnée adaptée au groupe et à la neige du jour : vallée de la Clarée, Cerces, Montgenèvre. Des descentes choisies pour le plaisir.",
     prov=['DVA, pelle, sonde','Itinéraire du jour','Lecture de la neige'], req=['Skis, peaux, couteaux','Casque conseillé','Pique-nique'], season='Décembre à mai · 8h à Névache',
     rev=('LW','Lukas W.','Ski de rando · fév.',"Belle journée de ski de rando, Nicolas choisit bien ses pentes. Rythme soutenu !")),
}
def apply(s, pairs):
    for a, b in pairs:
        assert a in s, a[:60]; s = s.replace(a, b)
    return s
for name, d in V.items():
    chip_old = "{sp('mountaineering',14,'#FFF')}Alpinisme</span><span style=\"font-size:12px;color:{SEC};font-weight:600\">2 jours</span>"
    p6 = apply(P6, [
      (chip_old, f"{{sp('{d['sport_icon']}',14,'#FFF')}}{d['sport']}</span><span style=\"font-size:12px;color:{{SEC}};font-weight:600\">{d['dur_card']}</span>"),
      ("Dôme des Écrins · 2 jours", d['title']), ("{lx('bar',13,SEC)}Intermédiaire", f"{{lx('bar',13,SEC)}}{d['level']}"),
      ("jusqu'à 2 pers.", d['group']), ("520 € <span", d['price'] + " <span"),
      ("font-size:12px\">LM</span>", f"font-size:12px\">{d['rev'][0]}</span>"),
      ("<b>Léa M.</b> <span style=\"color:{SEC}\">· Dôme des Écrins · sept.</span><div style=\"margin-top:2px\">Sérieux, calme, et une vraie attention à la cordée. Sommet au lever du soleil, je ne l'oublierai pas.</div>",
       f"<b>{d['rev'][1]}</b> <span style=\"color:{{SEC}}\">· {d['rev'][2]}</span><div style=\"margin-top:2px\">{d['rev'][3]}</div>"),
    ])
    tw = apply(TW, [
      ("open(f'{S}/_n_pro6.py').read()", "P6V"),
      ("background:url({PRO('p3.jpg')}) center/cover\">", f"background:url({{PRO('{d['cover']}')}}) center/cover\">"),
      ("{sp('mountaineering',14,'#FFF')}Alpinisme</div>", f"{{sp('{d['sport_icon']}',14,'#FFF')}}{d['sport']}</div>"),
      ("Dôme des Écrins · 2 jours", d['title']), ("<b>4,5</b><span style=\"opacity:.9\">· 2 avis</span>", f"<b>{d['rating']}</b><span style=\"opacity:.9\">· {d['count']}</span>"),
      ("520 €", d['price']),
      ("'DURÉE', '2 jours'", f"'DURÉE', '{d['dur']}'"), ("'NIVEAU', 'Intermédiaire'", f"'NIVEAU', '{d['level']}'"),
      ("'LIEU', 'Pré de Mme Carle'", f"'LIEU', '{d['place']}'"), ("\"jusqu'à 2 pers.\"", f"\"{d['group']}\""),
      ("Le 4 000 des Écrins en deux jours : montée au refuge par le Glacier Blanc, départ nocturne, arête sommitale au lever du soleil. Bonne condition physique et une première expérience de cramponnage.", d['about']),
      ("Juin à septembre · nuit au refuge", d['season']),
    ])
    # equipment chips
    import re
    tw = tw.replace("{li('check',13,'#246342',3)}Corde</span>", "§P0§", 1).replace("{li('check',13,'#246342',3)}Matériel glacier</span>", "§P1§", 1).replace("{li('check',13,'#246342',3)}Crampons, piolet</span>", "§P2§", 1)
    ok = '<span class="chip ok" style="font-size:12px;padding:5px 10px">'
    prov = [f"{{li('check',13,'#246342',3)}}{x}</span>" for x in d['prov']]
    tw = tw.replace("§P0§", prov[0]).replace("§P1§", prov[1] if len(prov) > 1 else "").replace("§P2§", prov[2] if len(prov) > 2 else "")
    if len(prov) < 3: tw = tw.replace(ok + "</span>", "")
    for a, b in zip(['Chaussures cramponnables', 'Baudrier et casque', 'Sac 35 L'], d['req']):
        tw = tw.replace(a + "</span>", b + "</span>", 1)
    tw = tw.replace("P6V", "__P6__", 1)
    code = tw.replace("__P6__", repr(p6))
    open(f'{S}/_gen_{name}.py', 'w').write(code)
print('ok')
