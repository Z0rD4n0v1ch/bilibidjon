#!/usr/bin/env bash
# Сборка «Малютки Билибиджона» в APK для Android (Capacitor 8).
#
# Запуск из папки с игрой (Git Bash):
#   bash build-apk.sh           — онлайн-режим: APK открывает игру с GitHub Pages,
#                                 обновления приходят сами (через release.sh)
#   bash build-apk.sh offline   — всё внутри APK, работает без интернета,
#                                 но для обновления нужно собрать APK заново
#
# Нужно один раз установить: Node.js (LTS) и Android Studio.
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-online}"
GH_USER="Z0rD4n0v1ch"; REPO="bilibidjon"
SITE="https://$(echo "$GH_USER" | tr 'A-Z' 'a-z').github.io/$REPO/"
APP_ID="com.$(echo "$GH_USER" | tr 'A-Z' 'a-z').bilibidjon"
APP_NAME="Билибиджон"
BUILD="apk-build"

say()  { printf '\n\033[1;33m== %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*"; exit 1; }
winpath() { command -v cygpath >/dev/null && cygpath -m "$1" || echo "$1"; }
unixpath() { command -v cygpath >/dev/null && cygpath -u "$1" || echo "$1"; }

[ "$MODE" = online ] || [ "$MODE" = offline ] || fail "Режим может быть только online или offline."

# --- 1. Проверяем инструменты ---------------------------------------------
say "Проверяю инструменты"
command -v node >/dev/null || fail "Нет Node.js. Скачай LTS-версию с nodejs.org, установи и открой Git Bash заново."
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
[ "$NODE_MAJOR" -ge 20 ] || fail "Node.js слишком старый ($(node -v)). Нужна LTS-версия 20 или новее."
ok "Node.js $(node -v)"

SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [ -z "$SDK" ] && [ -n "${LOCALAPPDATA:-}" ]; then SDK="$(unixpath "$LOCALAPPDATA")/Android/Sdk"; fi
[ -n "$SDK" ] && [ -d "$SDK" ] || fail "Не найден Android SDK. Открой Android Studio один раз — она сама скачает SDK (More Actions → SDK Manager)."
export ANDROID_HOME="$SDK"
ok "Android SDK: $SDK"

# Gradle 8.14 работает только с Java 17–24. Java 25+ (или 8/11) он не понимает,
# поэтому ищем подходящую: сначала встроенную в Android Studio, потом остальные.
java_major() { "$1/bin/java" -version 2>&1 | head -1 | grep -oE '"[0-9]+' | tr -d '"'; }
CANDIDATES=(
  "/c/Program Files/Android/Android Studio/jbr"
  "/c/Program Files/Android/Android Studio/jre"
)
[ -n "${LOCALAPPDATA:-}" ] && CANDIDATES+=("$(unixpath "$LOCALAPPDATA")/Programs/Android Studio/jbr")
[ -n "${JAVA_HOME:-}" ] && CANDIDATES+=("$(unixpath "$JAVA_HOME")")
if command -v java >/dev/null; then CANDIDATES+=("$(dirname "$(dirname "$(command -v java)")")"); fi
for d in "/c/Program Files/Java/"* "/c/Program Files/Eclipse Adoptium/"* "/c/Program Files/Microsoft/"jdk*; do
  [ -d "$d" ] && CANDIDATES+=("$d")
done
for d in "$BUILD/jdk/"*; do [ -d "$d" ] && CANDIDATES=("$(cd "$d" && pwd)" "${CANDIDATES[@]}"); done
find_java() {
  GOOD_JAVA=""
  for J in "${CANDIDATES[@]}"; do
    { [ -x "$J/bin/java" ] || [ -x "$J/bin/java.exe" ]; } || continue
    V=$(java_major "$J"); [ -n "$V" ] || continue
    if [ "$V" -ge 17 ] && [ "$V" -le 24 ]; then GOOD_JAVA="$J"; return 0; fi
    echo "  пропускаю Java $V ($J) — Gradle её не поддерживает"
  done
  return 1
}
if ! find_java; then
  # Подходящей Java нет — скачиваем переносную JDK 21 (Eclipse Temurin) прямо в папку сборки.
  # Ничего не устанавливается в систему, Java 25 остаётся как есть.
  say "Скачиваю переносную Java 21 (один раз, ~190 МБ)"
  mkdir -p "$BUILD/jdk"
  ZIP="$BUILD/jdk/jdk21.zip"
  curl -fL --progress-bar -o "$ZIP" "https://api.adoptium.net/v3/binary/latest/21/ga/windows/x64/jdk/hotspot/normal/eclipse" \
    || fail "Не удалось скачать Java 21. Проверь интернет или установи JDK 21 вручную с adoptium.net."
  echo "Распаковываю…"
  powershell.exe -NoProfile -Command "Expand-Archive -Force -Path '$(winpath "$ZIP")' -DestinationPath '$(winpath "$BUILD/jdk")'" \
    || fail "Не удалось распаковать Java. Распакуй $ZIP вручную в папку $BUILD/jdk и запусти скрипт снова."
  rm -f "$ZIP"
  for d in "$BUILD/jdk/"*; do [ -d "$d" ] && CANDIDATES=("$(cd "$d" && pwd)" "${CANDIDATES[@]}"); done
  find_java || fail "Java 21 скачалась, но не запускается. Пришли вывод скрипта — разберёмся."
fi
export JAVA_HOME="$GOOD_JAVA"; export PATH="$GOOD_JAVA/bin:$PATH"
ok "Java: $(java -version 2>&1 | head -1)  ($GOOD_JAVA)"

for f in index.html sw.js manifest.webmanifest version.json icon-192.png icon-512.png icon-1024.png; do
  [ -f "$f" ] || fail "Нет файла $f в папке игры."
done
VERSION=$(grep -o '"version": *"[0-9.]*"' version.json | grep -o '[0-9][0-9.]*')
IFS=. read -r MA MI PA <<< "$VERSION"
VCODE=$((MA*10000 + MI*100 + PA))
ok "Версия игры $VERSION"

# APK-сборка не должна попадать на GitHub
touch .gitignore
for line in "$BUILD/" "*.apk"; do grep -qxF "$line" .gitignore || echo "$line" >> .gitignore; done

# --- 2. Готовим проект Capacitor --------------------------------------------
say "Готовлю проект ($MODE)"
mkdir -p "$BUILD/www"
cp index.html sw.js manifest.webmanifest version.json icon*.png icon.svg "$BUILD/www/" 2>/dev/null || true
[ -d fonts ] && cp -r fonts "$BUILD/www/"
cat > "$BUILD/www/offline.html" << HTML
<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Билибиджон</title><style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#DDE7E9;font:18px system-ui;color:#14213D;text-align:center;padding:24px}
button{font:inherit;background:#FFC93C;border:3px solid #14213D;border-radius:4px;padding:12px 20px;box-shadow:3px 3px 0 #14213D}</style></head>
<body><div><p style="font-size:48px;margin:0">👷📶</p><h2>Нет интернета</h2><p>Для первого запуска Билибиджону нужен интернет — он скачает игру и дальше сможет работать офлайн.</p>
<button onclick="location.href='$SITE'">Попробовать снова</button></div></body></html>
HTML

cd "$BUILD"
if [ ! -f package.json ]; then
  npm init -y >/dev/null
  say "Скачиваю Capacitor (один раз, пара минут)"
  npm install @capacitor/core@8 @capacitor/android@8 @capacitor/app@8
  npm install -D @capacitor/cli@8 @capacitor/assets
fi
if [ ! -d node_modules/@capacitor/local-notifications ] || [ ! -d node_modules/@capacitor/background-runner ]; then
  say "Ставлю уведомления (один раз)"
  npm install @capacitor/local-notifications@8 @capacitor/background-runner@3 \
    || echo "Не удалось поставить плагины уведомлений — APK соберётся без них."
fi

# фоновая проверка новой версии: раз в ~30 минут, даже когда игра закрыта
mkdir -p www/runners
cat > www/runners/background.js << RUNNER
// Работает вне игры (Capacitor Background Runner). Проверяет version.json и шлёт уведомление.
addEventListener("syncVersion", (resolve, reject, args) => {
  try {
    if (args && args.version) CapacitorKV.set("knownVersion", args.version);
    if (args && args.notify !== undefined) CapacitorKV.set("notify", args.notify ? "1" : "0");
    resolve();
  } catch (e) { reject(e); }
});
addEventListener("checkVersion", async (resolve, reject) => {
  try {
    const n = CapacitorKV.get("notify");
    if (!n || n.value !== "1") return resolve();
    const res = await fetch("${SITE}version.json?t=" + Date.now());
    const info = await res.json();
    const known = CapacitorKV.get("knownVersion"), told = CapacitorKV.get("toldVersion");
    const k = known && known.value, t = told && told.value;
    if (info.version && info.version !== k && info.version !== t) {
      CapacitorNotifications.schedule([{ id: 1001, title: "Вышел Билибиджон " + info.version + " 🧱",
        body: info.notes || "Открой игру — обновление скачается само.", scheduleAt: new Date(Date.now() + 1000) }]);
      CapacitorKV.set("toldVersion", info.version);
    }
    resolve();
  } catch (e) { reject(e); }
});
RUNNER

if [ "$MODE" = online ]; then
  SERVER=",\"server\":{\"url\":\"$SITE\",\"errorPath\":\"offline.html\"}"
else
  SERVER=""
fi
cat > capacitor.config.json << JSON
{ "appId": "$APP_ID", "appName": "$APP_NAME", "webDir": "www"$SERVER,
  "android": { "backgroundColor": "#DDE7E9" },
  "plugins": {
    "BackgroundRunner": { "label": "com.z0rd4n0v1ch.bilibidjon.check", "src": "runners/background.js",
      "event": "checkVersion", "repeat": true, "interval": 30, "autoStart": true },
    "LocalNotifications": { "iconColor": "#FFC93C" }
  } }
JSON
ok "capacitor.config.json записан"

[ -d android ] || npx cap add android

say "Делаю иконку и заставку"
mkdir -p assets
cp ../icon-1024.png assets/icon-only.png
cp ../icon-1024.png assets/logo.png
npx @capacitor/assets generate --android --iconBackgroundColor '#9ED8C8' --splashBackgroundColor '#FFC93C' \
  && ok "Иконки готовы" || echo "Иконки не сгенерировались — будет стандартная иконка, игра от этого не сломается."

npx cap sync android

# путь к SDK и версия приложения
echo "sdk.dir=$(winpath "$SDK")" > android/local.properties
MANIFEST=android/app/src/main/AndroidManifest.xml
grep -q POST_NOTIFICATIONS "$MANIFEST" || sed -i 's#</manifest>#    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />\n</manifest>#' "$MANIFEST"
sed -i -E "s/versionCode [0-9]+/versionCode $VCODE/; s/versionName \"[^\"]*\"/versionName \"$VERSION\"/" android/app/build.gradle

# нужная версия Android SDK Platform (Capacitor 8 собирает под API 36)
API=$(grep -oE 'compileSdkVersion *= *[0-9]+' android/variables.gradle | grep -oE '[0-9]+$' || echo 36)
if [ ! -d "$SDK/platforms/android-$API" ]; then
  say "Ставлю Android SDK Platform $API"
  SDKM=""
  for s in "$SDK/cmdline-tools/latest/bin/sdkmanager.bat" "$SDK/cmdline-tools/"*/bin/sdkmanager.bat "$SDK/cmdline-tools/latest/bin/sdkmanager"; do
    [ -f "$s" ] && { SDKM="$s"; break; }
  done
  if [ -n "$SDKM" ]; then
    yes | "$SDKM" --licenses >/dev/null 2>&1 || true
    "$SDKM" "platforms;android-$API" || true
  fi
  [ -d "$SDK/platforms/android-$API" ] || fail "Не установлен Android SDK Platform $API. В Android Studio: More Actions → SDK Manager →
   вкладка SDK Platforms → отметь Android с API Level $API → Apply.
   На вкладке SDK Tools заодно отметь «Android SDK Command-line Tools (latest)» → Apply.
   Потом снова: bash build-apk.sh"
  ok "Android SDK Platform $API установлен"
fi

# --- 3. Сборка -------------------------------------------------------------
say "Собираю APK (первый раз 5–15 минут: Gradle качает зависимости)"
cd android
chmod +x gradlew
./gradlew assembleDebug --no-daemon || fail "Сборка не прошла. Скопируй последние 30 строк ошибки — разберёмся."
cd ../..
OUT="bilibidjon-$VERSION-$MODE.apk"
cp "$BUILD/android/app/build/outputs/apk/debug/app-debug.apk" "$OUT"

say "Готово!"
ok "Файл: $(pwd)/$OUT  ($(du -h "$OUT" | cut -f1))"
echo
echo "Как установить на телефон:"
echo "  1. Скинь $OUT на телефон (Telegram «Избранное», Google Диск или кабелем)."
echo "  2. Открой файл на телефоне → разреши «Установку из неизвестных источников»."
echo "  3. Нажми «Установить». Билибиджон на рабочем столе!"
[ "$MODE" = online ] && echo "Обновления игры дальше: bash release.sh \"что нового\" — APK пересобирать не нужно."
explorer . 2>/dev/null || true
