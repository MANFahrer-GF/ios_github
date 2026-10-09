import re,csv,json,collections
import os as _os
REPO=_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))))
S=_os.path.join(REPO,'tools','catalog','data')+'/'
src=open(REPO+'/TonneCore/Sources/TonneCore/Providers/CatalogRegions.swift',encoding='utf-8').read()
cat=open(REPO+'/TonneCore/Sources/TonneCore/Providers/Catalog.swift',encoding='utf-8').read()
titles={f"{k}:{key}:{t}":t for k,key,t in re.findall(r'CatalogEntry\(kind: \.(\w+), serviceKey: "((?:[^"\\]|\\.)*)", title: "((?:[^"\\]|\\.)*)"',cat)}
def block(name,end):
    t=src[src.index(name):src.index(end)]; d={}
    for line in t.split('\n'):
        m=re.match(r'\s*"((?:[^"\\]|\\.)*)": \[(.*)\],',line)
        if m: d[m.group(1)]=re.findall(r'"((?:[^"\\]|\\.)*)"',m.group(2))
    return d
reg=block('entryDistricts','localEntries'); loc=block('localEntries','districtStates')
rows=list(csv.DictReader(open(S+'geo/gemeinden.csv',encoding='utf-8-sig'),delimiter=';'))
land={}; gems=collections.defaultdict(set)
for r in rows: land[r['krs_name']]=r['lan_name']; gems[r['krs_name']].add(r['gem_name_short'])
byk=collections.defaultdict(list); lk=collections.defaultdict(lambda: collections.defaultdict(list))
for e,ds in reg.items():
    if e in titles:
        for d in ds: byk[d].append(titles[e])
for e,ps in loc.items():
    if e in titles:
        for p in ps:
            d,g=p.split('|',1); lk[d][g].append(titles[e])
out=[]
for k in sorted(land,key=lambda k:(land[k],k)):
    if byk[k]: st='ok'
    elif lk[k] and gems[k]<=set(lk[k]): st='ok'
    elif lk[k]: st='teil'
    else: st='fehlt'
    out.append({'land':land[k],'kreis':k,'status':st,'entsorger':sorted(set(byk[k]))[:6],'gemeinden':sorted(lk[k].keys()),'anzahl':len(gems[k])})
json.dump(out,open(S+'../report.json','w'),ensure_ascii=False,indent=0)
c=collections.Counter(o['status'] for o in out); print(c)
