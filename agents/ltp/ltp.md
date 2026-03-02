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
- `agents/ltp/` — AI agent configuration files

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

### Build from Source

```sh
make autotools
./configure
make
```

### Install (default prefix: /opt/ltp)

```sh
make install
```

## Agent Instructions

All agent configuration files are in the `agents/ltp` directory.

### Task: Patch Review

**Trigger**: User requests a review of a patch, commit, branch, PR, or
patchwork/lore URL.

**Action**: Load the `review` skill via `skill({ name: "ltp-review" })`.

### Task: Write or Modify Open POSIX Tests

**Trigger**: User asks to write, fix, or modify a test in
`testcases/open_posix_testsuite/`.

**Action**: Load `agents/ltp/openposix.md` before writing the code.

**Note**: Open POSIX tests use different APIs and conventions than LTP C tests.
Do NOT apply `agents/ltp/c-tests.md` rules to Open POSIX tests.

### Task: Write or Modify C Tests

**Trigger**: User asks to write, fix, or modify a C test.

**Action**: Load `agents/ltp/c-tests.md` and `agents/ltp/ground-rules.md` before
writing code.

### Task: Write or Modify Shell Tests

**Trigger**: User asks to write, fix, or modify a shell test.

**Action**: Load `agents/ltp/shell-tests.md` and `agents/ltp/ground-rules.md` before
writing code.

### Task: General Questions

**Trigger**: User asks about LTP architecture, APIs, or how to do something.

**Action**: Use the project structure and documentation paths below to find answers.

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
