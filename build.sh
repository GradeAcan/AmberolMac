#!/usr/bin/env bash
set -e

APP_NAME="AmberolMac"
BUNDLE="$APP_NAME.app"

echo "🔨 Construction, packaging et signature de $BUNDLE..."

# 1. Nettoyage et création de l'arborescence
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

# 2. Génération d'un Info.plist complet avec types de documents supportés
cat << 'EOF' > "$BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AmberolMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.AmberolMac</string>
    <key>CFBundleName</key>
    <string>AmberolMac</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <false/>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Fichier Audio</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSHandlerRank</key>
            <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.audio</string>
                <string>public.mp3</string>
                <string>com.apple.m4a-audio</string>
                <string>org.xiph.flac</string>
                <string>org.xiph.opus</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
EOF

# 3. Compilation Swift optimisée directement dans le bundle
swiftc -O -parse-as-library main.swift -o "$BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Signature ad-hoc obligatoire pour débloquer le MediaRemote / Control Center
codesign --force --deep -s - "$BUNDLE"

echo "✨ Application prête et signée avec succès !"
