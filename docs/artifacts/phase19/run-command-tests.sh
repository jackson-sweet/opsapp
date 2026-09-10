#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../../.." && pwd)
scratch=$(mktemp -d /private/tmp/ops-phone-command-tests.XXXXXX)
trap 'rm -rf "$scratch"' EXIT
platform=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer
swiftc -module-cache-path "$scratch/cache" -enable-testing -emit-library -emit-module -module-name OPS "$root/OPS/Network/Sync/SiteVisitWriteCommand.swift" "$root/OPS/DataModels/SiteVisits/SiteVisitType.swift" "$root/OPS/DataModels/SyncOperation.swift" "$root/OPS/Network/Sync/SiteVisitWriteModels.swift" "$root/OPS/Network/Supabase/DTOs/SupabaseDateParsing.swift" "$root/OPS/Views/Settings/SiteVisitTypeSettingsLogic.swift" -emit-module-path "$scratch/OPS.swiftmodule" -o "$scratch/libOPS.dylib"
cat > "$scratch/main.swift" <<'SWIFT'
import XCTest
let suite = XCTestSuite(name: "Phone writes")
suite.addTest(XCTestSuite(forTestCaseClass: SiteVisitWriteCommandTests.self))
suite.addTest(XCTestSuite(forTestCaseClass: SiteVisitWritePersistenceTests.self))
suite.run()
guard let run = suite.testRun, run.executionCount == 10, run.totalFailureCount == 0 else { fatalError("Focused XCTest failed or did not execute ten tests") }
print("PASS: ten Foundation command XCTest cases")
SWIFT
swiftc -module-cache-path "$scratch/cache" -I "$scratch" -L "$scratch" -lOPS -I "$platform/usr/lib" -L "$platform/usr/lib" -F "$platform/Library/Frameworks" -framework XCTest -Xlinker -rpath -Xlinker "$scratch" -Xlinker -rpath -Xlinker "$platform/Library/Frameworks" -Xlinker -rpath -Xlinker "$platform/usr/lib" "$root/OPSTests/SiteVisits/SiteVisitWriteCommandTests.swift" "$root/OPSTests/SiteVisits/SiteVisitWritePersistenceTests.swift" "$scratch/main.swift" -o "$scratch/tests"
"$scratch/tests"
