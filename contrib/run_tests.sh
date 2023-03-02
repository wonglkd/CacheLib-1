#!/usr/bin/env bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Optional (e.g., flaky tests).
OPTIONAL=()
OPTIONAL+=("allocator-test-AllocationClassTest")
OPTIONAL+=("allocator-test-MemoryAllocatorTest")
OPTIONAL+=("allocator-test-MM2QTest")
OPTIONAL+=("allocator-test-NavySetupTest")
OPTIONAL+=("allocator-test-NvmCacheTests")
OPTIONAL+=("navy-test-DeviceTest")
OPTIONAL+=("shm-test-test_page_size")

# Skip long-running benchmarks.
TO_SKIP=()
TO_SKIP+=("benchmark-test-CompactCacheBench")  # 26 mins.
TO_SKIP+=("benchmark-test-MutexBench")  # 60 mins.

OPTIONAL_LIST=`printf -- '%s\n' ${OPTIONAL[@]}`
TO_SKIP_LIST=`printf -- '%s\n' ${TO_SKIP[@]}`

dir=$(dirname "$0")
cd "$dir/.." || die "failed to change-dir into $dir/.."
test -d cachelib || die "failed to change-dir to expected root directory"

cd opt/cachelib/tests || die "failed to change-dir into opt/cachelib/tests"

PREFIX="$PWD/opt/cachelib/"
LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib64:${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH

echo "== Running tests for CI =="
find * -type f -not -name "*bench*" -executable \
  | grep -vF "$TO_SKIP_LIST" \
  | xargs -n1 -I {} make -s {}.log || echo Test {} failed
echo "Successful tests: `find -name '*.ok' | wc -l`"
echo "Failed tests: `find -name '*.fail' | wc -l`"

echo "== Running benchmarks for CI =="
find * -type f -name "*bench*" -executable \
  | grep -vF "$TO_SKIP_LIST" \
  | xargs -n1 -I {} make -s {}.log || echo Test {} failed
echo "Successful benchmarks: `find -name '*bench*.ok' | wc -l`"
echo "Failed benchmarks: `find -name '*bench*.fail' | wc -l`"

N_PASSED=`find -name '*.ok' | wc -l`
N_FAILED=`find -name '*.fail' | wc -l`
N_IGNORED=`find * -type f -name "*.fail" -exec basename {} .log.fail ';' | grep -F "$OPTIONAL_LIST" | wc -l`
N_SKIPPED=${#TO_SKIP[@]}
let "N_FAILED_NOT_IGNORED = $N_FAILED - $N_IGNORED"
echo "## Test summary" >> $GITHUB_STEP_SUMMARY
echo "| Passed | Failed | Ignored | Skipped" >> $GITHUB_STEP_SUMMARY
echo "|--|--|--|--|" >> $GITHUB_STEP_SUMMARY
echo "| $N_PASSED | $N_FAILED | $N_IGNORED | $N_SKIPPED |" >> $GITHUB_STEP_SUMMARY


if ls *.fail > /dev/null 2>&1; then
    echo "== Failure details =="
    grep "Segmentation fault" *.log || true
    grep "FAILED.*ms" *.log || true
    echo
    echo "=== Ignored test failures ==="
    find * -type f -name "*.fail" -exec basename {} .log.fail ';' \
        | grep -F "$OPTIONAL_LIST"
    echo
    echo "== Summary of failures =="
    find * -type f -name "*.fail" -exec basename {} .log.fail ';' \
        | grep -vF "$OPTIONAL_LIST"
    STATUS=$?

    if [ $STATUS -ne 0 ]; then
        echo "Only ignored tests failed."
    else
        echo >> $GITHUB_STEP_SUMMARY
        echo "## Failing tests" >> $GITHUB_STEP_SUMMARY
        find * -type f -name "*.fail" -exec basename {} .log.fail ';' \
            | grep -vF "$OPTIONAL_LIST" \
            | awk ' { print "- " $1 } ' >> $GITHUB_STEP_SUMMARY

        echo "$N_FAILED_NOT_IGNORED tests/benchmarks failed."
        exit 1
    fi
else
    echo "All tests passed."
fi
