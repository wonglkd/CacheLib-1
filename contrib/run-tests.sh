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

# Flakey tests, or those expected to fail.
IGNORE_STATUS=()
IGNORE_STATUS+=("allocator-test-AllocationClassTest")
IGNORE_STATUS+=("allocator-test-MemoryAllocatorTest")
IGNORE_STATUS+=("allocator-test-MM2QTest")
IGNORE_STATUS+=("allocator-test-NavySetupTest")
IGNORE_STATUS+=("navy-test-DeviceTest")
IGNORE_STATUS+=("shm-test-test_page_size")

# Do not run: long-running benchmarks.
DO_NOT_RUN=()
DO_NOT_RUN+=("benchmark-test-CompactCacheBench")  # 26 mins.
DO_NOT_RUN+=("benchmark-test-MutexBench")  # 60 mins.

IGNORE_STATUS_LIST=`printf -- '%s\n' ${IGNORE_STATUS[@]}`
DO_NOT_RUN_LIST=`printf -- '%s\n' ${DO_NOT_RUN[@]}`

dir=$(dirname "$0")
cd "$dir/.." || die "failed to change-dir into $dir/.."
test -d cachelib || die "failed to change-dir to expected root directory"

cd opt/cachelib/tests

echo "== Running tests for CI =="
find * -type f -not -name "*bench*" -executable \
  | grep -vF "$DO_NOT_RUN_LIST" \
  | xargs -n1 -I {} make {}.log || echo Test {} failed
echo "Successful tests: `find -name '*.ok' | wc -l`"
echo "Failed tests: `find -name '*.fail' | wc -l`"

echo "== Running benchmarks for CI =="
find * -type f -name "*bench*" -executable \
  | grep -vF "$DO_NOT_RUN_LIST" \
  | xargs -n1 -I {} make {}.log || echo Test {} failed
echo "Successful benchmarks: `find -name '*bench*.ok' | wc -l`"
echo "Failed benchmarks: `find -name '*bench*.fail' | wc -l`"

if ls *.fail > /dev/null 2>&1; then
    echo "== Failure details =="
    grep "Segmentation fault" *.log || true
    grep "FAILED.*ms" *.log || true
    echo
    echo "=== Ignored test failures ==="
    find * -type f -name "*.fail" -exec basename {} .log.fail ';' | grep -F "$IGNORE_STATUS_LIST"
    echo
    echo "== Summary of failures =="
    find * -type f -name "*.fail" -exec basename {} .log.fail ';' | grep -vF "$IGNORE_STATUS_LIST"
    echo

fi

# Return success if we have no failures except ignored tests
find * -type f -name "*.fail" -exec basename {} .log.fail ';' | grep -vF "$IGNORE_STATUS_LIST" > /dev/null
