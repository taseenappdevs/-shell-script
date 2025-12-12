#!/bin/bash
set -e

# ==== Configuration ====
# REPLACE WITH YOUR GITHUB USERNAME OR ORGANIZATION NAME
GITHUB_USER="taseenappdevs" 
# List of applications to display
APPS=("qrpay-user" "qrpay-agent" "walletium" "multi-radio" "Enter Custom Name")

# ==== 1. Input Versions ====
echo "🔹 Enter the NEW version (e.g., v3.2.0):"
read -r NEW_VERSION

echo "🔹 Enter the PREVIOUS version (e.g., v3.1.1):"
read -r PREVIOUS_VERSION

if [ -z "$NEW_VERSION" ] || [ -z "$PREVIOUS_VERSION" ]; then
  echo "❌ Error: detailed versions are required."
  exit 1
fi

# ==== 2. Select App ====
echo "🔹 Select the application to build:"
PS3="Please enter your choice (number): "
select APP_NAME in "${APPS[@]}"; do
    if [ "$APP_NAME" == "Enter Custom Name" ]; then
        echo "Enter the custom application name (must match repo name):"
        read -r APP_NAME
    fi
    
    if [ -n "$APP_NAME" ]; then
        echo "✅ Selected App: $APP_NAME"
        break
    else
        echo "❌ Invalid selection. Try again."
    fi
done

# ==== 3. Clone Repository ====
# Remove existing folder if it exists to ensure clean clone
if [ -d "$APP_NAME" ]; then
    echo "⚠️  Directory $APP_NAME exists. Removing it to clone fresh..."
    rm -rf "$APP_NAME"
fi

echo "⬇️  Cloning $APP_NAME from GitHub (default branch)..."
# Try SSH first, fallback to HTTPS or just assume one. 
# Using HTTPS format for general compatibility if no keys, or let user configure.
# Assuming standard github url structure.
git clone "https://github.com/${GITHUB_USER}/${APP_NAME}.git"

cd "$APP_NAME"

# Check if clone was successful
if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found. Clone might have failed or this is not a Flutter project."
    cd ..
    exit 1
fi

# ==== 4. Flutter Build ====
echo "🚀 Starting Flutter Build for $APP_NAME..."
flutter clean
flutter pub get
flutter build apk --target-platform android-arm,android-arm64,android-x64 --split-per-abi

# ==== 5. Prepare Release Folder Structure ====
# We are currently INSIDE the app folder.
# We want to create the release artifacts in the PARENT directory (where the script ran).

cd ..
RELEASE_ROOT="${APP_NAME}-release-bundle-${NEW_VERSION}"
APP_RELEASE_DIR="${APP_NAME}-app-${NEW_VERSION}"

# Clean up previous release dir
rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT/$APP_RELEASE_DIR/apk"

echo "📂 Organizing files in $RELEASE_ROOT..."

# Copy APKs
# Note: Path to build differs now because we are outside the app folder
cp "${APP_NAME}/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" \
   "$RELEASE_ROOT/$APP_RELEASE_DIR/apk/${APP_NAME}-armeabi-v7a.apk"

cp "${APP_NAME}/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" \
   "$RELEASE_ROOT/$APP_RELEASE_DIR/apk/${APP_NAME}-arm64-v8a.apk"

# Optional: x86_64
# cp "${APP_NAME}/build/app/outputs/flutter-apk/app-x86_64-release.apk" \
#    "$RELEASE_ROOT/$APP_RELEASE_DIR/apk/${APP_NAME}-x86_64.apk"


# ==== 6. Copy Full Project Code (Cleaned) ====
# We want a copy of the SOURCE code in the release folder.
FULL_CODE_DIR="$RELEASE_ROOT/$APP_RELEASE_DIR/${APP_NAME}-app-new-${NEW_VERSION}"
mkdir -p "$FULL_CODE_DIR"

# Rsync from the cloned folder to the release folder
rsync -av \
  --exclude '.git' \
  --exclude '.gitignore' \
  --exclude '.gitattributes' \
  --exclude '.github' \
  --exclude '.dart_tool' \
  --exclude '.idea' \
  --exclude '.vscode' \
  --exclude 'build' \
  --exclude '.gradle' \
  --exclude 'build_file.sh' \
  "${APP_NAME}/" \
  "$FULL_CODE_DIR/"

# Remove git remotes just in case (though we excluded .git, so this is redundant but safe)
# Logic from original script:
# if [ -d "$FULL_CODE_DIR/.git" ]; then ... fi 
# Since we excluded .git, we don't need to remove remotes.


# ==== 7. Copy Only Updated Files (Lib + Pubspec) ====
UPDATED_FILES_DIR="$RELEASE_ROOT/$APP_RELEASE_DIR/${APP_NAME}-app-only-updated-files-${PREVIOUS_VERSION}-to-${NEW_VERSION}"
mkdir -p "$UPDATED_FILES_DIR/lib"

cp -r "${APP_NAME}/lib/"* "$UPDATED_FILES_DIR/lib/"
cp "${APP_NAME}/pubspec.yaml" "$UPDATED_FILES_DIR/"


# ==== 8. Create Zip Archives ====
echo "📦 Creating Zip Archives..."

cd "$RELEASE_ROOT"

# Zip 1: The Full Code Folder
cd "$APP_RELEASE_DIR"
# zip -r "${APP_NAME}-app-new-${NEW_VERSION}.zip" "${APP_NAME}-app-new-${NEW_VERSION}"
# rm -rf "${APP_NAME}-app-new-${NEW_VERSION}" # Keeping folder as per screenshot logic
cd ..

# Zip 2: The Only Updated Files Folder
cd "$APP_RELEASE_DIR"
# zip -r "${APP_NAME}-app-only-updated-files-${PREVIOUS_VERSION}-to-${NEW_VERSION}.zip" "${APP_NAME}-app-only-updated-files-${PREVIOUS_VERSION}-to-${NEW_VERSION}"
# rm -rf "${APP_NAME}-app-only-updated-files-${PREVIOUS_VERSION}-to-${NEW_VERSION}" # Keeping folder as per screenshot logic
cd ..

# Zip 3: The Entire Package (APKs + Zips)
zip -r "${APP_NAME}-app-${NEW_VERSION}.zip" "$APP_RELEASE_DIR"

echo "✅ ==========================================="
echo "🎉 Build & Packaging Complete!"
echo "📂 Output Location: $(pwd)/${APP_NAME}-app-${NEW_VERSION}.zip"
echo "✅ ==========================================="

# Cleanup the cloned repo?
# echo "Cleaning up cloned repo..."
# rm -rf "$APP_NAME"