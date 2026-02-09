#!/usr/bin/env python3
"""Organize pages currently sitting in "00. Inbox (Unsorted)" across books.

This script is intentionally opinionated and page-id based (not keyword matching).
It encodes a one-time IA decision to move known inbox pages into the most
appropriate chapters/books.

Pages that contain prompt-leak / tooling logs or otherwise need cleanup are
moved into a dedicated Drafts chapter so clean chapters stay clean.

Default mode is DRY-RUN. Use --apply to perform changes.

Run as the stack owner user (admin) so we can read setup/.env.setup.
"""

from __future__ import annotations

import argparse
import json
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent
ENV_SETUP_PATH = SCRIPT_DIR / ".env.setup"


def load_env_file(path: Path) -> Dict[str, str]:
    env: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        v = v.strip()
        if (v.startswith("\"") and v.endswith("\"")) or (v.startswith(") and v.endswith(")):
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

        max_attempts = 5
        last_resp = None

        for attempt in range(1, max_attempts + 1):
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
                raise RuntimeError(
                    f"BookStack API {method} {path} failed: {resp.status_code} {snippet}"
                )

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

    def post(self, path: str, body: Dict[str, Any]) -> Any:
        return self.request("POST", path, body)

    def put(self, path: str, body: Dict[str, Any]) -> Any:
        return self.request("PUT", path, body)


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


@dataclass(frozen=True)
class ChapterSpec:
    book_id: int
    name: str
    description: str = ""


Target = Union[int, ChapterSpec]


def get_book_chapters(api: BookStackApi, book_id: int) -> Dict[str, int]:
    book = api.get(f"/books/{book_id}")
    out: Dict[str, int] = {}
    for c in book.get("contents") or []:
        if c.get("type") != "chapter":
            continue
        name = str(c.get("name") or "")
        if not name:
            continue
        # If duplicates exist, keep the first. Callers should use explicit
        # chapter ids for books known to have duplicates.
        out.setdefault(name, int(c["id"]))
    return out


def ensure_chapter(
    api: BookStackApi, cache: Dict[int, Dict[str, int]], spec: ChapterSpec, apply: bool
) -> int:
    chapters = cache.get(spec.book_id)
    if chapters is None:
        chapters = get_book_chapters(api, spec.book_id)
        cache[spec.book_id] = chapters

    existing = chapters.get(spec.name)
    if existing is not None:
        return existing

    if not apply:
        # Fake id in dry-run; caller must not write using this.
        return -1

    created = api.post(
        "/chapters", {"book_id": spec.book_id, "name": spec.name, "description": spec.description}
    )
    ch_id = int(created["id"])
    chapters[spec.name] = ch_id
    return ch_id


def move_page(api: BookStackApi, page_id: int, target_chapter_id: int, apply: bool) -> Tuple[bool, Dict[str, Any]]:
    page = api.get(f"/pages/{page_id}")
    current_ch = page.get("chapter_id")
    current_ch_id = int(current_ch) if current_ch is not None else None
    if current_ch_id == target_chapter_id:
        return False, {
            "page_id": page_id,
            "name": page.get("name"),
            "from": current_ch_id,
            "to": target_chapter_id,
        }

    if apply:
        api.put(f"/pages/{page_id}", {"chapter_id": int(target_chapter_id)})

    return True, {
        "page_id": page_id,
        "name": page.get("name"),
        "from": current_ch_id,
        "to": target_chapter_id,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true", help="Perform changes (default is dry-run)")
    ap.add_argument(
        "--out",
        default="",
        help="Write a JSON move report to this path (default: data/hierarchy/inbox-organize-<ts>.json)",
    )
    args = ap.parse_args()

    apply = bool(args.apply)
    api = BookStackApi(build_api_config())
    ts = time.strftime("%Y%m%d-%H%M%S")

    out_path = Path(args.out) if args.out else (PROJECT_DIR / "data" / "hierarchy" / f"inbox-organize-{ts}.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # =========================================================================
    # Target chapter ids (use ids where books contain duplicate chapter names)
    # =========================================================================
    # CAD/BIM Production Skills
    CADBIM_BOOK_ID = 926
    CADBIM_AUTOCH_ID = 936  # "3.1 AutoCAD Core Skills" (the populated one)
    CADBIM_NAVIS_ID = 951  # "3.3 Navisworks"

    # Electrical Power Technical Skills
    ELEC_ARCH_ID = 834  # "1.2 Power System Architecture"
    ELEC_CALC_ID = 841  # "1.3 Electrical Calculations"
    ELEC_PHYS_ID = 848  # "1.4 Raceway, Cabling, and Physical Design"

    # Controls and Automation Technical Skills
    CTRL_ARCH_ID = 886  # "2.1 Control System Architecture" (set A)
    CTRL_INST_ID = 887  # "2.2 Instrumentation Fundamentals" (set A)
    CTRL_DOCS_ID = 889  # "2.4 Controls Documentation"

    # Supporting Engineering Toolchain
    TOOL_EXCEL_ID = 958  # "4.2 Excel for Engineering"
    TOOL_CARS_ID = 959  # "4.3 Aeries CARS"

    # Deliverable Quality Skills
    QUAL_COORD_ID = 972  # "5.4 Interdiscipline Coordination"

    # Book ids
    HELP_BOOK_ID = 101
    PLAYBOOK_BOOK_ID = 126
    CALC_BOOK_ID = 746

    # =========================================================================
    # Chapters we will create (by name) if missing
    # =========================================================================
    # Book 101: How to Use This BookStack
    ch_help_master = ChapterSpec(HELP_BOOK_ID, "0. Master Index", "Navigation hub and index pages")
    ch_help_getting_started = ChapterSpec(HELP_BOOK_ID, "1. Getting Started", "What BookStack is and how the KB is organized")
    ch_help_contributing = ChapterSpec(HELP_BOOK_ID, "2. Contributing", "Editing, tags, and writing practices")
    ch_help_governance = ChapterSpec(HELP_BOOK_ID, "3. Roles, Permissions, and Governance", "Access levels and responsibilities")

    # Book 299: Demo Project
    ch_demo_overview = ChapterSpec(299, "1. Overview", "What good looks like and expected deliverables")
    ch_demo_walkthrough = ChapterSpec(299, "2. Walkthrough", "Step-by-step demo project build")

    # Book 309: Centerline 2100
    ch_cl_overview = ChapterSpec(309, "1. Platform Overview", "Key concepts and scope")
    ch_cl_structure = ChapterSpec(309, "2. Structure and Bus", "Lineup structure, bus, and ratings")
    ch_cl_buckets = ChapterSpec(309, "3. Buckets and Starters", "FVS, VFD, and soft starter buckets")
    ch_cl_network = ChapterSpec(309, "4. IntelliCENTER and Networking", "Network architecture and integration")
    ch_cl_install = ChapterSpec(309, "5. Layout and Installation", "GA, clearance, and install considerations")

    # Book 370: AI / LLM
    ch_ai_use = ChapterSpec(370, "Use Cases", "Approved use cases and guardrails")

    # Book 391: Licensure
    ch_lic = ChapterSpec(391, "Licensure", "Licensure basics and process")

    # Book 413: Proposal Resources
    ch_proposal_templates = ChapterSpec(413, "Templates", "Reusable proposal templates and examples")

    # Book 554: Software Training
    ch_software_templates = ChapterSpec(554, "Templates", "Training module templates and examples")

    # Book 672: Bluebeam Tools
    ch_bluebeam_howto = ChapterSpec(672, "How-To", "Task-focused Bluebeam workflows")

    # Book 676: Marketing Materials
    ch_marketing_templates = ChapterSpec(676, "Templates", "Reusable marketing templates and examples")

    # Book 739: Quality Standards
    ch_quality_templates = ChapterSpec(739, "Templates", "Templates for standards and quality artifacts")

    # Book 746: Design Calculators
    ch_calc_templates = ChapterSpec(CALC_BOOK_ID, "0. Templates", "Calculator and index templates")
    ch_calc_power = ChapterSpec(CALC_BOOK_ID, "1. Power Systems", "Transformers, generators, UPS sizing examples")
    ch_calc_raceway = ChapterSpec(CALC_BOOK_ID, "2. Conductor and Raceway", "Ampacity, derating, conduit and tray fill examples")
    ch_calc_ground = ChapterSpec(CALC_BOOK_ID, "3. Grounding", "GEC/EGC worked examples")
    ch_calc_lighting = ChapterSpec(CALC_BOOK_ID, "4. Lighting", "Lighting and emergency lighting worked examples")
    ch_calc_econ = ChapterSpec(CALC_BOOK_ID, "5. Economics and Estimating", "Demand charges and cost estimating examples")
    ch_calc_drives = ChapterSpec(CALC_BOOK_ID, "6. Drives", "VFD worked examples")

    # Book 749: Electrical Design
    ch_electrical_templates = ChapterSpec(749, "Templates", "Templates and example page structures")

    # Book 752: Allen-Bradley/Rockwell
    ch_ab_templates = ChapterSpec(752, "Templates", "Templates and example page structures")

    # Book 792: Deliverable Templates
    ch_deliv_playbook_templates = ChapterSpec(792, "Playbook Templates", "Deliverable playbook templates")

    # Book 818: Quick Sharing (Public)
    ch_qs_quickstart = ChapterSpec(818, "1. Knowledge Base Quick Start", "Public quick-start pages")
    ch_qs_ai = ChapterSpec(818, "2. AI Assistance", "Public AI assistance guidance")

    # Book 1023: Laporte Consultants
    ch_laporte_overview = ChapterSpec(1023, "1. Company Overview", "Who Laporte is and what we do")
    ch_laporte_people = ChapterSpec(1023, "2. People and Teams", "Leadership and support teams")
    ch_laporte_delivery = ChapterSpec(1023, "3. Project Delivery", "How projects are phased and delivered")

    # Book 1024: EIC Team
    ch_eic_overview = ChapterSpec(1024, "1. Team Overview", "Who we are, what we do, and how we operate")
    ch_eic_tenets = ChapterSpec(1024, "2. Tenets", "How we work")
    ch_eic_services = ChapterSpec(1024, "3. Services", "What we deliver")

    # Book 1032: Square D NQ Panelboards
    ch_nq_overview = ChapterSpec(1032, "1. Overview", "Platform architecture and limits")
    ch_nq_main = ChapterSpec(1032, "2. Main Device Selection", "Main lug vs main breaker")
    ch_nq_branch = ChapterSpec(1032, "3. Branch Protection", "Branch breaker selection")
    ch_nq_protection = ChapterSpec(1032, "4. Protection and Coordination", "Selective coordination, SPDs, and protection strategy")
    ch_nq_options = ChapterSpec(1032, "5. Options and Physical Configuration", "Bus, safety, enclosure sizing, and circuit strategy")
    ch_nq_specs = ChapterSpec(1032, "6. Specifications and Schedules", "Specs and schedule development")

    # Book 926: CAD/BIM Production Skills
    ch_cadbim_xl2cad = ChapterSpec(CADBIM_BOOK_ID, "xl2cad: Excel to CAD Automation", "xl2cad workflows, templates, and QA")
    ch_cadbim_jtb = ChapterSpec(CADBIM_BOOK_ID, "JTB Tools for AutoCAD Productivity", "JTB utilities, batch ops, and SSM tooling")
    ch_cadbim_drafts = ChapterSpec(CADBIM_BOOK_ID, "99. Drafts (Needs Rewrite)", "Pages needing SME rewrite/cleanup")

    # Book 126: Deliverables Playbooks Contractor Ready
    ch_playbook_pkg = ChapterSpec(PLAYBOOK_BOOK_ID, "0. Package Assembly & QC", "Assemble, QC, and issue contractor-ready packages")

    # =========================================================================
    # Page -> target mapping (page ids from inbox snapshot 2026-02-09)
    # =========================================================================
    targets: Dict[int, Target] = {}

    # How to Use This BookStack
    for pid in (102, 103, 104):
        targets[pid] = ch_help_getting_started
    for pid in (105, 107, 108):
        targets[pid] = ch_help_contributing
    targets[106] = ch_help_governance

    # Master index (was in CAD/BIM inbox)
    targets[1249] = ch_help_master

    # Demo Project #1
    targets[300] = ch_demo_overview
    targets[308] = ch_demo_walkthrough

    # Allen-Bradley Centerline 2100
    targets[310] = ch_cl_overview
    targets[311] = ch_cl_structure
    targets[312] = ch_cl_buckets
    targets[313] = ch_cl_buckets
    targets[314] = ch_cl_network
    targets[315] = ch_cl_install

    # Basis of Design Equipment
    targets[1042] = ChapterSpec(361, "Disconnect Switches", "Basis of design guidance for disconnecting means")
    targets[1043] = ChapterSpec(361, "Panelboards", "Basis of design guidance for panelboards and branch panels")

    # AI / LLM / Programming Topics
    targets[371] = ch_ai_use

    # FE and PE Exam, Licensure
    targets[1029] = ch_lic

    # Proposal Resources
    targets[816] = ch_proposal_templates

    # Software Training
    targets[823] = ch_software_templates

    # Bluebeam Tools
    targets[814] = ch_bluebeam_howto

    # Marketing Materials
    targets[827] = ch_marketing_templates

    # Quality Standards
    targets[821] = ch_quality_templates

    # Design Calculators template page
    targets[825] = ch_calc_templates

    # Electrical Design template page
    targets[822] = ch_electrical_templates

    # Allen-Bradley/Rockwell template page
    targets[826] = ch_ab_templates

    # Deliverable Templates - playbook template
    targets[824] = ch_deliv_playbook_templates

    # Quick Sharing (Public)
    for pid in (1073, 1074, 1075, 1076, 1077):
        targets[pid] = ch_qs_quickstart
    targets[819] = ch_qs_ai

    # Laporte Consultants
    targets[901] = ch_laporte_overview
    targets[914] = ch_laporte_overview
    targets[906] = ch_laporte_delivery
    targets[903] = ch_laporte_people
    targets[1007] = ch_laporte_people

    # EIC Team
    targets[1009] = ch_eic_overview
    targets[1010] = ch_eic_tenets
    targets[1011] = ch_eic_services

    # Square D NQ Panelboards
    targets[1033] = ch_nq_overview
    targets[1034] = ch_nq_main
    targets[1035] = ch_nq_branch
    targets[1036] = ch_nq_protection
    targets[1039] = ch_nq_protection
    targets[1037] = ch_nq_options
    targets[1038] = ch_nq_options
    targets[1040] = ch_nq_specs

    # -------------------------------------------------------------------------
    # CAD/BIM Production Skills inbox (book 926)
    # -------------------------------------------------------------------------
    # AutoCAD core (clean)
    for pid in (1049, 1050, 1053, 1115):
        targets[pid] = CADBIM_AUTOCH_ID

    # Navisworks
    for pid in (1111, 1112):
        targets[pid] = CADBIM_NAVIS_ID

    # xl2cad (clean)
    for pid in (1054, 1056, 1057, 1060, 1069):
        targets[pid] = ch_cadbim_xl2cad

    # JTB (clean)
    for pid in (1070, 1071, 1072):
        targets[pid] = ch_cadbim_jtb

    # Drafts / needs rewrite (prompt-leak/tool logs)
    for pid in (1051, 1052, 1055, 1058, 1059, 1061, 1062, 1063, 1064, 1065, 1066, 1067, 1068):
        targets[pid] = ch_cadbim_drafts

    # Electrical power topics -> Electrical Power Technical Skills
    targets[1082] = ELEC_CALC_ID  # Arc Flash Hazard Assessment
    targets[1087] = ELEC_ARCH_ID  # Panel Submittal Packages
    targets[1088] = ELEC_PHYS_ID  # Sanitary Design for Wash-Down Zones

    for pid in (1122, 1123, 1124, 1127, 1128):
        targets[pid] = ELEC_CALC_ID
    for pid in (1132, 1133, 1136, 1138, 1140, 1142, 1146):
        targets[pid] = ELEC_ARCH_ID

    # Controls topics -> Controls and Automation Technical Skills
    targets[1083] = CTRL_ARCH_ID
    targets[1091] = CTRL_ARCH_ID
    targets[1147] = CTRL_ARCH_ID
    targets[1108] = CTRL_ARCH_ID  # ISA-88 coordination (architecture-level)

    targets[1084] = CTRL_DOCS_ID
    targets[1086] = CTRL_DOCS_ID
    targets[1104] = CTRL_DOCS_ID

    targets[1107] = CTRL_INST_ID  # CIP/SIP integration (process + instrumentation context)

    # Toolchain topics -> Supporting Engineering Toolchain
    for pid in (1093, 1094, 1096):
        targets[pid] = TOOL_CARS_ID
    for pid in (1097, 1098, 1099, 1100):
        targets[pid] = TOOL_EXCEL_ID

    # Deliverable quality / coordination
    for pid in (1102, 1103, 1105, 1106, 1110):
        targets[pid] = QUAL_COORD_ID

    # Package assembly -> Deliverables playbook
    for pid in (1114, 1116, 1117, 1118, 1119):
        targets[pid] = ch_playbook_pkg

    # Calculation worked examples -> Design Calculators
    for pid in (1255, 1267, 1268):
        targets[pid] = ch_calc_power
    for pid in (1256, 1257, 1270):
        targets[pid] = ch_calc_raceway
    for pid in (1261, 1262):
        targets[pid] = ch_calc_ground
    for pid in (1263, 1264):
        targets[pid] = ch_calc_lighting
    for pid in (1265, 1266):
        targets[pid] = ch_calc_econ
    targets[1269] = ch_calc_drives

    # =========================================================================
    # Resolve chapters + move pages
    # =========================================================================
    chapter_cache: Dict[int, Dict[str, int]] = {}
    resolved_targets: Dict[int, int] = {}

    for pid, t in targets.items():
        if isinstance(t, int):
            resolved_targets[pid] = t
            continue
        ch_id = ensure_chapter(api, chapter_cache, t, apply)
        resolved_targets[pid] = ch_id

    moves: List[Dict[str, Any]] = []
    moved = 0
    skipped = 0

    for pid in sorted(resolved_targets.keys()):
        ch_id = resolved_targets[pid]
        if ch_id == -1:
            moves.append({"page_id": pid, "to": "(create chapter)", "note": "dry-run"})
            skipped += 1
            continue

        did_move, info = move_page(api, pid, ch_id, apply)
        moves.append(info)
        if did_move:
            moved += 1
        else:
            skipped += 1

    report = {
        "generated_at": time.strftime("%Y-%m-%d %H:%M:%S"),
        "apply": apply,
        "moved": moved,
        "skipped": skipped,
        "moves": moves,
    }
    out_path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")

    print(f"Wrote report: {out_path}")
    print(f"Moved: {moved} (skipped/no-op: {skipped})")
    print("NOTE: Run setup/extract-inbox.py to verify inbox is empty.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
