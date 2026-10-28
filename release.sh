#!/usr/bin/env bash
# Выпуск обновления игры.
# Запуск из папки с игрой (Git Bash):   bash release.sh "Что нового в этой версии"
# Скрипт поднимет версию (1.0.5 -> 1.0.6), запишет её в sw.js, index.html
# и version.json, сделает коммит и отправит на GitHub. Через несколько минут
# GitHub Pages обновится, и игра у игроков сама скачает новую версию.
set -euo pipefail
cd "$(dirname "$0")"

NOTES="${1:-}"
if [ -z "$NOTES" ]; then
  read -r -p "Что нового в этой версии? " NOTES
fi
NOTES="${NOTES//\"/\'}"   # двойные кавычки сломали бы JSON

OLD=$(grep -o '"version": *"[0-9.]*"' version.json | grep -o '[0-9][0-9.]*')
IFS=. read -r MA MI PA <<< "$OLD"
NEW="$MA.$MI.$((PA+1))"
echo "Версия: $OLD -> $NEW"

sed -i "s/^const VERSION = \"[0-9.]*\";/const VERSION = \"$NEW\";/" sw.js
sed -i "s/^const APP_VERSION = \"[0-9.]*\";/const APP_VERSION = \"$NEW\";/" index.html
printf '{ "version": "%s", "notes": "%s" }\n' "$NEW" "$NOTES" > version.json

grep -q "\"$NEW\"" sw.js && grep -q "\"$NEW\"" index.html || { echo "Не удалось обновить версию в файлах"; exit 1; }

git add -A
git commit -m "v$NEW: $NOTES"
git push
echo "Готово! v$NEW отправлена. Игроки получат её в фоне."
