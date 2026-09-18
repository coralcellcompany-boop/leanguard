#!/usr/bin/env python3
"""Generate the iOS Google callback build setting from public Dart defines.

Usage: python3 tool/configure_firebase_native.py dart_defines.json
Run again whenever the iOS OAuth client changes. Server secrets are ignored.
"""
import argparse
import json
import re
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("defines", type=Path, help="Private --dart-define-from-file JSON")
    args = parser.parse_args()
    data = json.loads(args.defines.read_text())
    client = data.get("GOOGLE_IOS_CLIENT_ID", "").strip()
    if client and not re.fullmatch(r"[A-Za-z0-9-]+\.apps\.googleusercontent\.com", client):
        parser.error("GOOGLE_IOS_CLIENT_ID must be the real iOS OAuth client ID, not a key or URL.")
    scheme = ".".join(reversed(client.split("."))) if client else "com.coralcell.leanguard.google-unconfigured"
    target = Path(__file__).resolve().parents[1] / "ios/Flutter/Firebase.generated.xcconfig"
    target.write_text(
        "// Generated public OAuth callback identifier. Never put server secrets here.\n"
        f"GOOGLE_REVERSED_CLIENT_ID = {scheme}\n"
    )
    print("Generated iOS Google callback configuration." if client else
          "Google OAuth is not configured; native callback remains disabled.")


if __name__ == "__main__":
    main()
