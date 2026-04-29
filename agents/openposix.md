<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Open POSIX Test Suite Rules

This file contains MANDATORY rules for Open POSIX Test Suite tests located in
`testcases/open_posix_testsuite/`. Load this file when writing or modifying
any test in this directory.

## Overview

The Open POSIX Test Suite is a fork of the POSIX Test Suite that validates
POSIX API compliance. Tests are organized by:

- `conformance/` — POSIX conformance tests
- `functional/` — Functional tests
- `stress/` — Stress tests

Most of the header files included by the tests can be found in
`testcases/open_posix_testsuite/include`.

## Building Open POSIX Tests

Open POSIX tests have a specific build system that differs from LTP C tests.

### Building a Single Test

To compile a specific Open POSIX test that has been modified:

```sh
# navigate into the test's directory
cd testcases/open_posix_testsuite/<test parent folder>/<syscall name>
# build the test
make <syscall name>_<test name>.run-test
```

**Example**: To build `conformance/interfaces/aio_cancel/3-1.c`:

```sh
cd testcases/open_posix_testsuite/conformance/interfaces/aio_cancel
make aio_cancel_3-1.run-test
```

### Building All Tests

From the `testcases/open_posix_testsuite/` directory:

```sh
./configure
make
```

### Rule: Always execute Open POSIX tests from their directory

- Open POSIX tests must be run from their specific directory due to their build
  system requirements

### Important Notes

- **DO NOT** run `make` from the top-level LTP directory to build Open POSIX tests
- **DO NOT** run `make <test name>` in the test folder to build Open POSIX tests

## Required Test Structure

Every Open POSIX test MUST follow this structure:

```c
/*
 * Copyright (c) YYYY, Organization. All rights reserved.
 * Created by:  author.name REMOVE-THIS AT domain DOT com
 * This file is licensed under the GPL license.  For the full content
 * of this license, see the COPYING file at the top level of this
 * source tree.
 */

/*
 * Test that function_name() does something specific.
 *
 * Steps:
 * 1. Step one description
 * 2. Step two description
 * 3. Expected result
 */

#include <stdio.h>
#include "posixtest.h"

int test_main(int argc PTS_ATTRIBUTE_UNUSED, char **argv PTS_ATTRIBUTE_UNUSED)
{
    /* Test implementation */

    printf("Test PASSED\n");
    return PTS_PASS;
}
```

## Checklist

When writing or modifying Open POSIX tests, verify ALL of the following:

### 1. Coding Style

- Code MUST follow Linux kernel coding style
- Tests are written in C99 (or later C standard)
- Use tabs for indentation, not spaces
- Function opening braces go on a new line (K&R style for functions)

### 2. Header and License

- MUST include GPL license header with copyright notice
- Copyright format: `Copyright (c) YYYY, Organization. All rights reserved.`
- Author format: `Created by:  name REMOVE-THIS AT domain DOT com`
- License reference: `This file is licensed under the GPL license...`

### 3. Test Description

- MUST include a comment block describing what the test does
- Format: `Test that function_name() [behavior]`
- Include a "Steps:" section listing test procedure
- Be specific about what is being tested

### 4. API Usage

- MUST include `posixtest.h`
- MUST define `test_main()` as the test entry point (**NOT** `main()`)
  - The real `main()` is provided by `lib/common.c` and calls `test_main()`
  - Signature: `int test_main(int argc PTS_ATTRIBUTE_UNUSED, char **argv PTS_ATTRIBUTE_UNUSED)`
  - Use `PTS_ATTRIBUTE_UNUSED` to suppress warnings on unused parameters
- MUST use PTS return codes:
  - `PTS_PASS` (0) — Test passed
  - `PTS_FAIL` (1) — Test failed
  - `PTS_UNRESOLVED` (2) — Test encountered unexpected error
  - `PTS_UNSUPPORTED` (4) — Feature not supported
  - `PTS_UNTESTED` (5) — Test not implemented
- Use standard POSIX APIs (pthread, semaphore, signals, timers, etc.)

### 5. Result Reporting

- MUST print status message before returning
- Pass: `printf("Test PASSED\n");` before `return PTS_PASS;`
- Fail: `printf("Test FAILED: [reason]\n");` before `return PTS_FAIL;`
- Unresolved: `fprintf(stderr, "[function](): %s\n", strerror(errno));` before `return PTS_UNRESOLVED;`
- Unsupported: `printf("Test UNSUPPORTED: [reason]\n");` before `return PTS_UNSUPPORTED;`

### 6. Error Handling

- Check return values of all POSIX functions
- Return `PTS_UNRESOLVED` for unexpected errors (setup failures)
- Return `PTS_FAIL` only when the tested behavior is incorrect
- Use `strerror()` to print error descriptions for debugging

### 7. Resource Cleanup

- Clean up ALL resources before returning (threads, mutexes, files, etc.)
- Cleanup MUST happen on all exit paths
- Use pthread_join() to wait for threads
- Destroy mutexes, condition variables, barriers, semaphores
- Close file descriptors
- Unlink temporary files

### 8. Test Naming and Organization

- Test files named: `[N]-[M].c` where N is assertion/requirement number, M is variant
- Example: `1-1.c`, `1-2.c`, `2-1.c`
- Tests organized in directories by function name: `conformance/interfaces/pthread_create/`
- Each test should verify ONE specific assertion or requirement

### 9. Global Variables

- Minimize use of global variables
- Use `static` for global variables that don't need external linkage
- Document why globals are necessary (typically for signal handlers or thread communication)

## Code Examples

### CORRECT: Open POSIX Test

```c
/*
 * Copyright (c) 2002, Intel Corporation. All rights reserved.
 * Created by:  julie.n.fleischer REMOVE-THIS AT intel DOT com
 * This file is licensed under the GPL license.  For the full content
 * of this license, see the COPYING file at the top level of this
 * source tree.
 */

/*
 * Test that pthread_mutex_lock() locks a mutex.
 *
 * Steps:
 * 1. Create and initialize a mutex
 * 2. Lock the mutex
 * 3. Verify the mutex is locked
 * 4. Unlock and destroy the mutex
 */

#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include "posixtest.h"

int test_main(int argc PTS_ATTRIBUTE_UNUSED, char **argv PTS_ATTRIBUTE_UNUSED)
{
    pthread_mutex_t mutex;
    int ret;

    ret = pthread_mutex_init(&mutex, NULL);
    if (ret != 0) {
        fprintf(stderr, "pthread_mutex_init(): %s\n", strerror(ret));
        return PTS_UNRESOLVED;
    }

    ret = pthread_mutex_lock(&mutex);
    if (ret != 0) {
        fprintf(stderr, "pthread_mutex_lock(): %s\n", strerror(ret));
        pthread_mutex_destroy(&mutex);
        return PTS_FAIL;
    }

    ret = pthread_mutex_unlock(&mutex);
    if (ret != 0) {
        fprintf(stderr, "pthread_mutex_unlock(): %s\n", strerror(ret));
        pthread_mutex_destroy(&mutex);
        return PTS_UNRESOLVED;
    }

    ret = pthread_mutex_destroy(&mutex);
    if (ret != 0) {
        fprintf(stderr, "pthread_mutex_destroy(): %s\n", strerror(ret));
        return PTS_UNRESOLVED;
    }

    printf("Test PASSED\n");
    return PTS_PASS;
}
```

### INCORRECT: Common Mistakes

```c
/* WRONG: Missing license header */
#include "posixtest.h"

/* WRONG: Defining main() instead of test_main() */
int main(void)
{
    pthread_mutex_t mutex;

    /* WRONG: Not checking return value */
    pthread_mutex_init(&mutex, NULL);
    pthread_mutex_lock(&mutex);

    /* WRONG: Not cleaning up resources */

    /* WRONG: Not printing status message */
    return PTS_PASS;
}
```

## Additional Resources

- Coding guidelines: `testcases/open_posix_testsuite/Documentation/HOWTO_CodingGuidelines`
- Result codes: `testcases/open_posix_testsuite/Documentation/HOWTO_ResultCodes`
- Coverage docs: `testcases/open_posix_testsuite/Documentation/COVERAGE.*`
- Linux kernel coding style: https://www.kernel.org/doc/html/latest/process/coding-style.html
