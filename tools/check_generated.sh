#!/bin/bash
# Prüft, dass alle erzeugten Swift-Dateien dem Stand ihrer Generatoren entsprechen. Läuft in der CI und vor Commits.
# Exit 0 aktuell, 1 Abweichung, 2 erzeugte Dateien hatten schon lokale Änderungen, sonst Fehler von git/Python.
set -euo pipefail
cd "$(dirname "$0")/.."
P=TonneCore/Sources/TonneCore/Providers
FILES=("$P/Catalog.swift" "$P/CatalogRegions.swift" "$P/CatalogPlaceMap.swift" "$P/CatalogLocalities.swift" "$P/JahresdatenData.swift")

# git diff --quiet: 0 gleich, 1 verschieden, sonst Fehler (wird durchgereicht)
unchanged() { local rc=0; git diff --quiet "$@" -- "${FILES[@]}" || rc=$?; [ $rc -le 1 ] || exit $rc; return $rc; }

if ! unchanged || ! unchanged --cached; then
  echo "Erzeugte Dateien haben schon lokale Änderungen – erst committen oder verwerfen." >&2; exit 2
fi
python3 tools/catalog/gen_catalog.py > /dev/null
python3 tools/catalog/gen_place_map.py > /dev/null
python3 tools/catalog/gen_localities.py > /dev/null
python3 tools/pdfkalender/build_swift.py > /dev/null
if ! unchanged; then
  echo "Erzeugte Dateien weichen von ihren Generatoren ab:" >&2
  git --no-pager diff --stat -- "${FILES[@]}" >&2
  exit 1
fi
echo "Erzeugte Dateien aktuell."
