"""Rasterkalender, in denen die Abfallart nur in der Füllfarbe steckt.

cell_kinds:  Farbe der Flächen in der Tageszelle (Stemwede, Rahden: Text = Bezirke, Farbe = Art).
token_kinds: Farbe der Fläche unter jedem Textstück (Liederbach, Sontra) – aus den Vektorflächen
             oder, wenn die PDF keine einfachen Flächen hat (Mainhausen), aus dem gerenderten Bild.
Farben, die in keiner Palette stehen, werden gemeldet statt geraten."""
import common


def classify(col, palette, tol=0.04):
    for ref, name in palette:
        if common.near(col, ref, tol):
            return name
    return None


def cell_fills(doc, cells):
    fills = {p: common.page_fills(doc[p]) for p in {c['page'] for c in cells}}
    for c in cells:
        row = []
        for r, col in fills[c['page']]:
            cy = (r.y0 + r.y1) / 2
            if c['y0'] - 2 <= cy <= c['y1'] + 2 and r.x0 >= c['x0'] - 3 and r.x1 <= c['right'] + 3:
                row.append((r, col))
        c['fills'] = row
    return cells


def cell_kinds(cell, palette, ignore):
    """Arten aus den Flächen einer Zelle; unbekannte Farben (außer `ignore`) werden zurückgegeben."""
    kinds, unknown = set(), set()
    for _, col in cell['fills']:
        k = classify(col, palette)
        if k:
            kinds.add(k)
        elif not any(common.near(col, i) for i in ignore):
            unknown.add(tuple(round(v, 2) for v in col))
    return kinds, unknown


def token_kind_vector(cell, x, palette, max_width=140):
    ax = cell['x0'] + x + 1.5
    under = [col for r, col in cell['fills'] if r.x0 - 0.5 <= ax <= r.x1 + 0.5 and r.width < max_width]
    kinds = [k for k in (classify(c, palette) for c in under) if k]
    return kinds[-1] if kinds else None


class PixelSampler:
    def __init__(self, doc, zoom=4):
        self.doc, self.zoom, self.pix = doc, zoom, {}

    def color(self, pno, x, y):
        if pno not in self.pix:
            self.pix[pno] = self.doc[pno].get_pixmap(matrix=common.fitz.Matrix(self.zoom, self.zoom))
        return tuple(v / 255 for v in self.pix[pno].pixel(int(x * self.zoom), int(y * self.zoom))[:3])
