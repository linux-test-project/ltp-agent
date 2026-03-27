#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Andrea Cervesato <andrea.cervesato@suse.com>
#
# Clone the LTP repo, apply a patch, and run an AI review with email reply.
# Supports both Claude Code and OpenCode as the review agent.
# By default only the email reply body is printed to stdout.
#
# Usage:
#   start-review.sh [-d <dir>] [-c] [-v] [-a claude|opencode] <source>
#
# Options:
#   -d <dir>           Clone into <dir> instead of /tmp/ltp-<id>
#   -c                 Clean up (delete) the clone when finished
#   -v                 Verbose: show all output (clone, apply, review, email reply)
#   -a claude|opencode Choose the AI agent (default: auto-detect)
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
AGENT=""

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

while getopts "d:cva:h" opt; do
	case "$opt" in
		d) CLONE_DIR="$OPTARG" ;;
		c) CLEANUP=1 ;;
		v) VERBOSE=1 ;;
		a) AGENT="$OPTARG" ;;
		h) usage ;;
		*) usage ;;
	esac
done
shift $((OPTIND - 1))

[ $# -eq 0 ] && usage

SOURCE="$1"

command -v git >/dev/null 2>&1 || die "git is required"

# Auto-detect agent if not specified
if [ -z "$AGENT" ]; then
	if command -v claude >/dev/null 2>&1; then
		AGENT="claude"
	elif command -v opencode >/dev/null 2>&1; then
		AGENT="opencode"
	else
		die "no AI agent found: install claude or opencode"
	fi
fi

case "$AGENT" in
	claude)
		command -v claude >/dev/null 2>&1 || die "claude CLI is required"
		;;
	opencode)
		command -v opencode >/dev/null 2>&1 || die "opencode CLI is required"
		;;
	*)
		die "unsupported agent: $AGENT (use 'claude' or 'opencode')"
		;;
esac

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
log "Running review with $AGENT ..."
log ""

PROMPT_VERBOSE="Run /ltp-review and show the results, then run /ltp-email-reply and show the results"
PROMPT_QUIET="Run /ltp-review, then run /ltp-email-reply and show only the email reply body"

if [ "$VERBOSE" -eq 1 ]; then
	PROMPT="$PROMPT_VERBOSE"
else
	PROMPT="$PROMPT_QUIET"
fi

case "$AGENT" in
	claude)
		if [ "$VERBOSE" -eq 1 ]; then
			claude -p "$PROMPT" \
				--allowedTools "Bash(git:*)" "Bash(grep:*)" "Read"
		else
			claude -p "$PROMPT" \
				--allowedTools "Bash(git:*)" "Bash(grep:*)" "Read" 2>/dev/null
		fi
		;;
	opencode)
		# opencode permissions are set in ~/.config/opencode/opencode.json;
		# bash and read must be allowed for non-interactive use.
		if [ "$VERBOSE" -eq 1 ]; then
			opencode run "$PROMPT"
		else
			opencode run "$PROMPT" 2>/dev/null
		fi
		;;
esac
