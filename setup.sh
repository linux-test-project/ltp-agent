#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (c) 2026 Andrea Cervesato <andrea.cervesato@suse.com>
#
# Symlink ltp-agent config files into an LTP repo.
#
# Usage:
#   setup.sh [<ltp-dir>]
#
# If <ltp-dir> is omitted, the current directory is used.
#
# Examples:
#   cd /path/to/ltp && setup.sh
#   setup.sh /path/to/ltp

set -e

AGENT_DIR="$(cd "$(dirname "$0")" && pwd)"

die() {
	echo "ERROR: $1" >&2
	exit 1
}

LTP_DIR="${1:-.}"
LTP_DIR="$(cd "$LTP_DIR" && pwd)"

# Verify we are inside an LTP repo
[ -d "$LTP_DIR/.git" ] ||
	die "$LTP_DIR is not a git repository"
[ -d "$LTP_DIR/testcases" ] ||
	die "$LTP_DIR does not look like an LTP repo"
[ -f "$LTP_DIR/include/tst_test.h" ] ||
	die "$LTP_DIR does not look like an LTP repo"

# Create symlinks
for name in .agents AGENTS.md agents; do
	target="$AGENT_DIR/$name"
	link="$LTP_DIR/$name"

	if [ -L "$link" ]; then
		rm "$link"
	elif [ -e "$link" ]; then
		die "$link already exists and is not a symlink"
	fi

	ln -s "$target" "$link"
done

# Agent-specific symlinks
# .claude -> .agents   (Claude Code)
# GEMINI.md -> AGENTS.md (Gemini CLI)
for link_pair in ".claude .agents" "GEMINI.md AGENTS.md"; do
	set -- $link_pair
	link="$LTP_DIR/$1"
	target="$2"

	if [ -L "$link" ]; then
		rm "$link"
	elif [ -e "$link" ]; then
		die "$link already exists and is not a symlink"
	fi

	ln -s "$target" "$link"
done

echo "ltp-agent linked into $LTP_DIR"
