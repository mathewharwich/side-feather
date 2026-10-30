#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/side-feather-check.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
compiler="${CXX:-c++}"
flags=(-std=c++17 -O1 -g -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined)
"$compiler" "${flags[@]}" tests/feather_core_test.cpp -o "$test_dir/core"
"$test_dir/core"
"$compiler" "${flags[@]}" tests/feather_bridge_test.cpp src/FeatherBridge.cpp -o "$test_dir/bridge"
"$test_dir/bridge"
