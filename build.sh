#!/bin/bash
# Собирает «Надиктовка.app». Нужны только Command Line Tools, Xcode не требуется.
#   ./build.sh            — собрать в dist/
#   ./build.sh install    — собрать и установить в /Applications, затем запустить
set -euo pipefail

cd "$(dirname "$0")"

EXECUTABLE="Nadiktovka"
APP_NAME="Надиктовка"
APP_DIR="dist/${APP_NAME}.app"
BIN="build/${EXECUTABLE}"

TARGET="$(uname -m)-apple-macos13.0"

echo "==> Компиляция"
mkdir -p build

# Исходники разложены по подпапкам, поэтому собираем их обходом дерева,
# а не плоским глобом. sort нужен для повторяемости порядка аргументов.
SOURCES=()
while IFS= read -r file; do
    SOURCES+=("$file")
done < <(find Sources/Nadiktovka -name '*.swift' | sort)

if [ "${#SOURCES[@]}" -eq 0 ]; then
    echo "Не найдено ни одного .swift в Sources/Nadiktovka" >&2
    exit 1
fi

swiftc \
    -swift-version 5 \
    -O \
    -target "$TARGET" \
    -o "$BIN" \
    "${SOURCES[@]}"

echo "==> Иконка"
swift Tools/MakeIcon.swift build/AppIcon.iconset >/dev/null
iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns

echo "==> Сборка бандла"
# Бандл собирается во временной папке: в Documents файлы обрастают
# метаданными Finder и iCloud, а codesign от них отказывается.
STAGE_ROOT="$(mktemp -d)"
STAGE="${STAGE_ROOT}/${APP_NAME}.app"
trap 'rm -rf "$STAGE_ROOT"' EXIT

mkdir -p "${STAGE}/Contents/MacOS" "${STAGE}/Contents/Resources"

cp "$BIN" "${STAGE}/Contents/MacOS/${EXECUTABLE}"
cp Resources/Info.plist "${STAGE}/Contents/Info.plist"
cp build/AppIcon.icns "${STAGE}/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "${STAGE}/Contents/PkgInfo"

xattr -cr "$STAGE"

# Постоянный сертификат разработчика, если он заведён в связке ключей.
# С ним macOS считает пересобранное приложение тем же самым и не сбрасывает
# «Универсальный доступ». Без него подпись ad-hoc — и разрешение слетает
# после каждой сборки.

# `|| true` обязателен: без совпадения grep возвращает 1 и set -e рвёт скрипт.
# Сертификат самоподписанный, поэтому ищем среди всех, а не только доверенных.
SIGN_IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
    | grep -o '"Nadiktovka Dev"' | head -1 | tr -d '"' || true)"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "==> Подпись сертификатом «${SIGN_IDENTITY}»"
    codesign --force --sign "$SIGN_IDENTITY" "$STAGE"
    STABLE_SIGNATURE=1
else
    echo "==> Подпись ad-hoc (постоянного сертификата нет)"
    codesign --force --sign - "$STAGE"
    STABLE_SIGNATURE=0
fi

# ditto переносит бандл, не таща за собой метаданные и не ломая подпись.
rm -rf "$APP_DIR"
mkdir -p dist
ditto --norsrc --noextattr --noqtn "$STAGE" "$APP_DIR"

if [ "${1:-}" != "install" ]; then
    echo
    echo "Готово: ${APP_DIR}"
    echo "  Установить: ./build.sh install"
    exit 0
fi

TARGET_APP="/Applications/${APP_NAME}.app"

echo "==> Установка в /Applications"
# Старая копия могла остаться запущенной — иначе не перезапишется.
pkill -x "$EXECUTABLE" 2>/dev/null || true

if [ "$STABLE_SIGNATURE" = "0" ]; then
    # У ad-hoc подписи меняется хеш, и прежнее разрешение становится
    # недействительным: галочка в списке стоит, а доступа нет. Убираем
    # мёртвую запись, чтобы галочку можно было выдать заново.
    tccutil reset Accessibility com.grisha.nadiktovka >/dev/null 2>&1 || true
    tccutil reset ListenEvent com.grisha.nadiktovka >/dev/null 2>&1 || true
fi

rm -rf "$TARGET_APP"
# Ставим подписанный оригинал, а не копию из dist — так подпись точно цела.
ditto --norsrc --noextattr --noqtn "$STAGE" "$TARGET_APP"

# Сбрасываем карантин, иначе Gatekeeper ругнётся на подпись без нотаризации.
xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

# Чтобы Finder и «Объекты входа» подхватили новую копию сразу.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "$TARGET_APP" 2>/dev/null || true

echo "==> Запуск"
# Даём Launch Services заметить, что старый процесс уже завершился,
# иначе open иногда падает с ошибкой -600.
sleep 1
open "$TARGET_APP" || { sleep 2; open "$TARGET_APP"; }

echo
echo "Установлено: ${TARGET_APP}"

if [ "$STABLE_SIGNATURE" = "0" ]; then
    echo
    echo "ВНИМАНИЕ: подпись ad-hoc — прежнее разрешение сброшено."
    echo "Выдай «Универсальный доступ» заново:"
    echo "  Системные настройки → Конфиденциальность и безопасность → Универсальный доступ"
    echo "Чтобы это перестало повторяться, заведи постоянный сертификат — см. README."
fi
