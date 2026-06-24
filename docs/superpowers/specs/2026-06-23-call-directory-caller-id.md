# Call Directory caller-ID — "OPS lead: Jane" on the incoming-call screen

**Status:** Code ready to drop in. Blocked only on Apple Developer portal provisioning + a real-device test (the externally-gated piece flagged in feature 154cb8a3). This doc is the complete package: the extension is delivered as source + a precise checklist rather than committed as a live Xcode target, because adding a target hand-edits the shared `OPS.xcodeproj` (risky for parallel sessions) and the extension can't sign/function without the App Group + App IDs from the OPS Apple Developer account.

## What the user gets

When a number that belongs to a pipeline lead calls the operator, the **native iPhone incoming-call screen** shows **"OPS lead: Jane"** instead of an unknown number. Pure identification — display only, no data written, no taps. It's the inbound-call counterpart to the auto-log of outbound calls.

## Hard constraints (Apple)

- The user must turn it on once: **Settings → Phone → Call Blocking & Identification → OPS**. The app cannot force-enable it; it can detect the status and prompt.
- Numbers handed to CallKit must be **Int64 E.164** (country code + number, no `+`), **sorted ascending, unique**.
- The extension runs in a **memory-constrained** process — fine for a typical pipeline (hundreds–low-thousands of numbers); chunk if it ever grows huge.
- **Real device only** — Call Directory does not work meaningfully in the Simulator.
- Needs an **App Group** shared between the app and the extension (the app writes numbers, the extension reads them).

## Architecture

```
PipelineViewModel.loadData()  ──►  CallDirectoryRefresher.refresh(opps)
                                        │ writes E.164 entries (sorted)
                                        ▼
                                 App Group  group.co.opsapp.ops  (shared UserDefaults)
                                        ▲
                                        │ reads on demand
   incoming call ──► iOS ──► OPSCallDirectory extension (CXCallDirectoryProvider)
                                        │ addIdentificationEntry(number, "OPS lead: Jane")
                                        ▼
                              native call screen shows the label
```

---

## Source — app + extension

### 1. `PhoneNumber` addition (app target) — E.164 Int64

```swift
extension PhoneNumber {
    /// CallKit-ready E.164 as Int64 (NANP-centric: 10-digit numbers get a `1`
    /// country code). Returns nil when the result isn't a plausible phone int.
    static func e164Int64(_ raw: String?) -> Int64? {
        guard let digits = normalize(raw) else { return nil }   // strips formatting + leading NANP 1 → 10 digits
        let withCountry = digits.count == 10 ? "1" + digits : digits
        guard withCountry.count >= 11, withCountry.count <= 15 else { return nil }
        return Int64(withCountry)
    }
}
```

### 2. `CallDirectoryStore.swift` — add to BOTH the app target AND the extension target

```swift
import Foundation

/// Shared store the app writes and the Call Directory extension reads, via an
/// App Group. Entries are kept sorted ascending + unique (CallKit's contract).
enum CallDirectoryStore {
    /// MUST match the App Group registered in the Apple Developer portal and
    /// enabled on both the app and the extension.
    static let appGroupID = "group.co.opsapp.ops"
    private static let key = "ops.callDirectory.entries"

    struct Entry: Codable { let number: Int64; let label: String }

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroupID) }

    /// APP SIDE — persist the pipeline's numbers (dedup + ascending sort here so
    /// the extension just iterates).
    static func save(_ entries: [Entry]) {
        let deduped = Dictionary(entries.map { ($0.number, $0.label) }, uniquingKeysWith: { first, _ in first })
            .map { Entry(number: $0.key, label: $0.value) }
            .sorted { $0.number < $1.number }
        guard let data = try? JSONEncoder().encode(deduped) else { return }
        defaults?.set(data, forKey: key)
    }

    /// EXTENSION SIDE — already sorted + unique.
    static func loadEntries() -> [Entry] {
        guard let data = defaults?.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }
}
```

### 3. `CallDirectoryHandler.swift` — extension target only (principal class)

```swift
import Foundation
import CallKit

final class CallDirectoryHandler: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self
        // Full reload of the identification set. Works for both full and
        // incremental requests (clear-then-add when incremental).
        if context.isIncremental {
            context.removeAllIdentificationEntries()
        }
        for entry in CallDirectoryStore.loadEntries() { // ascending, unique
            context.addIdentificationEntry(withNextSequentialPhoneNumber: entry.number, label: entry.label)
        }
        context.completeRequest()
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // CallKit retries later; nothing to recover here.
        print("[CALL_DIR] request failed: \(error)")
    }
}
```

### 4. `CallDirectoryRefresher.swift` — app target

```swift
import Foundation
import CallKit

enum CallDirectoryRefresher {
    /// MUST match the extension target's bundle identifier.
    static let extensionID = "co.opsapp.ops.CallDirectory"

    /// Toggle that mirrors the Settings switch.
    @inline(__always) static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "showLeadsOnIncomingCalls") as? Bool ?? false
    }

    /// Rebuild the directory from the current pipeline and ask iOS to reload.
    static func refresh(from opportunities: [OpportunityDTO]) {
        guard isEnabled else { return }
        let entries: [CallDirectoryStore.Entry] = opportunities.compactMap { opp in
            guard opp.deletedAt == nil,
                  let number = PhoneNumber.e164Int64(opp.contactPhone) else { return nil }
            let name = (opp.contactName?.isEmpty == false) ? opp.contactName! : "lead"
            return .init(number: number, label: "OPS lead: \(name)")
        }
        CallDirectoryStore.save(entries)
        CXCallDirectoryManager.shared.reloadExtension(withIdentifier: extensionID) { error in
            if let error { print("[CALL_DIR] reload failed: \(error)") }
        }
    }

    /// Clear the directory (Settings toggle off).
    static func disable() {
        CallDirectoryStore.save([])
        CXCallDirectoryManager.shared.reloadExtension(withIdentifier: extensionID, completionHandler: nil)
    }

    /// Whether the user has enabled OPS under Settings → Phone → Call Blocking
    /// & Identification. Drive an in-app "turn it on" hint from this.
    static func fetchEnabledStatus(_ completion: @escaping (CXCallDirectoryManager.EnabledStatus) -> Void) {
        CXCallDirectoryManager.shared.getEnabledStatusForExtension(withIdentifier: extensionID) { status, _ in
            DispatchQueue.main.async { completion(status) }
        }
    }
}
```

### 5. Settings toggle (add to `PipelineSettingsView`)

```swift
@AppStorage("showLeadsOnIncomingCalls") private var showLeadsOnIncomingCalls = false

// in the CALL LOGGING card or a new "INCOMING CALLS" card:
SettingsToggle(
    title: "Show OPS leads on incoming calls",
    description: "When a lead calls, their name shows on the call screen. Turn on in Settings → Phone → Call Blocking & Identification → OPS.",
    isOn: $showLeadsOnIncomingCalls
)
.onChange(of: showLeadsOnIncomingCalls) { _, on in
    if on { CallDirectoryRefresher.refresh(from: /* current opportunities */ []) }
    else { CallDirectoryRefresher.disable() }
}
```

### 6. Refresh trigger

Call `CallDirectoryRefresher.refresh(from: allOpportunities)` wherever the pipeline list is loaded/refreshed — e.g. at the end of `PipelineViewModel.loadData()` after `fetchAll()` returns, and after a lead is created/edited/deleted. (Opportunities are network-only, so this naturally rides the existing fetch.)

---

## Checklist — the parts that need the OPS Apple Developer account

These are done once, in Xcode + the developer portal (a few minutes), then the code above compiles and ships:

1. **Apple Developer portal**
   - ✅ **App Group already exists** — `group.co.opsapp.ops`, already on the main app (in `OPS.entitlements`, from the share-extension work). `CallDirectoryStore.appGroupID` is already set to it. Nothing to do here.
   - Create an **App ID** for the extension (e.g. `co.opsapp.ops.CallDirectory`) and check the **App Groups** capability, selecting the existing `group.co.opsapp.ops`.
   - Regenerate/automatic-manage the extension's provisioning profile.
2. **Xcode**
   - File → New → Target → **Call Directory Extension** → name `OPSCallDirectory`, bundle id `co.opsapp.ops.CallDirectory`.
   - Replace the generated `CallDirectoryHandler.swift` with §3 above.
   - Add `CallDirectoryStore.swift` (§2) to **both** the app and extension targets (Target Membership).
   - Add `CallDirectoryRefresher.swift` (§4) + the `PhoneNumber` extension (§1) to the **app** target.
   - On **both** targets: Signing & Capabilities → **App Groups** → check `group.co.opsapp.ops`.
   - Set `CallDirectoryStore.appGroupID` and `CallDirectoryRefresher.extensionID` to the real values.
3. **Test on a real iPhone**
   - Build/run on device, enable OPS under Settings → Phone → Call Blocking & Identification.
   - Have a number that matches a lead call the phone → the call screen should read "OPS lead: <name>".

## Notes
- This is **identification only** — it does not (and cannot) log the call or write data. Pair it with the manual "Log a Call" path for inbound calls.
- `caller_number` we store on activities is normalized digits; the directory uses E.164 Int64 — both derive from `PhoneNumber.normalize`, so they stay consistent.
