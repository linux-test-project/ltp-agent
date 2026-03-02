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

### CORRECT: New API

```c
#include <stdlib.h>
#include "tst_test.h"

static int fd;

static void setup(void)
{
    fd = SAFE_OPEN("test_file", O_RDWR | O_CREAT, 0644);
}

static void cleanup(void)
{
    if (fd > 0)
        SAFE_CLOSE(fd);
}

static void run(void)
{
    SAFE_WRITE(SAFE_WRITE_ALL, fd, "a", 1);
    tst_res(TPASS, "write() succeeded");
}

static struct tst_test test = {
    .test_all = run,
    .setup = setup,
    .cleanup = cleanup,
    .needs_tmpdir = 1,
    .needs_root = 1,
};

```

### INCORRECT: Legacy/Unsafe

```c
/* WRONG: old header */
#include "test.h"

/* WRONG: defining main */
int main(void)
{
    /* WRONG: unsafe call, hardcoded path */
    int fd = open("/tmp/file", O_RDWR);

    if (fd < 0) {
        /* WRONG: use tst_res or SAFE macro */
        perror("open");
        exit(1);
    }

    /* WRONG: old print function */
    tst_resm(TPASS, "test passed");
    tst_exit();
}
```
