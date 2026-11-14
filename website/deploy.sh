#!/bin/bash
# Webseite tonne.kant.ovh ausliefern (IONOS-Server, Plesk-Abo tonne.kant.ovh).
# Aufruf aus dem Repo: website/deploy.sh   Danach Abgleich: website/deploy.sh --check
set -euo pipefail
cd "$(dirname "$0")"
ZIEL=/var/www/vhosts/tonne.kant.ovh/httpdocs
if [ "${1:-}" = "--check" ]; then
  diff <(find . -type f ! -name deploy.sh ! -name '*.md' ! -path './tools/*' -exec md5 -r {} \; | sed 's| \./| |' | awk '{print $1, $2}' | sort -k2) \
       <(ssh gsg "cd $ZIEL && find . -type f -exec md5sum {} \; | sed 's| \./| |; s|  | |'" | sort -k2) \
    && echo "Live = Repo (0 Abweichungen)"
  exit
fi
ssh gsg "install -d -m 700 -o tonne_kant -g psacln /var/www/vhosts/tonne.kant.ovh/private"
rsync -rlc --delete --exclude deploy.sh --exclude '*.md' --exclude tools ./ "gsg:$ZIEL/"
# httpdocs selbst bleibt wie von Plesk angelegt (tonne_kant:psaserv, 750), nur der Inhalt wird gesetzt
ssh gsg "find $ZIEL -mindepth 1 -exec chown tonne_kant:psacln {} + && find $ZIEL -mindepth 1 -type d -exec chmod 755 {} + && find $ZIEL -mindepth 1 -type f -exec chmod 644 {} +"
echo "Ausgeliefert nach $ZIEL"
