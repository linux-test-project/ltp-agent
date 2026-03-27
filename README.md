<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# LTP Agent

AI agent configuration for reviewing, converting, and testing
[Linux Test Project](https://github.com/linux-test-project/ltp) patches.

This repository provides rule files and skills that teach AI coding agents how
to work with the LTP codebase. It is designed to be placed alongside an LTP git
checkout so that the agent can read source files, apply patches, build tests,
and run them.

## Prerequisites

- An AI coding agent that supports `AGENTS.md` and skill files (e.g.
  [Claude Code](https://claude.com/claude-code),
  [Gemini CLI](https://github.com/google-gemini/gemini-cli),
  [OpenCode](https://opencode.ai))
- An LTP git checkout
- Build dependencies for LTP: `git`, `gcc`, `make`, `autoconf`, `automake`,
  `m4`, `pkgconf`, Linux/libc headers
- Optional: `b4` (for fetching patches from lore/patchwork), `gh` (for GitHub
  PRs)

## Setup

1. Clone the LTP source tree:

   ```sh
   git clone --recurse-submodules https://github.com/linux-test-project/ltp.git
   cd ltp
   ```

2. Clone this repository and run the setup script:

   ```sh
   git clone <this-repo-url> ltp-agent
   ./ltp-agent/setup.sh
   ```

   This symlinks the agent configuration (`.agents`, `.claude`, `GEMINI.md`,
   `AGENTS.md`, `agents`) into the LTP tree.

3. Build LTP once so that tests can be compiled:

   ```sh
   make autotools
   ./configure
   make
   ```

4. Start your AI coding agent from the LTP directory.

## Usage

### Applying a Patch

Before running any review or smoke test, apply the patch onto a review branch.
The helper script `ltp-agent/scripts/apply-patch.sh` supports multiple
sources:

```sh
# Patchwork URL
./ltp-agent/scripts/apply-patch.sh https://patchwork.ozlabs.org/project/ltp/patch/<id>/

# Lore URL
./ltp-agent/scripts/apply-patch.sh https://lore.kernel.org/ltp/<message-id>/

# GitHub PR
./ltp-agent/scripts/apply-patch.sh https://github.com/linux-test-project/ltp/pull/42

# Local .patch or .mbox file
./ltp-agent/scripts/apply-patch.sh /tmp/my-patch.mbox

# Existing branch
./ltp-agent/scripts/apply-patch.sh branch:feature-xyz

# Specific commit
./ltp-agent/scripts/apply-patch.sh commit:abc1234
```

### Cleaning Up Review Branches

To delete all `review/*` branches created by `apply-patch.sh`:

```sh
# Interactive — lists branches and asks for confirmation
./ltp-agent/scripts/review-cleanup.sh

# Force — no confirmation prompt
./ltp-agent/scripts/review-cleanup.sh -f
```

### Reviewing a Patch

With the patch applied, invoke the review skill inside your agent:

```
/ltp-review
```

This performs a deep code review against all LTP rules (ground rules, C test
rules, shell test rules, or Open POSIX rules depending on the files changed).

### Smoke Testing a Patch

After applying a patch, run:

```
/ltp-review-smoke
```

This compiles the changed tests, runs them with increasing iteration counts
(`-i 0`, `-i 10`, `-i 100`), and analyzes any build or runtime failures.

### Generating a Mailing List Reply

After running `/ltp-review` (and optionally `/ltp-review-smoke`), generate a
ready-to-send email reply:

```
/ltp-email-reply
```

This produces a plain-text inline review in Linux kernel mailing list style.

### Converting Old Tests to New API

To convert a test from the legacy `test.h` API to the modern `tst_test.h` API:

```
/ltp-convert
```

The agent will analyze the old test, show a conversion plan, rewrite it using
the new API, build and run the converted test, then self-review the result.

### Asking General Questions

You can ask the agent about LTP architecture, APIs, or conventions directly.
The instructions in `AGENTS.md` guide it to load the appropriate rule files and
use project documentation to answer.

## Rule Files

The `agents/` directory contains rule files that the agent loads on demand
based on the task:

- **ground-rules.md** — Mandatory rules for all LTP code: no kernel bug
  workarounds, no sleep-based synchronization, runtime feature detection,
  minimal root usage, cleanup on all paths, portable code, one change per
  patch, staging prefix for unreleased features.

- **c-tests.md** — Rules for LTP C tests: required structure, API usage
  (`SAFE_*` macros, `TST_EXP_*` result macros), file organization, resource
  management, test parametrization, architecture guards, compile-time feature
  guards, child process handling.

- **shell-tests.md** — Rules for LTP shell tests: required block order,
  POSIX shell portability, env block JSON format.

- **openposix.md** — Rules for the Open POSIX Test Suite: different structure
  from LTP tests (`main()`, `posixtest.h`, `PTS_*` return codes), separate
  build system.

## Additional Resources

- LTP documentation: https://linux-test-project.readthedocs.io/
- LTP source code: https://github.com/linux-test-project/ltp
- LTP mailing list: https://lore.kernel.org/ltp/
- Patchwork: https://patchwork.ozlabs.org/project/ltp/list/
- Kirk test runner: https://github.com/linux-test-project/kirk

## License

This project is licensed under the GNU General Public License v2.0 or later.
See [COPYING](COPYING) for the full license text.
