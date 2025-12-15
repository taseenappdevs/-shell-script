#!/bin/bash
set -e

# ========================
# CONFIGURATION
# ========================
GITHUB_USER="appdevsx"

# Apps List (Format: repo_name:apk_name)
APPS_LIST=(
  "Efunding-v2-App:eFunding"
  "tiktok-shop-v2-app:tiktok-shop"
  "crypinvest-v2-app:crypinvest"
  "Xremit-Pro-App:xremit"
  "escroc-app-v2:escroc"

  
)

# ========================
# 1. Select App using fzf
# ========================
# Convert array to repo names for fzf
apps=()
for APP in "${APPS_LIST[@]}"; do
    apps+=("${APP%%:*}")
done

# fzf searchable selection
selected_app=$(printf "%s\n" "${apps[@]}" | fzf --prompt="Search app: " --height=15 --border)

if [ -z "$selected_app" ]; then
    echo "❌ No app selected. Exiting."
    exit 1
fi

# Get APK_NAME from APPS_LIST
for APP in "${APPS_LIST[@]}"; do
    REPO_NAME="${APP%%:*}"
    APK_NAME="${APP##*:}"
    if [ "$selected_app" == "$REPO_NAME" ]; then
        APP_NAME="$REPO_NAME"
        break
    fi
done

echo "✅ Selected App: $APP_NAME"
echo "✅ APK Name Prefix: $APK_NAME"

# ========================
# 2. Clone Repository
# ========================
if [ -d "$APP_NAME" ]; then
    echo "⚠️  Directory $APP_NAME exists. Removing it..."
    rm -rf "$APP_NAME"
fi

echo "⬇️  Cloning $APP_NAME from GitHub..."
git clone "https://github.com/${GITHUB_USER}/${APP_NAME}.git"
cd "$APP_NAME"

if [ ! -f "pubspec.yaml" ]; then
    echo "❌ Error: pubspec.yaml not found. Not a Flutter project?"
    cd ..
    exit 1
fi

# ========================
# 3. Detect Latest & Previous Version Branches
# ========================
echo "🔹 Detecting latest and previous version branches..."

# Fetch all remote branches
git fetch --all

# List version branches sorted by semantic version (version-x.y.z)
VERSION_BRANCHES=$(git branch -r | grep 'origin/v' | sed 's|origin/||' | sort -rV)

NEW_VERSION=$(echo "$VERSION_BRANCHES" | head -n1 | xargs)
PREVIOUS_VERSION=$(echo "$VERSION_BRANCHES" | sed -n '2p' | xargs)

if [ -z "$NEW_VERSION" ] || [ -z "$PREVIOUS_VERSION" ]; then
    echo "❌ Could not detect latest or previous version branches. Make sure branches exist with format version-x.y.z"
    exit 1
fi

echo "✅ Latest version branch detected: $NEW_VERSION"
echo "✅ Previous version branch detected: $PREVIOUS_VERSION"

# ========================
# 4. Flutter Build
# ========================
echo "🚀 Starting Flutter Build for $APP_NAME..."
flutter clean
# flutter pub get # Optimization: User previously asked to skip pub get during comparison, but here we need it for build. 
# However, this build section comes AFTER branch detection.
# We need to be on the NEW_VERSION branch to build the latest code.
# The script cloned the repo, but didn't explicitly checkout a branch yet (default is usually main/master).
# We should checkout NEW_VERSION before building.

git checkout "$NEW_VERSION"
flutter pub get
flutter build apk --target-platform android-arm,android-arm64,android-x64 --split-per-abi

# ========================
# 5. Prepare Release Folder
# ========================
cd ..
RELEASE_ROOT="${APK_NAME}-release-bundle-${NEW_VERSION}"

# Clean up previous release dir
rm -rf "$RELEASE_ROOT"
mkdir -p "$RELEASE_ROOT"

# 1. APK Folder
APK_DIR="$RELEASE_ROOT/apk"
mkdir -p "$APK_DIR"

echo "📂 Organizing files in $RELEASE_ROOT..."

# Copy APKs
# Check and copy split-per-abi APKs
if [ -f "${APP_NAME}/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" ]; then
    cp "${APP_NAME}/build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk" "$APK_DIR/${APK_NAME}-armeabi-v7a.apk"
fi

if [ -f "${APP_NAME}/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" ]; then
    cp "${APP_NAME}/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk" "$APK_DIR/${APK_NAME}-arm64-v8a.apk"
fi

# Fallback check for universal release or others
if [ -f "${APP_NAME}/build/app/outputs/flutter-apk/app-release.apk" ]; then
    cp "${APP_NAME}/build/app/outputs/flutter-apk/app-release.apk" "$APK_DIR/${APK_NAME}-release.apk"
fi

# ========================
# 6. Copy Full Project Code
# ========================
FULL_CODE_DIR="$RELEASE_ROOT/${APK_NAME}-app-new-${NEW_VERSION}"
mkdir -p "$FULL_CODE_DIR"

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

# ========================
# 7. Generate Updated Files Between Branches
# ========================
echo "🔹 Generating updated files between $PREVIOUS_VERSION and $NEW_VERSION..."

# Go back to repo dir to run git commands
cd "$APP_NAME"

# Get changed files between branches
UPDATED_FILES=$(git diff --name-only "origin/$PREVIOUS_VERSION" "origin/$NEW_VERSION")

cd .. # Back to parent containing RELEASE_ROOT

UPDATED_FILES_DIR="$RELEASE_ROOT/${APK_NAME}-app-only-updated-files-${PREVIOUS_VERSION}-${NEW_VERSION}"
mkdir -p "$UPDATED_FILES_DIR"

if [ -z "$UPDATED_FILES" ]; then
    echo "ℹ️  No changes detected between $PREVIOUS_VERSION and $NEW_VERSION."
else
    echo "📂 Copying updated files to $UPDATED_FILES_DIR..."
    # We need to copy files from the APP_NAME directory (which is currently checked out to NEW_VERSION)
    
    for FILE in $UPDATED_FILES; do
        SOURCE_FILE="${APP_NAME}/$FILE"
        if [ -f "$SOURCE_FILE" ]; then
            DEST_DIR="$UPDATED_FILES_DIR/$(dirname "$FILE")"
            mkdir -p "$DEST_DIR"
            cp "$SOURCE_FILE" "$DEST_DIR/"
        fi
    done

    # Always include pubspec.yaml
    if [ -f "${APP_NAME}/pubspec.yaml" ]; then
         cp "${APP_NAME}/pubspec.yaml" "$UPDATED_FILES_DIR/"
    fi
fi

# ========================
# 8. Create Final Zip Archive
# ========================
echo "📦 Creating final zip archive..."
zip -r "${RELEASE_ROOT}.zip" "$RELEASE_ROOT"

# ========================
# 9. Final Message
# ========================
echo "✅ ==========================================="
echo "🎉 Build & Packaging Complete!"
echo "📂 Output Directory: $(pwd)/$RELEASE_ROOT"
echo "📦 Final Zip: $(pwd)/${RELEASE_ROOT}.zip"
echo "   ├── apk/"
echo "   ├── ${APK_NAME}-app-new-${NEW_VERSION}/"
echo "   └── ${APK_NAME}-app-only-updated-files-${PREVIOUS_VERSION}-${NEW_VERSION}/"
echo "✅ ==========================================="