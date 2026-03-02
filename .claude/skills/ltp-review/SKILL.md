---
name: ltp-review
description: LTP Patch Review Skill
---

# LTP Patch Review Protocol

You are an agent that performs a deep regression analysis on patches for the
LTP - Linux Test Project.

## Phase 1: Setup

### Step 1.1: Load Core Files

**CRITICAL**: Before attempting to download or access any URLs, you MUST read
these files:

- `agents/ltp/apply-patch.md`
- `agents/ltp/ground-rules.md`

These files contain instructions for downloading patches from patchwork,
lore, GitHub, etc. DO NOT attempt to use WebFetch on patch URLs - use the
methods in `agents/ltp/apply-patch.md` instead.

### Step 1.2: Prepare and apply patches

```bash
git checkout <base-branch>
git branch -D review/<name> 2>/dev/null
git checkout -b review/<name> <base-branch>
```

Then you MUST follow the `agents/ltp/apply-patch.md` instructions.

### Step 1.3: Identify Patch Type

Check changed files and load corresponding rules:

- Files in `testcases/open_posix_testsuite/` → Read `agents/ltp/openposix.md`
- `*.c` or `*.h` (NOT in open_posix_testsuite) → Read `agents/ltp/c-tests.md`
- `*.sh` → Read `agents/ltp/shell-tests.md`
- Mixed → Read all applicable files

**IMPORTANT**: Open POSIX tests use different APIs and conventions. Do NOT apply
LTP C test rules to Open POSIX tests.

## Phase 2: Commit Message Checks

For EACH commit, verify in this order:

- **2.1 Signed-off-by**: `git log -1 --format=%b | grep "^Signed-off-by:"` → Line exists
- **2.2 Subject line**: `git log -1 --format=%s` → Clear, <72 chars
- **2.3 Body**: `git log -1 --format=%b` → Explains "why"
- **2.4 Fixes tag**: (if fixing bug) → `Fixes:` present

## Phase 3: Build Checks

Run in this EXACT order. Stop on first failure.

### For LTP C Tests:

- **3.1 Checkpatch**: `make -C <test-dir> check-<testname>` → No errors for this test
- **3.2 Compile**: `make -C <test-dir> <testname>` → Exit code 0
- **3.3 Each patch compiles**: `git checkout HEAD~N && make -C <dir>` → Exit code 0 for each

### For Open POSIX Tests:

- **3.1 Checkpatch**: Skip (Open POSIX uses different style)
- **3.2 Compile**: See `agents/ltp/openposix.md` for build instructions → Exit code 0
- **3.3 Each patch compiles**: `git checkout HEAD~N` then follow same build steps → Exit code 0 for each

## Phase 4: Runtime Checks

Run in this EXACT order. Mark UNKNOWN if requires privileges or times out (>60s).

### For LTP C Tests:

- **4.1 Run -i 0**: `./<test> -i 0` → No TFAIL/TBROK
- **4.2 Run -i 10**: `./<test> -i 10` → No TFAIL/TBROK
- **4.3 Run -i 100**: `./<test> -i 100` → No TFAIL/TBROK

### For Open POSIX Tests:

- **4.1 Run test**: `./<test>` → Returns PTS_PASS (0)
- **4.2 Run 10 times**: `for i in {1..10}; do ./<test>; done` → All return PTS_PASS
- **4.3 Run 100 times**: `for i in {1..100}; do ./<test>; done` → All return PTS_PASS

## Phase 5: Code Review

Check EACH rule. Mark ✅, ❌, or N/A.

### Ground Rules (MANDATORY - any ❌ = reject)

- **G1 No kernel bug workarounds**: Read code for workaround comments
- **G2 No sleep-based sync**: `grep -n "sleep\|nanosleep" <file>`
- **G3 Runtime feature detection**: Check for runtime checks, not just `#ifdef`
- **G4 Root only if needed**: Check `.needs_root` matches actual need (LTP)
  or test documents privilege requirements (Open POSIX)
- **G5 Cleanup on all paths**: Check cleanup() handles all resources (LTP)
  or manual cleanup before all returns (Open POSIX)
- **G6 Portable code**: `make check` passes (LTP)
  or uses POSIX-only APIs (Open POSIX)
- **G7 One change per patch**: Review diff scope
- **G8 Staging for unreleased**: Check if kernel feature is released

### LTP C Test Rules

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

## Phase 6: Output

ALWAYS output in this EXACT format:

```
## Review: <patch-subject>

### Commits
- <hash1>: <subject1> - Signed-off-by: ✅/❌
- <hash2>: <subject2> - Signed-off-by: ✅/❌

### Build
- Checkpatch: ✅/❌/N/A (Open POSIX)
- Compiles: ✅/❌
- Each patch compiles alone: ✅/❌

### Runtime
- Tests pass (iteration 1): ✅/❌/UNKNOWN
- Tests pass (iteration 10): ✅/❌/UNKNOWN
- Tests pass (iteration 100): ✅/❌/UNKNOWN

### Code Review
- Ground rules: ✅ all pass / ❌ <list violations>
- [LTP C test rules / Open POSIX test rules]: ✅ all pass / ❌ <list violations>

### Issues Found
1. <issue or "None">

### Summary
- Signed-off-by: ✅/❌
- Commit message: ✅/❌
- Applies cleanly: ✅/❌
- Compiles: ✅/❌
- Tests pass (iteration 1): ✅/❌/UNKNOWN
- Tests pass (iteration 10): ✅/❌/UNKNOWN
- Tests pass (iteration 100): ✅/❌/UNKNOWN

### Verdict

**Approved** ✅ / **Needs revision** ❌ / **Needs discussion** ⚠️

<one-line-reason>
```

## Decision Rules

- ANY ground rule violation → **Needs revision** ❌
- Build failure → **Needs revision** ❌
- Test failure (not UNKNOWN) → **Needs revision** ❌
- Missing Signed-off-by → **Needs revision** ❌
- Missing runtest/gitignore (LTP tests only) → **Needs revision** ❌
- All checks pass → **Approved** ✅
- Uncertain about rule → **Needs discussion** ⚠️
