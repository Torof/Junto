import json,os
S=os.path.dirname(os.path.abspath(__file__))
IC=json.load(open(f'{S}/icons.json'))
MAP='file:///home/torof/Desktop/Junto/web/public/hero-map-ecrins.jpg'
PH=lambda k:f'photos/demo-channel-{k}.jpg'
MARK=open('/home/torof/Desktop/Junto/assets/brand/askandgo-mark.svg').read().replace('#000000','currentColor')
INK='#1F1A15'; GREEN='#2FA46A'; DEEP='#1D3A2A'; SEC='#6F665A'
UNI={'ski-touring':'#4A7C59','climbing-sport':'#4A7C59','hiking':'#4A7C59','via-ferrata':'#4A7C59','trail-running':'#E11D48','paragliding':'#8B5CF6','canyoning':'#2563EB'}
L={ # lucide-ish paths (24 grid)
'pin':'<path d="M20 10c0 4.99-5.54 10.19-7.4 11.8a1 1 0 0 1-1.2 0C9.54 20.19 4 14.99 4 10a8 8 0 0 1 16 0"/><circle cx="12" cy="10" r="3"/>',
'users':'<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
'msg':'<path d="M7.9 20A9 9 0 1 0 4 16.1L2 22Z"/>',
'menu':'<path d="M4 6h16M4 12h16M4 18h16"/>',
'map':'<path d="M14.1 6.3 9.9 3.7a1 1 0 0 0-1 0L3.5 6.4A1 1 0 0 0 3 7.3v12a1 1 0 0 0 1.5.9l4.4-2.5a1 1 0 0 1 1 0l4.2 2.6a1 1 0 0 0 1 0l5.4-2.7a1 1 0 0 0 .5-.9v-12a1 1 0 0 0-1.5-.9l-4.4 2.5a1 1 0 0 1-1 0"/><path d="M15 5.8v15.4M9 3.5v15.4"/>',
'cal':'<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
'car':'<path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2"/><circle cx="7" cy="17" r="2"/><path d="M9 17h6"/><circle cx="17" cy="17" r="2"/>',
'bag':'<path d="M4 10a4 4 0 0 1 4-4h8a4 4 0 0 1 4 4v10a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2Z"/><path d="M9 6V4a3 3 0 0 1 6 0v2"/><path d="M8 21v-5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v5"/>',
'check':'<path d="M20 6 9 17l-5-5"/>',
'clock':'<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
'phone':'<path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8.1 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7A2 2 0 0 1 22 16.9z"/>',
'route':'<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
'shield':'<path d="M20 13c0 5-3.5 7.5-7.7 9a.6.6 0 0 1-.6 0C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.2-2.7a1.2 1.2 0 0 1 1.6 0C14.5 3.8 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
'star':'<path d="M11.5 2.6a.6.6 0 0 1 1 0l2.5 5.2 5.7.8a.6.6 0 0 1 .3 1l-4.1 4 1 5.7a.6.6 0 0 1-.9.6L12 17.3l-5 2.7a.6.6 0 0 1-.9-.6l1-5.7-4.1-4a.6.6 0 0 1 .3-1l5.7-.8z"/>',
'chev':'<path d="m9 18 6-6-6-6"/>',
'search':'<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
'sliders':'<path d="M4 21v-7M4 10V3M12 21v-9M12 8V3M20 21v-5M20 12V3M2 14h4M10 8h4M18 16h4"/>',
'layers':'<path d="m12.8 2.2 8.5 4.2a1 1 0 0 1 0 1.8l-8.5 4.2a2 2 0 0 1-1.8 0L2.5 8.2a1 1 0 0 1 0-1.8l8.5-4.2a2 2 0 0 1 1.8 0"/><path d="m22 17.7-9.3 4.6a2 2 0 0 1-1.8 0L2 17.7"/><path d="m22 12.5-9.3 4.6a2 2 0 0 1-1.8 0L2 12.5"/>',
'plus':'<path d="M5 12h14M12 5v14"/>',
'eye':'<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12"/><circle cx="12" cy="12" r="3"/>',
'bell':'<path d="M10.3 21a1.9 1.9 0 0 0 3.4 0"/><path d="M3.3 17c-.3.3-.3.8 0 1.1.2.2.4.3.7.3h16c.6 0 1-.4 1-1 0-.3-.1-.5-.3-.7-1.1-1.1-2.1-2.3-2.1-6.3a6.6 6.6 0 0 0-13.2 0c0 4-1 5.2-2.1 6.3"/>',
}
def li(k,sz=24,c=INK,w=2.2): return f'<svg class="li" width="{sz}" height="{sz}" viewBox="0 0 24 24" fill="none" stroke="{c}" stroke-width="{w}" stroke-linecap="round" stroke-linejoin="round">{L[k]}</svg>'
def sp(k,sz,c='#FFF'): return f'<span class="sp" style="width:{sz}px;height:{sz}px;color:{c}">{IC[k]}</span>'
def pin(k,x,y,label,sub,n=None):
    c=UNI[k]
    return f'''<div class="pin" style="left:{x}px;top:{y}px"><div class="drop" style="background:{c}">{sp(k,30)}{f'<b>{n}</b>' if n else ''}</div><div class="plab" style="color:{c}"><span>{label}</span><small>{sub}</small></div></div>'''
PHONE_TOP=740; SCALE=0.8
def callout(x,y,icon_html,title,sub,side='left',w=250):
    y=int(PHONE_TOP+(y-720)*SCALE)
    al='flex-end;text-align:right' if side=='right' else 'flex-start;text-align:left'
    return f'<div class="co" style="left:{x}px;top:{y}px;width:{w}px;align-items:{al}"><div class="cob">{icon_html}</div><b>{title}</b><span>{sub}</span></div>'
def tabbar(active=0):
    items=[('map','Carte'),('users','Partenaires'),('msg','Messages'),('menu','Menu')]
    return '<div class="tabs">'+''.join(f'<div class="tab {"on" if i==active else ""}">{li(k,30,GREEN if i==active else SEC)}<span>{t}</span></div>' for i,(k,t) in enumerate(items))+'</div>'
def screen(title,sub,body,extra='',tilt=-3,top=None,pills='',scale=None):
    top=top or PHONE_TOP; scale=scale or SCALE
    return f'''<!doctype html><html lang="fr"><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;800&display=swap">
<style>
*{{box-sizing:border-box}}html,body{{margin:0;width:1080px;height:1920px;overflow:hidden}}
body{{font-family:Outfit,system-ui,sans-serif;color:{INK};background:#E4EDDF;position:relative}}
.arcs{{position:absolute;inset:0;pointer-events:none}}
h1{{position:relative;margin:150px 70px 0;text-align:center;font-size:82px;line-height:1.04;font-weight:800;color:{DEEP};letter-spacing:-1.5px}}
.bar{{width:84px;height:7px;border-radius:4px;background:{GREEN};margin:30px auto 0}}
.sub{{position:relative;margin:30px 110px 0;text-align:center;font-size:35px;line-height:1.38;color:#4B584D;font-weight:500}}
.pills{{position:relative;margin:34px auto 0;width:860px;display:flex;flex-direction:column;gap:14px}}
.pr{{display:flex;align-items:center;gap:18px;font-size:29px;color:#3E4B41}}.pr b{{background:{GREEN};color:#FFF;border-radius:999px;padding:8px 24px;font-size:24px;letter-spacing:1px;font-weight:800}}
.phone{{position:absolute;left:220px;top:{top}px;width:640px;height:1300px;border-radius:64px;background:{INK};padding:16px;transform-origin:50% 0;transform:scale({scale}) rotate({tilt}deg);box-shadow:0 40px 80px rgba(31,26,21,.28)}}
.scr{{position:relative;width:100%;height:100%;border-radius:50px;overflow:hidden;background:#FFF;display:flex;flex-direction:column}}
.hd{{display:flex;align-items:center;gap:14px;padding:58px 28px 16px;font-size:34px;font-weight:800}}
.hd .sm{{font-size:21px;color:{SEC};font-weight:600}}
.tabs{{margin-top:auto;display:flex;justify-content:space-around;padding:16px 10px 34px;border-top:1px solid rgba(31,26,21,.08);background:#FFF}}
.tab{{display:flex;flex-direction:column;align-items:center;gap:6px;font-size:17px;color:{SEC};font-weight:600}}.tab.on{{color:{GREEN}}}
.sp{{display:inline-flex;flex-shrink:0}}.sp svg{{width:100%;height:100%}}
.li{{flex-shrink:0}}
.pin{{position:absolute;display:flex;align-items:center;gap:8px}}
.drop{{position:relative;width:60px;height:60px;border-radius:50%;border:4px solid #FFF;display:flex;align-items:center;justify-content:center;box-shadow:0 6px 14px rgba(0,0,0,.25)}}
.drop:after{{content:"";position:absolute;left:50%;bottom:-16px;width:0;height:0;border:10px solid transparent;border-top:14px solid #FFF;transform:translateX(-50%)}}
.drop b{{position:absolute;right:-12px;top:-12px;background:#FFF;color:{INK};font-size:17px;border-radius:999px;min-width:28px;height:28px;display:flex;align-items:center;justify-content:center;padding:0 7px;box-shadow:0 2px 6px rgba(0,0,0,.2)}}
.plab{{display:flex;flex-direction:column;white-space:nowrap;font-weight:800;font-size:20px;line-height:1.1;text-shadow:0 0 6px #FFF,0 0 6px #FFF,0 0 10px #FFF}}.plab small{{font-size:16px;font-weight:600}}
.co{{position:absolute;display:flex;flex-direction:column;gap:8px}}
.cob{{width:98px;height:98px;border-radius:50%;background:#FFF;border:4px solid #FFF;box-shadow:0 10px 24px rgba(31,26,21,.22);display:flex;align-items:center;justify-content:center;margin-bottom:6px}}
.co b{{font-size:29px;color:{DEEP};line-height:1.1}}.co span{{font-size:21px;color:#4B584D;line-height:1.25;font-weight:500}}
.card{{margin:0 24px 18px;border-radius:24px;background:#FFF;box-shadow:0 2px 8px rgba(31,26,21,.12);padding:22px}}
.alt{{background:#F1EFEA;box-shadow:none}}
.sec{{display:flex;align-items:center;gap:12px;font-size:19px;font-weight:800;letter-spacing:1px;text-transform:uppercase;color:{SEC}}}
.sec:after{{content:"";flex:1;height:2px;background:{GREEN};opacity:.5;margin-left:8px}}
.row{{display:flex;align-items:center;gap:12px;margin-top:14px;font-size:22px}}
.row .t{{flex:1;min-width:0}}.row .t b{{display:block;font-size:24px}}.row .t small{{color:{SEC};font-size:19px}}
.chip{{display:inline-flex;align-items:center;gap:7px;border-radius:999px;padding:8px 16px;font-size:19px;font-weight:700;background:#F1EFEA}}
.chip.ok{{background:#E6F4EC;color:#1E6B45}}.chip.miss{{background:#FBE7E4;color:#B3261E}}
.gp{{background:{GREEN};color:#FFF;border-radius:999px;padding:8px 16px;font-size:19px;font-weight:800;white-space:nowrap}}
.bub{{max-width:78%;border-radius:20px;padding:12px 16px;font-size:21px;line-height:1.3;background:#F1EFEA;border:1px solid rgba(31,26,21,.12);margin-top:10px;border-bottom-left-radius:6px}}
.bub.own{{align-self:flex-end;background:{GREEN};color:#FFF;border-color:{GREEN};border-bottom-left-radius:20px;border-bottom-right-radius:6px}}
.who{{display:block;font-size:17px;font-weight:700;color:{GREEN};margin-bottom:2px}}
.av{{width:52px;height:52px;border-radius:50%;background:#DCE5D3;color:#3F7A56;display:flex;align-items:center;justify-content:center;font-weight:800;font-size:19px;flex-shrink:0}}
.tile{{position:relative;height:200px;border-radius:22px;overflow:hidden;margin:0 24px 16px;background-size:cover;background-position:center;color:#FFF;padding:16px;display:flex;flex-direction:column;justify-content:space-between}}
.tile:before{{content:"";position:absolute;inset:0;background:rgba(15,12,9,.42)}}
.tile>*{{position:relative}}
.tt{{display:flex;justify-content:space-between}}.tt .sc{{display:inline-flex;align-items:center;gap:7px;background:rgba(255,255,255,.22);border-radius:999px;padding:6px 12px;font-size:17px;font-weight:700;margin-left:auto}}
.tb{{display:flex;flex-direction:column;gap:8px}}.tb b{{font-size:26px;line-height:1.15}}.tm{{display:flex;align-items:center;gap:18px;font-size:18px;font-weight:600}}.tm span{{display:inline-flex;align-items:center;gap:5px}}
.mark{{position:absolute;left:50%;top:58px;transform:translateX(-50%);display:flex;align-items:center;gap:12px;font-size:27px;font-weight:800;color:{DEEP};opacity:.85}}
.mark .sp{{width:38px;height:38px;color:{DEEP}}}
</style></head><body>
<svg class="arcs" viewBox="0 0 1080 1920" fill="none" stroke="#FFF" stroke-opacity=".55" stroke-width="3">
<circle cx="920" cy="300" r="260"/><circle cx="920" cy="300" r="380"/><circle cx="920" cy="300" r="520"/>
<circle cx="120" cy="1500" r="240"/><circle cx="120" cy="1500" r="380"/><circle cx="120" cy="1500" r="540"/></svg>
<h1>{title}</h1><div class="bar"></div><div class="sub">{sub}</div>{pills}
<div class="phone"><div class="scr">{body}</div></div>
{extra}
<div class="mark"><span class="sp">{MARK}</span>Askandgo</div>
</body></html>'''

out={}
# 1 — carte
body=f'''<div style="position:absolute;inset:0;background:url({MAP}) center/cover"></div>
<div style="position:absolute;left:22px;right:22px;top:66px;display:flex;gap:12px;align-items:center">
 <div style="flex:1;display:flex;align-items:center;gap:12px;background:#FFF;border-radius:999px;padding:14px 20px;font-size:21px;color:{SEC};box-shadow:0 4px 12px rgba(0,0,0,.14)">{li('search',24,SEC)}Chercher un lieu…</div>
 <div style="width:54px;height:54px;border-radius:50%;background:#FFF;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,.14)">{li('sliders',26)}</div>
 <div style="width:54px;height:54px;border-radius:50%;background:#FFF;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(0,0,0,.14)">{li('layers',26)}</div></div>
{pin('climbing-sport',96,300,'Grande voie à Ailefroide','sam. 9h · 5c → 6a',3)}
{pin('ski-touring',330,560,'Col de Buffère','dim. 7h30 · 800 m D+',4)}
{pin('trail-running',70,760,'Trail à la frontale','ven. 19h · 12 km')}
{pin('paragliding',300,950,'Déco du Chalvet','sam. 14h · thermiques',2)}
<div style="position:absolute;left:24px;right:24px;bottom:150px;display:flex;align-items:flex-end;justify-content:space-between">
 <div style="background:#FFF;border-radius:999px;padding:14px 22px;font-size:21px;font-weight:700;box-shadow:0 4px 12px rgba(0,0,0,.14);display:flex;align-items:center;gap:10px">{li('eye',22)}Voir la liste · 7</div>
 <div style="width:68px;height:68px;border-radius:50%;background:{GREEN};display:flex;align-items:center;justify-content:center;box-shadow:0 8px 20px rgba(47,164,106,.45)">{li('plus',34,'#FFF',2.8)}</div></div>
<div style="position:absolute;left:0;right:0;bottom:0">{tabbar(0)}</div>'''
extra=callout(26,900,sp('climbing-sport',54,INK),'Quoi','le sport, dans le pin','left',212)+callout(838,1040,li('pin',52,INK),'Où','posé sur le spot exact','right',212)+callout(26,1460,li('cal',50,INK),'Quand','et le niveau attendu','left',212)
out['1-carte']=screen('Où que tu ailles,<br>vois qui part.','Chaque sortie est posée sur la carte, pile là où ça se passe. Filtre par sport, par date — ou lance la tienne.',body,extra)

# 2 — sortie
body=f'''<div class="hd" style="padding-bottom:6px"><div class="av" style="background:#4A7C59;color:#FFF">{sp('climbing-sport',32)}</div><div><div>Grande voie à Ailefroide</div><div class="sm">sam. 26 juil. · 7h30 · 5c → 6a · 3 / 4</div></div></div>
<div class="card alt" style="margin-top:14px"><div class="sec">{li('car',24,GREEN)}Transport</div>
 <div class="row"><div class="av">LM</div><div class="t"><b>Léa conduit · 3 places</b><small>Briançon → Ailefroide · départ 7h00</small></div><span class="gp">Monter</span></div>
 <div class="row"><div class="av">SB</div><div class="t"><b>Sam conduit · 1 place</b><small>Gap → Ailefroide · départ 6h15</small></div><span class="chip">complet</span></div></div>
<div class="card alt"><div class="sec">{li('bag',24,GREEN)}Matériel</div>
 <div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:16px"><span class="chip ok">{li('check',18,'#1E6B45',3)}Corde 60 m · Léa</span><span class="chip ok">{li('check',18,'#1E6B45',3)}12 dégaines · Sam</span><span class="chip ok">{li('check',18,'#1E6B45',3)}Casque · toi</span><span class="chip miss">Jeu de friends · manque 1</span></div></div>
<div class="card alt"><div class="sec">{li('msg',24,GREEN)}Discussion · 4</div>
 <div style="display:flex;flex-direction:column"><div class="bub"><span class="who">Sam B.</span>Je serai 10 min en retard, commencez sans moi.</div><div class="bub own">Pas de souci, on t'attend au parking. Pense à ton casque !</div><div class="bub"><span class="who">Léa M.</span>J'ai mis la trace GPX, 650 m de D+ 👍</div></div></div>
<div class="card alt"><div class="sec">{li('pin',24,GREEN)}Rendez-vous</div>
 <div class="row"><div class="av" style="background:#FFF">{li('route',26,GREEN)}</div><div class="t"><b>Parking du Pré de Madame Carle</b><small>7h30 · trace GPX · 650 m D+ · 5 h</small></div><span class="chip">Itinéraire</span></div></div>
{tabbar(2)}'''
pills=f'<div class="pills"><div class="pr"><b>TRANSPORT</b>qui conduit, qui monte, d\'où</div><div class="pr"><b>MATÉRIEL</b>qui apporte quoi, ce qui manque</div><div class="pr"><b>DISCUSSION</b>les participants, et personne d\'autre</div></div>'
out['2-sortie']=screen('Dedans, tout<br>s\'organise.','Qui conduit, qui apporte la corde, qui est en retard : tout le monde le voit au même endroit. Personne ne relance personne.',body,'',top=830,pills=pills,scale=0.78)

# 3 — partenaires
def dispo(ini,name,sports,when,zone,bg='#DCE5D3',fg='#3F7A56'):
    ss=''.join(f'<span class="sp" style="width:26px;height:26px;color:{UNI[s]}">{IC[s]}</span>' for s in sports)
    return f'<div class="card"><div class="row" style="margin:0"><div class="av" style="background:{bg};color:{fg}">{ini}</div><div class="t"><b>{name}</b><small>{when} · {zone}</small></div><span class="gp">Inviter</span></div><div style="display:flex;gap:10px;margin-top:14px;align-items:center">{ss}<span style="font-size:18px;color:{SEC};margin-left:4px">cherche un binôme</span></div></div>'
body=f'''<div class="hd">Partenaires</div>
<div class="card" style="background:{DEEP};color:#FFF;margin-top:0"><div style="font-size:18px;font-weight:700;letter-spacing:1px;opacity:.8">TA DISPO</div>
 <div style="display:flex;align-items:center;gap:12px;margin-top:10px;font-size:25px;font-weight:800">{li('cal',26,'#FFF')}Samedi matin</div>
 <div style="display:flex;align-items:center;gap:10px;margin-top:10px;font-size:20px"><span class="sp" style="width:28px;height:28px;color:#FFF">{IC['climbing-sport']}</span><span class="sp" style="width:28px;height:28px;color:#FFF">{IC['ski-touring']}</span>Escalade, ski de rando</div>
 <div style="display:flex;align-items:center;gap:10px;margin-top:8px;font-size:20px">{li('pin',22,'#FFF')}Briançon · 35 km</div></div>
<div style="padding:10px 28px 12px;font-size:19px;font-weight:800;letter-spacing:1px;color:{SEC}">QUI CHERCHE LA MÊME CHOSE · 5</div>
{dispo('TB','Thomas B.',['climbing-sport'],'sam. matin','Briançon · 35 km')}
{dispo('JR','Julie R.',['ski-touring','climbing-sport'],'sam. matin','Névache · 60 km','#E7DCEB','#6B4E8B')}
{dispo('YA','Youssef A.',['climbing-sport','via-ferrata'],'sam. + dim.','Gap · 60 km','#F0E1D6','#A4552D')}
{dispo('CD','Chloé D.',['ski-touring'],'dim. matin','Montgenèvre · 35 km','#DDE8F0','#2B5F86')}
{dispo('PL','Pierre-Yves L.',['climbing-sport'],'sam. après-midi','Briançon · 35 km')}
{tabbar(1)}'''
extra=callout(26,1000,li('cal',50,INK),'Quand','ton créneau, pas ton agenda','left',212)+callout(838,1180,li('pin',50,INK),'Où','ta zone, jamais ton adresse','right',212)
out['3-partenaires']=screen('Dis quand<br>tu es dispo.','Pour quels sports, dans quelle zone — et vois qui cherche la même chose. Un message, et vous partez ensemble.',body,extra)

# 4 — canaux
def tile(k,sk,sport,name,place,n,tag):
    return f'<div class="tile" style="background-image:url({PH(k)})"><div class="tt"><span class="sc">{sp(sk,20)}{sport}</span></div><div class="tb"><b>{name}</b><div class="tm"><span>{li("pin",18,"#FFF")}{place}</span><span>{li("users",18,"#FFF")}{n}</span><span class="gp" style="margin-left:auto;font-size:17px;padding:7px 14px;{"background:rgba(255,255,255,.25)" if tag=="Membre" else ""}">{tag}</span></div></div></div>'
body=f'''<div class="hd">Discussions<span class="sm" style="margin-left:auto">{li('search',26,SEC)}</span></div>
{tile(4,'climbing-sport','Escalade','Grimpe au soleil à Céüse','Gap',128,'Membre')}
{tile(1,'ski-touring','Ski de rando','Peaux de phoque & poudreuse','Briançon',87,'Rejoindre')}
<div class="card alt" style="margin-top:4px"><div style="display:flex;align-items:center;gap:12px"><div class="av">TB</div><div style="font-size:19px;color:{SEC}"><b style="color:{INK}">Thomas B.</b> a proposé une sortie</div></div>
 <div style="margin-top:12px;background:#FFF;border-radius:16px;padding:14px 16px;display:flex;align-items:center;gap:12px"><div class="av" style="background:#4A7C59;color:#FFF;width:44px;height:44px">{sp('climbing-sport',26)}</div><div style="flex:1"><b style="font-size:22px">Rocher Baron, samedi 9h</b><div style="font-size:18px;color:{SEC}">Villar-Saint-Pancrace · 5c à 6a · 2 places</div></div>{li('chev',24,SEC)}</div></div>
{tile(2,'canyoning','Canyoning','Les mouillés de la Haute-Durance',"L'Argentière",64,'Rejoindre')}
{tile(6,'paragliding','Parapente','Thermiques & décos du Gapençais','Gap',41,'Rejoindre')}
{tabbar(1)}'''
extra=callout(26,1060,sp('ski-touring',54,INK),'Par sport','et par vallée','left',212)+callout(838,1430,li('msg',50,INK),'Et dedans','les sorties se lancent','right',212)
out['4-canaux']=screen('Des discussions qui<br>finissent dehors.','Conditions du jour, binômes, matos, sorties proposées : chaque vallée a ses canaux, ouverts à qui passe par là.',body,extra)

# 5 — confiance
body=f'''<div class="hd"><div class="av" style="width:72px;height:72px;font-size:26px">LM</div><div><div>Léa M.</div><div class="sm">Membre depuis mars 2026 · Briançon</div></div></div>
<div class="card alt" style="margin-top:8px"><div class="sec">{li('shield',24,GREEN)}Fiabilité</div>
 <div style="display:flex;align-items:baseline;gap:14px;margin-top:12px"><span style="font-size:40px;font-weight:800;color:{GREEN}">Bonne</span><span style="font-size:22px;color:{SEC}">présente à 94 % de ses sorties</span></div>
 <div style="height:12px;border-radius:6px;background:#E2DFD8;margin-top:12px"><div style="width:94%;height:100%;border-radius:6px;background:{GREEN}"></div></div>
 <div style="display:flex;justify-content:space-between;margin-top:18px;text-align:center">{"".join(f'<div><div style="font-size:32px;font-weight:800">{n}</div><div style="font-size:17px;color:{SEC}">{t}</div></div>' for n,t in [(53,'terminées'),(29,'créées'),(24,'rejointes')])}</div></div>
<div class="card alt"><div class="sec">Sports pratiqués</div>
 <div class="row"><span class="sp" style="width:34px;height:34px;color:#4A7C59">{IC['climbing-sport']}</span><div class="t"><b>Escalade · ×29</b><small>6a confirmé par 7 partenaires</small></div><span class="chip ok">{li('check',18,'#1E6B45',3)}confirmé</span></div>
 <div class="row"><span class="sp" style="width:34px;height:34px;color:#4A7C59">{IC['ski-touring']}</span><div class="t"><b>Ski de rando · ×11</b><small>Intermédiaire · déclaré</small></div></div>
 <div class="row"><span class="sp" style="width:34px;height:34px;color:#E11D48">{IC['trail-running']}</span><div class="t"><b>Trail · ×6</b><small>Confirmé · 1 200 m D+</small></div></div></div>
<div class="card alt"><div class="sec">Ses partenaires disent</div>
 <div style="display:flex;flex-wrap:wrap;gap:10px;margin-top:16px"><span class="chip">Ponctuelle <b style="color:{GREEN}">38</b></span><span class="chip">Préparée <b style="color:{GREEN}">17</b></span><span class="chip">Prudente <b style="color:{GREEN}">12</b></span><span class="chip">Conciliante <b style="color:{GREEN}">9</b></span></div></div>
<div class="card alt"><div class="sec">Badges</div>
 <div style="display:flex;gap:10px;margin-top:16px">{"".join(f'<div style="flex:1;background:#FFF;border-radius:16px;padding:12px;text-align:center"><div style="font-size:30px">{e}</div><div style="font-size:17px;font-weight:700;margin-top:4px">{t}</div></div>' for e,t in [('🏔️','Encordée ×25'),('🌅','Lève-tôt'),('🧭','Organisatrice')])}</div></div>
{tabbar(3)}'''
extra=callout(26,960,li('pin',50,INK),'Présence','vérifiée sur place, sortie après sortie','left',212)+callout(838,1240,li('users',50,INK),'Niveau','confirmé par ceux qui ont grimpé avec elle','right',212)
out['5-confiance']=screen('Des inconnus, oui.<br>Des inconnus fiables.','Pas de notes, pas de classement. Une fiabilité qui se construit dehors, et des niveaux confirmés par les partenaires.',body,extra)

# 6 — pros
body=f'''<div style="height:290px;background:url({PH(9)}) center/cover;position:relative"><div style="position:absolute;left:24px;top:66px;width:50px;height:50px;border-radius:50%;background:#FFF;display:flex;align-items:center;justify-content:center;font-size:28px">‹</div>
 <div style="position:absolute;left:24px;bottom:18px;background:#2563EB;color:#FFF;border-radius:999px;padding:6px 14px;font-size:17px;font-weight:800;letter-spacing:1px">PRO</div></div>
<div style="padding:18px 28px 6px"><div style="font-size:32px;font-weight:800">Vertige Canyon</div><div style="font-size:21px;color:{SEC}">Moniteurs canyoning · L'Argentière-la-Bessée</div>
 <div style="display:flex;align-items:center;gap:8px;margin-top:8px;font-size:21px">{li('star',22,'#FBBF24')}<b>4,9</b><span style="color:{SEC}">· 24 avis · « Pédagogues et super pros »</span></div>
 <div style="display:flex;gap:10px;margin-top:16px"><span class="chip">{li('route',20)}Itinéraire</span><span class="chip">{li('phone',20)}Appeler</span><span class="chip">{li('msg',20)}Contacter</span></div></div>
<div style="padding:18px 28px 10px;font-size:19px;font-weight:800;letter-spacing:1px;color:{SEC}">SORTIES ENCADRÉES</div>
<div class="card alt"><div class="row" style="margin:0"><div class="av" style="background:#2563EB;color:#FFF">{sp('canyoning',30)}</div><div class="t"><b>Initiation · canyon du Fournel</b><small>dim. 27 juil. · 9h · 4 h · tous niveaux</small></div><div style="text-align:right"><b style="font-size:26px">55 €</b><div style="font-size:16px;color:{SEC}">/ pers</div></div></div>
 <div style="display:flex;justify-content:space-between;align-items:center;margin-top:14px"><span class="chip ok">4 places</span><span class="gp">Réserver</span></div></div>
<div class="card alt"><div class="row" style="margin:0"><div class="av" style="background:#2563EB;color:#FFF">{sp('canyoning',30)}</div><div class="t"><b>Sportif · Rif Bel intégral</b><small>sam. 2 août · 8h · 6 h · bons nageurs</small></div><div style="text-align:right"><b style="font-size:26px">85 €</b><div style="font-size:16px;color:{SEC}">/ pers</div></div></div>
 <div style="display:flex;justify-content:space-between;align-items:center;margin-top:14px"><span class="chip ok">2 places</span><span class="gp">Réserver</span></div></div>
<div class="card alt"><div class="row" style="margin:0"><div class="av" style="background:#4A7C59;color:#FFF">{sp('via-ferrata',30)}</div><div class="t"><b>Via ferrata des Vigneaux</b><small>mer. 30 juil. · 14h · 3 h · dès 12 ans</small></div><div style="text-align:right"><b style="font-size:26px">45 €</b><div style="font-size:16px;color:{SEC}">/ pers</div></div></div></div>
{tabbar(0)}'''
extra=callout(26,1000,'<div style="width:60px;height:60px;border-radius:50%;background:#FFF;border:4px solid #2563EB;display:flex;align-items:center;justify-content:center;color:#2563EB">'+sp('canyoning',34,'#2563EB')+'</div>','Épinglés','sur la même carte que les sorties entre passionnés','left',212)+callout(838,1300,li('cal',50,INK),'Réserve','dans l\'app, à la date qui t\'arrange','right',212)
out['6-pros']=screen('Guides et moniteurs,<br>sur la même carte.','Leurs sorties encadrées, avec photos, tarifs et agenda. Tu choisis l\'activité, tu dis où tu seras, tu réserves.',body,extra)

for k,h in out.items(): open(f'{S}/out/{k}.html','w').write(h)
print(' '.join(out))
