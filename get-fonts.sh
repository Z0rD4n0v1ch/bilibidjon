#!/usr/bin/env bash
# Скачивает шрифты игры в папку fonts/, чтобы она работала без интернета.
# Запуск (Git Bash, из папки с index.html):  bash get-fonts.sh
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p fonts
BASE="https://cdn.jsdelivr.net/npm/@fontsource"
get() { # пакет файл
  echo "→ $2"
  curl -fsSL "$BASE/$1@5/files/$2" -o "fonts/$2"
}
for sub in cyrillic latin; do
  get russo-one "russo-one-$sub-400-normal.woff2"
  for w in 400 500 700; do get rubik "rubik-$sub-$w-normal.woff2"; done
done
echo "Готово: $(ls fonts | wc -l) файлов в fonts/"
