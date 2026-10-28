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
start_agent() {  # если у ключа есть пароль — спросит его один раз, дальше проверки пройдут без вопросов
  for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa"; do
    [ -f "$k" ] || continue
    [ -n "${SSH_AUTH_SOCK:-}" ] || eval "$(ssh-agent -s)" >/dev/null
    ssh-add "$k" 2>/dev/null || true
  done
}
ssh_ok() { ssh -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; }
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
git config core.autocrlf false   # переносы строк задаёт .gitattributes, предупреждения не нужны

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
start_agent
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
    if ssh_ok; then git remote add origin "git@github.com:$GH_USER/$REPO.git"; else git remote add origin "$REPO_URL.git"; fi
  fi
fi

push_ok=0
git push -u origin main && push_ok=1
if [ $push_ok = 0 ] && git remote get-url origin | grep -q '^https' && ssh_ok; then
  echo "HTTPS не пустил — пробую через SSH-ключ…"
  git remote set-url origin "git@github.com:$GH_USER/$REPO.git"
  git push -u origin main && push_ok=1
fi
if [ $push_ok = 0 ]; then
  echo
  echo "Push не прошёл. Частые причины:"
  echo " • 403 — вошёл не в тот аккаунт. Открой «Диспетчер учётных данных» Windows,"
  echo "   удали запись git:https://github.com и запусти скрипт снова — Git попросит войти."
  echo " • Repository not found — репозиторий не создан или имя не $REPO."
  echo " • «Базовое соединение закрыто» / «No anonymous write access» — окно входа GitHub не смогло"
  echo "   подключиться. Обнови Git for Windows с git-scm.com (вместе с ним обновится вход в GitHub)"
  echo "   или настрой SSH-ключ: github.com/settings/keys. Потом снова bash deploy.sh"
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
