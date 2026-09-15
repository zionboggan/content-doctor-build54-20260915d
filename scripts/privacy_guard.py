#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

BANNED_DART_DEPS = {
    "firebase_analytics",
    "firebase_crashlytics",
    "sentry_flutter",
    "mixpanel_flutter",
    "amplitude_flutter",
    "appcenter_analytics",
    "appcenter_crashes",
    "bugsnag_flutter",
    "datadog_flutter_plugin",
    "newrelic_mobile",
    "instabug_flutter",
}

# Iris is a WebView around a private gateway. It holds the microphone and
# nothing else, so every other permission prompt would be a lie about what the
# app does. Keys the old journal app needed are banned outright now.
BANNED_IOS_KEYS = {
    "NSCameraUsageDescription",
    "NSPhotoLibraryUsageDescription",
    "NSLocationWhenInUseUsageDescription",
    "NSLocationAlwaysUsageDescription",
    "NSLocationAlwaysAndWhenInUseUsageDescription",
    "NSContactsUsageDescription",
    "NSUserTrackingUsageDescription",
    "NSBluetoothAlwaysUsageDescription",
}

REQUIRED_IOS_KEYS = {
    # Push to talk cannot work without it, and iOS terminates the app on a
    # microphone request with no purpose string.
    "NSMicrophoneUsageDescription",
}


def fail(message: str) -> None:
    print(f"[privacy-guard] {message}")
    raise SystemExit(1)


def check_pubspec() -> None:
    text = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    for dep in sorted(BANNED_DART_DEPS):
        if re.search(rf"(?m)^\s*{re.escape(dep)}\s*:", text):
            fail(f"banned telemetry/crash dependency in pubspec.yaml: {dep}")


def check_ios_info_plist() -> None:
    text = (ROOT / "ios/Runner/Info.plist").read_text(encoding="utf-8")
    for key in sorted(BANNED_IOS_KEYS):
        if f"<key>{key}</key>" in text:
            fail(f"iOS Info.plist must not declare {key}")
    for key in sorted(REQUIRED_IOS_KEYS):
        if f"<key>{key}</key>" not in text:
            fail(f"iOS Info.plist is missing required app permission copy: {key}")


def check_ats_is_scoped() -> None:
    """A blanket ATS opt-out would let the app load cleartext from anywhere.

    The gateway has no certificate on its HTTP fallbacks, so the exception has
    to exist, but it stays pinned to the two known addresses.
    """
    text = (ROOT / "ios/Runner/Info.plist").read_text(encoding="utf-8")
    match = re.search(
        r"<key>NSAllowsArbitraryLoads</key>\s*<(true|false)\s*/>", text
    )
    if match is None:
        fail("Info.plist must state NSAllowsArbitraryLoads explicitly")
    if match.group(1) == "true":
        fail("NSAllowsArbitraryLoads must stay false; scope exceptions per host")


def main() -> int:
    check_pubspec()
    check_ios_info_plist()
    check_ats_is_scoped()
    print("[privacy-guard] clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
