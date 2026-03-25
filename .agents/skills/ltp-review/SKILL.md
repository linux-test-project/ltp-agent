---
name: ltp-review
description: LTP Patch Review Skill
---

<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# LTP Patch Review Protocol

You are an agent that performs a deep code review on patches for the
LTP - Linux Test Project.

Commit message checks, checkpatch, checkbashisms, compilation, and runtime
tests are handled by CI (`ci/tools/patch-precheck.sh` and the ci-docker-build
matrix). Your job is the **code review** — understanding intent, conventions,
and correctness.

## Phase 1: Setup

### Step 1.1: Load Rules

Read `agents/ground-rules.md`.

### Step 1.2: Verify patches are applied

Run `git rev-list --count master..HEAD`. If the count is 0 (no commits ahead
of master), or the current branch IS master, **stop immediately** and tell the
user:

> No patches found. Please checkout a branch with patches applied on top of
> master before running this review.

Do NOT proceed with the review.

### Step 1.3: Identify Changed Files and Patch Type

The current branch already has the patches applied (master..HEAD).
Use `git diff --name-only master..HEAD` to list changed files, then load
corresponding rules:

- Files in `testcases/open_posix_testsuite/` → Read `agents/openposix.md`
- `*.c` or `*.h` (NOT in open_posix_testsuite) → Read `agents/c-tests.md`
- `*.sh` → Read `agents/shell-tests.md`
- Mixed → Read all applicable files

**IMPORTANT**: Open POSIX tests use different APIs and conventions. Do NOT apply
LTP C test rules to Open POSIX tests.

**IMPORTANT**: `agents/c-tests.md` is the single source of truth for LTP C
test rules. The checklist below is a structural guide only — when `c-tests.md`
and the inline checklist conflict, `c-tests.md` wins.

## Phase 2: Commit Message Review

For EACH commit (`git log master..HEAD`), review the message quality:

- **M1 Subject is clear**: Describes WHAT changed concisely
- **M2 Body explains WHY**: Not just what, but the motivation for the change
- **M3 One logical change**: Each commit is a single, self-contained change
- **M4 Fixes tag**: If fixing a bug, `Fixes:` tag is present

CI already checks the mechanical parts (Signed-off-by presence, subject length).
Your job is to judge whether the message is **clear and informative**.

## Phase 3: Code Review

Read the full changed files (not just the diff) and check EACH rule.
Mark ✅, ❌, or N/A.

### Ground Rules (MANDATORY - any ❌ = reject)

- **G1 No kernel bug workarounds**: Read code for workaround comments
- **G2 No sleep-based sync**: `grep -n "sleep\|nanosleep" <file>`
- **G3 Runtime feature detection**: Check for runtime checks, not just `#ifdef`
- **G4 Root only if needed**: Check `.needs_root` matches actual need (LTP)
  or test documents privilege requirements (Open POSIX)
- **G5 Cleanup on all paths**: Check cleanup() handles all resources (LTP)
  or manual cleanup before all returns (Open POSIX)
- **G6 Portable code**: Uses POSIX-only APIs (Open POSIX) or portable constructs (LTP)
- **G7 One change per patch**: Review diff scope
- **G8 Staging for unreleased**: Check if kernel feature is released

### LTP C Test Rules

Apply ALL rules from `agents/c-tests.md` (already loaded in Step 1.3).
Do not rely on memory or prior knowledge — use the live file content.

Key structural checks (verify these explicitly):

- **C1 SPDX header**: First line is `// SPDX-License-Identifier: GPL-2.0-or-later`
- **C2 Copyright**: Second block has `Copyright`
- **C3 Doc comment**: `/*\` block exists with description
- **C4 Uses tst_test.h**: `grep "tst_test.h" <file>`
- **C5 No main()**: `grep "^int main\|^void main" <file>` returns empty
- **C6 struct tst_test**: `grep "struct tst_test test" <file>`
- **C7 .gitignore entry**: `grep <testname> <dir>/.gitignore`
- **C8 runtest entry**: `grep <testname> runtest/*`
- **C9 SAFE\_\* macros**: No raw syscalls that should use SAFE\_\*
- **C10 Static vars reset**: Static vars in run() are reset or set in setup()
- **C11 Result reporting**: Uses tst_res()/tst_brk() correctly
- **C12 TCONF for unsupported**: Feature unavailable → TCONF, not TFAIL

For code patterns (string handling, memory allocation, fd init, PATH_MAX,
parametrization, child processes, etc.) apply the examples from
`agents/c-tests.md` directly — those examples are the authoritative
WRONG/CORRECT reference.

### LTP Shell Test Rules

Apply ALL rules from `agents/shell-tests.md` (already loaded in Step 1.3).
Do not rely on memory or prior knowledge — use the live file content.

Key structural checks (verify these explicitly):

- **S1 Shebang**: First line is exactly `#!/bin/sh`
- **S2 SPDX header**: `# SPDX-License-Identifier: GPL-2.0-or-later`
- **S3 Copyright**: Copyright line with year and author
- **S4 Doc block**: `# --- doc` block present with RST description
- **S5 Env block**: `# --- env` block present (even if empty `{}`)
- **S6 Variable assignments before loader**: `TST_SETUP`/`TST_CLEANUP` set BEFORE `. tst_loader.sh`
- **S7 Loader sourced**: `. tst_loader.sh` present, AFTER variables, BEFORE functions
- **S8 Functions after loader**: `setup()`/`cleanup()`/`tst_test()` defined AFTER loader
- **S9 Runner last**: `. tst_run.sh` is the LAST line, nothing after it
- **S10 POSIX shell only**: No bash-isms (`[[ ]]`, arrays, `function` keyword, process substitution)
- **S11 Quoted expansions**: All variable expansions are quoted
- **S12 Result reporting**: Uses `tst_res` and `tst_brk` for reporting

### Open POSIX Test Rules

- **P1 GPL header**: Has GPL license header with copyright
- **P2 Author line**: Has `Created by:` line with author email
- **P3 Test description**: Comment block describes what is tested
- **P4 Steps section**: Includes "Steps:" section listing procedure
- **P5 Uses posixtest.h**: `grep "posixtest.h" <file>`
- **P6 Has main()**: `grep "^int main" <file>` returns match
- **P7 Return codes**: Uses PTS_PASS, PTS_FAIL, PTS_UNRESOLVED, PTS_UNSUPPORTED
- **P8 Status messages**: Prints status message before each return
- **P9 Error checking**: Checks return values of all POSIX functions
- **P10 Resource cleanup**: Cleans up all resources before returning
- **P11 Portable POSIX**: Uses only POSIX APIs (unless testing Linux-specific behavior)

## Phase 4: Output

ALWAYS output in this EXACT format:

```
## Review: <patch-subject>

### Commit Messages
- <hash>: <subject> — ✅ / ❌ <issue>

### Code Review
- Ground rules: ✅ all pass / ❌ <list violations>
- [LTP C test rules / LTP shell test rules / Open POSIX test rules]: ✅ all pass / ❌ <list violations>

### Issues Found
1. <issue or "None">

### Verdict

**Approved** ✅ / **Needs revision** ❌ / **Needs discussion** ⚠️

<one-line-reason>
```

## Decision Rules

- ANY ground rule violation → **Needs revision** ❌
- Missing runtest/gitignore (LTP tests only) → **Needs revision** ❌
- Unclear or missing commit message body → **Needs revision** ❌
- All checks pass → **Approved** ✅
- Uncertain about rule → **Needs discussion** ⚠️
