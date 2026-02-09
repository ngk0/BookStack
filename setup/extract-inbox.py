#!/usr/bin/env python3
"""Extract a detailed snapshot of all pages currently in "00. Inbox (Unsorted)".

Writes a JSON and a Markdown summary under:
  /srv/stacks/work/bookstack/data/hierarchy/

Run as `admin` so we can read setup/.env.setup.
"""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
ENV_SETUP_PATH = SCRIPT_DIR / ".env.setup"
OUT_DIR = PROJECT_DIR / "data" / "hierarchy"

INBOX_CHAPTER_NAME = "00. Inbox (Unsorted)"


def load_env_file(path: Path) -> Dict[str, str]:
    env: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
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
        self._last_req = 0.0

    def _sleep_rate_limit(self) -> None:
        # ~5 rps to stay well under server throttles.
        min_interval = 0.20
        now = time.time()
        elapsed = now - self._last_req
        if elapsed < min_interval:
            time.sleep(min_interval - elapsed)
        self._last_req = time.time()

    def request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Any:
        url = f"{self._cfg.api_base}{path}"

        max_attempts = 5
        last_resp = None

        for attempt in range(1, max_attempts + 1):
            self._sleep_rate_limit()
            resp = self._s.request(method, url, json=body, timeout=90)
            last_resp = resp

            if resp.status_code == 429 and attempt < max_attempts:
                retry_after = resp.headers.get("Retry-After")
                try:
                    delay = int(retry_after) if retry_after else 0
                except ValueError:
                    delay = 0
                if delay <= 0:
                    delay = min(60, 2**attempt)
                time.sleep(delay)
                continue

            if 500 <= resp.status_code < 600 and attempt < max_attempts:
                time.sleep(min(30, 2 ** (attempt - 1)))
                continue

            if not resp.ok:
                snippet = (resp.text or "").strip().replace("\n", " ")[:200]
                raise RuntimeError(f"BookStack API {method} {path} failed: {resp.status_code} {snippet}")

            if not (resp.text or "").strip():
                return None
            return resp.json()

        if last_resp is not None:
            snippet = (last_resp.text or "").strip().replace("\n", " ")[:200]
            raise RuntimeError(
                f"BookStack API {method} {path} failed after retries: {last_resp.status_code} {snippet}"
            )
        raise RuntimeError(f"BookStack API {method} {path} failed after retries")

    def get(self, path: str) -> Any:
        return self.request("GET", path)


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
    return ApiConfig(api_base=f"{base}/api", token_id=token_id, token_secret=token_secret)


def extract_headings_from_html(html: str) -> List[str]:
    headings: List[str] = []
    for m in re.finditer(r"<h([1-6])[^>]*>(.*?)</h\1>", html, flags=re.IGNORECASE | re.DOTALL):
        inner = m.group(2)
        inner = re.sub(r"<[^>]+>", " ", inner)
        inner = re.sub(r"\s+", " ", inner).strip()
        if inner:
            headings.append(inner)
        if len(headings) >= 12:
            break
    return headings


def extract_headings_from_markdown(md: str) -> List[str]:
    out: List[str] = []
    for line in md.splitlines():
        m = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*$", line)
        if not m:
            continue
        t = m.group(1).strip()
        if t:
            out.append(t)
        if len(out) >= 12:
            break
    return out


def strip_html_to_text(s: str) -> str:
    s = re.sub(r"<style[^>]*>.*?</style>", " ", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<script[^>]*>.*?</script>", " ", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<[^>]+>", " ", s)
    s = s.replace("&nbsp;", " ")
    s = re.sub(r"\s+", " ", s).strip()
    return s


def page_content_fields(page: Dict[str, Any]) -> Tuple[str, str]:
    # Prefer raw_html/html; fall back to markdown.
    raw_html = page.get("raw_html")
    if isinstance(raw_html, str) and raw_html:
        return "html", raw_html

    html = page.get("html")
    if isinstance(html, str) and html:
        return "html", html

    md = page.get("markdown")
    if isinstance(md, str) and md:
        return "markdown", md

    return "", ""


def main() -> int:
    api = BookStackApi(build_api_config())
    ts = time.strftime("%Y%m%d-%H%M%S")

    books = api.get("/books")
    book_ids = [int(b["id"]) for b in books.get("data", [])]

    snapshot: Dict[str, Any] = {
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "inbox_chapter_name": INBOX_CHAPTER_NAME,
        "books": [],
    }

    md_lines: List[str] = []
    md_lines.append(f"# Inbox Snapshot ({snapshot['generated_at']})")
    md_lines.append("")

    total_pages = 0

    for bid in book_ids:
        book = api.get(f"/books/{bid}")
        contents = book.get("contents") or []
        inbox = next(
            (c for c in contents if c.get("type") == "chapter" and c.get("name") == INBOX_CHAPTER_NAME),
            None,
        )
        if not inbox:
            continue

        inbox_id = int(inbox["id"])
        # Fetch full chapter to get pages list with priority
        chapter = api.get(f"/chapters/{inbox_id}")
        pages = chapter.get("pages") or []

        book_entry: Dict[str, Any] = {
            "book_id": bid,
            "book_name": book.get("name"),
            "book_slug": book.get("slug"),
            "inbox_chapter_id": inbox_id,
            "inbox_page_count": len(pages),
            "chapters": [
                {
                    "chapter_id": int(c["id"]),
                    "name": c.get("name"),
                    "page_count": len(c.get("pages") or []),
                }
                for c in contents
                if c.get("type") == "chapter"
            ],
            "pages": [],
        }

        md_lines.append(f"## {book_entry['book_name']} (book_id={bid}, inbox_chapter_id={inbox_id})")
        md_lines.append("")

        for p in pages:
            page_id = int(p["id"])
            page = api.get(f"/pages/{page_id}")

            kind, raw = page_content_fields(page)
            headings: List[str] = []
            if kind == "html":
                headings = extract_headings_from_html(raw)
            elif kind == "markdown":
                headings = extract_headings_from_markdown(raw)

            text = strip_html_to_text(raw) if kind == "html" else re.sub(r"\s+", " ", raw).strip()
            text_sample = text[:600]

            tags = page.get("tags") or []
            tag_pairs = []
            for t in tags:
                if not isinstance(t, dict):
                    continue
                name = t.get("name")
                value = t.get("value")
                if name is None:
                    continue
                tag_pairs.append({"name": name, "value": value})

            page_entry = {
                "page_id": page_id,
                "name": page.get("name"),
                "slug": page.get("slug"),
                "draft": page.get("draft"),
                "updated_at": page.get("updated_at"),
                "created_at": page.get("created_at"),
                "priority": p.get("priority"),
                "headings": headings,
                "content_kind": kind,
                "text_sample": text_sample,
                "tags": tag_pairs,
                "url": page.get("url"),
            }
            book_entry["pages"].append(page_entry)

            md_lines.append(f"- page_id={page_id}  {page_entry['name']}")
            if headings:
                md_lines.append(f"  - headings: {headings[:6]}")
            if text_sample:
                md_lines.append(f"  - sample: {text_sample[:220]}{'...' if len(text_sample) > 220 else ''}")

        md_lines.append("")

        snapshot["books"].append(book_entry)
        total_pages += len(pages)

    snapshot["total_books_with_inbox"] = len(snapshot["books"])
    snapshot["total_inbox_pages"] = total_pages

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    json_path = OUT_DIR / f"inbox-snapshot-{ts}.json"
    md_path = OUT_DIR / f"inbox-snapshot-{ts}.md"

    json_path.write_text(json.dumps(snapshot, indent=2, sort_keys=True), encoding="utf-8")
    md_path.write_text("\n".join(md_lines) + "\n", encoding="utf-8")

    print(str(json_path))
    print(str(md_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
