#!/bin/zsh
# Portal-Prüfung: spielt das Einrichten für alle Entsorger (oder alle Gemeinden) gegen das echte Netz durch
# und öffnet danach die Bericht-Seite.
#
#   tools/health/pruefen.sh                 alle Entsorger (ca. 15–30 Minuten)
#   tools/health/pruefen.sh gemeinden       alle Gemeinden (mehrere Stunden, setzt nach Abbruch fort)
#   tools/health/pruefen.sh entsorger köln  nur Einträge mit „köln“ im Namen
#   tools/health/pruefen.sh neu             alten Stand verwerfen und alle Entsorger neu prüfen
set -e
cd "$(dirname "$0")/../.."
REPO=$PWD
MODE=${1:-entsorger}
FRESH=0
if [[ $MODE == neu ]]; then FRESH=1; MODE=entsorger; fi
ONLY=${2:-}
OUT_DIR="$HOME/Tonne-Pruefung"
mkdir -p "$OUT_DIR"
DAY=$(date +%Y-%m-%d)
SUFFIX=${ONLY:+-$ONLY}
DATA="$OUT_DIR/$DAY-$MODE$SUFFIX.jsonl"
PAGE="$OUT_DIR/$DAY-$MODE$SUFFIX.html"
[[ $FRESH == 1 ]] && rm -f "$DATA"

echo "Prüfe $MODE${ONLY:+ (nur „$ONLY“)} – Ergebnis: $PAGE"
echo "Abbrechen mit Ctrl-C; ein neuer Start am selben Tag macht dort weiter."
cd "$REPO/TonneCore"
TONNE_HEALTH="$DATA" TONNE_HEALTH_MODE="$MODE" TONNE_HEALTH_ONLY="$ONLY" \
  swift test --filter PortalHealthLiveTests 2>&1 | grep --line-buffered -E "^HEALTH|error:" || true
python3 "$REPO/tools/health/report.py" "$DATA" "$PAGE"
open "$PAGE"
