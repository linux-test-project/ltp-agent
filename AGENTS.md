<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Linux Test Project (LTP)

LTP delivers tests to the open source community that validate the
reliability, robustness, and stability of the Linux kernel and related
features. Tests are written in C or portable POSIX shell. The project uses
GNU Autotools for its build system and follows the Linux kernel coding style.

**License**: GPL-2.0-or-later (`SPDX-License-Identifier: GPL-2.0-or-later`)

## Technology Stack

- **Languages**: C (primary), portable POSIX shell
- **Build system**: GNU Autotools (autoconf, automake, make)
- **Compiler**: gcc (clang also supported in CI)
- **Coding style**: Linux kernel coding style
- **Test runner**: kirk (replacing legacy `runltp`)
- **Documentation**: reStructuredText + Sphinx

## Project Structure

- `testcases/` — All test binaries (C and shell)
  - `testcases/kernel/syscalls/` — Syscall and libc wrapper tests
  - `testcases/open_posix_testsuite/` — Open POSIX testsuite fork
  - `testcases/lib/` — Shell test library and shell loader
- `include/` — LTP library headers (`tst_test.h` is the main API)
  - `include/lapi/` — Fallback kernel API definitions for older systems
  - `include/mk/` — Build system include files
- `lib/` — LTP C library source (`tst_*.c` files)
  - `lib/newlib_tests/` — LTP library self-tests
- `runtest/` — Runtest files defining test suites (e.g. `syscalls`, `mm`)
- `scenario_groups/` — Default sets of runtest files
- `doc/` — Sphinx documentation (RST format)
- `scripts/` — Helper scripts
- `ci/` — CI dependency installation scripts
- `.github/workflows/` — GitHub Actions CI workflows
- `tools/` — Release and maintenance tools
- `agents/` — AI agent configuration files

## Environment Setup

### Prerequisites

- git
- autoconf, automake, m4
- make
- gcc
- pkgconf / pkg-config
- libc headers
- linux headers

### Download Source

```sh
git clone --recurse-submodules https://github.com/linux-test-project/ltp.git
cd ltp
```

### Install (default prefix: /opt/ltp)

```sh
make install
```

## Agent Instructions

All agent configuration files are in the `agents/` directory.

### Task: Patch Review

**Trigger**: User requests a review of a patch, commit, branch, PR, or
patchwork/lore URL.

**Action**: Run the `/ltp-review` skill.

### Task: Smoke Test

**Trigger**: User requests a smoke test, build test, or runtime test of a
patch.

**Action**: Run the `/ltp-review-smoke` skill.

### Task: Email Reply

**Trigger**: User requests a mailing list reply or email for a patch review.

**Action**: Run the `/ltp-email-reply` skill.

### Task: Convert Old Test API

**Trigger**: User requests converting a test from old API (`test.h`) to new
API (`tst_test.h`).

**Action**: Run the `/ltp-convert` skill.

### Task: CI Report

**Trigger**: User requests a CI report or GitHub Actions summary for a review.

**Action**: Run the `/ltp-ci-report` skill.

### Task: Write or Modify Open POSIX Tests

**Trigger**: User asks to write, fix, or modify a test in
`testcases/open_posix_testsuite/`.

**Action**: Load `agents/openposix.md` before writing the code.

**Note**: Open POSIX tests use different APIs and conventions than LTP C tests.
Do NOT apply `agents/c-tests.md` rules to Open POSIX tests.

### Task: Write or Modify C Tests

**Trigger**: User asks to write, fix, or modify a C test.

**Action**: Load `agents/c-tests.md` and `agents/ground-rules.md` before
writing code.

### Task: Write or Modify Shell Tests

**Trigger**: User asks to write, fix, or modify a shell test.

**Action**: Load `agents/shell-tests.md` and `agents/ground-rules.md` before
writing code.

### Task: General Questions

**Trigger**: User asks about LTP architecture, APIs, or how to do something.

**Action**: Use the project structure and documentation paths below to find answers.

## Build System

LTP uses a custom GNU Make build system layered on top of autoconf. The
build include files live in `include/mk/`.

### Build LTP from Sources

```sh
make autotools      # generate ./configure from configure.ac
./configure         # probe system, generate include/mk/config.mk and include/config.h
make                # build libltp.a, then all tests
make install        # install to /opt/ltp (default)
```

### Test Makefiles

Every test directory contains a minimal Makefile with two includes:

```make
top_srcdir		?= ../../../..

include $(top_srcdir)/include/mk/testcases.mk

include $(top_srcdir)/include/mk/generic_leaf_target.mk
```

The build system automatically discovers all `.c` files in the directory and
creates one binary per file (e.g. `epoll_wait01.c` → `epoll_wait01`). Each
binary is linked against `-lltp`. No explicit target list is needed.

**Trunk Makefiles** (directories containing only subdirectories) use
`env_pre.mk` + `generic_trunk_target.mk` instead and recurse into
subdirectories automatically.

**Open POSIX testsuite** (`testcases/open_posix_testsuite/`) has its own
independent build system. It does NOT use the LTP include files or link
against `libltp.a`. Leaf-level Makefiles are NOT hand-written — they are
auto-generated by `scripts/generate-makefiles.sh`, which discovers test
sources by naming convention and reads per-directory `CFLAGS`, `LDFLAGS`,
and `LDLIBS` plain-text files. The generated Makefiles are not checked into
git.

### Key Include Files

| File                       | Purpose                                                                        |
|----------------------------|--------------------------------------------------------------------------------|
| `testcases.mk`             | Sets up libltp dependency, `-lltp` linking, install dir                        |
| `generic_leaf_target.mk`   | For directories with source files; provides `all`, `clean`, `install`, `check` |
| `generic_trunk_target.mk`  | For directories with only subdirectories; recurses into them                   |
| `env_pre.mk`               | Sets up paths, includes `config.mk` + `features.mk`                            |
| `env_post.mk`              | Auto-discovers `.c` files, sets up `MAKE_TARGETS`, includes `rules.mk`         |
| `rules.mk`                 | Pattern rules for compilation (`.c` → binary) and `check` targets              |
| `lib.mk`                   | For building static libraries (`.a` files)                                     |

### Building a Single Test

```sh
make -C testcases/kernel/syscalls/epoll_wait epoll_wait01
```

The libltp.a dependency is resolved automatically.

### Running Checks

```sh
# checkpatch on a single test
make -C testcases/kernel/syscalls/epoll_wait check-epoll_wait01

# checkpatch on all tests in a directory
make -C testcases/kernel/syscalls/epoll_wait check
```

This runs `scripts/checkpatch.pl` (coding style) and `tools/sparse/sparse-ltp`
(static analysis) on the source files.

### Common Makefile Variables

Variables set **between** the two includes to customize the build:

| Variable                   | Purpose                                                       |
|----------------------------|---------------------------------------------------------------|
| `MAKE_TARGETS`             | Override auto-detected build targets                          |
| `FILTER_OUT_MAKE_TARGETS`  | Exclude specific targets                                      |
| `FILTER_OUT_DIRS`          | Exclude specific subdirectories                               |
| `INSTALL_TARGETS`          | Extra files to install (scripts, data)                        |
| `LTPLIBS`                  | Internal LTP libraries needed (set **before** `testcases.mk`) |
| `LTPLDLIBS`                | Linker flags for `LTPLIBS` (set **after** `testcases.mk`)     |

Per-target flags can be added as:

```make
epoll_wait02: LDLIBS += -lrt
accept02: CFLAGS += -pthread
```

## Additional Resources

- Documentation: https://linux-test-project.readthedocs.io/
- Source code: https://github.com/linux-test-project/ltp
- Mailing list: https://lore.kernel.org/ltp/
- Patchwork: https://patchwork.ozlabs.org/project/ltp/list/
- Kirk (test runner): https://github.com/linux-test-project/kirk
- Linux kernel coding style: https://www.kernel.org/doc/html/latest/process/coding-style.html

### In-Repository Documentation

- Development guide: `doc/developers/`
- Maintenance guide: `doc/maintenance/`
- User guide: `doc/users/`
- C API reference: `doc/developers/api_c_tests.rst`
- Shell API reference: `doc/developers/api_shell_tests.rst`
- Build system: `doc/developers/build_system.rst`
- Test writing tutorial: `doc/developers/test_case_tutorial.rst`
