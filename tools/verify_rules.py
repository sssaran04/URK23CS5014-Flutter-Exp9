"""Prove the deployed rules with unauthenticated REST calls, as any client would send.

Uses one book and always restores its copies. Stops before the create and delete
tests if the title test shows the new rules are not live, so a book is never added
or lost. The delete test carries a wrong updateTime precondition as well, so it
cannot remove the book even if the rule were wrong.
"""
import json
import os

import requests

PROJECT = "urk23cs5014-flutter-exp7"
URL = (
    f"https://firestore.googleapis.com/v1/projects/{PROJECT}"
    "/databases/(default)/documents/books"
)
BOOK_ID = "9781491950357"  # Building Microservices
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "original_copies.json")


def patch(field, value):
    return requests.patch(
        f"{URL}/{BOOK_ID}",
        params={"updateMask.fieldPaths": field, "currentDocument.exists": "true"},
        json={"fields": {field: value}},
        timeout=30,
    )


def check(label, response, expected):
    ok = response.status_code == expected
    print(f"{'PASS' if ok else 'FAIL'}  {label}: HTTP {response.status_code} (expected {expected})")
    return ok


def main():
    with open(SRC, encoding="utf-8") as f:
        original = json.load(f)[BOOK_ID]["copies"]
    int_value = lambda n: {"integerValue": str(n)}
    results = []
    try:
        results.append(check("update copies", patch("copies", int_value(original + 1)), 200))
        title_ok = check("change title", patch("title", {"stringValue": "Hacked"}), 403)
        results.append(title_ok)
        results.append(check("copies = -1", patch("copies", int_value(-1)), 403))
        results.append(check("copies = 1001", patch("copies", int_value(1001)), 403))
        results.append(check("copies as text", patch("copies", {"stringValue": "5"}), 403))
        if not title_ok:
            raise SystemExit("New rules are not live; skipping create and delete tests")
        results.append(check(
            "create book",
            requests.post(
                URL,
                params={"documentId": "rule-test-must-not-exist"},
                json={"fields": {"title": {"stringValue": "Rule test"}}},
                timeout=30,
            ),
            403,
        ))
        results.append(check(
            "delete book",
            requests.delete(
                f"{URL}/{BOOK_ID}",
                params={"currentDocument.updateTime": "2000-01-01T00:00:00Z"},
                timeout=30,
            ),
            403,
        ))
    finally:
        restored = patch("copies", int_value(original))
        restored.raise_for_status()
        print(f"restored copies of {BOOK_ID} to {original}")
    if not all(results):
        raise SystemExit("Some rule checks failed")
    print("All rule checks passed")


if __name__ == "__main__":
    main()
