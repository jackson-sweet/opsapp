#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
test "$(git rev-parse HEAD)" = 2e46d7285170b7520ee73a7a12be0751b0713c9e
test -f OPS/Utilities/Secrets.xcconfig
test -d /private/tmp/ops-site-visits-choice-20260912/SourcePackages
test ! -e /private/tmp/ops-site-visits-choice-20260912/signed-build.log
xcodebuild -project OPS.xcodeproj -scheme OPS -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /private/tmp/ops-site-visits-choice-20260912/DerivedData \
  -clonedSourcePackagesDirPath /private/tmp/ops-site-visits-choice-20260912/SourcePackages \
  build > /private/tmp/ops-site-visits-choice-20260912/signed-build.log 2>&1
