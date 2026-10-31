"""Put every book's copies back to original_copies.json, then verify all 6 books.

Sends a REST update of the copies field only, so the security rules allow it.
"""
import json
import os

import requests

PROJECT = "urk23cs5014-flutter-exp7"
URL = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    "/databases/(default)/documents/books"
)
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "original_copies.json")


def set_copies(book_id, copies):
    return requests.patch(
        f"{URL}/{book_id}",
        params={"updateMask.fieldPaths": "copies", "currentDocument.exists": "true"},
        json={"fields": {"copies": {"integerValue": str(copies)}}},
        timeout=30,
    )


def main():
    with open(SRC, encoding="utf-8") as f:
        originals = json.load(f)
    for book_id, book in originals.items():
        set_copies(book_id, book["copies"]).raise_for_status()

    response = requests.get(URL, params={"pageSize": 100}, timeout=30)
    response.raise_for_status()
    docs = response.json()["documents"]
    live = {
        doc["name"].rsplit("/", 1)[1]: {
            "title": doc["fields"]["title"]["stringValue"],
            "author": doc["fields"]["author"]["stringValue"],
            "copies": int(doc["fields"]["copies"]["integerValue"]),
        }
        for doc in docs
    }
    for book_id, book in live.items():
        print(book_id, book["title"], book["copies"])
    if live != originals:
        raise SystemExit("MISMATCH: live books differ from original_copies.json")
    print(f"OK: all {len(live)} books match the originals")


if __name__ == "__main__":
    main()
