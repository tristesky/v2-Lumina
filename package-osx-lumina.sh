#!/bin/bash
set -euo pipefail

# Usage:
#   ./package-osx-lumina.sh macos-arm64 publish/lumina-osx-arm64 1.0.0
#   ./package-osx-lumina.sh macos-64    publish/lumina-osx-64    1.0.0
#
# 参数说明：
#   $1 = Arch，例如 macos-arm64 或 macos-64
#   $2 = dotnet publish 输出目录
#   $3 = 版本号，例如 1.0.0

Arch="${1:-}"
OutputPath="${2:-}"
Version="${3:-0.0.0}"

AppName="Lumina"
CoreName="v2rayN"

if [[ -z "$Arch" || -z "$OutputPath" ]]; then
  echo "Usage: ./package-osx-lumina.sh <macos-arm64|macos-64> <publish-output-dir> <version>"
  echo "Example: ./package-osx-lumina.sh macos-arm64 publish/lumina-osx-arm64 1.0.0"
  exit 1
fi

if [[ ! -d "$OutputPath" ]]; then
  echo "[ERROR] OutputPath not found: $OutputPath"
  exit 1
fi

if [[ ! -f "$OutputPath/$AppName" ]]; then
  echo "[ERROR] Main executable not found: $OutputPath/$AppName"
  echo "你需要先确认 v2rayN.Desktop.csproj 里已经改成："
  echo "  <AssemblyName>Lumina</AssemblyName>"
  echo
  echo "并且重新 dotnet publish。"
  echo
  echo "如果你输出目录里还是 v2rayN，说明 AssemblyName 还没生效。"
  exit 1
fi

if ! command -v create-dmg >/dev/null 2>&1; then
  echo "[ERROR] create-dmg not found. Install it first:"
  echo "  brew install create-dmg"
  exit 1
fi

if ! command -v 7z >/dev/null 2>&1; then
  echo "[ERROR] 7z not found. Install it first:"
  echo "  brew install p7zip"
  exit 1
fi

WorkDir="$(mktemp -d)"
trap 'rm -rf "$WorkDir"' EXIT

CoreZip="${CoreName}-${Arch}.zip"
CoreDir="${CoreName}-${Arch}"

echo "[*] Download core package: $CoreZip"

wget --show-progress --progress=bar:force -O "$WorkDir/$CoreZip" \
  "https://github.com/2dust/v2rayN-core-bin/raw/refs/heads/master/$CoreZip"

echo "[*] Extract core package"

7z x "$WorkDir/$CoreZip" -o"$WorkDir" >/dev/null

if [[ ! -d "$WorkDir/$CoreDir" ]]; then
  echo "[ERROR] Extracted core directory not found: $WorkDir/$CoreDir"
  echo "Current extracted files:"
  ls -lah "$WorkDir"
  exit 1
fi

echo "[*] Copy core files into publish output"

cp -rf "$WorkDir/$CoreDir/"* "$OutputPath/"

PackagePath="${AppName}-Package-${Arch}"
AppPath="$PackagePath/$AppName.app"
MacOSPath="$AppPath/Contents/MacOS"
ResourcesPath="$AppPath/Contents/Resources"

echo "[*] Prepare app bundle: $AppPath"

rm -rf "$PackagePath"
mkdir -p "$ResourcesPath"

cp -rf "$OutputPath" "$MacOSPath"

if [[ -f "$MacOSPath/v2rayN.icns" ]]; then
  cp -f "$MacOSPath/v2rayN.icns" "$ResourcesPath/AppIcon.icns"
else
  echo "[WARN] Icon file not found: $MacOSPath/v2rayN.icns"
  echo "       App can still be packaged, but icon may be missing."
fi

echo "When this file exists, app will not store configs under this folder" \
  > "$MacOSPath/NotStoreConfigHere.txt"

chmod +x "$MacOSPath/$AppName"

# 尽量给常见 core 加执行权限，不存在就跳过
find "$MacOSPath" -type f \( \
  -name "xray" -o \
  -name "sing-box" -o \
  -name "hysteria" -o \
  -name "hysteria2" -o \
  -name "tuic" -o \
  -name "mieru" -o \
  -name "juicity" -o \
  -name "brook" -o \
  -name "naive" -o \
  -name "naiveproxy" \
\) -exec chmod +x {} \; 2>/dev/null || true

cat > "$AppPath/Contents/Info.plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>English</string>

  <key>CFBundleDisplayName</key>
  <string>${AppName}</string>

  <key>CFBundleExecutable</key>
  <string>${AppName}</string>

  <key>CFBundleIconFile</key>
  <string>AppIcon</string>

  <key>CFBundleIconName</key>
  <string>AppIcon</string>

  <key>CFBundleIdentifier</key>
  <string>com.lumina.systems.lumina</string>

  <key>CFBundleName</key>
  <string>${AppName}</string>

  <key>CFBundlePackageType</key>
  <string>APPL</string>

  <key>CFBundleShortVersionString</key>
  <string>${Version}</string>

  <key>CFBundleVersion</key>
  <string>${Version}</string>

  <key>CSResourcesFileMapped</key>
  <true/>

  <key>NSHighResolutionCapable</key>
  <true/>

  <key>LSMinimumSystemVersion</key>
  <string>12.7</string>
</dict>
</plist>
EOF_PLIST

DmgName="${AppName}-${Arch}.dmg"

echo "[*] Remove old dmg if exists: $DmgName"
rm -f "$DmgName"

echo "[*] Create dmg: $DmgName"

create-dmg \
  --volname "${AppName} Installer" \
  --window-size 700 420 \
  --icon-size 100 \
  --icon "${AppName}.app" 160 185 \
  --hide-extension "${AppName}.app" \
  --app-drop-link 500 185 \
  "$DmgName" \
  "$AppPath"

echo
echo "======================================"
echo "Done."
echo "App bundle:"
echo "  $AppPath"
echo
echo "DMG:"
echo "  $DmgName"
echo "======================================"
