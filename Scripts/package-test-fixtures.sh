#!/bin/sh
set -eu
# Tests execute on Cloud workers without the build worker's source checkout.
# Carry the exact reviewed inputs in the test product, before Xcode signs it.
fixtures="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}/RepositoryFixtures"
# A removed source must not survive in an incremental test build.
/bin/rm -rf "$fixtures"
mkdir -p "$fixtures/Documentation/AppStore" "$fixtures/Resources/Watch" "$fixtures/Config" "$fixtures/Tests/APlayaNamedGusTests"
/usr/bin/ditto "$SRCROOT/Sources" "$fixtures/Sources"
/usr/bin/ditto "$SRCROOT/Resources/Assets.xcassets" "$fixtures/Resources/Assets.xcassets"
/usr/bin/ditto "$SRCROOT/Resources/Watch/Assets.xcassets" "$fixtures/Resources/Watch/Assets.xcassets"
cp "$SRCROOT/Documentation/AppStore/apple-app-site-association.json" "$fixtures/Documentation/AppStore/apple-app-site-association.json"
cp "$SRCROOT/Resources/Info.plist" "$fixtures/Resources/Info.plist"
cp "$SRCROOT/Config/Shared.xcconfig" "$fixtures/Config/Shared.xcconfig"
cp "$SRCROOT/project.yml" "$fixtures/project.yml"
cp "$SRCROOT/Tests/APlayaNamedGusTests/StreamURLBuilderTests.swift" "$fixtures/Tests/APlayaNamedGusTests/StreamURLBuilderTests.swift"
# Never package Local.xcconfig, environment files, credentials, or signing keys.
for file in "$SRCROOT"/Config/*.entitlements; do
    cp "$file" "$fixtures/Config/"
done
