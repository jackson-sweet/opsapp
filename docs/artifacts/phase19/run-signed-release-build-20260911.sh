#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
test "$(git rev-parse HEAD)" = 3f5eaffebd3d81e22d9165140f3c002bc4d22edd
test -f OPS/Utilities/Secrets.xcconfig
test ! -e /private/tmp/ops-site-visits-p19/signed-release-build-20260911.log
xcodebuild -project OPS.xcodeproj -scheme OPS -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/ops-site-visits-p19/DerivedData \
  -clonedSourcePackagesDirPath /private/tmp/ops-site-visits-p19/SourcePackages \
  build 2>&1 | tee /private/tmp/ops-site-visits-p19/signed-release-build-20260911.log
