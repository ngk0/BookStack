#!/usr/bin/env python3
"""One-off + repeatable BookStack content organizer.

Goals:
- Shelve known unshelved books.
- Move direct (book-level) pages into chapters.
- Move empty chapters into a holding book.
- Delete obvious junk pages ("New Page", "Test") when effectively empty.

Default mode is DRY-RUN. Use --apply to perform changes.

Run as the stack owner user (admin) so we can read setup/.env.setup.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.parse
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent

ENV_SETUP_PATH = SCRIPT_DIR / ".env.setup"
ENV_APP_PATH = PROJECT_DIR / ".env"

HOLDING_SHELF_NAME = "9. Orphaned"
HOLDING_BOOK_NAME = "Empty Chapters Holding"
INBOX_CHAPTER_NAME = "00. Inbox (Unsorted)"


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def load_env_file(path: Path) -> Dict[str, str]:
    """Parse a simple KEY=VALUE .env file (supports quoted values)."""
    env: Dict[str, str] = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = v.strip()
        if (v.startswith('"') and v.endswith('"')) or (v.startswith("'") and v.endswith("'")):
            v = v[1:-1]
        env[k] = v
    return env


@dataclass(frozen=True)
class ApiConfig:
    api_base: str
    token_id: str
    token_secret: str


class BookStackApi:
    def __init__(self, cfg: ApiConfig):
        self._cfg = cfg
        self._s = requests.Session()
        self._s.headers.update(
            {
                "Authorization": f"Token {cfg.token_id}:{cfg.token_secret}",
                "Accept": "application/json",
                "Content-Type": "application/json",
            }
        )

    def request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Any:
        url = f"{self._cfg.api_base}{path}"

        # Retry on 429/5xx with backoff. This script can generate hundreds of
        # writes; BookStack will sometimes rate-limit bursts.
        max_attempts = 5
        last_resp = None

        for attempt in range(1, max_attempts + 1):
            resp = self._s.request(method, url, json=body, timeout=60)
            last_resp = resp

            if resp.status_code == 429 and attempt < max_attempts:
                retry_after = resp.headers.get("Retry-After")
                try:
                    delay = int(retry_after) if retry_after else 0
                except ValueError:
                    delay = 0
                if delay <= 0:
                    delay = min(60, 2 ** attempt)
                time.sleep(delay)
                continue

            if 500 <= resp.status_code < 600 and attempt < max_attempts:
                time.sleep(min(30, 2 ** (attempt - 1)))
                continue

            if not resp.ok:
                # Avoid dumping secrets; limit response snippet.
                snippet = (resp.text or "").strip().replace("\n", " ")[:200]
                raise RuntimeError(
                    f"BookStack API {method} {path} failed: {resp.status_code} {snippet}"
                )

            if not (resp.text or "").strip():
                return None
            return resp.json()

        # Should be unreachable, but keep a helpful error if it happens.
        if last_resp is not None:
            snippet = (last_resp.text or "").strip().replace("\n", " ")[:200]
            raise RuntimeError(
                f"BookStack API {method} {path} failed after retries: {last_resp.status_code} {snippet}"
            )
        raise RuntimeError(f"BookStack API {method} {path} failed after retries")

    def get(self, path: str) -> Any:
        return self.request("GET", path)

    def post(self, path: str, body: Dict[str, Any]) -> Any:
        return self.request("POST", path, body)

    def put(self, path: str, body: Dict[str, Any]) -> Any:
        return self.request("PUT", path, body)

    def delete(self, path: str) -> Any:
        return self.request("DELETE", path)


STOPWORDS: Set[str] = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "but",
    "by",
    "for",
    "from",
    "has",
    "have",
    "how",
    "if",
    "in",
    "into",
    "is",
    "it",
    "its",
    "of",
    "on",
    "or",
    "our",
    "out",
    "the",
    "this",
    "to",
    "using",
    "vs",
    "we",
    "what",
    "when",
    "where",
    "why",
    "with",
    "you",
    "your",
}

WEAK_TOKENS: Set[str] = {
    "overview",
    "guide",
    "basics",
    "introduction",
    "getting",
    "started",
    "general",
    "notes",
    "reference",
    "resources",
    "tools",
    "software",
    "training",
    "development",
    "project",
    "projects",
    "design",
    "standards",
    "procedures",
    "procedure",
    "process",
    "setup",
    "library",
    "archive",
}


def extract_numeric_prefix(title: str) -> Optional[str]:
    # Examples: "3.1 AutoCAD" -> "3.1"; "2 Getting Started" -> "2"
    m = re.match(r"^\s*(\d+(?:\.\d+)*)\b", title)
    if not m:
        return None
    return m.group(1)


def tokenize(title: str) -> Set[str]:
    s = title.lower()
    s = re.sub(r"[^a-z0-9]+", " ", s)
    parts = [p for p in s.split() if p and p not in STOPWORDS]
    # Keep short tokens for acronyms (ip, io), but drop 1-char noise.
    parts = [p for p in parts if len(p) >= 2]
    return set(parts)


def best_chapter_for_page(page_name: str, chapters: List[Dict[str, Any]]) -> Tuple[Optional[int], str]:
    """Return (chapter_id, reason)."""
    page_prefix = extract_numeric_prefix(page_name)

    # Prefix match takes precedence.
    if page_prefix:
        prefix_matches = [ch for ch in chapters if ch.get("prefix") == page_prefix]
        if len(prefix_matches) == 1:
            return int(prefix_matches[0]["id"]), f"prefix:{page_prefix}"
        if len(prefix_matches) > 1:
            # Disambiguate by overlap among the prefix group.
            page_toks = tokenize(page_name)
            best = None
            best_score = -1
            for ch in prefix_matches:
                score = len(page_toks & ch["tokens"])
                if score > best_score:
                    best_score = score
                    best = ch
            if best is not None:
                return int(best["id"]), f"prefix+overlap:{page_prefix}:{best_score}"

    page_toks = tokenize(page_name)
    best = None
    best_score = -1
    best_intersection: Set[str] = set()

    for ch in chapters:
        inter = page_toks & ch["tokens"]
        score = len(inter)
        if score > best_score:
            best_score = score
            best = ch
            best_intersection = inter

    if best is None or best_score <= 0:
        return None, "no-match"

    if best_score >= 2:
        return int(best["id"]), f"overlap:{best_score}"

    # best_score == 1: only accept if token is not "weak".
    tok = next(iter(best_intersection)) if best_intersection else ""
    if tok and tok not in WEAK_TOKENS:
        return int(best["id"]), f"weak-overlap:{tok}"

    return None, "low-confidence"


def strip_html_to_text(s: str) -> str:
    # Very small sanitizer for empty-page detection.
    s = re.sub(r"<style[^>]*>.*?</style>", " ", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<script[^>]*>.*?</script>", " ", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<[^>]+>", " ", s)
    s = s.replace("&nbsp;", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def run_backup() -> Tuple[Path, Path]:
    env = load_env_file(ENV_APP_PATH)
    db_name = env.get("DB_NAME")
    db_root_password = env.get("DB_ROOT_PASSWORD")
    if not db_name or not db_root_password:
        raise RuntimeError("Missing DB_NAME/DB_ROOT_PASSWORD in .env")

    backup_dir = Path("/srv/backups/work/bookstack")
    backup_dir.mkdir(parents=True, exist_ok=True)
    os.chmod(backup_dir, 0o700)

    ts = time.strftime("%Y%m%d-%H%M%S")

    sql_path = backup_dir / f"bookstack-db-{ts}.sql"
    with sql_path.open("wb") as f:
        subprocess.run(
            [
                "docker",
                "exec",
                "bookstack-db",
                "mariadb-dump",
                "-u",
                "root",
                f"-p{db_root_password}",
                "--databases",
                db_name,
                "--single-transaction",
                "--quick",
                "--routines",
                "--triggers",
            ],
            stdout=f,
            check=True,
        )
    subprocess.run(["gzip", "-9", str(sql_path)], check=True)
    sql_gz = sql_path.with_suffix(".sql.gz")

    files_path = backup_dir / f"bookstack-files-{ts}.tar.gz"
    subprocess.run(
        [
            "tar",
            "-czf",
            str(files_path),
            "-C",
            str(PROJECT_DIR),
            "data/bookstack",
        ],
        check=True,
    )

    return sql_gz, files_path


def ensure_holding_book(api: BookStackApi) -> int:
    shelves = api.get("/shelves")
    shelf_id = None
    for s in shelves.get("data", []):
        if s.get("name") == HOLDING_SHELF_NAME:
            shelf_id = int(s["id"])
            break
    if shelf_id is None:
        raise RuntimeError(f"Holding shelf not found: {HOLDING_SHELF_NAME}")

    books = api.get("/books")
    holding_book_id = None
    for b in books.get("data", []):
        if b.get("name") == HOLDING_BOOK_NAME:
            holding_book_id = int(b["id"])
            break

    if holding_book_id is None:
        created = api.post(
            "/books",
            {"name": HOLDING_BOOK_NAME, "description": "Holding area for empty placeholder chapters."},
        )
        holding_book_id = int(created["id"])

    # Ensure holding book is on the holding shelf.
    shelf = api.get(f"/shelves/{shelf_id}")
    current = [int(x["id"]) for x in shelf.get("books", [])]
    if holding_book_id not in current:
        api.put(f"/shelves/{shelf_id}", {"books": sorted(current + [holding_book_id])})

    return holding_book_id


def list_unshelved_books(api: BookStackApi) -> List[Dict[str, Any]]:
    books = api.get("/books")
    all_books = [{"id": int(b["id"]), "name": str(b.get("name", ""))} for b in books.get("data", [])]

    shelves = api.get("/shelves")
    shelved_ids: Set[int] = set()
    for s in shelves.get("data", []):
        sid = int(s["id"])
        shelf = api.get(f"/shelves/{sid}")
        for b in shelf.get("books", []):
            shelved_ids.add(int(b["id"]))

    unshelved = [b for b in all_books if b["id"] not in shelved_ids]
    unshelved.sort(key=lambda x: x["id"])
    return unshelved


def shelve_books(api: BookStackApi, apply: bool) -> List[Tuple[str, str]]:
    # Mapping based on current library conventions.
    book_to_shelf = {
        "Vendor Documentation": "3. Technical References",
        "Templates Library": "5. Project Resources",
        "Lessons Learned": "5. Project Resources",
        "Project Case Studies": "5. Project Resources",
        "How to Use This BookStack": "EIC Knowledgebase Help",
        "Demo Project #1 - CAD / CARS Basics": "4. Training & Development",
        "Allen-Bradley Centerline 2100": "7. Integration & Automation",
        "Job Classifications": "1. Onboarding",
        "Documentation Standards": "2. Standards & Procedures",
        "Drawing Standards": "2. Standards & Procedures",
        "Instrumentation": "7. Integration & Automation",
        "Controls & Networking": "7. Integration & Automation",
        "Code & Standards Reference": "3. Technical References",
        "Lunch & Learn Archive": "4. Training & Development",
        "PDH Courses": "4. Training & Development",
        "Project Folder Setup": "5. Project Resources",
        "Estimating Guide": "5. Project Resources",
        "Proposal Writing": "8. Business Development",
        "Commissioning": "5. Project Resources",
        "SKM Power Tools": "6. Tools & Software",
        "IFM IO-Link": "7. Integration & Automation",
        "EtherNet/IP": "7. Integration & Automation",
        "HMI Development": "7. Integration & Automation",
        "Client Relations": "8. Business Development",
        "EIC Onboarding Guide": "1. Onboarding",
    }

    shelves = api.get("/shelves")
    shelf_name_to_id = {str(s["name"]): int(s["id"]) for s in shelves.get("data", [])}

    unshelved = list_unshelved_books(api)

    actions: List[Tuple[str, str]] = []

    for b in unshelved:
        shelf_name = book_to_shelf.get(b["name"], HOLDING_SHELF_NAME)
        shelf_id = shelf_name_to_id.get(shelf_name)
        if shelf_id is None:
            raise RuntimeError(f"Shelf not found: {shelf_name}")

        # Update shelf's book list.
        shelf = api.get(f"/shelves/{shelf_id}")
        current_ids = [int(x["id"]) for x in shelf.get("books", [])]
        if b["id"] in current_ids:
            continue
        actions.append((b["name"], shelf_name))
        if apply:
            api.put(f"/shelves/{shelf_id}", {"books": sorted(current_ids + [b["id"]])})

    return actions


def ensure_inbox_chapter(api: BookStackApi, book: Dict[str, Any], apply: bool) -> int:
    # If exists, return it.
    for item in book.get("contents", []) or []:
        if item.get("type") == "chapter" and item.get("name") == INBOX_CHAPTER_NAME:
            return int(item["id"])

    if not apply:
        return -1

    created = api.post(
        "/chapters",
        {
            "name": INBOX_CHAPTER_NAME,
            "description": "Catch-all for pages that were created directly in the book.",
            "book_id": int(book["id"]),
        },
    )
    return int(created["id"])


def move_direct_pages(api: BookStackApi, apply: bool) -> Dict[str, Any]:
    books = api.get("/books")
    book_ids = [int(b["id"]) for b in books.get("data", [])]

    moved = 0
    assigned = 0
    inboxed = 0
    inbox_created = 0

    # For reporting: store a small sample of moves.
    samples: List[Dict[str, Any]] = []

    for bid in book_ids:
        book = api.get(f"/books/{bid}")
        contents = book.get("contents") or []

        chapters_raw = [c for c in contents if c.get("type") == "chapter"]
        chapters: List[Dict[str, Any]] = []
        for ch in chapters_raw:
            name = str(ch.get("name", ""))
            chapters.append(
                {
                    "id": int(ch["id"]),
                    "name": name,
                    "tokens": tokenize(name),
                    "prefix": extract_numeric_prefix(name),
                }
            )

        direct_pages = [p for p in contents if p.get("type") == "page"]
        if not direct_pages:
            continue

        # Only create inbox when we actually need to put something in it.
        inbox_id: Optional[int] = None

        for p in direct_pages:
            page_id = int(p["id"])
            page_name = str(p.get("name", ""))

            target_ch_id, reason = best_chapter_for_page(page_name, chapters)
            if target_ch_id is not None:
                assigned += 1
            else:
                # Create inbox lazily.
                if inbox_id is None:
                    inbox_id = ensure_inbox_chapter(api, book, apply)
                    if inbox_id == -1:
                        inbox_id = None
                    else:
                        inbox_created += 1
                target_ch_id = inbox_id
                inboxed += 1
                reason = f"inbox:{reason}"

            if target_ch_id is None:
                # Dry-run without apply and no existing inbox.
                continue

            moved += 1
            if apply:
                api.put(f"/pages/{page_id}", {"chapter_id": int(target_ch_id)})

            if len(samples) < 20:
                samples.append(
                    {
                        "book_id": bid,
                        "book": str(book.get("name", "")),
                        "page_id": page_id,
                        "page": page_name,
                        "chapter_id": int(target_ch_id),
                        "reason": reason,
                    }
                )

    return {
        "moved": moved,
        "assigned": assigned,
        "inboxed": inboxed,
        "inbox_created": inbox_created,
        "samples": samples,
    }


def move_empty_chapters(api: BookStackApi, holding_book_id: int, apply: bool) -> Dict[str, Any]:
    books = api.get("/books")
    book_ids = [int(b["id"]) for b in books.get("data", [])]

    moved = 0
    renamed = 0
    failures: List[Dict[str, Any]] = []

    for bid in book_ids:
        if bid == holding_book_id:
            continue
        book = api.get(f"/books/{bid}")
        contents = book.get("contents") or []

        empty_chapters = [
            c
            for c in contents
            if c.get("type") == "chapter" and isinstance(c.get("pages"), list) and len(c.get("pages")) == 0
        ]
        if not empty_chapters:
            continue

        for ch in empty_chapters:
            ch_id = int(ch["id"])
            ch_name = str(ch.get("name", ""))

            if not apply:
                moved += 1
                continue

            try:
                api.put(f"/chapters/{ch_id}", {"book_id": holding_book_id})
                moved += 1
            except Exception:
                # Retry with a rename to avoid slug conflicts in holding book.
                try:
                    new_name = f"[From {bid}] {ch_name}"
                    api.put(f"/chapters/{ch_id}", {"book_id": holding_book_id, "name": new_name})
                    moved += 1
                    renamed += 1
                except Exception as ex2:
                    failures.append(
                        {
                            "book_id": bid,
                            "book": str(book.get("name", "")),
                            "chapter_id": ch_id,
                            "chapter": ch_name,
                            "error": str(ex2),
                        }
                    )

    return {"moved": moved, "renamed": renamed, "failures": failures}


def find_pages_by_exact_name(api: BookStackApi, name: str) -> List[int]:
    q = urllib.parse.quote(name)
    res = api.get(f"/search?query={q}")
    ids: List[int] = []
    for item in res.get("data", []) or []:
        if item.get("type") == "page" and item.get("name") == name:
            ids.append(int(item["id"]))
    return sorted(set(ids))


def is_effectively_empty_page(page: Dict[str, Any]) -> bool:
    # BookStack may return html/raw_html/markdown depending on storage.
    raw = page.get("markdown") or page.get("raw_html") or page.get("html") or ""
    if not isinstance(raw, str):
        return True

    raw = raw.strip()
    if not raw:
        return True

    txt = strip_html_to_text(raw)
    # A tiny amount of text (like a single heading) counts as non-empty.
    return len(txt) < 30


def delete_junk_pages(api: BookStackApi, apply: bool) -> Dict[str, Any]:
    deleted: List[Dict[str, Any]] = []
    kept: List[Dict[str, Any]] = []

    for name in ("New Page", "Test"):
        for pid in find_pages_by_exact_name(api, name):
            page = api.get(f"/pages/{pid}")
            empty = is_effectively_empty_page(page)
            entry = {
                "id": pid,
                "name": name,
                "book_id": page.get("book_id"),
                "chapter_id": page.get("chapter_id"),
                "empty": empty,
            }
            if empty:
                if apply:
                    api.delete(f"/pages/{pid}")
                deleted.append(entry)
            else:
                kept.append(entry)

    return {"deleted": deleted, "kept": kept}


def build_api_config() -> ApiConfig:
    if not ENV_SETUP_PATH.exists():
        raise RuntimeError(f"Missing env file: {ENV_SETUP_PATH}")

    env = load_env_file(ENV_SETUP_PATH)
    base = (env.get("BOOKSTACK_API_URL") or env.get("BOOKSTACK_URL") or "").rstrip("/")
    if not base:
        raise RuntimeError("BOOKSTACK_URL/BOOKSTACK_API_URL not set")

    token_id = env.get("BOOKSTACK_TOKEN_ID")
    token_secret = env.get("BOOKSTACK_TOKEN_SECRET")
    if not token_id or not token_secret:
        raise RuntimeError("BOOKSTACK_TOKEN_ID/BOOKSTACK_TOKEN_SECRET not set")

    api_base = f"{base}/api"
    return ApiConfig(api_base=api_base, token_id=token_id, token_secret=token_secret)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Apply changes (default: dry-run)")
    ap.add_argument("--skip-backup", action="store_true", help="Skip backup step")
    ap.add_argument("--skip-shelving", action="store_true")
    ap.add_argument("--skip-pages", action="store_true")
    ap.add_argument("--skip-empty-chapters", action="store_true")
    ap.add_argument("--skip-deletes", action="store_true")
    args = ap.parse_args()

    apply = bool(args.apply)
    eprint(f"Mode: {'APPLY' if apply else 'DRY-RUN'}")

    if not args.skip_backup:
        eprint("Creating backup...")
        sql_gz, files_tgz = run_backup()
        eprint(f"Backup DB: {sql_gz}")
        eprint(f"Backup files: {files_tgz}")
    else:
        eprint("Backup: skipped")

    api = BookStackApi(build_api_config())

    report: Dict[str, Any] = {"apply": apply, "ts": time.strftime("%Y-%m-%d %H:%M:%S")}

    if not args.skip_shelving:
        eprint("Shelving unshelved books...")
        actions = shelve_books(api, apply)
        report["shelved_books"] = [{"book": b, "shelf": s} for (b, s) in actions]
        eprint(f"Shelved books: {len(actions)}")
    else:
        report["shelved_books"] = []

    holding_book_id: Optional[int] = None
    if not args.skip_empty_chapters:
        eprint("Ensuring empty-chapters holding book...")
        holding_book_id = ensure_holding_book(api)
        report["holding_book_id"] = holding_book_id

    if not args.skip_pages:
        eprint("Moving direct pages into chapters...")
        rep = move_direct_pages(api, apply)
        report["direct_pages"] = rep
        eprint(
            f"Direct pages moved: {rep['moved']} (assigned: {rep['assigned']}, inboxed: {rep['inboxed']}), inbox chapters created: {rep['inbox_created']}"
        )

    if not args.skip_empty_chapters and holding_book_id is not None:
        eprint("Moving empty chapters into holding book...")
        rep = move_empty_chapters(api, holding_book_id, apply)
        report["empty_chapters"] = rep
        eprint(
            f"Empty chapters moved: {rep['moved']} (renamed on conflict: {rep['renamed']}, failures: {len(rep['failures'])})"
        )

    if not args.skip_deletes:
        eprint("Deleting junk pages (empty New Page/Test)...")
        rep = delete_junk_pages(api, apply)
        report["junk_pages"] = rep
        eprint(f"Junk pages deleted: {len(rep['deleted'])}, kept (non-empty): {len(rep['kept'])}")

    # Write report to the hierarchy folder for audit.
    out_dir = PROJECT_DIR / "data" / "hierarchy"
    out_dir.mkdir(parents=True, exist_ok=True)
    report_path = out_dir / f"organize-report-{time.strftime('%Y%m%d-%H%M%S')}.json"
    report_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    eprint(f"Report written: {report_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
