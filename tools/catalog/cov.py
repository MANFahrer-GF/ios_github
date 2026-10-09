import re,csv,json,sys
import os as _os
REPO=_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))))
S=_os.path.join(REPO,'tools','catalog','data')+'/'
src=open(REPO+'/TonneCore/Sources/TonneCore/Providers/CatalogRegions.swift',encoding='utf-8').read()
part=src[src.index('entryDistricts'):]
cov=set(); part=part[:part.find('localEntries')]
for line in part.split('\n'):
    m=re.match(r'\s*"((?:[^"\\]|\\.)*)": \[(.*)\],',line)
    if m and not m.group(1).startswith(('heimatInfo:','icsURL:')): cov|=set(re.findall(r'"((?:[^"\\]|\\.)*)"',m.group(2)))
rows=list(csv.DictReader(open(S+'geo/gemeinden.csv',encoding='utf-8-sig'),delimiter=';'))
kr={}
for r in rows: kr[r['krs_name']]=r['lan_name']
missing=sorted([k for k in kr if k not in cov], key=lambda k:(kr[k],k))
bad=[c for c in cov if c not in kr]
print('Kreise',len(kr),'abgedeckt',len(kr)-len(missing),'fehlend',len(missing))
if bad: print('UNBEKANNT',bad)
loc=src[src.index('localEntries'):src.index('districtStates')]
lk={}
for line in loc.split('\n'):
    m=re.match(r'\s*"((?:[^"\\]|\\.)*)": \[(.*)\],',line)
    if m:
        for x in re.findall(r'"((?:[^"\\]|\\.)*)"',m.group(2)):
            k,g=x.split('|',1)
            if k not in kr: print('UNBEKANNT LOKAL',x)
            lk.setdefault(k,set()).add(g)
gems={}
# Gemeindefreie Gebiete (meist unbewohnte Forste) zählen wie in der App nicht mit
for r in rows:
    if r['gem_type']!='Gemeindefreies Gebiet': gems.setdefault(r['krs_name'],set()).add(r['gem_name_short'])
full=[k for k in missing if k in lk and gems[k]<=lk[k]]
missing=[k for k in missing if k not in full]
print('voll über Gemeinde-Einträge:', full, '-> fehlend jetzt', len(missing))
print('davon nur einzelne Gemeinden:', len([k for k in missing if k in lk]))
if '-v' in sys.argv:
    for k in missing: print(kr[k],'|',k, ('| nur: '+', '.join(sorted(lk[k]))) if k in lk else '')
json.dump(missing,open(S+'../missing_now.json','w'),ensure_ascii=False,indent=0)
