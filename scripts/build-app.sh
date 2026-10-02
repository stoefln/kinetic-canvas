#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
configuration="${1:-release}"
app_dir="$repo_dir/.build/DanceFX.app"
model_paths=(
    "$repo_dir/Vendor/Models/rvm_mobilenetv3_640x360_s0.5_fp16.mlmodel"
    "$repo_dir/Vendor/Models/rvm_mobilenetv3_1280x720_s0.375_fp16.mlmodel"
)
model_license="$repo_dir/Vendor/RobustVideoMatting-LICENSE.txt"

cd "$repo_dir"
export CLANG_MODULE_CACHE_PATH="$repo_dir/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_dir/.build/swiftpm-module-cache"
swift build --disable-sandbox -c "$configuration"
binary_dir="$(swift build --disable-sandbox -c "$configuration" --show-bin-path)"

mkdir -p "$app_dir/Contents/MacOS"
mkdir -p "$app_dir/Contents/Resources"
cp "$repo_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$binary_dir/DanceFX" "$app_dir/Contents/MacOS/DanceFX"
for model_path in "${model_paths[@]}"; do
    xcrun coremlcompiler compile "$model_path" "$app_dir/Contents/Resources" \
        --platform macOS --deployment-target 14.0
done
cp "$model_license" "$app_dir/Contents/Resources/RobustVideoMatting-LICENSE.txt"
for video_asset in "$repo_dir"/Assets/*; do
    extension="${video_asset##*.}"
    case "$extension" in
        m4v|M4V|mov|MOV|mp4|MP4)
            cp "$video_asset" "$app_dir/Contents/Resources/${video_asset:t}"
            ;;
    esac
done
rm -rf "$app_dir/Contents/_CodeSignature"
xattr -cr "$app_dir"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
