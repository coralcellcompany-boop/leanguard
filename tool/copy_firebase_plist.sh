#!/bin/sh
# Keep the SDK file optional for credential-free preview/CI, but validate the
# real configuration before copying it into a configured native app bundle.
set -eu
source_plist="$SRCROOT/Runner/GoogleService-Info.plist"
resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
target_plist="$resource_dir/GoogleService-Info.plist"
if [ ! -f "$source_plist" ]; then
  # A previously configured build must not contaminate a later preview build.
  rm -f "$target_plist"
  exit 0
fi
configured_bundle=$(/usr/libexec/PlistBuddy -c 'Print BUNDLE_ID' "$source_plist")
if [ "$configured_bundle" != "$PRODUCT_BUNDLE_IDENTIFIER" ]; then
  echo 'error: Firebase iOS configuration does not match PRODUCT_BUNDLE_IDENTIFIER. Download the matching app configuration.' >&2
  exit 1
fi
mkdir -p "$resource_dir"
cp "$source_plist" "$target_plist"
