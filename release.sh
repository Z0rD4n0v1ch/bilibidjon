#!/usr/bin/env bash
# Выпуск новой версии «Малютки Билибиджона».
#
#   bash release.sh "Что нового"            — обновить игру на сайте + собрать APK
#                                             + страница релиза на GitHub с APK для скачивания
#   bash release.sh "Что нового" --no-apk   — только обновить сайт (быстро, без APK)
#
# Игроки с установленной игрой получат обновление сами (плашка «Обновление готово»).
# Новым игрокам можно давать постоянную ссылку на APK — её скрипт покажет в конце.
set -euo pipefail
cd "$(dirname "$0")"

GH_USER="Z0rD4n0v1ch"; REPO="bilibidjon"
SITE="https://$(echo "$GH_USER" | tr 'A-Z' 'a-z').github.io/$REPO/"
API="https://api.github.com/repos/$GH_USER/$REPO"
TOKEN_FILE="$HOME/.config/bilibidjon/github-token"

say()  { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;35m! %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }
open_url() { start "" "$1" 2>/dev/null || explorer "$1" 2>/dev/null || echo "Открой: $1"; }

NOTES=""; WITH_APK=1
for a in "$@"; do case "$a" in --no-apk) WITH_APK=0 ;; *) NOTES="$a" ;; esac; done
if [ -z "$NOTES" ]; then read -r -p "Что нового в этой версии? " NOTES; fi
NOTES="${NOTES//\"/\'}"   # двойные кавычки сломали бы JSON

# --- 1. Версия ------------------------------------------------------------
say "Поднимаю версию"
OLD=$(grep -o '"version": *"[0-9.]*"' version.json | grep -o '[0-9][0-9.]*')
IFS=. read -r MA MI PA <<< "$OLD"
NEW="$MA.$MI.$((PA+1))"
sed -i "s/^const VERSION = \"[0-9.]*\";/const VERSION = \"$NEW\";/" sw.js
sed -i "s/^const APP_VERSION = \"[0-9.]*\";/const APP_VERSION = \"$NEW\";/" index.html
printf '{ "version": "%s", "notes": "%s" }\n' "$NEW" "$NOTES" > version.json
grep -q "\"$NEW\"" sw.js && grep -q "\"$NEW\"" index.html || fail "Не удалось обновить версию в файлах"
ok "Версия: $OLD -> $NEW"

# --- 2. Сайт ----------------------------------------------------------------
say "Отправляю на GitHub"
git add -A
git commit -q -m "v$NEW: $NOTES"
git push -q || fail "Push не прошёл. Проверь интернет и вход в GitHub (bash setup-ssh.sh)."
ok "Игра на сайте обновится через 1–3 минуты: $SITE"

if [ $WITH_APK = 0 ]; then echo; ok "Готово! v$NEW выпущена (без APK)."; exit 0; fi

# --- 3. APK -----------------------------------------------------------------
say "Собираю APK"
[ -f build-apk.sh ] || fail "Нет build-apk.sh в папке игры."
mkdir -p apk-build
if ! bash build-apk.sh online > apk-build/build.log 2>&1; then
  tail -n 30 apk-build/build.log
  warn "APK не собрался. Сайт уже обновлён — игроки получат v$NEW."
  fail "Пришли эти строки — разберёмся. Полный лог: apk-build/build.log"
fi
APK="bilibidjon-$NEW-online.apk"
[ -f "$APK" ] || fail "Не нашёл $APK после сборки."
ok "APK: $APK ($(du -h "$APK" | cut -f1))"
mkdir -p apk-build/release && rm -f apk-build/release/*
cp "$APK" "apk-build/release/bilibidjon-$NEW.apk"
cp "$APK" "apk-build/release/bilibidjon.apk"      # постоянная ссылка «последняя версия»

BODY="$NOTES

📱 **Android:** скачай \`bilibidjon.apk\` ниже, открой на телефоне и нажми «Установить».
Если игра уже установлена — обновление придёт само, ничего качать не нужно.

🌐 **Играть в браузере / iPhone:** $SITE"

# --- 4. Страница релиза на GitHub ---------------------------------------------
say "Создаю релиз v$NEW на GitHub"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh release delete "v$NEW" -R "$GH_USER/$REPO" -y >/dev/null 2>&1 || true
  gh release create "v$NEW" -R "$GH_USER/$REPO" --title "Билибиджон $NEW" --notes "$BODY" --latest \
    "apk-build/release/bilibidjon.apk" "apk-build/release/bilibidjon-$NEW.apk" || fail "gh не смог создать релиз."
else
  # Токен GitHub: хранится только у тебя на компьютере, в репозиторий не попадает.
  TOKEN="${GITHUB_TOKEN:-}"
  [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ] && TOKEN=$(cat "$TOKEN_FILE")
  check_token() { [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $1" "$API")" = 200 ]; }
  if [ -z "$TOKEN" ] || ! check_token "$TOKEN"; then
    echo "Для релиза нужен токен GitHub (один раз). Сейчас откроется страница создания:"
    echo "  • Token name: bilibidjon-release"
    echo "  • Expiration: на твой выбор (например, 1 год)"
    echo "  • Repository access: Only select repositories → bilibidjon"
    echo "  • Permissions → Repository permissions → Contents: Read and write"
    echo "  • Generate token → скопируй его (начинается с github_pat_)"
    open_url "https://github.com/settings/personal-access-tokens/new"
    read -r -s -p "Вставь токен (символы не видны) и нажми Enter: " TOKEN; echo
    check_token "$TOKEN" || fail "GitHub не принял токен. Проверь, что выбран репозиторий bilibidjon и Contents: Read and write."
    mkdir -p "$(dirname "$TOKEN_FILE")"; printf '%s' "$TOKEN" > "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"
    ok "Токен сохранён в $TOKEN_FILE"
  fi
  AUTH=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json")
  json() { node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8"));const v=process.argv[1].split(".").reduce((o,k)=>o&&o[k],d);console.log(v===undefined?"":v)' "$1"; }

  # если релиз с этим номером уже был (повторный запуск) — удаляем и создаём заново
  OLD_ID=$(curl -s "${AUTH[@]}" "$API/releases/tags/v$NEW" | json id)
  [ -n "$OLD_ID" ] && curl -s -o /dev/null -X DELETE "${AUTH[@]}" "$API/releases/$OLD_ID"

  printf '%s' "$BODY" > apk-build/release/body.txt
  REQ=$(NEW="$NEW" node -e 'const fs=require("fs");console.log(JSON.stringify({tag_name:"v"+process.env.NEW,name:"\u0411\u0438\u043b\u0438\u0431\u0438\u0434\u0436\u043e\u043d "+process.env.NEW,body:fs.readFileSync("apk-build/release/body.txt","utf8"),target_commitish:"main",make_latest:"true"}))')
  RESP=$(printf '%s' "$REQ" | curl -s -X POST "${AUTH[@]}" "$API/releases" --data-binary @-)
  REL_ID=$(printf '%s' "$RESP" | json id)
  [ -n "$REL_ID" ] || { echo "$RESP" | head -20; fail "Не удалось создать релиз."; }
  for f in bilibidjon.apk "bilibidjon-$NEW.apk"; do
    echo "Загружаю $f…"
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${AUTH[@]}" -H "Content-Type: application/vnd.android.package-archive" \
      --data-binary @"apk-build/release/$f" "https://uploads.github.com/repos/$GH_USER/$REPO/releases/$REL_ID/assets?name=$f")
    [ "$CODE" = 201 ] || fail "Не загрузился $f (код $CODE)."
  done
fi

REL_URL="https://github.com/$GH_USER/$REPO/releases/tag/v$NEW"
LATEST="https://github.com/$GH_USER/$REPO/releases/latest/download/bilibidjon.apk"
echo
ok "Релиз v$NEW готов: $REL_URL"
echo
echo "Постоянная ссылка на APK (всегда последняя версия) — её можно давать друзьям:"
echo "  $LATEST"
open_url "$REL_URL"
