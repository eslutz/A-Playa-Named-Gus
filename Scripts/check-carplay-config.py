#!/usr/bin/env python3
"""Verify the CarPlay scene and the iOS-only signing configuration."""
from pathlib import Path
import plistlib

keys = {"com.apple.developer.carplay-audio", "com.apple.developer.siri"}
for path in Path("Config").glob("*.entitlements"):
    entitlements = plistlib.loads(path.read_bytes())
    expected = keys if path.name == "Gus-iOS.entitlements" else set()
    assert keys.intersection(entitlements) == expected, path
    assert all(entitlements[key] is True for key in expected), path
config = Path("Config/Shared.xcconfig").read_text()
for sdk in ("iphoneos", "iphonesimulator"):
    assert f"CODE_SIGN_ENTITLEMENTS[sdk={sdk}*] = Config/Gus-iOS.entitlements" in config
info = plistlib.loads(Path("Resources/Info.plist").read_bytes())
manifest = info["UIApplicationSceneManifest"]
assert manifest["UIApplicationSupportsMultipleScenes"] is True
scene, = manifest["UISceneConfigurations"]["CPTemplateApplicationSceneSessionRoleApplication"]
assert scene["UISceneClassName"] == "CPTemplateApplicationScene"
assert scene["UISceneDelegateClassName"] == "$(PRODUCT_MODULE_NAME).GusCarPlaySceneDelegate"
assert "audio" in info["UIBackgroundModes"]
assert "INPlayMediaIntent" in info["INIntentsSupported"]
assert set(info["INSupportedMediaCategories"]) == {"INMediaCategoryMusic", "INMediaCategoryAudiobooks"}
assert info["NSSiriUsageDescription"]
