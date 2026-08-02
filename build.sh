#!/bin/bash
# Собирает «Надиктовка.app». Нужны только Command Line Tools, Xcode не требуется.
#   ./build.sh            — собрать в dist/
#   ./build.sh install    — собрать и установить в /Applications, затем запустить
#   ./build.sh dmg        — собрать образ для раздачи в dist/
#   ./build.sh zip        — собрать архив для раздачи в dist/
set -euo pipefail

cd "$(dirname "$0")"

EXECUTABLE="Nadiktovka"
APP_NAME="SayPer"
APP_DIR="dist/${APP_NAME}.app"
BIN="build/${EXECUTABLE}"

TARGET="$(uname -m)-apple-macos26.0"

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

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${STAGE}/Contents/Info.plist")"

if [ "${1:-}" = "zip" ]; then
    ZIP="dist/${APP_NAME}-${VERSION}.zip"
    echo "==> Архив ${ZIP}"
    rm -f "$ZIP"
    # ditto сохраняет подпись; --keepParent кладёт в архив саму папку .app.
    ditto -c -k --keepParent --norsrc --noextattr "$STAGE" "$ZIP"
    echo
    echo "Готово: ${ZIP}  ($(du -h "$ZIP" | cut -f1))"
    exit 0
fi

if [ "${1:-}" = "dmg" ]; then
    DMG="dist/${APP_NAME}-${VERSION}.dmg"
    echo "==> Образ ${DMG}"

    echo "  фон"
    swift Tools/MakeDMGBackground.swift build/dmg-background >/dev/null

    # Содержимое образа собираем отдельной папкой: в неё кладём приложение,
    # ссылку на «Программы» и скрытый фон.
    ROOM="$(mktemp -d)"
    ditto --norsrc --noextattr --noqtn "$STAGE" "${ROOM}/${APP_NAME}.app"
    ln -s /Applications "${ROOM}/Applications"
    mkdir -p "${ROOM}/.background"
    cp build/dmg-background@2x.png "${ROOM}/.background/background.png"

    RW="$(mktemp -d)/rw.dmg"
    rm -f "$DMG"
    # UDRW: образ нужен записываемым, чтобы Finder сохранил в нём раскладку окна.
    hdiutil create -srcfolder "$ROOM" -volname "$APP_NAME" -fs HFS+ \
        -format UDRW -ov "$RW" >/dev/null

    MOUNT="/Volumes/${APP_NAME}"
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    hdiutil attach "$RW" -readwrite -noverify -noautoopen >/dev/null

    echo "  раскладка окна"
    # Координаты повторяют Tools/MakeDMGBackground.swift — правятся вместе.
    # Finder считает от левого верхнего угла, фон рисуется от левого нижнего.
    osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
    tell disk "${APP_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set sidebar width of container window to 0
        -- Высота окна = высота фона плюс полоса заголовка: bounds задаёт рамку
        -- целиком, а фон рисуется только в содержимом, и без этой добавки
        -- нижний край картинки обрезается.
        set the bounds of container window to {200, 120, 820, 578}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 112
        set text size of opts to 12
        set background picture of opts to file ".background:background.png"
        set position of item "${APP_NAME}.app" of container window to {165, 205}
        set position of item "Applications" of container window to {455, 205}
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
APPLESCRIPT

    # Права на чтение всем — иначе у скачавшего образ может не открыться.
    chmod -Rf go-w "$MOUNT" 2>/dev/null || true
    sync
    hdiutil detach "$MOUNT" >/dev/null

    echo "  сжатие"
    hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
    rm -rf "$ROOM" "$(dirname "$RW")"

    if [ -n "$SIGN_IDENTITY" ]; then
        codesign --force --sign "$SIGN_IDENTITY" "$DMG"
    fi

    echo
    echo "Готово: ${DMG}  ($(du -h "$DMG" | cut -f1))"
    exit 0
fi

if [ "${1:-}" != "install" ]; then
    echo
    echo "Готово: ${APP_DIR}  (версия ${VERSION})"
    echo "  Установить: ./build.sh install"
    echo "  Собрать образ: ./build.sh dmg"
    echo "  Собрать архив: ./build.sh zip"
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
