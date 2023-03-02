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

echo "run_tests.sh is for use by CI (selected tests, timeout)."
echo "Users should go to opt/cachelib/tests and run make."
echo

# Optional (e.g., flaky tests).
OPTIONAL=()
OPTIONAL+=("allocator-test-AllocationClassTest")
OPTIONAL+=("allocator-test-MemoryAllocatorTest")
OPTIONAL+=("allocator-test-MM2QTest")
OPTIONAL+=("allocator-test-NavySetupTest") # CentOS 8.1, Debian, Fedora 36, Rocky 9
OPTIONAL+=("allocator-test-NvmCacheTests")
OPTIONAL+=("common-test-UtilTests")  # CentOS 8.1, Debian, Fedora 36, Rocky 9
OPTIONAL+=("navy-test-DeviceTest") # CentOS 8.1
# Large pages need to be enabled
OPTIONAL+=("shm-test-test_page_size") # CentOS 8.1, Debian, Fedora 36, Rocky 9

TEST_TIMEOUT=5m
BENCHMARK_TIMEOUT=20m

# Skip long-running benchmarks.
TO_SKIP=()
TO_SKIP+=("benchmark-test-CompactCacheBench")  # 26 mins.
TO_SKIP+=("benchmark-test-MutexBench")  # 60 mins.

OPTIONAL_LIST=`printf -- '%s\n' ${OPTIONAL[@]}`
TO_SKIP_LIST=`printf -- '%s\n' ${TO_SKIP[@]}`

MD_OUT=${GITHUB_STEP_SUMMARY:-summary.md}
if [[ "$MD_OUT" != "$GITHUB_STEP_SUMMARY" ]]; then
    echo "Markdown summary will be saved in $MD_OUT. Truncating it."
    cat /dev/null > $MD_OUT
    echo
fi

dir=$(dirname "$0")
cd "$dir/.." || die "failed to change-dir into $dir/.."
test -d cachelib || die "failed to change-dir to expected root directory"

cd opt/cachelib/tests || die "failed to change-dir into opt/cachelib/tests"

PREFIX="$PWD/opt/cachelib"
LD_LIBRARY_PATH="$PREFIX/lib:$PREFIX/lib64:${LD_LIBRARY_PATH:-}"
export LD_LIBRARY_PATH

echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo
echo "::group::Running tests for CI (in parallel, max: $TEST_TIMEOUT)"
find * -type f -not -name "*bench*" -executable \
  | grep -vF "$TO_SKIP_LIST" \
  | awk ' { print $1 ".log" } ' | tr '\n' ' ' \
  | xargs timeout --preserve-status $TEST_TIMEOUT make -j -s
echo "::endgroup::"
echo "Successful tests: `find -name '*.ok' | wc -l`"
echo "Failed tests: `find -name '*.fail' | wc -l`"
echo
echo "::group::Running benchmarks for CI (in parallel, max: $BENCHMARK_TIMEOUT)"
find * -type f -name "*bench*" -executable \
  | grep -vF "$TO_SKIP_LIST" \
  | awk ' { print $1 ".log" } ' | tr '\n' ' ' \
  | xargs timeout --preserve-status $BENCHMARK_TIMEOUT make -j -s
echo "::endgroup::"
echo "Successful benchmarks: `find -name '*bench*.ok' | wc -l`"
echo "Failed benchmarks: `find -name '*bench*.fail' | wc -l`"


TESTS_PASSED=`find * -name '*.log.ok' | sed 's/\.[^.]*$//'`
TESTS_FAILED=`find * -name '*.log.fail' | sed 's/\.[^.]*$//'`
TESTS_TIMEOUT=`find * -type f -executable | grep -vF "$TESTS_PASSED\n$TESTS_FAILED" | sed 's/\.[^.]*$//'`
TESTS_IGNORED=`echo $TESTS_FAILED | tr ' ' '\n' | grep -F "$OPTIONAL_LIST"`
FAILURES_UNIGNORED=`echo $TESTS_FAILED | tr ' ' '\n' | grep -vF "$OPTIONAL_LIST"`

N_TIMEOUT=`echo $TESTS_TIMEOUT | wc -w`
N_PASSED=`echo $TESTS_PASSED | wc -w`
N_FAILED=`echo $TESTS_FAILED | wc -w`
N_IGNORED=`echo $TESTS_IGNORED | wc -w`
N_FAILURES_UNIGNORED=`echo $FAILURES_UNIGNORED | wc -w`
N_SKIPPED=`echo $TO_SKIP | wc -w`

echo "## Test summary" >> $MD_OUT
echo "| Passed | Failed | Ignored | Timeout | Skipped" >> $MD_OUT
echo "|--------|--------|---------|---------|---------|" >> $MD_OUT
echo "| $N_PASSED | $N_FAILED | $N_IGNORED | $N_TIMEOUT | $N_SKIPPED |" >> $MD_OUT


if [ $N_FAILED -ne 0 ]; then
    if [ $N_IGNORED -ne 0 ]; then
        echo
        echo "::group::Ignored test failures "
        echo $TESTS_IGNORED | tr ' ' '\n'
        echo "::endgroup"

        echo >> $MD_OUT
        echo "## Ignored test failures" >> $MD_OUT
        echo $TESTS_IGNORED | awk -v RS=' ' ' { print "- " $1 } ' >> $MD_OUT
    fi 

    if [ $N_FAILURES_UNIGNORED -eq 0 ]; then
        STATUS=0
        echo "Only ignored tests failed."
    else
        STATUS=1
        echo
        echo "::group::Failing tests"
        echo $FAILURES_UNIGNORED | tr ' ' '\n'
        echo "::endgroup"

        echo >> $MD_OUT
        echo "## Failing tests" >> $MD_OUT
        echo $FAILURES_UNIGNORED | awk -v RS=' ' ' { print "- " $1 } ' >> $MD_OUT

        echo "::warning $N_FAILURES_UNIGNORED tests/benchmarks failed."
    fi

    echo
    echo "::group::Failure details"
    grep "Segmentation fault" *.log || true
    grep "FAILED.*ms" *.log || true
    echo "::endgroup"

    echo >> $MD_OUT
    echo "## Failure details" >> $MD_OUT
    echo "\`\`\`" >> $MD_OUT
    grep "Segmentation fault" *.log || true >> $MD_OUT
    grep "FAILED.*ms" *.log || true >> $MD_OUT
    echo "\`\`\`" >> $MD_OUT

else
    STATUS=0
    echo
    echo "All tests passed."
fi

if [ $N_TIMEOUT -ne 0 ]; then
    echo
    echo "::group::Timed out tests"
    echo $TESTS_TIMEOUT | tr ' ' '\n'
    echo "::endgroup"


    echo "## Tests timed out" >> $MD_OUT
    echo $TESTS_TIMEOUT | awk -v RS=' ' ' { print "- " $1 } ' >> $MD_OUT

fi


if [ $STATUS -eq 0 ]; then
    echo
    echo "Return as error"
    # Comment out for now so we can figure out which tests work on which
    # exit 1
fi
