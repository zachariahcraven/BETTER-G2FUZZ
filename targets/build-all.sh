#!/bin/bash
# build-all.sh OUT: every fuzz target, three ways (.afl AFL++, .cmp CmpLog, .asan AddressSanitizer for
# crash triage), with its stock seeds in OUT/seeds/<target>/. The image runs each build.sh into /targets;
# this does all of them at once, inside the image (e.g. to rebuild into targets/bin on Tempest).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
for t in jhead libtiff libpng libxml2 doom; do
  echo "== $t"; bash "$HERE/$t/build.sh" "${1:?usage: build-all.sh OUT}"
done
