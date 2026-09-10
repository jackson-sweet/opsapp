#!/bin/bash
set -euo pipefail
# Acquire the shared build baton and verify global process ownership first.
# Only the private P19 simulator/cache paths below are used. No signing.
run=${1:?Supply a new result suffix after acquiring the build baton}
root=$(cd "$(dirname "$0")/../../.." && pwd)
cd "$root"
xcodebuild test -project OPS.xcodeproj -scheme OPS \
  -destination 'platform=iOS Simulator,id=FA315A2B-AD37-45C2-937A-816BD34CDCDD' \
  -derivedDataPath /private/tmp/ops-site-visits-p19/DerivedData \
  -clonedSourcePackagesDirPath /private/tmp/ops-site-visits-p19/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO -jobs 2 \
  -only-testing:OPSTests/SiteVisitWriteCommandTests \
  -only-testing:OPSTests/SiteVisitWritePersistenceTests \
  -only-testing:OPSTests/SiteVisitVersionedSyncTests \
  -only-testing:OPSTests/SiteVisitPersistenceCoordinatorTests \
  -only-testing:OPSTests/SiteVisitRecoveryVaultTests \
  -only-testing:OPSTests/SiteVisitConflictReviewSnapshotTests \
  -only-testing:OPSTests/SiteVisitRepositoryTests \
  -only-testing:OPSTests/SiteVisitOutboundSyncTests/testCaptureRejectsReplacementActorBeforeWrite \
  -only-testing:OPSTests/SiteVisitOutboundSyncTests/testCaptureTransmitsOriginalActorAndRejectsPostResponseSessionSwitch \
  -only-testing:OPSTests/SiteVisitOutboundSyncTests/testCoalescingCannotSupersedeAnotherActorsCapture \
  -only-testing:OPSTests/SiteVisitOutboundSyncTests/test_parentUpsertUsesCurrentModelSnapshotAndClearsDirtyFlag \
  -only-testing:OPSTests/SiteVisitOutboundSyncTests/test_completionRetryUsesPersistedPayloadAndStoresActivityId \
  -resultBundlePath "/private/tmp/ops-site-visits-p19/phone-tests-$run.xcresult" \
  CODE_SIGNING_ALLOWED=NO MBX_ACCESS_TOKEN=pk.test-hosted-xctest-token \
  > "docs/artifacts/phase19/phone-app-tests-$run.log" 2>&1
