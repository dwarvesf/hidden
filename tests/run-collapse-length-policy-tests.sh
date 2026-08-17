#!/bin/sh
set -eu

test_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$test_dir/.." && pwd)
test_binary=$(mktemp -d)/collapse-length-policy-tests
trap 'rm -rf "$(dirname -- "$test_binary")"' EXIT

swiftc "$repo_dir/hidden/Common/CollapseLengthPolicy.swift" \
  "$test_dir/CollapseLengthPolicyTests.swift" \
  -o "$test_binary"
"$test_binary"
