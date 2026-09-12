# Site-visit settings keyboard repair — verified locally

Report `ea83a41c-33e8-477a-91f5-3db669c4ab2c`. Production repair `26c9667b` was integrated as `f8515508`.

Actual editor-sheet diagnostics proved that the canonical DONE accessory was installed during UITextField editing activation, then replaced by SwiftUI's empty accessory on the next main-queue turn. The coordinator now retains each field's canonical accessory in weak-key storage and reconciles it once after that focus update, provided the coordinator lifecycle and active first responder still match. There is no polling, private SwiftUI class dependency or form-input/draft rewrite.

All three actual-editor tests passed with zero failures/skips in `keyboard-tests-6.xcresult` on the dedicated iPhone 17 / iOS 26.5 simulator. They cover visit name, checklist label, focus transitions through description, DONE dismissal, refocus identity and retained multiline/name/label drafts. Eleven existing description-input checks and six existing global-accessory checks also passed in the prior focused run with the same production keyboard repair: 20 distinct input/accessory checks in total.

Four raw simulator screen captures, two actual keyboard crops and four geometry records are retained here. Root independently inspected all four full screens: software keys and DONE are visible before dismissal; the same editor and entered text remain afterward. The helper acknowledgment binds each image to its fresh request, exact simulator/bundle and SHA256. The app-hosted XCTest target cannot capture remote keyboard pixels through view drawing and lacks XCUIScreen UI-testing authority; the documented simulator helper captures the actual composited screen. Missing screenshots fail explicitly.

The passing run used application/test sources at `ca4c2141`; subsequent helper-only change `84d1fae5` handles a request retired between listing and reading. It does not change application or Swift test sources. The helper follows Xcode's replacement data container and preserves the original freshness boundary. Python syntax and source checks pass.

This fixture mounts the actual SiteVisitTypeEditorView inside a settings-style cover and sheet. It does not exercise the production type-list loading/authentication route. This is simulator evidence, not physical-device acceptance or customer distribution. No push, release, real type save, or production business-data mutation occurred.
