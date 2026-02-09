#!/usr/bin/env python3
"""Seed starter content into BookStack books that are currently empty.

Goals
- Create draft chapters/pages in placeholder books so nothing is empty.
- Use WYSIWYG-friendly HTML with the Laporte heading/list patterns.

Safety
- Default is DRY-RUN.
- Use --apply to make changes.
- Idempotent: will not re-create chapters/pages that already exist.

Run as the stack owner user (admin) so we can read setup/.env.setup.
Example:
  sudo /srv/stacks/work/bookstack/setup/seed-empty-books.py --apply
"""

from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional

import requests

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_DIR = SCRIPT_DIR.parent

ENV_SETUP_PATH = SCRIPT_DIR / ".env.setup"
HIERARCHY_PATH = PROJECT_DIR / "data" / "hierarchy" / "hierarchy.json"


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def load_env_file(path: Path) -> Dict[str, str]:
    env: Dict[str, str] = {}
    text = path.read_text(encoding="utf-8", errors="replace")
    for raw in text.splitlines():
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

    def request(self, method: str, path: str, body: Optional[Dict[str, Any]] = None) -> Any:
        url = f"{self._cfg.api_base}{path}"

        max_attempts = 5
        last_resp: Optional[requests.Response] = None
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
                snippet = (resp.text or "").strip().replace("\n", " ")[:250]
                raise RuntimeError(
                    f"BookStack API {method} {path} failed: {resp.status_code} {snippet}"
                )

            if not (resp.text or "").strip():
                return None
            return resp.json()

        if last_resp is not None:
            snippet = (last_resp.text or "").strip().replace("\n", " ")[:250]
            raise RuntimeError(
                f"BookStack API {method} {path} failed after retries: {last_resp.status_code} {snippet}"
            )
        raise RuntimeError(f"BookStack API {method} {path} failed after retries")

    def get(self, path: str) -> Any:
        return self.request("GET", path)

    def post(self, path: str, body: Dict[str, Any]) -> Any:
        return self.request("POST", path, body)


@dataclass(frozen=True)
class EmptyBook:
    shelf_name: str
    book_id: int
    book_name: str
    book_desc: str


@dataclass(frozen=True)
class PagePlan:
    name: str
    html: str
    tags: List[Dict[str, str]]


@dataclass(frozen=True)
class ChapterPlan:
    name: str
    description: str
    pages: List[PagePlan]


def today_iso() -> str:
    return dt.date.today().isoformat()


def next_review_iso(years: int = 1) -> str:
    return (dt.date.today().replace(year=dt.date.today().year + years)).isoformat()


def ai_warning_html() -> str:
    return (
        '<!-- AI-Generated Content Warning -->\n'
        '<div class="ai-warning" style="background: #fef3c7; border-left: 4px solid #f59e0b; '
        'padding: 12px 16px; margin: 0 0 24px 0; border-radius: 4px;">\n'
        '  <p style="margin: 0; font-size: 14px;">\n'
        '    <strong>⚠️ AI-Generated Content:</strong> This article was generated using AI (Codex) and should be '
        'reviewed by subject matter experts before use in critical applications. Verify applicability, client '
        'requirements, and current code editions.\n'
        '  </p>\n'
        '</div>\n'
    )


def revision_table_html(author: str = "AI (Codex)", description: str = "Initial AI-generated draft") -> str:
    d = today_iso()
    return (
        "<!-- Document Revision Control -->\n"
        '<table class="revision-table" style="width: 100%; border-collapse: collapse; margin: 0 0 24px 0; '
        'font-size: 14px; border: 1px solid #e5e7eb;">\n'
        "  <thead>\n"
        '    <tr style="background: #f3f4f6;">\n'
        '      <th style="padding: 8px; text-align: left; border: 1px solid #e5e7eb; width: 100px;">Revision</th>\n'
        '      <th style="padding: 8px; text-align: left; border: 1px solid #e5e7eb; width: 120px;">Date</th>\n'
        '      <th style="padding: 8px; text-align: left; border: 1px solid #e5e7eb; width: 150px;">Author</th>\n'
        '      <th style="padding: 8px; text-align: left; border: 1px solid #e5e7eb;">Description</th>\n'
        "    </tr>\n"
        "  </thead>\n"
        "  <tbody>\n"
        "    <tr>\n"
        '      <td style="padding: 8px; border: 1px solid #e5e7eb;">1.0</td>\n'
        f'      <td style="padding: 8px; border: 1px solid #e5e7eb;">{html.escape(d)}</td>\n'
        f'      <td style="padding: 8px; border: 1px solid #e5e7eb;">{html.escape(author)}</td>\n'
        f'      <td style="padding: 8px; border: 1px solid #e5e7eb;">{html.escape(description)}</td>\n'
        "    </tr>\n"
        "    <tr>\n"
        '      <td style="padding: 8px; border: 1px solid #e5e7eb; background: #f9fafb;"></td>\n'
        '      <td style="padding: 8px; border: 1px solid #e5e7eb; background: #f9fafb;"></td>\n'
        '      <td style="padding: 8px; border: 1px solid #e5e7eb; background: #f9fafb;"></td>\n'
        '      <td style="padding: 8px; border: 1px solid #e5e7eb; background: #f9fafb;"><em>Future revisions...</em></td>\n'
        "    </tr>\n"
        "  </tbody>\n"
        "</table>\n"
    )


def metadata_table_html(owner_role: str, applies_to: str, source_of_truth: str) -> str:
    d = today_iso()
    nr = next_review_iso(1)
    rows = [
        ("Owner role", owner_role),
        ("Status", "Draft"),
        ("Last reviewed", d),
        ("Next review", nr),
        ("Applies to", applies_to),
        ("Source of truth", source_of_truth),
    ]
    row_html = "".join(
        f"<tr><td>{html.escape(k)}</td><td>{html.escape(v)}</td></tr>\n" for k, v in rows
    )
    return (
        '<h4><strong>Metadata</strong></h4>\n'
        "<table>\n"
        "  <thead><tr><th>Field</th><th>Value</th></tr></thead>\n"
        f"  <tbody>\n{row_html}  </tbody>\n"
        "</table>\n"
    )


def h4(title: str) -> str:
    return f"<h4><strong>{html.escape(title)}</strong></h4>\n"


def h5(title: str) -> str:
    return f"<h5><strong>{html.escape(title)}</strong></h5>\n"


def p(text: str) -> str:
    return f"<p>{text}</p>\n"


def ul(items: Iterable[str]) -> str:
    li = "".join(f"<li>{i}<br></li>\n" for i in items)
    return f"<ul>\n{li}</ul>\n"


def ol(items: List[str]) -> str:
    parts: List[str] = []
    for i, item in enumerate(items, start=1):
        parts.append(f'<li value="{i}">{item}<br></li>')
    return "<ol>\n" + "\n".join(parts) + "\n</ol>\n"


def table(headers: List[str], rows: List[List[str]]) -> str:
    thead = "<thead><tr>" + "".join(f"<th>{html.escape(h)}</th>" for h in headers) + "</tr></thead>\n"
    tbody_rows: List[str] = []
    for r in rows:
        tbody_rows.append("<tr>" + "".join(f"<td>{c}</td>" for c in r) + "</tr>")
    tbody = "<tbody>\n" + "\n".join(tbody_rows) + "\n</tbody>\n"
    return "<table>\n" + thead + tbody + "</table>\n"


def slugify_code(s: str) -> str:
    letters = re.findall(r"[A-Za-z0-9]+", s)
    if not letters:
        return "GEN"
    code = "".join(w[0].upper() for w in letters if w)
    return (code[:4] or "GEN").upper()


def standard_page_html(book: EmptyBook, topic: str) -> str:
    applies_to = f"{book.book_name} - {topic}"
    req_code = slugify_code(topic)

    requirements_1 = [
        [
            f"REQ-{req_code}-001",
            f"Design packages SHALL define the scope and assumptions for <strong>{html.escape(topic)}</strong>.",
            "Prevents hidden requirements and rework.",
        ],
        [
            f"REQ-{req_code}-002",
            "Deliverables SHALL be internally reviewed against applicable codes, client standards, and this standard.",
            "Ensures contractor-ready quality.",
        ],
        [
            f"REQ-{req_code}-003",
            "Any deviation SHALL be documented and approved per the Exceptions process.",
            "Maintains traceability and risk control.",
        ],
    ]

    requirements_2 = [
        [
            f"REQ-{req_code}-010",
            "Drawings SHALL include enough information for construction without back-and-forth RFIs.",
            "Reduces field ambiguity.",
        ],
        [
            f"REQ-{req_code}-011",
            "All tags, labels, and references SHALL be consistent across drawings, schedules, and registers.",
            "Prevents coordination errors.",
        ],
        [
            f"REQ-{req_code}-012",
            "Issued packages SHALL be publish-validated (cold open, XREF resolution, plot preview/PDF check).",
            "Prevents broken submissions.",
        ],
    ]

    html_parts = [
        ai_warning_html(),
        revision_table_html(),
        metadata_table_html(owner_role="Standards Authority", applies_to=applies_to, source_of_truth="This document"),
        p(
            f"<em>Draft normative standard for <strong>{html.escape(topic)}</strong>. "
            "This page establishes SHALL requirements. Review and adjust for client/project context.</em>"
        ),
        h4("1. Context & Scope"),
        h5("1.1 Purpose"),
        p(
            f"This standard defines minimum requirements for <strong>{html.escape(topic)}</strong> work products and "
            "decision points so deliverables are contractor-ready and reviewable."
        ),
        h5("1.2 Scope"),
        p("<strong>This standard applies to:</strong>"),
        ul(
            [
                f"All projects where <strong>{html.escape(topic)}</strong> is in scope",
                "All external (client/contractor) deliverables and internal review packages",
            ]
        ),
        p("<strong>This standard does NOT apply to:</strong>"),
        ul(
            [
                "Purely exploratory sketches not intended for external use",
                "Vendor-owned design where the vendor is the Engineer of Record (unless contract requires)",
            ]
        ),
        h5("1.3 Normative References"),
        table(
            ["Reference", "Edition", "Notes"],
            [
                ["NEC", "Project-specific", "Confirm client-required edition and local amendments."],
                ["NFPA 70E", "Project-specific", "Applies to labeling, PPE references, and arc flash coordination."],
            ],
        ),
        p(
            '<strong>Disclaimer:</strong><span style="white-space: pre-wrap;"> Verify applicability and final signoff with the licensed engineer/project lead.</span>'
        ),
        h4("2. Definitions & Acronyms"),
        table(
            ["Term", "Definition"],
            [
                ["SHALL", "Mandatory requirement."],
                ["SHOULD", "Recommended practice."],
                ["MAY", "Permitted option."],
                ["Contractor-ready", "A package that can be constructed without major clarifications."],
            ],
        ),
        h4("3. Requirements"),
        h5("3.1 General Requirements"),
        table(["ID", "Requirement", "Rationale"], requirements_1),
        h5("3.2 Deliverable Requirements"),
        table(["ID", "Requirement", "Rationale"], requirements_2),
        h4("4. Approved Options / Typicals"),
        p(
            "Use approved typicals where available. If no typical exists, document the decision basis and reviewer sign-off."
        ),
        table(
            ["Option", "When to Use", "Notes"],
            [
                [
                    "Standard typical (preferred)",
                    "Typical use cases with no client deviations",
                    "Reference the typical drawing or library item when available.",
                ],
                [
                    "Project-specific design",
                    "Non-typical process constraints or client delta",
                    "Record assumptions and get lead approval.",
                ],
            ],
        ),
        h4("5. Exceptions & Deviations"),
        h5("5.1 Exception Process"),
        ol(
            [
                "Describe the deviation, why it is required, and any risk introduced.",
                "Propose mitigation (alternate detail, note, calculation, or inspection step).",
                "Obtain approval from Lead Engineer (and PE if required).",
                "Record the approval in the project file and reference it in the deliverable package.",
            ]
        ),
        h4("6. Verification & Acceptance Criteria"),
        h5("6.1 Verification Checklist"),
        table(
            ["ID", "Check Item", "Method", "Pass Criteria"],
            [
                [
                    "V-001",
                    "Scope and assumptions stated",
                    "Inspection",
                    "Assumptions are explicit and reviewable.",
                ],
                [
                    "V-002",
                    "Cross-references consistent",
                    "Inspection",
                    "Tags/IDs match across all artifacts.",
                ],
                [
                    "V-003",
                    "Publish validation completed",
                    "Test",
                    "Cold open + publish outputs show no missing refs.",
                ],
            ],
        ),
        h5("6.2 Reviewer Checklist"),
        ul(
            [
                "[ ] All SHALL statements have been addressed",
                "[ ] Deviations are documented and approved",
                "[ ] Evidence of compliance is attached (screenshots, logs, calc outputs as applicable)",
            ]
        ),
        h4("Open Questions / Dependencies"),
        table(
            ["Question", "Owner Role", "Priority", "Status"],
            [
                [
                    f"What client delta standards apply to <strong>{html.escape(topic)}</strong> for this project?",
                    "Project Lead",
                    "High",
                    "Open",
                ],
                [
                    "Where is the canonical typical/details library stored for this topic?",
                    "CAD Admin / Standards Authority",
                    "Medium",
                    "Open",
                ],
            ],
        ),
        h4("Sources"),
        table(
            ["#", "Source", "URL", "Accessed", "Note"],
            [
                [
                    "1",
                    "Project/client specification",
                    "",
                    today_iso(),
                    "Add the governing spec section(s).",
                ],
                [
                    "2",
                    "Applicable code/standard",
                    "",
                    today_iso(),
                    "Add edition and relevant clauses.",
                ],
            ],
        ),
    ]

    return "".join(html_parts)


def workflow_page_html(book: EmptyBook, topic: str) -> str:
    applies_to = f"{book.book_name} - {topic}"
    html_parts = [
        ai_warning_html(),
        revision_table_html(),
        metadata_table_html(owner_role="Project Manager / Lead Engineer", applies_to=applies_to, source_of_truth="This document"),
        p(
            f"<em>Draft workflow procedure for <strong>{html.escape(topic)}</strong>. "
            "Tune the roles, evidence, and gates to match the specific project delivery model.</em>"
        ),
        h4("1. Context & When to Use"),
        h5("Purpose"),
        p(
            f"This workflow defines how we execute <strong>{html.escape(topic)}</strong> with clear inputs, outputs, gates, and required evidence."
        ),
        h5("When to Use This Workflow"),
        ul(
            [
                "At the start of a project phase where this activity is required",
                "When packaging deliverables for internal review or client submission",
            ]
        ),
        h5("When NOT to Use This Workflow"),
        ul(
            [
                "Ad-hoc internal sketches not intended for review or submission",
                "Client-mandated alternative workflows (document as a client delta)",
            ]
        ),
        h4("2. Inputs & Outputs"),
        h5("Required Inputs"),
        table(
            ["Input", "Source", "Format", "Notes"],
            [
                ["Project requirements", "Client / PM", "PDF / email / meeting notes", "Confirm revision and assumptions."],
                ["Existing registers/logs", "Project files", "Excel / SharePoint", "Use the latest version."],
            ],
        ),
        h5("Outputs Produced"),
        table(
            ["Output", "Destination", "Format", "Notes"],
            [
                [f"{html.escape(topic)} package", "Project folder / transmittal", "PDF + source files", "Must be publish-validated."],
                ["Evidence bundle", "Project folder", "PDF / screenshots / logs", "Enough to prove completion and compliance."],
            ],
        ),
        h4("3. Roles & Responsibilities (RACI)"),
        table(
            ["Activity", "Designer", "Engineer", "Lead Engineer", "Project Manager"],
            [
                ["Assemble inputs", "R", "C", "I", "I"],
                ["Develop outputs", "C", "R", "A", "I"],
                ["Internal review + sign-off", "I", "C", "A", "R"],
            ],
        ),
        p('<strong>Legend:</strong><span style="white-space: pre-wrap;"> R=Responsible, A=Accountable, C=Consulted, I=Informed</span>'),
        h4("4. Workflow Steps"),
        h5("Step 1: Confirm Scope + Assumptions"),
        p("<strong>Who:</strong> Engineer<br><strong>Timing:</strong> Before starting detailed work"),
        ol(
            [
                "Confirm the deliverable list, milestones, and review gate (IFR/IFA/IFC as applicable).",
                "Record assumptions and open questions in a visible place (notes page or issue log).",
                "Identify required client standards/deltas and confirm code edition expectations.",
            ]
        ),
        p('<strong>Gate:</strong><span style="white-space: pre-wrap;"> Scope and assumptions are documented and agreed.</span>'),
        h5("Step 2: Produce Draft Outputs"),
        p("<strong>Who:</strong> Designer/Engineer<br><strong>Timing:</strong> During production"),
        ol(
            [
                "Develop the drawings/documents using standards and templates.",
                "Run a self-check (publish validation, cross-reference check, spelling/units review).",
                "Prepare an evidence bundle (screenshots, logs, calc outputs) for reviewer efficiency.",
            ]
        ),
        h5("Step 3: Internal Review + Close Comments"),
        p("<strong>Who:</strong> Lead Engineer<br><strong>Timing:</strong> Before submission"),
        ol(
            [
                "Perform review using the applicable checklist and flag blockers.",
                "Resolve comments and record dispositions.",
                "Re-run publish validation and confirm deliverable package readiness.",
            ]
        ),
        h4("5. Evidence Required"),
        table(
            ["Evidence Item", "Format", "Storage Location", "Retention"],
            [
                ["Review checklist + sign-off", "PDF", "Project folder", "Per contract"],
                ["Publish validation proof", "Screenshot / log", "Project folder", "Per contract"],
            ],
        ),
        h4("6. QA/QC Checklist"),
        h5("Pre-Execution Checklist"),
        ul(["[ ] Requirements and code edition confirmed", "[ ] Client deltas identified (if any)", "[ ] Latest templates and title blocks loaded"]),
        h5("Post-Execution Checklist"),
        ul(["[ ] Self-check complete", "[ ] Peer/lead review complete", "[ ] Evidence bundle stored and linked"]),
        h5("Definition of Done"),
        ul(["[ ] Outputs produced in the correct formats", "[ ] All blockers resolved and signed off", "[ ] Package is publish-validated and contractor-ready"]),
        h4("7. Failure Modes & RFI Prevention"),
        table(
            ["Failure Mode", "Symptoms", "Prevention", "If It Happens"],
            [
                ["Missing or conflicting references", "RFIs, field delays, review rework", "Cross-reference checks + register alignment", "Issue an internal correction package and update registers"],
                ["Broken publish (missing XREFs/fonts)", "Reviewer cannot open/publish; submission rejected", "Cold open + publish validation before review", "Fix paths/fonts, republish, and attach proof"],
            ],
        ),
        h4("8. Related Templates & Documents"),
        table(
            ["Document", "Purpose", "Link"],
            [
                ["Template library", "Use the latest registers/logs/checklists", "[Link](#)"],
                ["Standards book", "Normative requirements for deliverables", "[Link](#)"],
            ],
        ),
    ]
    return "".join(html_parts)


def deep_dive_page_html(book: EmptyBook, topic: str) -> str:
    applies_to = f"{book.book_name} - {topic}"
    html_parts = [
        ai_warning_html(),
        revision_table_html(),
        metadata_table_html(owner_role="Subject Matter Expert", applies_to=applies_to, source_of_truth="This document"),
        p(
            f"<em>Draft deep dive for <strong>{html.escape(topic)}</strong>. "
            "Add project-specific typicals and vendor references as you validate in the field.</em>"
        ),
        h4("Context"),
        p("This page captures common patterns, review checks, and failure modes that repeatedly show up in projects."),
        h4("Common Patterns & Typicals"),
        ul(
            [
                "<strong>Pattern 1</strong><br>Describe the most common implementation pattern and when to use it.<br><br><strong>Tip:</strong><span style=\"white-space: pre-wrap;\"> Add a diagram or link to a typical drawing.</span><br>",
                "<strong>Pattern 2</strong><br>Describe an alternate pattern and the tradeoffs.<br>",
            ]
        ),
        h4("Interfaces to Deliverables"),
        table(
            ["Deliverable", "How This Topic Affects It"],
            [
                ["Device list / network diagram", "Define naming, addressing, and topology impacts."],
                ["Loop drawings / schematics", "Define wiring, shielding, and termination impacts."],
                ["Commissioning evidence", "Define tests and acceptance criteria."],
            ],
        ),
        h4("Review Checks"),
        ul(["[ ] Requirements captured", "[ ] Failure modes mitigated", "[ ] Field validation steps explicit"]),
        h4("Failure Modes & Field Symptoms"),
        table(
            ["Failure Mode", "Field Symptom", "Root Cause", "Prevention"],
            [
                ["Configuration mismatch", "Device offline/intermittent", "Wrong parameters/version drift", "Baseline configs + backup/restore"],
                ["Wiring/termination error", "Unexpected readings/alarms", "Incorrect terminations/shields", "Termination standard + inspection checklist"],
            ],
        ),
        h4("References"),
        table(
            ["Resource", "Purpose", "Link"],
            [["Vendor manual", "Parameters and diagnostics", "[Link](#)"], ["Internal standard", "Documentation rules", "[Link](#)"]],
        ),
    ]
    return "".join(html_parts)


def onboarding_page_html(book: EmptyBook, topic: str) -> str:
    applies_to = f"{book.book_name} - {topic}"
    html_parts = [
        ai_warning_html(),
        revision_table_html(),
        metadata_table_html(owner_role="Training Lead / Engineering Manager", applies_to=applies_to, source_of_truth="This document"),
        p(
            f"<em>Draft onboarding module: <strong>{html.escape(topic)}</strong>. "
            "Replace placeholders (systems, contacts, links) with the real internal resources.</em>"
        ),
        h4("Context & Purpose"),
        p("This page exists to make onboarding repeatable and reduce time-to-productivity."),
        h4("Quick-Start Checklist"),
        h5("First 15 Minutes"),
        ul(["Confirm you can log in to BookStack.", "Bookmark your discipline standards and templates."]),
        h5("First Day"),
        ul(["Request required accounts.", "Install core tools and validate with a sample.", "Read the standards overview."]),
        h5("First Week"),
        ul(["Complete required safety training.", "Shadow a package review."]),
        h4("Step-by-Step"),
        ol(["Identify required access/tools.", "Submit access requests early.", "Validate tools by opening/publishing a sample."]),
        h4("Common Issues & Troubleshooting"),
        table(
            ["Issue", "Likely Cause", "Solution"],
            [["Cannot access a tool/license", "License not assigned", "Contact IT/Admin"], ["Cannot publish a DWG", "Missing fonts/XREF paths", "Run cold open + fix paths/fonts"]],
        ),
        h4("Where to Get Help"),
        table(["Question Type", "Contact/Resource"], [["Tooling/licenses", "IT/Admin"], ["Standards", "Lead Engineer / Standards Authority"], ["Project", "Project Manager"]]),
    ]
    return "".join(html_parts)


def track_overview_html(book: EmptyBook, track_name: str) -> str:
    applies_to = track_name
    html_parts = [
        ai_warning_html(),
        revision_table_html(),
        metadata_table_html(owner_role="Training Lead", applies_to=applies_to, source_of_truth="This document"),
        p(
            f"<em>Draft track overview for <strong>{html.escape(track_name)}</strong>. "
            "Replace module titles and evidence requirements based on the real curriculum.</em>"
        ),
        h4("Track Purpose"),
        h5("What You'll Learn"),
        p("This track defines outcomes, evidence, and quality gates. Link to standards, templates, and examples."),
        h5("Target Audience"),
        table(["Role", "Readiness Level", "Expected Outcome"], [["Designer", "Entry to intermediate", "Assemble compliant packages with supervision."], ["Engineer", "Intermediate", "Own packages and drive reviews to closure."]]),
        h4("Prerequisites"),
        ul(["[ ] Access to core tools", "[ ] Read relevant standards", "[ ] Basic safety orientation (if applicable)"]),
        h4("Module Map"),
        p("<pre>" + html.escape(track_name + "\n|\n+-- Module 1: Fundamentals\n+-- Module 2: Standards + Templates\n+-- Module 3: Package Assembly + QA\n+-- Module 4: Review + Field Feedback (Capstone)\n") + "</pre>"),
        h4("Quality Gates"),
        table(["Gate", "Completion Criteria"], [["Module completion", "Assessment + sign-off"], ["Track completion", "Capstone reviewed and accepted"]]),
        h4("Completion Outputs"),
        table(["Output", "Description", "Evidence"], [["Reviewed deliverable package", "Contractor-ready example", "PDF + checklist + comment log"], ["Personal checklist", "Reusable self-check", "Saved checklist/template copy"]]),
    ]
    return "".join(html_parts)


def competency_checklist_html(book: EmptyBook, role_name: str) -> str:
    applies_to = role_name
    html_parts = [
        ai_warning_html(),
        revision_table_html(),
        metadata_table_html(owner_role="Training Lead / Lead Engineer", applies_to=applies_to, source_of_truth="This document"),
        p(
            f"<em>Draft competency checklist for <strong>{html.escape(role_name)}</strong>. "
            "Convert placeholders into measurable criteria and link to training modules.</em>"
        ),
        h4("Overview"),
        p("This checklist captures minimum competencies required for role progression."),
        h4("Completion Requirements"),
        ul(["All core competencies completed", "Practical assessments witnessed", "Final sign-off recorded"]),
        h4("Core Competencies (Draft)"),
        table(["Topic", "Completed", "Date", "Verified By"], [["Standards awareness", "[ ]", "", ""], ["Package assembly + publish validation", "[ ]", "", ""], ["Review response + closure", "[ ]", "", ""], ["Field feedback loop", "[ ]", "", ""]]),
        h4("Practical Skills Assessment"),
        table(["Skill", "Demonstrated", "Date", "Evaluator", "Notes"], [["Assemble contractor-ready package", "[ ]", "", "", ""], ["Run and document self-check", "[ ]", "", "", ""], ["Respond to review comments", "[ ]", "", "", ""]]),
        h4("Sign-Off"),
        table(["Role", "Name", "Date", "Notes"], [["Trainee", "", "", ""], ["Supervisor", "", "", ""], ["Standards Authority", "", "", ""]]),
    ]
    return "".join(html_parts)


def parse_topics_from_description(desc: str) -> List[str]:
    parts = [p.strip() for p in re.split(r",", desc or "") if p.strip()]
    out: List[str] = []
    seen = set()
    for p0 in parts:
        p1 = p0.rstrip(".").strip()
        # Strip leading conjunctions introduced by comma-splitting.
        p1 = re.sub(r"^(and|&)\s+", "", p1, flags=re.IGNORECASE).strip()
        if not p1:
            continue
        k = p1.lower()
        if k in seen:
            continue
        seen.add(k)
        out.append(p1)
    return out[:6]


def build_plan_for_book(book: EmptyBook) -> List[ChapterPlan]:
    """Return chapter/page plans for a given book.

    Philosophy:
    - Standards & delivery workflow books get structured, template-aligned pages.
    - Everything else gets at least one useful overview/deep-dive style page.
    - Where the book description is a short comma-separated topic list, use it.
    """

    # -------------------------------------------------------------------------
    # 2. Standards & Procedures
    # -------------------------------------------------------------------------

    if book.book_id == 121:  # Electrical Engineering Standards
        topics = [
            "Power Distribution",
            "Motor Control",
            "Grounding and Bonding",
            "Cable and Raceway",
            "Arc Flash and Labeling",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 122:  # Controls & Instrumentation Standards
        topics = [
            "PLC Standards",
            "HMI Standards",
            "OT Network Architecture Standards",
            "Cybersecurity and Remote Access",
            "Time Synchronization and Historian Interfaces",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 124:  # Document Control and CAD Standards
        topics = [
            "Drawing Standards",
            "File Naming and Numbering",
            "Revision Control and Transmittals",
            "Document Registers and Metadata",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 125:  # Client Standards
        topics = [
            "How to Use Client Standards",
            "Client Delta Template",
            "Conflict Resolution (Core vs Client)",
            "Client Delta Index (Add Clients Here)",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=t,
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 384:  # Documentation Standards
        topics = parse_topics_from_description(book.book_desc) or [
            "Naming Conventions",
            "File Organization",
            "Version Control",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 385:  # Drawing Standards
        topics = parse_topics_from_description(book.book_desc) or [
            "General Requirements",
            "Symbol Libraries",
            "Title Blocks",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 1025:  # Behavioral Standards
        topics = [
            "Professional Conduct",
            "Communication & Responsiveness",
            "Review Culture",
            "Meeting Etiquette",
            "Field Behavior & Safety",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 1026:  # On-Drawing Notes
        topics = [
            "General Notes",
            "Sheet Notes",
            "Key Notes",
            "Hold Notes",
            "Note Maintenance Rules",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 1027:  # Reports and Technical Documents
        topics = [
            "Engineering Reports (Minimum Content)",
            "Calculation Packages",
            "Narratives & Cause/Effect",
            "Submission Packaging",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Standard: {t}",
                        html=standard_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    # -------------------------------------------------------------------------
    # 5. Project Resources + 8. Business Development
    # -------------------------------------------------------------------------

    # High-value delivery workflow books: use explicit chapter maps (avoid parsing long sentences).
    if book.book_id == 127:  # Project Setup and Closeout
        topics = [
            "Kickoff Package and RACI",
            "Project Foldering and Registers",
            "Deliverable Planning and Milestones",
            "Closeout and As-Builts",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Workflow: {t}",
                        html=workflow_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 128:  # Reviews Submittals and Change Control
        topics = [
            "Review Gates and Readiness Definitions",
            "Internal Review Workflow",
            "Commenting Standard and Severity",
            "Client Submittal and Transmittals",
            "RFI Workflow and Tracking",
            "Change Management and Scope Control",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Workflow: {t}",
                        html=workflow_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 129:  # Vendor Data and Package Integration
        topics = [
            "Vendor Submittal Tracking",
            "Vendor Drawing Review Workflow",
            "Package Boundaries and Interfaces",
            "Integrating Vendor Data into IFC",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Workflow: {t}",
                        html=workflow_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id == 130:  # Field Execution and Commissioning Workflow
        topics = [
            "Site Safety Essentials",
            "Installation Verification Walkdowns",
            "Loop Check Workflow",
            "SAT Workflow",
            "Startup Support Workflow",
            "Redlines and As-Built Capture",
        ]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=f"Workflow: {t}",
                        html=workflow_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    if book.book_id in {397, 398, 400, 401, 399, 412}:
        topics = parse_topics_from_description(book.book_desc)
        if not topics:
            topics = ["Overview"]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=("Overview" if t.lower() == "overview" else f"Workflow: {t}"),
                        html=workflow_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    # Templates / examples / libraries
    if book.book_id in {21, 140, 141, 24, 26, 145, 146}:
        base = [
            ChapterPlan(
                name="1. Overview",
                description="",
                pages=[
                    PagePlan(
                        name="Overview",
                        html=deep_dive_page_html(book, "Overview"),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
        ]

        if book.book_id == 145:  # RFI Prevention Library
            base.append(
                ChapterPlan(
                    name="2. RFI Prevention Template",
                    description="",
                    pages=[
                        PagePlan(
                            name="Template: RFI Prevention Entry",
                            html=workflow_page_html(book, "RFI Prevention Entry Template"),
                            tags=[{"name": "status:draft", "value": ""}],
                        )
                    ],
                )
            )
        elif book.book_id == 146:  # Troubleshooting
            base.append(
                ChapterPlan(
                    name="2. Troubleshooting Template",
                    description="",
                    pages=[
                        PagePlan(
                            name="Template: Troubleshooting Entry",
                            html=deep_dive_page_html(book, "Troubleshooting Entry Template"),
                            tags=[{"name": "status:draft", "value": ""}],
                        )
                    ],
                )
            )
        else:
            base.append(
                ChapterPlan(
                    name="2. Template",
                    description="",
                    pages=[
                        PagePlan(
                            name="Template (Copy Me)",
                            html=deep_dive_page_html(book, "Template (Copy Me)"),
                            tags=[{"name": "status:draft", "value": ""}],
                        )
                    ],
                )
            )

        return base

    # -------------------------------------------------------------------------
    # 4. Training & Development
    # -------------------------------------------------------------------------

    if book.book_id in {131, 132, 133, 134}:
        track_name = book.book_name
        return [
            ChapterPlan(
                name="Track Overview",
                description="",
                pages=[
                    PagePlan(
                        name="Track Overview",
                        html=track_overview_html(book, track_name),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            ),
            ChapterPlan(
                name="Module Map",
                description="",
                pages=[
                    PagePlan(
                        name="Module Map",
                        html=track_overview_html(book, f"{track_name} - Module Map"),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            ),
        ]

    if book.book_id in {135, 136, 137, 139}:
        role_name = book.book_name
        return [
            ChapterPlan(
                name="Competency Checklist",
                description="",
                pages=[
                    PagePlan(
                        name="Competency Checklist",
                        html=competency_checklist_html(book, role_name),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            ),
            ChapterPlan(
                name="Review & Mentorship Guidance",
                description="",
                pages=[
                    PagePlan(
                        name="Review & Mentorship Guidance",
                        html=workflow_page_html(book, "Review & Mentorship Guidance"),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            ),
        ]

    # -------------------------------------------------------------------------
    # 1. Onboarding
    # -------------------------------------------------------------------------

    if book.book_id in {981, 381}:
        topics = parse_topics_from_description(book.book_desc)
        if book.book_id == 981:
            topics = [
                "Start Here",
                "Accounts, Access, and Permissions",
                "Engineering Workstation Setup",
                "Required Software and Licenses",
                "Safety Training Requirements",
                "First Week Checklist",
                "Where to Get Help",
            ]
        if not topics:
            topics = ["Overview"]
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=t,
                        html=onboarding_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    # -------------------------------------------------------------------------
    # Other shelves
    # -------------------------------------------------------------------------

    # If a book description is a short comma-separated list (example: "Setup, Libraries, Reporting"),
    # treat that as the intended chapter map.
    desc = (book.book_desc or "").strip()
    desc_l = desc.lower()
    topics = parse_topics_from_description(desc)
    looks_like_topic_list = (
        len(topics) >= 2
        and len(desc) <= 120
        and "covering" not in desc_l
        and "guidance" not in desc_l
        and "comprehensive" not in desc_l
    )

    if looks_like_topic_list:
        return [
            ChapterPlan(
                name=t,
                description="",
                pages=[
                    PagePlan(
                        name=t,
                        html=deep_dive_page_html(book, t),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
            for t in topics
        ]

    # Integration & Automation and Technical References: deep-dive style by default.
    if book.shelf_name in {"7. Integration & Automation", "3. Technical References"}:
        return [
            ChapterPlan(
                name="Overview",
                description="",
                pages=[
                    PagePlan(
                        name="Overview",
                        html=deep_dive_page_html(book, "Overview"),
                        tags=[{"name": "status:draft", "value": ""}],
                    )
                ],
            )
        ]

    # Default: a single useful overview so the book is no longer empty.
    return [
        ChapterPlan(
            name="1. Overview",
            description="",
            pages=[
                PagePlan(
                    name="Overview",
                    html=deep_dive_page_html(book, "Overview"),
                    tags=[{"name": "status:draft", "value": ""}],
                )
            ],
        )
    ]
def read_empty_books_from_hierarchy(path: Path) -> List[EmptyBook]:
    data = json.loads(path.read_text(encoding="utf-8"))
    out: List[EmptyBook] = []
    for shelf in data.get("hierarchy", {}).get("shelves", []):
        shelf_name = shelf.get("name") or ""
        for book in shelf.get("books", []):
            if (book.get("chapters") or []) or (book.get("direct_pages") or []):
                continue
            out.append(
                EmptyBook(
                    shelf_name=shelf_name,
                    book_id=int(book["id"]),
                    book_name=str(book.get("name") or "").strip(),
                    book_desc=str(book.get("description") or "").strip(),
                )
            )
    return out


def find_chapter_by_name(book_contents: Dict[str, Any], name: str) -> Optional[Dict[str, Any]]:
    for item in book_contents.get("contents", []) or []:
        if item.get("type") == "chapter" and str(item.get("name") or "").strip().lower() == name.strip().lower():
            return item
    return None


def ensure_chapter(api: BookStackApi, book_id: int, name: str, description: str, dry_run: bool) -> int:
    book_data = api.get(f"/books/{book_id}")
    existing = find_chapter_by_name(book_data, name)
    if existing and existing.get("id"):
        return int(existing["id"])
    if dry_run:
        return -1
    created = api.post("/chapters", {"book_id": book_id, "name": name, "description": description})
    return int(created["id"])


def page_exists_in_chapter(api: BookStackApi, chapter_id: int, page_name: str) -> bool:
    ch = api.get(f"/chapters/{chapter_id}")
    for p0 in ch.get("pages", []) or []:
        if str(p0.get("name") or "").strip().lower() == page_name.strip().lower():
            return True
    return False


def create_page_in_chapter(api: BookStackApi, chapter_id: int, plan: PagePlan, dry_run: bool) -> Optional[int]:
    if chapter_id <= 0:
        return None
    if page_exists_in_chapter(api, chapter_id, plan.name):
        return None
    if dry_run:
        return None
    payload: Dict[str, Any] = {"chapter_id": chapter_id, "name": plan.name, "html": plan.html}
    if plan.tags:
        payload["tags"] = plan.tags
    created = api.post("/pages", payload)
    return int(created["id"])


def main() -> int:
    ap = argparse.ArgumentParser(description="Seed starter content into empty BookStack books.")
    ap.add_argument("--apply", action="store_true", help="Apply changes (default: dry-run).")
    ap.add_argument("--limit", type=int, default=0, help="Limit number of books processed.")
    ap.add_argument("--book-id", type=int, action="append", default=[], help="Process only the specified book ID (repeatable).")
    args = ap.parse_args()

    dry_run = not args.apply

    if not ENV_SETUP_PATH.exists():
        eprint(f"ERROR: Missing {ENV_SETUP_PATH} (run as admin user).")
        return 2
    if not HIERARCHY_PATH.exists():
        eprint(f"ERROR: Missing {HIERARCHY_PATH}. Run setup/sync-hierarchy.sh first.")
        return 2

    env = load_env_file(ENV_SETUP_PATH)
    url = (env.get("BOOKSTACK_API_URL") or env.get("BOOKSTACK_URL") or "").rstrip("/")
    token_id = env.get("BOOKSTACK_TOKEN_ID") or ""
    token_secret = env.get("BOOKSTACK_TOKEN_SECRET") or ""
    if not url or not token_id or not token_secret:
        eprint("ERROR: BOOKSTACK_URL/BOOKSTACK_API_URL or token vars missing in .env.setup")
        return 2

    api = BookStackApi(ApiConfig(api_base=f"{url}/api", token_id=token_id, token_secret=token_secret))

    empty_books = read_empty_books_from_hierarchy(HIERARCHY_PATH)
    if args.book_id:
        allow = set(args.book_id)
        empty_books = [b for b in empty_books if b.book_id in allow]

    empty_books.sort(key=lambda b: (b.shelf_name.lower(), b.book_name.lower(), b.book_id))
    if args.limit and args.limit > 0:
        empty_books = empty_books[: args.limit]

    eprint(f"Found {len(empty_books)} empty book(s) to seed. Dry-run={dry_run}.")

    pages_created = 0

    for idx, book in enumerate(empty_books, start=1):
        eprint(f"\n[{idx}/{len(empty_books)}] {book.shelf_name} :: {book.book_name} (ID {book.book_id})")
        plan = build_plan_for_book(book)
        for ch_plan in plan:
            try:
                ch_id = ensure_chapter(api, book.book_id, ch_plan.name, ch_plan.description, dry_run=dry_run)
            except Exception as ex:
                eprint(f"  ERROR chapter '{ch_plan.name}': {ex}")
                continue

            if ch_id == -1:
                eprint(f"  [DRY] would create chapter: {ch_plan.name}")
                for p_plan in ch_plan.pages:
                    eprint(f"    [DRY] would create page: {p_plan.name}")
                continue

            for p_plan in ch_plan.pages:
                try:
                    new_id = create_page_in_chapter(api, ch_id, p_plan, dry_run=dry_run)
                    if new_id is not None:
                        pages_created += 1
                        eprint(f"    created page: {p_plan.name} (ID {new_id})")
                    else:
                        eprint(f"    skipped page (exists): {p_plan.name}")
                except Exception as ex:
                    eprint(f"    ERROR page '{p_plan.name}': {ex}")

            time.sleep(0.15)

    eprint("\n=== Seed Summary ===")
    eprint(f"Pages created: {pages_created}")
    if dry_run:
        eprint("This was a dry run. Re-run with --apply to create content.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
