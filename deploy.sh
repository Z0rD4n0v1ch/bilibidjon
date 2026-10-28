#!/usr/bin/env bash
# Первая выкладка «Малютки Билибиджона» на GitHub Pages.
# Запуск из папки с игрой (Git Bash):   bash deploy.sh
# Дальше обновления выпускаются через:  bash release.sh "что нового"
set -euo pipefail
cd "$(dirname "$0")"

GH_USER="Z0rD4n0v1ch"
REPO="${1:-bilibidjon}"
SITE="https://$(echo "$GH_USER" | tr 'A-Z' 'a-z').github.io/$REPO/"
REPO_URL="https://github.com/$GH_USER/$REPO"

say()  { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }
open_url() { start "" "$1" 2>/dev/null || explorer "$1" 2>/dev/null || echo "Открой вручную: $1"; }

# --- 1. Проверки ---------------------------------------------------------
say "Проверяю файлы"
command -v git >/dev/null || fail "Git не найден. Установи Git for Windows и запусти скрипт в Git Bash."
for f in index.html sw.js manifest.webmanifest version.json icon-192.png icon-512.png release.sh; do
  [ -f "$f" ] || fail "Нет файла $f — положи все файлы игры в эту папку."
done
ok "Все файлы на месте"

if [ ! -f fonts/rubik-cyrillic-400-normal.woff2 ] && [ -f get-fonts.sh ]; then
  say "Скачиваю шрифты для офлайна"
  bash get-fonts.sh || echo "Шрифты не скачались — не страшно, игра возьмёт их из интернета."
fi

# служебные файлы
touch .nojekyll   # GitHub Pages отдаёт файлы как есть, без обработки Jekyll
[ -f .gitignore ] || printf 'artifacts/\n*.tmp\nThumbs.db\ndesktop.ini\n' > .gitignore

# --- 2. Локальный репозиторий --------------------------------------------
say "Готовлю git-репозиторий"
if [ ! -d .git ]; then
  git init -q
  git checkout -q -b main 2>/dev/null || git branch -M main
  ok "Репозиторий создан"
fi
git branch -M main

if [ -z "$(git config user.name || true)" ]; then
  read -r -p "Твоё имя для коммитов: " N; git config user.name "$N"
fi
if [ -z "$(git config user.email || true)" ]; then
  read -r -p "Твой email на GitHub: " E; git config user.email "$E"
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -q -m "Малютка Билибиджон v$(grep -o '[0-9][0-9.]*' version.json | head -1)"
  ok "Коммит сделан"
else
  ok "Новых изменений нет"
fi

# --- 3. Репозиторий на GitHub и отправка -----------------------------------
say "Отправляю на GitHub"
HAS_GH=0
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then HAS_GH=1; fi

if ! git remote get-url origin >/dev/null 2>&1; then
  if [ $HAS_GH = 1 ]; then
    gh repo create "$GH_USER/$REPO" --public --source=. --remote=origin --push \
      || fail "Не получилось создать репозиторий через gh."
    ok "Репозиторий $REPO_URL создан"
  else
    echo "Сейчас откроется GitHub. Создай ПУСТОЙ ПУБЛИЧНЫЙ репозиторий с именем: $REPO"
    echo "(без README, без .gitignore, без лицензии — галочки не ставь)"
    open_url "https://github.com/new?name=$REPO&visibility=public"
    read -r -p "Создал? Нажми Enter... " _
    git remote add origin "$REPO_URL.git"
  fi
fi

if ! git push -u origin main; then
  echo
  echo "Push не прошёл. Частые причины:"
  echo " • 403 — вошёл не в тот аккаунт. Открой «Диспетчер учётных данных» Windows,"
  echo "   удали запись git:https://github.com и запусти скрипт снова — Git попросит войти."
  echo " • Repository not found — репозиторий не создан или имя не $REPO."
  fail "Исправь и запусти bash deploy.sh ещё раз."
fi
ok "Код на GitHub"

# --- 4. Включаем GitHub Pages ---------------------------------------------
say "Включаю GitHub Pages"
if [ $HAS_GH = 1 ]; then
  gh api -X POST "repos/$GH_USER/$REPO/pages" -f "source[branch]=main" -f "source[path]=/" >/dev/null 2>&1 \
    && ok "Pages включены" || ok "Pages уже были включены"
else
  echo "Откроются настройки Pages. Там выбери:"
  echo "  Source: Deploy from a branch   →   Branch: main   /(root)   →   Save"
  open_url "$REPO_URL/settings/pages"
  read -r -p "Нажал Save? Нажми Enter... " _
fi

# --- 5. Ждём, пока сайт заработает ----------------------------------------
say "Жду, пока сайт поднимется (обычно 1–3 минуты)"
for i in $(seq 1 40); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "${SITE}sw.js" || echo 000)
  if [ "$code" = "200" ]; then
    echo; ok "Игра онлайн: $SITE"
    echo
    echo "На телефоне: открой ссылку в Chrome → меню ⋮ → «Установить приложение»."
    echo "Обновления дальше:  bash release.sh \"что нового\""
    open_url "$SITE"
    exit 0
  fi
  printf '.'; sleep 6
done
echo
echo "Сайт пока не ответил — GitHub иногда долго думает при первом запуске."
echo "Проверь через пару минут: $SITE"
echo "Статус сборки: $REPO_URL/actions"
