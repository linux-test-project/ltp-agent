# C Test Rules

This file contains MANDATORY rules for C tests. Load this file when reviewing
or writing any patch that modifies `*.c` or `*.h` files.

## Required Test Structure

Every C test MUST follow this structure:

```c
// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Copyright (c) YYYY Author Name <email@example.org>
 */

/*\
 * High-level RST-formatted test description goes here.
 * Explain _what_ is being tested (exported to docs).
 *
 * The following part is OPTIONAL:
 * [Algorithm]
 *
 * Explaination of how algorithm in the test works in a list (-) syntax.
 */

#include "tst_test.h"

static void run(void)
{
    tst_res(TPASS, "Test passed");
}

static struct tst_test test = {
    .test_all = run,
};
```

## Checklist

When reviewing or writing C tests, verify ALL of the following:

### 1. Coding Style

- Code MUST follow Linux kernel coding style
- `make check` or `make check-$TCID` MUST pass (uses vendored `checkpatch.pl`)
- C tests must be written in C99 (or later C standard)

### 2. API Usage

- MUST use new API (`tst_test.h`), NOT old API (`test.h`)
- MUST NOT define `main()` (unless `TST_NO_DEFAULT_MAIN` is used)
- MUST use `struct tst_test` for configuration
- Handlers MUST be thin; logic goes in `.setup` and `.cleanup` callbacks

### 3. Syscall Usage

- Syscall usage MUST match man pages and kernel code

### 4. File Organization

- New test binary MUST be added to corresponding `.gitignore`
- Datafiles go in `datafiles/` subdirectory (installed to `testcases/data/$TCID`)
- Syscall tests go under `testcases/kernel/syscalls/`
- Entry MUST exist in appropriate `runtest/` file
- Sub-executables MUST use `$TESTNAME_` prefix
- MUST use `.needs_tmpdir = 1` for temp files (work in current directory)

### 5. Result Reporting

- MUST use `tst_res()` for results: `TPASS`, `TFAIL`, `TCONF`, `TBROK`, `TINFO`
- MUST use `tst_brk()` for fatal errors that abort the test
- MUST use `TEST()` macro to capture return value (`TST_RET`) and errno (`TST_ERR`)
- MUST return `TCONF` (not `TFAIL`) when feature is unavailable

### 6. Safe Macros

- MUST use `SAFE_*` macros for system calls that must not fail
- Safe macros are defined in `include/` directory

### 7. Kernel Version Handling

- MUST use `.min_kver` for kernel version gating
- MUST prefer runtime checks over compile-time checks

### 8. Tagging

- Regression tests MUST include `.tags` in `struct tst_test`

### 9. Cleanup

- Cleanup MUST run on ALL exit paths
- MUST unmount, restore sysctls, delete temp files, kill processes

### 10. Static Variables

- Static variables MUST be initialized before use in test logic (for `-i` option)
- Static allocated variables MUST be released in cleanup if allocated in setup

### 11. Memory Allocation

- Memory MUST be correctly deallocated
- EXCEPTION: If `.bufs` is used, ignore check for memory allocated with it

### 12. String Handling

- MUST use `snprintf()` when combining strings

### 13. Deprecated Features

- MUST NOT define `[Description]` in the test description section

## Code Examples

The following sections contain examples which are considered reference when
rewriting old LTP tests or when writing new LTP tests.

ALWAYS follow these rules.

### LTP API usage

#### Use the correct import

```c
/* WRONG: this is importing legacy API */
#include "test.h"

/* CORRECT: use new LTP API*/
#include "tst_test.h"
```

#### Use SAFE\_\* macros

ALWAYS verify that syscalls we are using have a `SAFE_*` version associated
with it. If it exists, use it. If it doesn't, verify if you can create it.

```c
/* WRONG: don't use plain syscalls */
int fd = open("test_file", O_RDWR | O_CREAT, 0644);
if (fd > 0) {
    tst_brk(TBROK | TERRNO, "open() error");
}

/* CORRECT: use SAFE_* macros instead */
int fd = SAFE_OPEN("test_file", O_RDWR | O_CREAT, 0644);
```

### New SAFE\_\* macros definition

#### Don't use `cleanup_fn` in newly added `safe_*` definitions

```c
/* WRONG: cleanup_fn is used in the legacy LTP API */
void *safe_mysyscall(const char *file, const int lineno, void (*cleanup_fn) (void),
        size_t size)
{
    void *rval;

    rval = mysyscall(size);

    if (rval == NULL) {
        /* WRONG: tst_brkm_ is used by the legacy API */
        tst_brkm_(file, lineno, TBROK | TERRNO, cleanup_fn,
            "mysyscall(%zu) failed", size);
    }

    return rval;
}

/* CORRECT: use the new LTP API format */
void *safe_mysyscall(const char *file, const int lineno,
        size_t size)
{
    void *rval;

    rval = mysyscall(size);

    if (rval == NULL) {
        /* CORRECT: tst_brk_ is used by the new API */
        tst_brk_(file, lineno, TBROK | TERRNO,
            "mysyscall(%zu) failed", size);
    }

    return rval;
}
```

### Temporary folder

NEVER create files in the currently local folder:

```c
static int fd = -1;

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    /* WRONG: missing `.needs_tmpdir = 1` */
};
```

ALWAYS create files in the temporary folder:

```c
static int fd = -1;

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    /* CORRECT: create files in the temporary folder */
    .needs_tmpdir = 1,
};
```

### File descriptors

#### Initialization

NEVER initialize file descriptors to valid values:

```c
/* WRONG: zero value file descriptor is a valid value (stdin) */
static int fd;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```

ALWAYS set file descriptors to an invalid value:

```c
/* CORRECT: initialize file descriptor to an invalid value */
static int fd = -1;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static void cleanup(void) {
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```

#### Close open file descriptors

NEVER leave test without closing open file descriptors:

```c
static int fd = -1;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

static struct tst_test test = {
    .setup = setup,
    /* WRONG: missing .cleanup */
    .test_all = run,
    .needs_tmpdir = 1,
};
```

ALWAYS close file descriptors at cleanup:

```c
static int fd = -1;

static void run(void) {
    /* here we use fd */
}

static void setup(void) {
    fd = SAFE_OPEN("myfile", O_RDWR | O_CREAT, 0777);
}

/* CORRECT: close file descriptors at cleanup */
static void cleanup(void) {
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static struct tst_test test = {
    .setup = setup,
    .cleanup = cleanup,
    .test_all = run,
    .needs_tmpdir = 1,
};
```
