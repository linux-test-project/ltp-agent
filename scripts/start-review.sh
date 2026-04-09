#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Andrea Cervesato <andrea.cervesato@suse.com>
#
# Clone the LTP repo, apply a patch, and run an AI review with email reply.
# Supports Gemini CLI, Claude Code and OpenCode as the review agent.
# By default only the email reply body is printed to stdout.
#
# Usage:
#   start-review.sh [-d <dir>] [-c] [-v] [-i] [-a claude|opencode|gemini] <source>
#
# Options:
#   -d <dir>           Clone into <dir> instead of /tmp/ltp-<id>
#   -c                 Clean up (delete) the clone when finished
#   -v                 Verbose: show all output (clone, apply, review, email reply)
#   -i                 Interactive: open agent in the clone dir after review
#                      (allows claude --resume to work later)
#   -a claude|opencode|gemini Choose the AI agent (default: auto-detect)
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
INTERACTIVE=0
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

while getopts "d:cvia:h" opt; do
	case "$opt" in
	d) CLONE_DIR="$OPTARG" ;;
	c) CLEANUP=1 ;;
	v) VERBOSE=1 ;;
	i) INTERACTIVE=1 ;;
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
	if command -v gemini >/dev/null 2>&1; then
		AGENT="gemini"
	elif command -v claude >/dev/null 2>&1; then
		AGENT="claude"
	elif command -v opencode >/dev/null 2>&1; then
		AGENT="opencode"
	else
		die "no AI agent found: install gemini, claude or opencode"
	fi
fi

case "$AGENT" in
gemini)
	command -v gemini >/dev/null 2>&1 || die "gemini CLI is required"
	;;
claude)
	command -v claude >/dev/null 2>&1 || die "claude CLI is required"
	;;
opencode)
	command -v opencode >/dev/null 2>&1 || die "opencode CLI is required"
	;;
*)
	die "unsupported agent: $AGENT (use 'claude', 'opencode' or 'gemini')"
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
if [ "$VERBOSE" -eq 1 ]; then
	"$SCRIPT_DIR/../setup.sh" "$CLONE_DIR" >&2
else
	"$SCRIPT_DIR/../setup.sh" "$CLONE_DIR" >/dev/null
fi

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

PROMPT_VERBOSE="Run /ltp-review and print the full review output \
to the user. Then run /ltp-email-reply and print the full email \
reply output to the user. You MUST print both outputs as text."
PROMPT_QUIET="Run /ltp-review, then run /ltp-email-reply and show only the email reply body"

if [ "$VERBOSE" -eq 1 ]; then
	PROMPT="$PROMPT_VERBOSE"
else
	PROMPT="$PROMPT_QUIET"
fi

case "$AGENT" in
gemini)
	if [ "$INTERACTIVE" -eq 1 ]; then
		gemini -i "$PROMPT"
	elif [ "$VERBOSE" -eq 1 ]; then
		gemini -p "$PROMPT"
	else
		gemini -p "$PROMPT" 2>/dev/null
	fi
	;;
claude)
	if [ "$INTERACTIVE" -eq 1 ]; then
		claude "$PROMPT" \
			--allowedTools "Bash(git:*)" \
			"Bash(grep:*)" "Read"
	elif [ "$VERBOSE" -eq 1 ]; then
		claude -p "$PROMPT" \
			--allowedTools "Bash(git:*)" \
			"Bash(grep:*)" "Read"
	else
		claude -p "$PROMPT" \
			--allowedTools "Bash(git:*)" \
			"Bash(grep:*)" "Read" 2>/dev/null
	fi
	;;
opencode)
	if [ "$INTERACTIVE" -eq 1 ]; then
		opencode "$PROMPT"
	elif [ "$VERBOSE" -eq 1 ]; then
		opencode run "$PROMPT"
	else
		opencode run "$PROMPT" 2>/dev/null
	fi
	;;
esac
