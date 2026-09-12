# Choice-compatible signed iPhone test build — 2026-09-12

Exact source `2e46d7285170b7520ee73a7a12be0751b0713c9e` built successfully as Release/arm64 for generic iOS. Xcode exited 0 and `codesign --verify --deep --strict` exited 0 using normal macOS trust services. The initial sandbox-only verification could not establish trust (`CSSMERR_TP_NOT_TRUSTED`); the successful normal-trust check is the acceptance evidence. Build warnings remain recorded in the raw log; this is not a warning-free build claim.

Apple Development team `X47H96M34K`, bundle `co.opsapp.ops.OPS`, version/build 3.0.5. Exact executable/log hashes, signed timestamp and signature identity are in [the JSON record](choice-signed-build-20260912.json). The one-shot build command is [recorded here](run-choice-signed-build-20260912.sh).

New app: `/private/tmp/ops-site-visits-choice-20260912/DerivedData/Build/Products/Release-iphoneos/OPS.app`. Raw log: `/private/tmp/ops-site-visits-choice-20260912/signed-build.log`. DerivedData is isolated; dependency sources were APFS-cloned into a new owned path. The prior app and its build/dependency directories remain untouched. The serial build slot was returned after Xcode exited; no competing build was started by this task.

This source contains the reviewed single-choice Codable/queue behavior without changing SwiftData V28. It supersedes the older `3f5eaffe` artifact for a choice-compatible trial. The older app must not be installed over choice-used local data: schema identity alone does not prove metadata/queued-command compatibility.

The app was **not installed, launched, archived, uploaded or App Store-released**. Device inventory alone does not establish the installed source or pending-work custody. No phone store was copied or altered. The choice migration and MCP compatibility repair remain unapplied; exact company/host activation and physical-device/native-host acceptance remain separate, explicit gates. The MCP repair is local OPS-Web `babe8ec1d`; its 31 new SQL assertions and unchanged 115 workflow tests pass, with the 262 existing phone/choice checks also passing. Expense work remains separately owned.
