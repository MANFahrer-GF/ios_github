import re, json, csv, ast
import os as _os
REPO=_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))))
S=_os.path.join(REPO,'tools','catalog','data')+'/'
CAT=REPO+'/TonneCore/Sources/TonneCore/Providers/Catalog.swift'
src=open(CAT,encoding='utf-8').read()
# git_reset: Generator immer auf dem Stand ohne generierte Einträge ausführen (Marker unten)
if '// GENERATED-START' in src:
    a=src.index('        // GENERATED-START'); b=src.index('        // GENERATED-END\n')+len('        // GENERATED-END\n'); src=src[:a]+src[b:]

def q(s): return '"'+s.replace('\\','\\\\').replace('"','\\"')+'"'
def norm(s):
    s=s.lower().replace('ä','ae').replace('ö','oe').replace('ü','ue').replace('ß','ss')
    # Bindestriche bleiben Teil des Worts: „Alzey-Worms“ ist nicht „Worms“
    s=re.sub(r'[^a-z0-9-]+',' ',s); return ' '+s.strip()+' '

# --- vorhandene Einträge: kaputten ALBA-Eintrag entfernen
src=re.sub(r'\n\s*CatalogEntry\(kind: \.abfallIOLegacy, serviceKey: "9583a2fa1df97ed95363382c73b41b1b", title: "ALBA Berlin"[^\n]*', '', src)

# Im Live-Gesamttest (Oktober 2026) dauerhaft tot; Ersatz über die AbfallPlus-App
DEAD_TITLES = [
 ('abfallAppNet','Landkreis Böblingen'),
 ('abfallIOGraphQL','Abfallwirtschaft Landkreis Böblingen'),
 ('abfallIOGraphQL','KELL Kommunalentsorgung Landkreis Leipzig GmbH'),
 ('abfallIOLegacy','AWG Abfallwirtschaft Landkreis Calw'),
 ('abfallIOLegacy','Abfallwirtschaft Landkreis Freudenstadt'),
 ('abfallIOLegacy','Abfallwirtschaft Landkreis Kitzingen'),
 ('abfallIOLegacy','Abfallwirtschaft Landkreis Landsberg am Lech'),
 ('abfallIOLegacy','Göttinger Entsorgungsbetriebe'),
 ('abfallIOLegacy','Landkreis Bayreuth'),
 ('abfallIOLegacy','Landkreis Calw'),
 ('abfallIOLegacy','Landkreis Heilbronn'),
 ('abfallIOLegacy','Landkreis Limburg-Weilburg'),
 ('abfallIOLegacy','Landkreis Ostallgäu'),
 ('abfallIOLegacy','Landkreis Rottweil'),
 ('abfallIOLegacy','Landkreis Sigmaringen'),
 ('abfallIOLegacy','Landratsamt Traunstein'),
 ('abfallIOLegacy','VIVO Landkreis Miesbach'),
 ('abfallnavi','Gemeinde Roetgen'),
]
DEAD_APPS = {'de.k4systems.unterallgaeu','de.k4systems.willkommen'}
for kind,title in DEAD_TITLES:
    pat = r'\n\s*CatalogEntry\(kind: \.'+kind+r', serviceKey: "[^"]*", title: "'+re.escape(title)+r'"[^\n]*'
    src, n = re.subn(pat, '', src)
    if n != 1: print('WARN not removed', kind, title, n)
new=[]
svc=json.load(open(S+'hacs/supported_services.json',encoding='utf-8'))
special={'de.albagroup.app':'ALBA','de.abfallwecker':'Abfall+ Wecker','de.k4systems.regioentsorgung':'Regio Entsorgung'}
# Live ermittelte Gemeindelisten (Oktober 2026) – statt Firmennamen in supported_services.json
AP_LIVE={}
for line in open(S+'gapres/ap_places.txt',encoding='utf-8'):
    m=re.match(r"== (\S+) .* n=\d+ (\[.*\])$",line.strip())
    if m: AP_LIVE[m.group(1)]=[x for x in ast.literal_eval(m.group(2)) if len(x)>2]
AP_NAMES={'de.remondis.rheinland':'Remondis','de.k4systems.muellalarm':'Schönmackers Müllalarm','de.drekopf.abfallplaner':'Drekopf',
          'de.enzkreis.app':'Enzkreis','de.abfallplus.bodenseekreis':'Bodenseekreis','de.k4systems.abfallhr':'ALF Lahn-Fulda / Schwalm-Eder-Kreis',
          'de.k4systems.abfallappol':'Oldenburg (Stadt)','de.edg.abfallapp':'Dortmund (EDG)'}
for app in ('de.enzkreis.app','de.abfallplus.bodenseekreis'):
    svc.setdefault(app,[AP_NAMES[app]])
for app,regions in svc.items():
    if not regions or app in DEAD_APPS: continue
    if app in AP_NAMES:
        live=AP_LIVE.get(app,[])
        name=AP_NAMES[app]
        regions=[name]+[x for x in live if x!=name]
        title=name if len(live)<=1 else f"{name} ({', '.join(live[:3])}{' …' if len(live)>3 else ''})"
        if app=='de.edg.abfallapp': regions=['Dortmund','EDG']
        if app=='de.k4systems.abfallappol': regions=['Oldenburg','Oldenburg (Oldb)']
        new.append(('abfallPlusApp',app,title,'https://www.abfallplus.de/',regions)); continue
    if app in special: title=f"{special[app]} ({', '.join(regions[:3])}{' …' if len(regions)>3 else ''})"
    elif len(regions)==1: title=regions[0]
    else: title=', '.join(regions[:3])+(' …' if len(regions)>3 else '')
    new.append(('abfallPlusApp',app,title,'https://www.abfallplus.de/',regions))
new.append(('bsr','berlin','Berlin (BSR, inkl. Wertstofftonne)','https://www.bsr.de/',['Berlin','Mitte','Friedrichshain-Kreuzberg','Pankow','Charlottenburg-Wilmersdorf','Spandau','Steglitz-Zehlendorf','Tempelhof-Schöneberg','Neukölln','Treptow-Köpenick','Marzahn-Hellersdorf','Lichtenberg','Reinickendorf','ALBA','Berlin Recycling']))
lwl_places=[x for x in open(S+'gemos/lwl_places.txt',encoding='utf-8').read().split('\n') if x]
new.append(('gemosWasteBox','lwl','Ludwigslust-Parchim (ALP)','https://alp-lup.de/',lwl_places+['Ludwigslust','Parchim','Boizenburg','Hagenow','Lübtheen','Lübz','Crivitz','Sternberg','Plau am See','Grabow','Dömitz','Neustadt-Glewe','Brüel','Goldberg','Zarrentin','Wittenburg']))
new.append(('awsh','awsh','Abfallwirtschaft Südholstein (AWSH)','https://www.awsh.de/',['Herzogtum Lauenburg','Stormarn','Lauenburg','Mölln','Ratzeburg','Geesthacht','Schwarzenbek','Ahrensburg','Bad Oldesloe','Reinbek','Glinde','Bargteheide']))
lob=open(S+'hacs/src_lobbe_app.py',encoding='utf-8').read()
lob_places=re.findall(r'^\s+"([^"]+)",', lob[lob.index('PLACES'):lob.index('EXTRA_INFO')], re.M)
new.append(('lobbe','lobbe','Lobbe (Sauerland, Märkischer Kreis, Waldeck-Frankenberg …)','https://lobbe.app/',lob_places))
nb=open(S+'hacs/src_nerdbridge_de.py',encoding='utf-8').read()
nb_towns=re.findall(r'"title": "([^"]+)"', nb)
new.append(('nerdbridge','northeim','Landkreis Northeim','https://abfall.nerdbridge.de/',['Northeim','Einbeck','Bad Gandersheim','Uslar','Dassel','Moringen','Hardegsen','Bodenfelde','Kalefeld','Katlenburg-Lindau','Nörten-Hardenberg']+nb_towns))
# Sitepark IES (Kreis-/Stadtportale, z. B. Landkreis Peine) – Orte live ermittelt
sp_places=json.load(open(S+'peine/sitepark_places.json',encoding='utf-8'))
SITEPARK_DISTRICTS={}
for t in json.load(open(S+'peine/sitepark_tenants.json',encoding='utf-8')):
    pl=t['extra']+[p for p in sp_places.get(t['id'],[]) if p not in t['extra']]
    new.append(('sitepark',t['id'],t['title'],t['base']+'/',pl))
    if t.get('district'): SITEPARK_DISTRICTS[t['id']]=[t['district']]
# Insert IT (Großstädte)
INSERT_IT=[('Mannheim','Mannheim','https://www.insert-it.de/BmsAbfallkalenderMannheim',['Mannheim'],['Stadtkreis Mannheim']),
 ('Kassel','Kassel (Stadtreiniger)','https://www.insert-it.de/BmsAbfallkalenderKassel',['Kassel'],['Kreisfreie Stadt Kassel']),
 ('Luebeck','Lübeck (Entsorgungsbetriebe)','https://www.insert-it.de/BmsAbfallkalenderLuebeck',['Lübeck','Travemünde'],['Kreisfreie Stadt Lübeck']),
 ('Krefeld','Krefeld (GSAK)','https://www.insert-it.de/BmsAbfallkalenderKrefeld',['Krefeld'],['Kreisfreie Stadt Krefeld']),
 ('Herne','Herne (Entsorgung Herne)','https://www.insert-it.de/BmsAbfallkalenderHerne',['Herne','Wanne-Eickel'],['Kreisfreie Stadt Herne']),
 ('Offenbach','Offenbach am Main (ESO)','https://www.insert-it.de/BmsAbfallkalenderOffenbach',['Offenbach','Offenbach am Main'],['Kreisfreie Stadt Offenbach am Main']),
 ('Hattingen','Hattingen','https://www.insert-it.de/BmsAbfallkalenderHattingen',['Hattingen'],[])]
MANUAL_EXTRA={}
for key,title,web,places,districts in INSERT_IT:
    new.append(('insertIT',key,title,web,places))
    if districts: MANUAL_EXTRA[('insertIT',key)]=districts
# Müllabfuhr Deutschland (Thüringen, Sachsen-Anhalt)
mad=json.load(open(S+'peine/mad_places.json',encoding='utf-8'))
MAD={'7':('Landkreis Hildburghausen',['Hildburghausen','Eisfeld','Themar','Schleusingen','Römhild','Heldburg'],'Landkreis Hildburghausen'),
     '31':('Landkreis Wittenberg',['Wittenberg','Lutherstadt Wittenberg','Jessen','Zahna-Elster'],'Landkreis Wittenberg'),
     '40':('Burgenlandkreis',['Naumburg','Weißenfels','Zeitz','Hohenmölsen','Lützen','Teuchern','Nebra'],'Landkreis Burgenlandkreis'),
     '39':('Dessau-Roßlau',['Dessau','Roßlau','Dessau-Roßlau'],'Kreisfreie Stadt Dessau-Roßlau'),
     '194':('Weimarer Land',['Apolda','Bad Berka','Blankenhain','Bad Sulza','Kranichfeld'],'Landkreis Weimarer Land'),
     '12':('Landkreis Sömmerda',['Sömmerda','Kölleda','Weißensee','Buttstädt'],'Landkreis Sömmerda'),
     '35':('Saalekreis',['Merseburg','Leuna','Querfurt','Bad Dürrenberg','Landsberg','Wettin-Löbejün','Teutschenthal'],'Landkreis Saalekreis')}
for mid,(title,extra,district) in MAD.items():
    pl=extra+[p for p in mad.get(mid,{}).get('places',[]) if p not in extra and not p.startswith('(')]
    new.append(('muellabfuhrDeutschland',mid,title+' (Müllabfuhr Deutschland)','https://portal.muellabfuhr-deutschland.de/',pl))
    MANUAL_EXTRA[('muellabfuhrDeutschland',mid)]=[district]
# Heimat-Info: nur Gemeinden mit Abfallkalender (live ermittelt)
for slug,name,plz,n in json.load(open(S+'peine/hi_garbage.json',encoding='utf-8')):
    name=name.strip()
    new.append(('heimatInfo',slug,name+' (Heimat-Info)','https://heimat-info.de/',[name]+plz))
# Neue Kennungen bestehender Plattformen (live geprüft)
new.append(('awido','awhas','Abfallwirtschaft Landkreis Haßberge','https://www.awhas.de/',['Haßberge','Haßfurt','Ebern','Eltmann','Hofheim in Unterfranken','Königsberg in Bayern','Zeil am Main']))
new.append(('awido','weiden','Stadt Weiden in der Oberpfalz','https://www.weiden.de/',['Weiden','Weiden in der Oberpfalz']))
new.append(('gemosWasteBox','eaw','Mansfeld-Südharz (EAW Sangerhausen)','https://eaw.wastebox.gemos-management.de/',['Mansfeld-Südharz','Sangerhausen','Eisleben','Lutherstadt Eisleben','Hettstedt','Mansfeld','Allstedt','Arnstein','Gerbstedt','Seegebiet Mansfelder Land','Südharz','Kelbra']))
new.append(('gemosWasteBox','apm','Potsdam-Mittelmark (APM)','https://apm.wastebox.gemos-management.de/',['Potsdam-Mittelmark','Bad Belzig','Werder','Teltow','Kleinmachnow','Stahnsdorf','Beelitz','Treuenbrietzen','Niemegk','Michendorf','Schwielowsee','Wiesenburg']))
new.append(('gemosWasteBox','abikw','Anhalt-Bitterfeld (ABIKW)','https://www.abikw.de/',['Anhalt-Bitterfeld','Köthen','Köthen (Anhalt)','Bitterfeld-Wolfen','Zerbst','Zerbst/Anhalt','Sandersdorf-Brehna','Raguhn-Jeßnitz','Aken','Aken (Elbe)','Südliches Anhalt','Zörbig','Muldestausee','Osternienburger Land']))
new.append(('abfallAppNet','brandenburg','Brandenburg an der Havel','https://brandenburg.abfall-app.net/',['Brandenburg an der Havel','Brandenburg']))
bp=json.load(open(S+'peine/bp_places.json',encoding='utf-8'))
for key,title,web in [('alb_donau','Alb-Donau-Kreis','https://www.aw-adk.de/'),('cochem_zell','Landkreis Cochem-Zell','https://www.cochem-zell-online.de/'),
                      ('biedenkopf','MZV Biedenkopf','https://mzv-biedenkopf.de/'),('bedburg','Bedburg','https://www.bedburg.de/'),
                      ('klevestadt','Kleve (USK)','https://buerger-app-klevestadt.azurewebsites.net/calendar'),('neu_ulm','Landkreis Neu-Ulm (Illertissen, Weißenhorn …)','https://www.awb-neu-ulm.de/')]:
    new.append(('buergerportal',key,title,web,bp.get(key,[])))
new.append(('magdeburg','magdeburg','Magdeburg (SAB)','https://www.magdeburg.de/',['Magdeburg']))
# Volle Gemeindenamen, wo der Kurzname mehrdeutig ist („Hofheim“ gibt es in Hessen und Unterfranken)
MAK_FULL={'hofheim':'Hofheim am Taunus','bad-soden':'Bad Soden am Taunus','hochheim':'Hochheim am Main','sulzbach-taunus':'Sulzbach (Taunus)'}
for title,host in json.load(open(S+'hacs/mak_hosts.json',encoding='utf-8')):
    if not host: continue
    sub=re.sub(r'^https://([^.]+)\..*$',r'\1',host.rstrip('/'))
    full=MAK_FULL.get(sub)
    new.append(('icsURL',host.rstrip('/'),f"{full or title} (Mein-Abfallkalender)",host,[full,title] if full else [title]))

apiv2=json.load(open(S+'peine/apiv2_places.json',encoding='utf-8'))
for key,title,web,extra in [('steinburg','Kreis Steinburg (Itzehoe, Glückstadt …)','https://abfall.steinburg.de/',['Steinburg','Itzehoe','Glückstadt','Kellinghusen','Wilster']),
                            ('awd','Abfallwirtschaft Dithmarschen (AWD)','https://www.awd-online.de/',['Dithmarschen','Heide','Brunsbüttel','Meldorf','Marne','Büsum','Wesselburen']),
                            ('awr','Abfallwirtschaft Rendsburg-Eckernförde (AWR)','https://www.awr.de/',['Rendsburg-Eckernförde','Rendsburg','Eckernförde','Büdelsdorf','Kronshagen','Altenholz','Nortorf','Gettorf','Hohenwestedt']),
                            ('asf','Abfallwirtschaft Schleswig-Flensburg (ASF)','https://www.asf-online.de/',['Schleswig-Flensburg','Schleswig','Kappeln','Harrislee','Glücksburg','Handewitt','Tarp','Satrup']),
                            ('stade','Landkreis Stade','https://www.landkreis-stade.de/',['Stade','Buxtehude','Drochtersen','Jork','Harsefeld','Horneburg'])]:
    pl=extra+[p for p in apiv2.get(key,[]) if p not in extra]
    new.append(('awsh',key,title,web,pl))
# Mein-Abfallkalender: weitere Gemeinden (Vogelsberg, Wetterau, Kreis Offenbach), Oktober 2026 live geprüft
MAK_EXTRA=[('Alsfeld','alsfeld'),('Antrifttal','antrifttal'),('Feldatal','feldatal'),('Freiensteinau','freiensteinau'),('Mücke','gemeinde-muecke'),
 ('Gemünden (Felda)','gemuenden-felda'),('Grebenau','grebenau'),('Grebenhain','grebenhain'),('Herbstein','herbstein'),('Homberg (Ohm)','homberg'),
 ('Lauterbach (Hessen)','lauterbach-hessen'),('Lautertal (Vogelsberg)','lautertal-vogelsberg'),('Romrod','romrod'),('Schlitz','schlitz'),('Schotten','schotten'),
 ('Schwalmtal','schwalmtal-hessen'),('Kirtorf','stadt-kirtorf'),('Ulrichstein','ulrichstein'),
 ('Münzenberg','muenzenberg'),('Reichelsheim (Wetterau)','stadt-reichelsheim'),('Altenstadt','altenstadt'),('Bad Nauheim','bn'),('Büdingen','stadt-buedingen'),
 ('Gedern','gedern'),('Glauburg','glauburg'),('Kefenrod','gemeinde-kefenrod'),('Nidda','nidda'),('Ober-Mörlen','ober-moerlen'),('Ranstadt','ranstadt'),('Butzbach','stadt-butzbach'),
 ('Dreieich','dreieich'),('Neu-Isenburg','neu-isenburg'),
 ('Sulzbach (Taunus)','sulzbach-taunus'),('Bad Soden am Taunus','bad-soden'),('Hochheim am Main','hochheim'),('Hofheim am Taunus','hofheim')]
have={k for _,k,*__ in new}
for title,sub in MAK_EXTRA:
    host=f'https://{sub}.mein-abfallkalender.online'
    if host not in have: new.append(('icsURL',host,f"{title} (Mein-Abfallkalender)",host+'/',[title]))

# Ergebnisse der Portal-Familien (je Datei eine Liste von Betreibern, live geprüft)
import glob, os
for f in sorted(glob.glob(S+'catalog_additions/*.json')):
    swift=REPO+'/TonneCore/Sources/TonneCore/Providers/'+os.path.basename(f)[:-5]+'.swift'
    if not os.path.exists(swift) or 'Noch nicht verfügbar.", "Not available yet."' in open(swift,encoding='utf-8').read():
        print('SKIP (Provider noch nicht zusammengeführt):', os.path.basename(f)); continue
    for e in json.load(open(f,encoding='utf-8')):
        new.append((e['kind'],e['key'],e['title'],e.get('website') or '',e.get('places') or []))
        if e.get('districts'): MANUAL_EXTRA[(e['kind'],e['key'])]=list(e['districts'])

lines=[]
for kind,key,title,web,places in new:
    lines.append(f'        CatalogEntry(kind: .{kind}, serviceKey: {q(key)}, title: {q(title)}, website: {q(web)}, places: [{", ".join(q(p) for p in places)}]),')
marker='    ]\n\n    public static var count'
assert marker in src
src=src.replace(marker,'        // GENERATED-START\n'+'\n'.join(lines)+'\n        // GENERATED-END\n'+marker,1)
open(CAT,'w',encoding='utf-8').write(src)

# --- Gemeinde-Index und Zuordnung Eintrag → Kreis
rows=list(csv.DictReader(open(S+'geo/gemeinden.csv',encoding='utf-8-sig'),delimiter=';'))
kreise={}
for r in rows:
    kreise.setdefault(r['krs_name'],set()).add(r['gem_name_short'])
muni={}
for r in rows:
    muni.setdefault(r['gem_name_short'],set()).add(r['krs_name'])
MUNI_KINDS={'abfallPlusApp','icsURL','heimatInfo','insertIT'}
# Gleichnamige Orte: hier stimmt die eindeutige Zuordnung nicht
NO_GENERIC={('icsURL','https://langen.mein-abfallkalender.online')}
kreis_land={r['krs_name']:r['lan_name'] for r in rows}
def short(k):
    for p in ['Kreisfreie Stadt ','Landkreis ','Stadtkreis ','Regionalverband ','Städteregion ','Kreis ','Region ']:
        if k.startswith(p): return k[len(p):], p.strip()
    return k,''
entries=re.findall(r'CatalogEntry\(kind: \.(\w+), serviceKey: "((?:[^"\\]|\\.)*)", title: "((?:[^"\\]|\\.)*)"(?:, website: (?:"(?:[^"\\]|\\.)*"|nil))?(?:, places: \[([^\]]*)\])?\)', src)
mapping={}
for kind,key,title,places in entries:
    pl=re.findall(r'"((?:[^"\\]|\\.)*)"',places or '')
    text=norm(title) if kind not in ('abfallPlusApp','icsURL','lobbe','nerdbridge','gemosWasteBox','awsh','bsr','sitepark','insertIT','muellabfuhrDeutschland','heimatInfo','buergerportal','magdeburg','gemosWasteBox') else '  '
    def strip_pre(x):
        for pre in ['Landkreis ','Kreis ','Stadt ','LK ','Region ','Stadtkreis ']:
            if x.startswith(pre): return x[len(pre):]
        return x
    exact=({norm(x).strip() for x in pl} | {norm(strip_pre(x)).strip() for x in pl}) if kind not in ('lobbe','icsURL','sitepark','insertIT','muellabfuhrDeutschland','heimatInfo','buergerportal','magdeburg') else set()
    if kind=='abfallPlusApp' and key in AP_NAMES: exact=set()   # Gemeindelisten, keine Kreisnamen
    hits=[]
    for k in kreise:
        sh,prefix=short(k)
        n=norm(sh)
        if len(n.strip())<4: continue
        if n in text or n.strip() in exact or norm(k).strip() in exact:
            # Stadt vs. Landkreis gleichen Namens unterscheiden
            t=title.lower()
            if prefix=='Kreisfreie Stadt' and ('landkreis' in t or 'kreis ' in t or t.startswith('lk')) and 'stadt' not in t: continue
            if prefix in ('Landkreis','Kreis') and ('stadt ' in t and 'landkreis' not in t and 'kreis' not in t.replace('landkreis','')): continue
            hits.append(k)
    if kind=='lobbe':
        allowed={'Hessen','Nordrhein-Westfalen'}
        for r in rows:
            if r['lan_name'] in allowed and r['gem_name_short'] in pl: hits.append(r['krs_name'])
    if kind=='gemosWasteBox' and key=='lwl': hits=['Landkreis Ludwigslust-Parchim']
    if kind=='awsh': hits={'awsh':['Kreis Herzogtum Lauenburg','Kreis Stormarn'],'steinburg':['Kreis Steinburg'],'awd':['Kreis Dithmarschen'],'awr':['Kreis Rendsburg-Eckernförde'],'asf':['Kreis Schleswig-Flensburg'],'stade':['Landkreis Stade']}.get(key,[])
    if kind=='nerdbridge': hits=['Landkreis Northeim']
    if kind=='bsr': hits=['Kreisfreie Stadt Berlin']
    if kind=='sitepark': hits=SITEPARK_DISTRICTS.get(key,[])
    # Feste Zuordnungen, wo der Kreisname anders geschrieben ist als im Entsorgernamen
    MANUAL={
        ('abfallPlusApp','de.k4systems.neustadtaisch'): ['Landkreis Neustadt a.d.Aisch-Bad Windsheim'],
        ('abfallPlusApp','de.k4systems.kufiapp'): ['Landkreis Wunsiedel i.Fichtelgebirge'],
        ('abfallPlusApp','de.k4systems.abfallappzak'): ['Kreisfreie Stadt Kempten (Allgäu)','Landkreis Oberallgäu','Landkreis Lindau (Bodensee)'],
        ('awido','awb-ak'): ['Landkreis Altenkirchen (Westerwald)'],
        # Recherche Oktober 2026 (Ost/Bayern): Verbände, die mehrere Kreise abdecken
        ('awido','wgv'): ['Landkreis Bad Tölz-Wolfratshausen'],
        ('abfallPlusApp','de.k4systems.zawdw'): ['Landkreis Freyung-Grafenau','Landkreis Passau','Landkreis Deggendorf','Landkreis Regen','Kreisfreie Stadt Passau'],
        ('awido','neustadt'): ['Landkreis Neustadt a.d.Waldnaab'],
        ('abfallPlusApp','de.zawsr'): ['Landkreis Straubing-Bogen','Kreisfreie Stadt Straubing'],
        ('awido','awv-nordschwaben'): ['Landkreis Dillingen a.d.Donau','Landkreis Donau-Ries'],
        ('awido','awv-isar-inn'): ['Landkreis Rottal-Inn','Landkreis Dingolfing-Landau'],
        ('abfallPlusApp','de.k4systems.udb'): ['Landkreis Burgenlandkreis'],
        ('awido','zaso'): ['Landkreis Saale-Orla-Kreis','Landkreis Saalfeld-Rudolstadt'],
        ('abfallPlusApp','de.k4systems.aevapp'): ['Landkreis Elbe-Elster','Landkreis Oberspreewald-Lausitz'],
        ('awido','awhas'): ['Landkreis Haßberge'],
        ('awido','weiden'): ['Kreisfreie Stadt Weiden i.d.OPf.'],
        ('gemosWasteBox','eaw'): ['Landkreis Mansfeld-Südharz'],
        ('gemosWasteBox','apm'): ['Landkreis Potsdam-Mittelmark'],
        ('gemosWasteBox','abikw'): ['Landkreis Anhalt-Bitterfeld'],
        ('abfallAppNet','brandenburg'): ['Kreisfreie Stadt Brandenburg an der Havel'],
        ('buergerportal','alb_donau'): ['Landkreis Alb-Donau-Kreis'],
        ('buergerportal','cochem_zell'): ['Landkreis Cochem-Zell'],
        ('magdeburg','magdeburg'): ['Kreisfreie Stadt Magdeburg'],
        ('buergerportal','biedenkopf'): ['Landkreis Marburg-Biedenkopf'],
        ('buergerportal','bedburg'): ['Kreis Rhein-Erft-Kreis'],
        ('buergerportal','klevestadt'): ['Kreis Kleve'],
        ('buergerportal','neu_ulm'): ['Landkreis Neu-Ulm'],
        # Recherche Oktober 2026 (West/Nord): Name im Katalog anders geschrieben
        ('awido','rmk'): ['Landkreis Rems-Murr-Kreis'],
        ('awido','awld'): ['Landkreis Lahn-Dill-Kreis'],
        ('jumomind','rhe'): ['Landkreis Rhein-Hunsrück-Kreis'],
        ('jumomind','ben'): ['Landkreis Grafschaft Bentheim'],
        ('abfallnavi','frankenthal'): ['Kreisfreie Stadt Frankenthal (Pfalz)'],
        ('abfallnavi','aachen'): ['Kreis Städteregion Aachen'],
        ('abfallPlusApp','de.k4systems.regioentsorgung'): ['Kreis Städteregion Aachen'],
        ('abfallnavi','wml2'): ['Kreis Borken'],
        ('abfallnavi','bav'): ['Kreis Rheinisch-Bergischer Kreis','Kreis Oberbergischer Kreis'],
        ('abfallnavi','aw-bgl2'): ['Kreis Rheinisch-Bergischer Kreis'],
        ('abfallPlusApp','de.k4systems.abfallhr'): ['Landkreis Schwalm-Eder-Kreis'],
        ('abfallPlusApp','de.k4systems.abfallappol'): ['Kreisfreie Stadt Oldenburg (Oldb)'],
        ('abfallPlusApp','de.edg.abfallapp'): ['Kreisfreie Stadt Dortmund'],
        ('abfallPlusApp','de.enzkreis.app'): ['Landkreis Enzkreis'],
        ('abfallPlusApp','de.abfallplus.bodenseekreis'): ['Landkreis Bodenseekreis'],
        ('muellmax','Evs'): ['Landkreis Saarpfalz-Kreis','Landkreis Merzig-Wadern','Landkreis Neunkirchen','Landkreis Saarlouis','Landkreis Regionalverband Saarbrücken','Landkreis St. Wendel'],
        ('muellmax','Efb'): ['Landkreis Wetteraukreis'],
        ('awido','ebu'): ['Stadtkreis Ulm'],
        ('awido','zv-muc-so'): ['Landkreis München'],
        ('abfallPlusApp','de.cmcitymedia.shawaste'): ['Landkreis Schwäbisch Hall'],
        ('icsURL','https://langen.mein-abfallkalender.online'): ['Landkreis Offenbach'],
    }
    hits+=MANUAL.get((kind,key),[])+MANUAL_EXTRA.get((kind,key),[])
    # Orte, die in ganz Deutschland nur einmal vorkommen, eindeutig ihrem Kreis zuordnen
    if kind in MUNI_KINDS and (kind,key) not in NO_GENERIC:
        uniq=[]
        for p in pl:
            ks=muni.get(p) or muni.get(re.sub(r'^(Stadt|Gemeinde|Markt) ','',p))
            if ks and len(ks)==1: uniq.append(next(iter(ks)))
        # Ausreißer (Namensgleichheit in einem anderen Bundesland) verwerfen
        lands={}
        for k in uniq: lands[kreis_land[k]]=lands.get(kreis_land[k],0)+1
        keep={l for l,n in lands.items() if n>=max(1,0.2*len(uniq))}
        hits+=[k for k in uniq if kreis_land[k] in keep]
    if hits: mapping[f"{kind}:{key}:{title}"]=sorted(set(hits))
# --- Gemeinde-genaue Abdeckung: Einträge, die nur einzelne Gemeinden eines Kreises bedienen
def norm_name(x): return norm(re.sub(r'\s*\(.*?\)','',x)).strip()
# Voller Name (mit Klammerzusatz) eindeutig in Deutschland
full_index={}
for n,ks in muni.items():
    for k in ks: full_index.setdefault(norm(n).strip(),set()).add((k,n))
full_unique={key:next(iter(v)) for key,v in full_index.items() if len(v)==1 and len(key)>=4}
# Kurzform ohne Klammer: nur, wenn eindeutig und kein anderer Gemeindename damit beginnt („Freiburg“ ≠ „Freiburg im Breisgau“)
short_index={}
for n,ks in muni.items():
    for k in ks: short_index.setdefault(norm_name(n),set()).add((k,n))
all_norm=sorted(short_index)
def short_unique(key):
    v=short_index.get(key)
    if not v or len(v)!=1 or len(key)<5: return None
    if any(o!=key and o.startswith(key+' ') for o in all_norm[:]): return None
    return next(iter(v))
def lookup(name):
    # Mehrdeutige Kurzform („Langen“ = Emsland oder Hessen, „Frankenthal“ = Pfalz oder Sachsen) nur über den vollen Namen
    if '(' not in name and len(short_index.get(norm_name(name),()))>1: return None
    return full_unique.get(norm(name).strip()) or (short_unique(norm_name(name)) if '(' not in name else None)
LOCAL_KINDS=('heimatInfo','icsURL')
MULTI_CITY_APPS={('jumomind','mymuell')}
# Einzelne Städte mit eigener Kennung, deren Titel nicht eindeutig ist
LOCAL_MANUAL={('jumomind','hom'):[('Landkreis Hochtaunuskreis','Bad Homburg v.d.Höhe')],
              ('jumomind','kbl'):[('Landkreis Offenbach','Langen (Hessen)')]}
# Gemeinde-Einträge mit mehrdeutigem Namen – per PLZ (Heimat-Info) bzw. Seitentitel (Mein-Abfallkalender) geprüft
MAK='https://{}.mein-abfallkalender.online'
for (kind,key),(district,name) in {
    ('heimatInfo','buch'):('Landkreis Neu-Ulm','Buch'), ('heimatInfo','eisingen'):('Landkreis Würzburg','Eisingen'),
    ('heimatInfo','kastl-lauterachtal'):('Landkreis Amberg-Sulzbach','Kastl'), ('heimatInfo','kastl'):('Landkreis Altötting','Kastl'),
    ('heimatInfo','rottenbach'):('Landkreis Erlangen-Höchstadt','Röttenbach'), ('heimatInfo','postbauer-heng'):('Landkreis Neumarkt i.d.OPf.','Postbauer-Heng'),
    ('heimatInfo','rothenfels'):('Landkreis Main-Spessart','Rothenfels'), ('heimatInfo','altenstadt-an-der-waldnaab'):('Landkreis Neustadt a.d.Waldnaab','Altenstadt a.d.Waldnaab'),
    ('heimatInfo','lautertal-oberfranken'):('Landkreis Coburg','Lautertal'), ('heimatInfo','oberschwarzach'):('Landkreis Schweinfurt','Oberschwarzach'),
    ('heimatInfo','ettringen-wertach'):('Landkreis Unterallgäu','Ettringen'), ('heimatInfo','gundelsheim-oberfranken'):('Landkreis Bamberg','Gundelsheim'),
    ('heimatInfo','seebad-loddin'):('Landkreis Vorpommern-Greifswald','Loddin'),
    ('icsURL',MAK.format('stadtbetrieb-wetter')):('Kreis Ennepe-Ruhr-Kreis','Wetter (Ruhr)'), ('icsURL',MAK.format('rodenbach')):('Landkreis Main-Kinzig-Kreis','Rodenbach'),
    ('icsURL',MAK.format('saarlouis')):('Landkreis Saarlouis','Saarlouis'), ('icsURL',MAK.format('wasserburg')):('Landkreis Rosenheim','Wasserburg a.Inn'),
    ('jumomind','sbm'):('Kreis Minden-Lübbecke','Minden'), ('sitepark','muehlenkreis'):('Kreis Minden-Lübbecke','Preußisch Oldendorf'),
    ('sitepark','neunkirchen-siegerland'):('Kreis Siegen-Wittgenstein','Neunkirchen'),
    ('icsURL',MAK.format('schwalmtal-hessen')):('Landkreis Vogelsbergkreis','Schwalmtal'), ('icsURL',MAK.format('altenstadt')):('Landkreis Wetteraukreis','Altenstadt'),
}.items():
    LOCAL_MANUAL.setdefault((kind,key),[]).append((district,name))
local={}; title_hits=[]
for kind,key,title,places in entries:
    eid=f"{kind}:{key}:{title}"
    pl=re.findall(r'"((?:[^"\\]|\\.)*)"',places or '')
    regional=set(mapping.get(eid,[]))
    found=set(LOCAL_MANUAL.get((kind,key),[]))
    if kind in LOCAL_KINDS:
        mapping.pop(eid,None)
        for p in pl:
            for k in regional:
                for g in kreise[k]:
                    if g==p or g.startswith(p+' (') or norm_name(g)==norm_name(p): found.add((k,g))
    # Ortslisten großer Portale enthalten Ortsteile – nur Gemeinde-Einträge und Mehr-Städte-Apps auswerten
    if kind in LOCAL_KINDS or (kind,key) in MULTI_CITY_APPS:
        for p in pl:
            hit=lookup(p)
            if hit and (kind in LOCAL_KINDS or hit[0] not in regional): found.add(hit)
    if kind not in LOCAL_KINDS:
        bare=re.sub(r'^(Stadt|Gemeinde|Markt|Kreisstadt|Große Kreisstadt|Hansestadt|Universitätsstadt) ','',title)
        hit=lookup(bare)
        if hit and hit[0] not in regional:
            found.add(hit); title_hits.append((title,hit))
    if found: local[eid]=sorted(f"{k}|{n}" for k,n in found)
print('lokal', len(local), 'Titeltreffer', len(title_hits))
for th in title_hits: print('  TITEL', th)
print('entries', len(entries), 'mapped', len(mapping))
for k in ['gemosWasteBox:lwl:Ludwigslust-Parchim (ALP)','awsh:awsh:Abfallwirtschaft Südholstein (AWSH)']:
    print(k, mapping.get(k))
print([ (k,v) for k,v in mapping.items() if 'Lüneburg' in k])

gem_lines=[]
for k in sorted(kreise):
    gem_lines.append(k+'|'+','.join(sorted(kreise[k])))
out=['import Foundation','','/// Gemeinden je Landkreis (Quelle: Geo-Referenzdaten Deutschland, opendatasoft) und die Zuordnung',
     '/// der Katalogeinträge zu Landkreisen. So findet die Suche auch Orte, die nicht im Namen eines Entsorgers stehen.',
     'enum CatalogRegions {',
     '    /// Je Zeile: „Landkreis|Gemeinde,Gemeinde,…“',
     '    static let municipalities: String = #"""']
out+=gem_lines
out+=['"""#','','    /// Katalogeintrag (`CatalogEntry.id`) → Landkreise, die er abdeckt.','    static let entryDistricts: [String: [String]] = [']
for k,v in sorted(mapping.items()):
    out.append(f'        {q(k)}: [{", ".join(q(x) for x in v)}],')
out+=['    ]','','    /// Einträge, die nur einzelne Gemeinden bedienen: Eintrag → „Landkreis|Gemeinde“.','    static let localEntries: [String: [String]] = [']
for k,v in sorted(local.items()):
    out.append(f'        {q(k)}: [{", ".join(q(x) for x in v)}],')
out+=['    ]','','    /// Landkreis → Bundesland.','    static let districtStates: [String: String] = [']
for k in sorted(kreise):
    out.append(f'        {q(k)}: {q(kreis_land[k])},')
out+=['    ]','}','']
open(REPO+'/TonneCore/Sources/TonneCore/Providers/CatalogRegions.swift','w',encoding='utf-8').write('\n'.join(out))
