#!/bin/bash
# ============================================================
# Inject Aimbot dylib vào FreeFireMAX.ipa
# Yêu cầu: macOS + Xcode + Theos + ldid
# ============================================================

IPA_PATH="$1"
if [ -z "$IPA_PATH" ]; then
    echo "Usage: $0 /path/to/FreeFireMax.ipa"
    exit 1
fi

TEMP_DIR="/tmp/ff_inject_$$"
OUTPUT_IPA="${IPA_PATH%.*}_modded.ipa"

echo "[*] Extracting IPA..."
unzip -q "$IPA_PATH" -d "$TEMP_DIR"
APP_DIR=$(find "$TEMP_DIR/Payload" -name "*.app" -type d | head -1)
APP_NAME=$(basename "$APP_DIR")
EXECUTABLE=$(plutil -p "$APP_DIR/Info.plist" | grep CFBundleExecutable | awk -F'"' '{print $4}')

echo "[*] App: $APP_NAME"
echo "[*] Executable: $EXECUTABLE"

# Copy libsubstrate.dylib
cp "$THEOS/lib/libsubstrate.dylib" "$APP_DIR/Frameworks/"
ldid -S "$APP_DIR/Frameworks/libsubstrate.dylib"

# Copy aimbot tweak dylib
cp packages/FFAimbot.dylib "$APP_DIR/Frameworks/"
ldid -S "$APP_DIR/Frameworks/FFAimbot.dylib"

# Inject dylib vào executable
echo "[*] Injecting dylibs..."

# Lấy danh sách các framework cần inject
for dylib in libsubstrate.dylib FFAimbot.dylib; do
    FRAMEWORK_PATH="@executable_path/Frameworks/$dylib"
    
    # Kiểm tra xem đã inject chưa
    if ! otool -L "$APP_DIR/$EXECUTABLE" | grep -q "$dylib"; then
        echo "[*] Injecting $dylib..."
        insert_dylib --inplace --all-yes "$FRAMEWORK_PATH" "$APP_DIR/$EXECUTABLE"
    fi
done

# Sign lại entitlements
echo "[*] Re-signing..."
ldid -S"$APP_DIR/embedded.mobileprovision" "$APP_DIR/$EXECUTABLE"
ldid -S"$APP_DIR/embedded.mobileprovision" "$APP_DIR/Frameworks/libsubstrate.dylib"
ldid -S"$APP_DIR/embedded.mobileprovision" "$APP_DIR/Frameworks/FFAimbot.dylib"
ldid -S"$APP_DIR/embedded.mobileprovision" "$APP_DIR/Frameworks/UnityFramework.framework/UnityFramework"

# Packaging
echo "[*] Creating modded IPA..."
cd "$TEMP_DIR"
zip -qr "$OUTPUT_IPA" "Payload/"
echo "[*] Done! Output: $OUTPUT_IPA"
