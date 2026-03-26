#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Andrea Cervesato <andrea.cervesato@suse.com>
#
# Clone the LTP repo, apply a patch, and run a Claude review with email reply.
# By default only the email reply body is printed to stdout.
#
# Usage:
#   start-review.sh [-d <dir>] [-c] [-v] <source>
#
# Options:
#   -d <dir>   Clone into <dir> instead of /tmp/ltp-<id>
#   -c         Clean up (delete) the clone when finished
#   -v         Verbose: show all output (clone, apply, review, email reply)
#
# The <source> argument is anything accepted by apply-patch.sh:
#   <patchwork-url>    https://patchwork.ozlabs.org/project/ltp/patch/...
#   <lore-url>         https://lore.kernel.org/...
#   <github-pr>        https://github.com/<owner>/<repo>/pull/<number>
#   <local-file>       /path/to/patch.mbox
#   <branch>           branch:<name>
#   <commit>           commit:<hash>
#
# Examples:
#   start-review.sh https://patchwork.ozlabs.org/project/ltp/patch/abc123/
#   start-review.sh -v -c https://lore.kernel.org/r/abc123/
#   start-review.sh -d ~/reviews/my-patch /tmp/my-patch.mbox

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LTP_UPSTREAM="git@github.com:linux-test-project/ltp.git"
CLONE_DIR=""
CLEANUP=0
VERBOSE=0

die() {
	echo "ERROR: $1" >&2
	exit 1
}

usage() {
	sed -n '2,/^$/s/^# \?//p' "$0"
	exit 0
}

# Print to stderr only in verbose mode
log() {
	if [ "$VERBOSE" -eq 1 ]; then
		echo "$@" >&2
	fi
}

while getopts "d:cvh" opt; do
	case "$opt" in
		d) CLONE_DIR="$OPTARG" ;;
		c) CLEANUP=1 ;;
		v) VERBOSE=1 ;;
		h) usage ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))

[ $# -eq 0 ] && usage

SOURCE="$1"

command -v git >/dev/null 2>&1 || die "git is required"
command -v claude >/dev/null 2>&1 || die "claude CLI is required"

if [ -z "$CLONE_DIR" ]; then
	CLONE_DIR="/tmp/ltp-$(date +%s)-$$"
fi

# ── Clone ────────────────────────────────────────────────────────────────────
log "Cloning LTP into $CLONE_DIR ..."

if [ "$VERBOSE" -eq 1 ]; then
	git clone --depth 1 "$LTP_UPSTREAM" "$CLONE_DIR" >&2
else
	git clone --depth 1 --quiet "$LTP_UPSTREAM" "$CLONE_DIR" 2>/dev/null
fi

if [ "$CLEANUP" -eq 1 ]; then
	trap 'echo "Cleaning up $CLONE_DIR" >&2; rm -rf "$CLONE_DIR"' EXIT
fi

cd "$CLONE_DIR"

# Symlink ltp-agent config into the clone
ln -s "$SCRIPT_DIR/../.agents" .agents
ln -s "$SCRIPT_DIR/../AGENTS.md" AGENTS.md
ln -s "$SCRIPT_DIR/../agents" agents
ln -s .agents .claude

# ── Apply patch ──────────────────────────────────────────────────────────────
log "Applying patch: $SOURCE"

if [ "$VERBOSE" -eq 1 ]; then
	"$SCRIPT_DIR/apply-patch.sh" "$SOURCE" >&2
else
	"$SCRIPT_DIR/apply-patch.sh" "$SOURCE" >/dev/null 2>&1
fi

# ── Review ───────────────────────────────────────────────────────────────────
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
COMMITS="$(git rev-list --count master..HEAD)"

log ""
log "Branch:  $BRANCH"
log "Commits: $COMMITS"
log "Workdir: $CLONE_DIR"
log ""
log "Running Claude review ..."
log ""

if [ "$VERBOSE" -eq 1 ]; then
	claude -p "Run /ltp-review and show the results, then run /ltp-email-reply and show the results" \
		--allowedTools "Bash(git:*)" "Bash(grep:*)" "Read"
else
	claude -p "Run /ltp-review, then run /ltp-email-reply and show only the email reply body" \
		--allowedTools "Bash(git:*)" "Bash(grep:*)" "Read" 2>/dev/null
fi
