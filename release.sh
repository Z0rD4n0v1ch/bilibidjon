#!/usr/bin/env bash
# Выпуск новой версии «Малютки Билибиджона».
#
#   bash release.sh "Что нового"            — обновить игру на сайте + собрать APK
#                                             + страница релиза на GitHub с APK для скачивания
#   bash release.sh "Что нового" --no-apk   — только обновить сайт (быстро, без APK)
#   bash release.sh --release-only          — только создать страницу релиза для уже
#                                             собранного APK текущей версии (если прошлый
#                                             запуск упал на этом шаге)
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

NOTES=""; WITH_APK=1; RELEASE_ONLY=0
for a in "$@"; do case "$a" in --no-apk) WITH_APK=0 ;; --release-only) RELEASE_ONLY=1 ;; *) NOTES="$a" ;; esac; done
git config core.autocrlf false 2>/dev/null || true   # без предупреждений про LF/CRLF

if [ $RELEASE_ONLY = 1 ]; then
  NEW=$(grep -o '"version": *"[0-9.]*"' version.json | grep -o '[0-9][0-9.]*')
  NOTES=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("version.json","utf8")).notes||"")' 2>/dev/null || echo "Версия $NEW")
  ok "Делаю только релиз для версии $NEW"
else
  if [ -z "$NOTES" ]; then read -r -p "Что нового в этой версии? " NOTES; fi
  NOTES="${NOTES//\"/\'}"   # двойные кавычки сломали бы JSON

  # --- 1. Версия ----------------------------------------------------------
  say "Поднимаю версию"
  OLD=$(grep -o '"version": *"[0-9.]*"' version.json | grep -o '[0-9][0-9.]*')
  IFS=. read -r MA MI PA <<< "$OLD"
  NEW="$MA.$MI.$((PA+1))"
  sed -i "s/^const VERSION = \"[0-9.]*\";/const VERSION = \"$NEW\";/" sw.js
  sed -i "s/^const APP_VERSION = \"[0-9.]*\";/const APP_VERSION = \"$NEW\";/" index.html
  printf '{ "version": "%s", "notes": "%s" }\n' "$NEW" "$NOTES" > version.json
  grep -q "\"$NEW\"" sw.js && grep -q "\"$NEW\"" index.html || fail "Не удалось обновить версию в файлах"
  ok "Версия: $OLD -> $NEW"

  # --- 2. Сайт --------------------------------------------------------------
  say "Отправляю на GitHub"
  git add -A
  git commit -q -m "v$NEW: $NOTES"
  git push -q || fail "Push не прошёл. Проверь интернет и вход в GitHub (bash setup-ssh.sh)."
  ok "Игра на сайте обновится через 1–3 минуты: $SITE"
  if [ $WITH_APK = 0 ]; then echo; ok "Готово! v$NEW выпущена (без APK)."; exit 0; fi

  # --- 3. APK ---------------------------------------------------------------
  say "Собираю APK"
  [ -f build-apk.sh ] || fail "Нет build-apk.sh в папке игры."
  mkdir -p apk-build
  if ! bash build-apk.sh online > apk-build/build.log 2>&1; then
    tail -n 30 apk-build/build.log
    warn "APK не собрался. Сайт уже обновлён — игроки получат v$NEW."
    fail "Пришли эти строки — разберёмся. Полный лог: apk-build/build.log"
  fi
fi

APK="bilibidjon-$NEW-online.apk"
[ -f "$APK" ] || fail "Не нашёл $APK. Собери его: bash build-apk.sh"
ok "APK: $APK ($(du -h "$APK" | cut -f1))"
mkdir -p apk-build/release && rm -f apk-build/release/*
cp "$APK" "apk-build/release/bilibidjon-$NEW.apk"
cp "$APK" "apk-build/release/bilibidjon.apk"      # постоянная ссылка «последняя версия»

BODY="$NOTES

📱 **Android:** скачай \`bilibidjon.apk\` ниже, открой на телефоне и нажми «Установить».
Если игра уже установлена — обновление придёт само, ничего качать не нужно.

🌐 **Играть в браузере / iPhone:** $SITE"
printf '%s' "$BODY" > apk-build/release/body.txt

# --- 4. Страница релиза на GitHub ---------------------------------------------
say "Создаю релиз v$NEW на GitHub"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  gh release delete "v$NEW" -R "$GH_USER/$REPO" -y >/dev/null 2>&1 || true
  gh release create "v$NEW" -R "$GH_USER/$REPO" --title "Билибиджон $NEW" --notes-file apk-build/release/body.txt --latest \
    "apk-build/release/bilibidjon.apk" "apk-build/release/bilibidjon-$NEW.apk" || fail "gh не смог создать релиз."
else
  json() { node -e 'const d=JSON.parse(require("fs").readFileSync(0,"utf8")||"{}");const v=process.argv[1].split(".").reduce((o,k)=>o&&o[k],d);console.log(v===undefined?"":v)' "$1"; }
  scopes_of() { curl -sI -H "Authorization: Bearer $1" https://api.github.com/user | tr -d '\r' | grep -i '^x-oauth-scopes:' | cut -d: -f2- ; }
  token_can_write() {  # классический токен: нужна галочка public_repo или repo
    case "$1" in github_pat_*) return 0 ;; esac
    local s; s=$(scopes_of "$1"); echo "$s" | grep -qE '(^|[ ,])(public_repo|repo)(,|$| )'
  }
  ask_token() {
    echo
    echo "Нужен токен GitHub с правом создавать релизы. Сейчас откроется страница — галочка уже стоит:"
    echo "  1. Note: bilibidjon-release (уже вписано)"
    echo "  2. Expiration: выбери срок, например 1 год"
    echo "  3. Отмечено «public_repo» — ничего больше не трогай"
    echo "  4. Пролистай вниз → Generate token → скопируй его (начинается с ghp_)"
    open_url "https://github.com/settings/tokens/new?description=bilibidjon-release&scopes=public_repo"
    read -r -s -p "Вставь токен (символы не видны) и нажми Enter: " TOKEN; echo
    TOKEN=$(printf '%s' "$TOKEN" | tr -d '[:space:]')
    [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$API")" = 200 ] \
      || fail "GitHub не принял токен. Проверь, что скопировал его целиком."
    token_can_write "$TOKEN" || fail "У токена нет галочки «public_repo». Создай новый по ссылке выше, галочка там стоит сама."
    mkdir -p "$(dirname "$TOKEN_FILE")"; printf '%s' "$TOKEN" > "$TOKEN_FILE"; chmod 600 "$TOKEN_FILE"
    ok "Токен сохранён в $TOKEN_FILE (только на этом компьютере)"
  }
  TOKEN="${GITHUB_TOKEN:-}"
  [ -z "$TOKEN" ] && [ -f "$TOKEN_FILE" ] && TOKEN=$(cat "$TOKEN_FILE")
  if [ -z "$TOKEN" ] || [ "$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$API")" != 200 ] || ! token_can_write "$TOKEN"; then ask_token; fi

  create_release() {
    local AUTH=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json")
    local OLD_ID; OLD_ID=$(curl -s "${AUTH[@]}" "$API/releases/tags/v$NEW" | json id)
    [ -n "$OLD_ID" ] && curl -s -o /dev/null -X DELETE "${AUTH[@]}" "$API/releases/$OLD_ID"
    local REQ; REQ=$(NEW="$NEW" node -e 'const fs=require("fs");console.log(JSON.stringify({tag_name:"v"+process.env.NEW,name:"\u0411\u0438\u043b\u0438\u0431\u0438\u0434\u0436\u043e\u043d "+process.env.NEW,body:fs.readFileSync("apk-build/release/body.txt","utf8"),target_commitish:"main",make_latest:"true"}))')
    RESP=$(printf '%s' "$REQ" | curl -s -X POST "${AUTH[@]}" "$API/releases" --data-binary @-)
    REL_ID=$(printf '%s' "$RESP" | json id)
    [ -n "$REL_ID" ]
  }
  if ! create_release; then
    if printf '%s' "$RESP" | grep -q '"403"\|not accessible'; then
      warn "Этому токену GitHub не даёт создавать релизы. Сделаем классический токен — так надёжнее."
      rm -f "$TOKEN_FILE"; ask_token
      create_release || { echo "$RESP" | head -20; fail "Не удалось создать релиз."; }
    else echo "$RESP" | head -20; fail "Не удалось создать релиз."; fi
  fi
  AUTH=(-H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github+json")
  for f in bilibidjon.apk "bilibidjon-$NEW.apk"; do
    echo "Загружаю $f…"
    CODE=$(curl -s -o /dev/null -w '%{http_code}' -X POST "${AUTH[@]}" -H "Content-Type: application/vnd.android.package-archive" \
      --data-binary @"apk-build/release/$f" "https://uploads.github.com/repos/$GH_USER/$REPO/releases/$REL_ID/assets?name=$f")
    [ "$CODE" = 201 ] || fail "Не загрузился $f (код $CODE). Запусти снова: bash release.sh --release-only"
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
