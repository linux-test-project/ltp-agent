#!/usr/bin/env python3
"""
ltp-patch-queue: Evaluate and rank pending LTP patches by review priority.

Usage:
    ./ltp-patch-queue.py                  # quick mode (subject heuristics for lib detection)
    ./ltp-patch-queue.py --diffs          # fetch full diffs (~1 req/patch): enables accurate
                                          #   lib/include detection, Fixes: tag, and SOB count
    ./ltp-patch-queue.py --no-tags        # ignore Reviewed-by, Acked-by, Signed-off-by
    ./ltp-patch-queue.py --no-days        # ignore patch age; rank by version/fix/tags only
    ./ltp-patch-queue.py --min-score N    # only show patches with score >= N
    ./ltp-patch-queue.py --max N          # max patches to fetch (default: 500)
    ./ltp-patch-queue.py --json           # output raw scored JSON instead of table
"""

import argparse
import json
import re
import sys
from datetime import date, datetime
from urllib.request import Request, urlopen

PATCHWORK_BASE = "https://patchwork.ozlabs.org/api"
PROJECT = "ltp"
TODAY = date.today()

# ----- Terminal formatting ----------------------------------------------------

BOLD  = "\033[1m"
DIM   = "\033[2m"
RESET = "\033[0m"
RED   = "\033[91m"
YELLOW = "\033[93m"
CYAN  = "\033[96m"
BLUE  = "\033[94m"
GRAY  = "\033[90m"

TIER_COLOR = {"P1": RED, "P2": YELLOW, "P3": CYAN, "P4": BLUE, "P5": GRAY}

# ----- Regexes ----------------------------------------------------------------

# Patchwork strips "PATCH" from the name field; subjects look like:
#   [v2,1/2] foo: bar     [RFC,v5,2/6] baz     [v8] qux
VERSION_RE = re.compile(r"\[(?:[^\]]*?[,\s])?v(\d+)", re.IGNORECASE)
RFC_RE = re.compile(r"\[(?:[^\]]*,)?RFC(?:[,\]])", re.IGNORECASE)
COVER_RE = re.compile(r"\[(?:[^\]]*[,\s])?0/\d+", re.IGNORECASE)
SERIES_RE = re.compile(r"\[(?:[^\]]*[,\s])?(\d+)/(\d+)", re.IGNORECASE)
FIX_KEYWORDS_RE = re.compile(
    r"\b(fix(es)?|bug|regression|broken|bugfix|revert)\b", re.IGNORECASE
)
FIXES_TAG_RE = re.compile(r"^Fixes:", re.MULTILINE)
SOB_RE = re.compile(r"^Signed-off-by:", re.MULTILINE)
DIFF_PATH_RE = re.compile(r"^(?:\+\+\+ b/|--- a/)(.+)", re.MULTILINE)

# Subject-line heuristics for lib/include detection (used without --diffs)
LIB_SUBJECT_RE = re.compile(r"\b(tst_|safe_|lapi|^lib:|configure\.ac)\b", re.IGNORECASE)
INCLUDE_SUBJECT_RE = re.compile(r"\b(lapi|include/|syscalls\.h)\b", re.IGNORECASE)

# Path prefix → bonus points (highest match wins, not stacked)
LIB_PATH_RULES = [
    (re.compile(r"^lib/"), 15),
    (re.compile(r"^include/"), 10),
    (re.compile(r"^tools/"), 5),
    (re.compile(r"^m4/"), 5),
    (re.compile(r"^configure\.ac$"), 5),
]

# ----- Scoring ----------------------------------------------------------------


def score_version(version: int) -> int:
    return {1: 0, 2: 15, 3: 25, 4: 35}.get(version, 40)


def score_age(days: int) -> int:
    """
    Inverted-U curve: peaks at 61-90 days (genuinely neglected),
    then decays for very old patches (likely stale for a reason).
    """
    if days < 7:
        return 0  # too fresh
    if days < 15:
        return 10
    if days < 31:
        return 20
    if days < 61:
        return 45  # peak urgency
    if days < 91:
        return 35  # starting to look stale
    if days < 181:
        return 20
    if days < 366:
        return 10  # probably stale for a reason
    return 5  # very old — low odds of easy merge


def score_series(size: int) -> int:
    if size == 1:
        return 10
    if size <= 5:
        return 0
    if size <= 10:
        return -5
    return -15


def parse_version(name: str) -> int:
    m = VERSION_RE.search(name)
    return int(m.group(1)) if m else 1


def parse_series_size(name: str, series_field: list) -> int:
    if series_field:
        for s in series_field:
            total = s.get("total") or s.get("count")
            if total:
                return int(total)
    m = SERIES_RE.search(name)
    return int(m.group(2)) if m else 1


def age_days(date_str: str) -> int:
    try:
        dt = datetime.fromisoformat(date_str.replace("Z", "+00:00"))
        return (TODAY - dt.date()).days
    except Exception:
        return 30


def score_sob(count: int) -> int:
    """
    1 SOB = author only, meaningless baseline.
    Extra SOBs mean the patch passed through additional maintainer hands.
    Modest bonus — enough to matter, not enough to dominate.
    """
    if count <= 1:
        return 0
    if count == 2:
        return 5
    if count == 3:
        return 10
    return 15  # 4+


def lib_score_from_subject(name: str) -> int:
    if LIB_SUBJECT_RE.search(name):
        return 15
    if INCLUDE_SUBJECT_RE.search(name):
        return 10
    return 0


def lib_score_from_diff(diff_text: str) -> int:
    paths = DIFF_PATH_RE.findall(diff_text)
    best = 0
    for path in paths:
        for pattern, points in LIB_PATH_RULES:
            if pattern.search(path):
                best = max(best, points)
    return best


# ----- API helpers ------------------------------------------------------------


def fetch_json(url: str) -> dict | list:
    req = Request(url, headers={"Accept": "application/json"})
    with urlopen(req, timeout=30) as r:
        return json.loads(r.read())


def fetch_all_patches(
    states=("new", "under-review"), max_patches=500
) -> tuple[list, dict]:
    patches = []
    counts = {}
    for state in states:
        url = (
            f"{PATCHWORK_BASE}/patches/"
            f"?project={PROJECT}&state={state}&order=-date&per_page=100"
        )
        state_count = 0
        while url and len(patches) < max_patches:
            data = fetch_json(url)
            results = data.get("results", data) if isinstance(data, dict) else data
            for p in results:
                if len(patches) >= max_patches:
                    break
                patches.append(p)
                state_count += 1
            url = data.get("next") if isinstance(data, dict) else None
        counts[state] = state_count
    return patches, counts


def fetch_mbox(mbox_url: str) -> str:
    req = Request(mbox_url)
    with urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", errors="replace")


def fetch_patch_detail(patch_id: int) -> str:
    """Return diff text for a patch by fetching its mbox."""
    data = fetch_json(f"{PATCHWORK_BASE}/patches/{patch_id}/")
    mbox_url = data.get("mbox", "")
    if not mbox_url:
        return ""
    return fetch_mbox(mbox_url)


# ----- Scoring a single patch -------------------------------------------------


def score_patch(
    patch: dict,
    fetch_diffs: bool = False,
    ignore_tags: bool = False,
    ignore_days: bool = False,
) -> dict:
    name = patch.get("name", "")
    tags = patch.get("tags") or {}
    state = patch.get("state", "new")
    delegate = patch.get("delegate")
    series = patch.get("series") or []
    date_str = patch.get("date", "")
    patch_id = patch.get("id")

    version = parse_version(name)
    rfc = bool(RFC_RE.search(name))
    series_size = parse_series_size(name, series)
    days = age_days(date_str)
    reviewed = tags.get("reviewed-by-count", 0)
    acked = tags.get("acked-by-count", 0)
    fix_keyword = bool(FIX_KEYWORDS_RE.search(name))

    has_fixes_tag = False
    sob_count = tags.get("signed-off-by-count", 0)  # populated if patchwork tracks it
    if fetch_diffs:
        diff_text = fetch_patch_detail(patch_id)
        has_fixes_tag = bool(FIXES_TAG_RE.search(diff_text))
        lib_pts = lib_score_from_diff(diff_text)
        sob_count = len(SOB_RE.findall(diff_text)) or sob_count
    else:
        lib_pts = lib_score_from_subject(name)

    score = 0
    reasons = []

    # Rule 1 – version
    v = score_version(version)
    if v:
        score += v
        reasons.append(f"v{version}(+{v})")

    # Rule 2 – fix keywords
    if fix_keyword:
        score += 45
        reasons.append("fix(+45)")
    if has_fixes_tag:
        score += 30
        reasons.append("Fixes:(+30)")

    # Rule 3 – age (skipped with --no-days)
    if not ignore_days:
        a = score_age(days)
        if a:
            score += a
            reasons.append(f"age:{days}d(+{a})")

    # Rule 4 – RFC
    if rfc:
        score -= 25
        reasons.append("RFC(-25)")

    # Rule 5 – lib/infra
    if lib_pts:
        score += lib_pts
        reasons.append(f"lib(+{lib_pts})")

    # Rule 6 – series size
    s = score_series(series_size)
    if s:
        score += s
        reasons.append(f"series:{series_size}({s:+d})")

    # Rule 7 – review tags (skipped with --no-tags)
    if not ignore_tags:
        if reviewed >= 1:
            score += 20
            reasons.append("Reviewed-by(+20)")
        if acked >= 1:
            score += 10
            reasons.append("Acked-by(+10)")

    # Rule 7b – Signed-off-by count (requires --diffs or patchwork tag support)
    if not ignore_tags:
        sob_pts = score_sob(sob_count)
        if sob_pts:
            score += sob_pts
            reasons.append(f"SOB:{sob_count}(+{sob_pts})")

    # Rule 8 – delegated
    if delegate:
        score -= 10
        reasons.append("delegated(-10)")

    # Rule 9 – state
    if state == "under-review":
        score -= 20
        reasons.append("under-review(-20)")

    return {
        "id": patch_id,
        "name": name,
        "submitter": patch.get("submitter", {}).get("name", "Unknown"),
        "email": patch.get("submitter", {}).get("email", ""),
        "date": date_str,
        "days": days,
        "state": state,
        "version": version,
        "rfc": rfc,
        "series_size": series_size,
        "reviewed": reviewed,
        "acked": acked,
        "delegate": delegate,
        "fix_keyword": fix_keyword,
        "has_fixes_tag": has_fixes_tag,
        "sob_count": sob_count,
        "lib_pts": lib_pts,
        "score": score,
        "reasons": reasons,
        "url": patch.get("web_url")
        or f"https://patchwork.ozlabs.org/project/ltp/patch/{patch_id}/",
    }


# ----- Tier classification ----------------------------------------------------

TIERS = [
    (80, "P1", "🔴 URGENT"),
    (60, "P2", "🟠 HIGH"),
    (40, "P3", "🟡 NORMAL"),
    (20, "P4", "🔵 LOW"),
    (None, "P5", "⚪ DEFER"),
]


def classify(score: int) -> tuple[str, str]:
    for min_score, tier_id, label in TIERS:
        if min_score is None or score >= min_score:
            return tier_id, label
    return "P5", "⚪ DEFER"


def build_notes(p: dict) -> str:
    parts = []
    if p["has_fixes_tag"]:
        parts.append("Fixes:✓")
    if p["reviewed"]:
        parts.append("Reviewed-by ✅")
    if p["acked"]:
        parts.append("Acked-by ✅")
    if p["rfc"]:
        parts.append("RFC")
    if p["lib_pts"] >= 15:
        parts.append("lib/")
    elif p["lib_pts"] >= 10:
        parts.append("include/")
    elif p["lib_pts"] > 0:
        parts.append("tools/")
    if p["sob_count"] > 1:
        parts.append(f"SOB:{p['sob_count']}")
    if p["days"] > 60:
        parts.append("STALE")
    if p["series_size"] > 5:
        parts.append(f"SERIES {p['series_size']}")
    return ", ".join(parts) if parts else "—"


# ----- Output -----------------------------------------------------------------


def _hyperlink(url: str, text: str) -> str:
    """OSC 8 terminal hyperlink (degrades gracefully if unsupported)."""
    return f"\033]8;;{url}\033\\{text}\033]8;;\033\\"


def print_pretty(scored: list, counts: dict) -> None:
    total = len(scored)
    new_count = counts.get("new", 0)
    under_count = counts.get("under-review", 0)
    stale_count = sum(1 for p in scored if p["days"] > 60)
    rfc_count = sum(1 for p in scored if p["rfc"])
    waiting_count = sum(1 for p in scored if p["reviewed"] >= 1)

    rule = "─" * 80

    print(f"\n{BOLD}LTP Patch Review Queue — {TODAY}{RESET}\n")
    print(f"Fetched {BOLD}{total}{RESET} patches"
          f"  (new: {new_count}  under-review: {under_count})\n")
    print(rule)

    grouped = {tier_id: [] for _, tier_id, _ in TIERS}
    for p in scored:
        tier_id, _ = classify(p["score"])
        grouped[tier_id].append(p)
    for _, tier_id, _ in TIERS:
        grouped[tier_id].sort(key=lambda p: (-p["score"], p["days"]))

    # Column widths
    W_NUM, W_SCORE, W_VER, W_AGE, W_SUBJ = 3, 5, 3, 5, 58

    counter = 1
    for _, tier_id, label in TIERS:
        patches = grouped[tier_id]
        color = TIER_COLOR.get(tier_id, "")

        print(f"\n{color}{BOLD}{label}{RESET}  {GRAY}({len(patches)}){RESET}\n")

        if not patches:
            print(f"  {DIM}None{RESET}")
            continue

        # Header row
        hdr = (f"  {'#':>{W_NUM}}  {'Score':>{W_SCORE}}  {'Ver':>{W_VER}}"
               f"  {'Age':>{W_AGE}}  {'Subject':<{W_SUBJ}}  Notes")
        sep = (f"  {'─'*W_NUM}  {'─'*W_SCORE}  {'─'*W_VER}"
               f"  {'─'*W_AGE}  {'─'*W_SUBJ}  {'─'*22}")
        print(f"{BOLD}{hdr}{RESET}")
        print(GRAY + sep + RESET)

        for p in patches:
            score_str = f"{color}{BOLD}{p['score']:>{W_SCORE}}{RESET}"
            ver_str   = f"v{p['version']}"
            age_str   = f"{p['days']}d"
            subj_raw  = p["name"][:W_SUBJ] + ("…" if len(p["name"]) > W_SUBJ else "")
            subj_pad  = subj_raw + " " * max(0, W_SUBJ - len(subj_raw))
            num_disp  = _hyperlink(p["url"], f"{counter:>{W_NUM}}")
            notes     = build_notes(p)
            print(
                f"  {num_disp}  {score_str}  {ver_str:>{W_VER}}"
                f"  {age_str:>{W_AGE}}  {subj_pad}  {GRAY}{notes}{RESET}"
            )
            counter += 1

    print(f"\n{rule}\n")
    print(f"{BOLD}Summary{RESET}\n")
    stale_note = f"  {RED}← needs attention{RESET}" if stale_count else ""
    print(f"  Total patches evaluated:           {BOLD}{total}{RESET}")
    print(f"  Patches > 60 days old:             {BOLD}{stale_count}{RESET}{stale_note}")
    print(f"  RFC patches:                       {BOLD}{rfc_count}{RESET}")
    print(f"  Patches with Reviewed-by (ready):  {BOLD}{waiting_count}{RESET}")
    print()


# ----- Main -------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Rank pending LTP patches by review priority."
    )
    parser.add_argument(
        "--diffs",
        action="store_true",
        help="Fetch full diffs for accurate lib/include detection (slower, ~1 req/patch)",
    )
    parser.add_argument(
        "--json", action="store_true", help="Output raw scored JSON instead of markdown"
    )
    parser.add_argument(
        "--no-tags",
        action="store_true",
        help="Ignore Reviewed-by, Acked-by and Signed-off-by tags — surfaces unreviewed patches",
    )
    parser.add_argument(
        "--no-days",
        action="store_true",
        help="Ignore patch age (Rule 3) — rank purely on version, fix signals, and tags",
    )
    parser.add_argument(
        "--min-score",
        type=int,
        default=None,
        metavar="N",
        help="Only show patches with score >= N",
    )
    parser.add_argument(
        "--max",
        type=int,
        default=500,
        metavar="N",
        help="Maximum number of patches to fetch (default: 500)",
    )
    args = parser.parse_args()

    print("Fetching patches from patchwork…", file=sys.stderr)
    raw_patches, counts = fetch_all_patches(max_patches=args.max)

    # Drop cover letters
    raw_patches = [p for p in raw_patches if not is_cover(p.get("name", ""))]

    print(f"Scoring {len(raw_patches)} patches…", file=sys.stderr)
    scored = []
    for i, p in enumerate(raw_patches):
        if args.diffs:
            sys.stderr.write(
                f"\r  [{i + 1}/{len(raw_patches)}] {p.get('name', '')[:60]:<60}"
            )
            sys.stderr.flush()
        scored.append(
            score_patch(
                p,
                fetch_diffs=args.diffs,
                ignore_tags=args.no_tags,
                ignore_days=args.no_days,
            )
        )
    if args.diffs:
        print(file=sys.stderr)

    if args.min_score is not None:
        scored = [p for p in scored if p["score"] >= args.min_score]

    if args.json:
        print(json.dumps(scored, indent=2, default=str))
        return

    print_pretty(scored, counts)


def is_cover(name: str) -> bool:
    return bool(COVER_RE.search(name))


if __name__ == "__main__":
    main()
