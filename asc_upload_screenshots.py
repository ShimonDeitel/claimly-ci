#!/usr/bin/env python3
"""Upload app screenshots to App Store Connect via the API.
Requires env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, APP_ID, SCREENSHOT_PATH, DISPLAY_TYPE
DISPLAY_TYPE example: APP_IPHONE_67
This targets the primary app version's screenshot set for the given localization (en-US),
creating the set if it doesn't exist, then reserves+uploads+commits the asset.
"""
import base64
import hashlib
import json
import os
import sys
import time
import urllib.request
import urllib.error

import jwt

ASC_KEY_ID = os.environ["ASC_KEY_ID"]
ASC_ISSUER_ID = os.environ["ASC_ISSUER_ID"]
ASC_KEY_PATH = os.environ["ASC_KEY_PATH"]
APP_ID = os.environ["APP_ID"]
SCREENSHOT_PATH = os.environ["SCREENSHOT_PATH"]
DISPLAY_TYPE = os.environ.get("DISPLAY_TYPE", "APP_IPHONE_67")

BASE = "https://api.appstoreconnect.apple.com/v1"


def make_jwt():
    with open(ASC_KEY_PATH) as f:
        private_key = f.read()
    now = int(time.time())
    payload = {
        "iss": ASC_ISSUER_ID,
        "iat": now,
        "exp": now + 19 * 60,
        "aud": "appstoreconnect-v1",
    }
    headers = {"kid": ASC_KEY_ID, "typ": "JWT"}
    return jwt.encode(payload, private_key, algorithm="ES256", headers=headers)


def req(method, path, token, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    r.add_header("Authorization", f"Bearer {token}")
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        print(f"HTTP {e.code} on {method} {url}: {raw.decode()[:2000]}", file=sys.stderr)
        raise


def main():
    token = make_jwt()

    # 1. find the app's editable version (PREPARE_FOR_SUBMISSION or similar)
    status, versions = req("GET", f"/apps/{APP_ID}/appStoreVersions?limit=5", token)
    editable = None
    for v in versions["data"]:
        st = v["attributes"]["appVersionState"]
        if st in ("PREPARE_FOR_SUBMISSION", "REJECTED", "DEVELOPER_REJECTED", "WAITING_FOR_REVIEW", "READY_FOR_SALE"):
            editable = v
            break
    if not editable:
        print("No suitable app store version found; listing all:", [v["attributes"]["appVersionState"] for v in versions["data"]])
        sys.exit(1)
    version_id = editable["id"]
    print(f"Using version {version_id} (state={editable['attributes']['appVersionState']})")

    # 2. get localizations for this version
    status, locs = req("GET", f"/appStoreVersions/{version_id}/appStoreVersionLocalizations", token)
    loc = next((l for l in locs["data"] if l["attributes"]["locale"] == "en-US"), None)
    if not loc:
        print("No en-US localization found")
        sys.exit(1)
    loc_id = loc["id"]

    # 3. get or create the screenshot set for DISPLAY_TYPE
    status, sets_resp = req("GET", f"/appStoreVersionLocalizations/{loc_id}/appScreenshotSets", token)
    existing_set = next((s for s in sets_resp["data"] if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE), None)
    if existing_set:
        set_id = existing_set["id"]
        print(f"Using existing screenshot set {set_id}")
    else:
        body = {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": loc_id}}
                },
            }
        }
        status, created = req("POST", "/appScreenshotSets", token, body)
        set_id = created["data"]["id"]
        print(f"Created screenshot set {set_id}")

    # 4. reserve an appScreenshot asset
    file_size = os.path.getsize(SCREENSHOT_PATH)
    file_name = os.path.basename(SCREENSHOT_PATH)
    body = {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": file_name, "fileSize": file_size},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
        }
    }
    status, reserved = req("POST", "/appScreenshots", token, body)
    screenshot_id = reserved["data"]["id"]
    upload_ops = reserved["data"]["attributes"]["uploadOperations"]
    print(f"Reserved screenshot {screenshot_id}, {len(upload_ops)} upload op(s)")

    # 5. upload the bytes per uploadOperations
    with open(SCREENSHOT_PATH, "rb") as f:
        file_bytes = f.read()
    for op in upload_ops:
        offset = op["offset"]
        length = op["length"]
        chunk = file_bytes[offset:offset + length]
        url = op["url"]
        method = op["method"]
        r = urllib.request.Request(url, data=chunk, method=method)
        for h in op["requestHeaders"]:
            r.add_header(h["name"], h["value"])
        with urllib.request.urlopen(r) as resp:
            print(f"Uploaded chunk offset={offset} len={length} status={resp.status}")

    # 6. commit — set sourceFileChecksum + uploaded=true
    checksum = hashlib.md5(file_bytes).hexdigest()
    body = {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {"sourceFileChecksum": checksum, "uploaded": True},
        }
    }
    status, patched = req("PATCH", f"/appScreenshots/{screenshot_id}", token, body)
    print(f"Committed screenshot {screenshot_id}")

    # 7. poll until COMPLETE
    for _ in range(30):
        status, check = req("GET", f"/appScreenshots/{screenshot_id}", token)
        state = check["data"]["attributes"]["assetDeliveryState"]["state"]
        print(f"assetDeliveryState={state}")
        if state == "COMPLETE":
            print("SCREENSHOT_UPLOAD_COMPLETE")
            print(f"SCREENSHOT_ID={screenshot_id}")
            return
        if state == "FAILED":
            print("SCREENSHOT_UPLOAD_FAILED", check["data"]["attributes"]["assetDeliveryState"])
            sys.exit(1)
        time.sleep(3)
    print("Timed out waiting for COMPLETE state")
    sys.exit(1)


if __name__ == "__main__":
    main()
