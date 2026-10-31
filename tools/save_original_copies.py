"""Save the copies value of every book to original_copies.json. Reads only.

Refuses to overwrite an existing file, so the originals can never be replaced by
values changed during testing.
"""
import json
import os

import requests

PROJECT = "urk23cs5014-flutter-exp7"
URL = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    "/databases/(default)/documents/books"
)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "original_copies.json")


def main():
    if os.path.exists(OUT):
        raise SystemExit(f"{OUT} already exists")
    response = requests.get(URL, params={"pageSize": 100}, timeout=30)
    response.raise_for_status()
    books = {}
    for doc in response.json()["documents"]:
        fields = doc["fields"]
        books[doc["name"].rsplit("/", 1)[1]] = {
            "title": fields["title"]["stringValue"],
            "author": fields["author"]["stringValue"],
            "copies": int(fields["copies"]["integerValue"]),
        }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(books, f, indent=2)
        f.write("\n")
    print(json.dumps(books, indent=2))


if __name__ == "__main__":
    main()
