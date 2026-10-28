#!/usr/bin/env bash
# Настройка SSH-ключа для GitHub (один раз на компьютер).
# Запуск в Git Bash:  bash setup-ssh.sh
set -euo pipefail
EMAIL="85552878+Z0rD4n0v1ch@users.noreply.github.com"
KEY="$HOME/.ssh/id_ed25519"

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
test_ssh() { ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -T git@github.com 2>&1 | grep -q "successfully authenticated"; }

start_agent
if test_ssh; then ok "SSH уже работает — можно запускать bash deploy.sh"; exit 0; fi

say "Ключ"
mkdir -p "$HOME/.ssh"
if [ -f "$KEY" ]; then
  ok "Ключ уже есть: $KEY"
else
  ssh-keygen -t ed25519 -C "$EMAIL" -f "$KEY" -N "" -q
  ok "Создан новый ключ: $KEY"
fi

say "Добавляем ключ на GitHub"
# В буфер обмена кладём ТОЛЬКО публичную часть (.pub). Секретный файл без .pub никому не показывай.
clip.exe < "$KEY.pub" 2>/dev/null && ok "Публичный ключ скопирован в буфер обмена" || { echo "Скопируй эту строку целиком:"; cat "$KEY.pub"; }
echo
echo "Сейчас откроется GitHub → New SSH key:"
echo "  Title: любое, например «Ноутбук ThinkPad»"
echo "  Key type: Authentication Key"
echo "  Key: вставь Ctrl+V (строка начинается с ssh-ed25519)"
echo "  → Add SSH key"
start "" "https://github.com/settings/ssh/new" 2>/dev/null || echo "Открой: https://github.com/settings/ssh/new"
read -r -p "Добавил? Нажми Enter... " _

say "Проверяю"
start_agent
for i in 1 2 3; do
  if test_ssh; then ok "GitHub узнал ключ! Теперь: bash deploy.sh"; exit 0; fi
  sleep 3
done
echo
echo "Отпечаток твоего ключа на этом компьютере:"
ssh-keygen -lf "$KEY.pub"
echo "Открой https://github.com/settings/keys — там должен быть ключ с ТАКИМ ЖЕ отпечатком (SHA256:...)."
echo "Если ключа нет или отпечаток другой — вставь ключ ещё раз. Проверь, что вошёл в аккаунт Z0rD4n0v1ch."
fail "GitHub пока не принимает ключ."
