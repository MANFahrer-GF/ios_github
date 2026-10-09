"""Erzeugt TonneCore/Sources/TonneCore/Providers/JahresdatenData.swift aus tools/pdfkalender/out/*.json.
Aufruf aus dem Repo-Wurzelordner: python3 tools/pdfkalender/build_swift.py"""
import glob, json, os, re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "TonneCore/Sources/TonneCore/Providers/JahresdatenData.swift")

files = {}
for path in sorted(glob.glob(os.path.join(ROOT, "tools/pdfkalender/out/*.json"))):
    data = json.load(open(path, encoding="utf-8"))
    key = data["key"]
    assert re.fullmatch(r"[a-z0-9_]+", key), key
    assert os.path.basename(path) == key + ".json", path
    text = json.dumps(data, ensure_ascii=False, separators=(",", ":"))
    assert '"##' not in text
    files[key] = text

lines = ["// GENERIERT von tools/pdfkalender/build_swift.py – nicht von Hand ändern.",
         "// Quelle: tools/pdfkalender/out/*.json (Format: tools/pdfkalender/FORMAT.md)",
         "",
         "enum JahresdatenData {",
         "    static let files: [String: String] = [" if files else "    static let files: [String: String] = [:]"]
for key, text in files.items():
    lines.append(f'        "{key}": ##"{text}"##,')
if files:
    lines.append("    ]")
lines.append("}")
open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print(f"{len(files)} Orte → {os.path.relpath(OUT, ROOT)}")
