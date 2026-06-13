//
//  CompanyNameStepView.swift
//  OPS
//
//  Onboarding rebuild P4 — S4o (Company name): the COMPANY-CREATION COMMIT POINT.
//
//  Design spec §4.2 S4o. The owner has just created their account; here they name
//  their company and the company is actually created on the server (the live
//  `create_company_for_owner` RPC). The role is STILL uncommitted until a company
//  exists, so Back returns to role pick (the wrong-role escape) — companyName has
//  a back-edge in BOTH auth contexts.
//
//  Layout (top → bottom):
//    • Header — Back → role pick (role uncommitted), Cake Mono title.
//    • Bracketed micro-instruction — this is the once-ever company setup.
//    • Company-name field (required) + a one-line reassurance subline.
//    • OPTIONAL primary-trade chips (single-select) → `formData.industries`.
//      Zero required friction — chips never gate the CTA.
//    • Primary CTA — "Create company" (the one accented control), loading +
//      disabled-until-a-name-is-typed.
//
//  COMMIT CONTRACT — the screen owns NO company-creation logic and reaches NO
//  singletons. The commit is funnelled through an injected
//  `CompanyCreationBoundary` whose single async method returns a
//  `CompanyCreationOutcome`. The gateway wires the live boundary (backed by
//  `OnboardingManager.createCompanyViaRPC()`); tests inject a stub so name-gating,
//  the success → crewCode advance (carrying the DB-truth code), and the typed
//  error branches are all verifiable WITHOUT touching the network.
//
//  TYPED-ERROR MAPPING (from `OnboardingManager.CreateCompanyError`):
//    • invalidName     → inline FIELD error (rose border on the name field).
//    • alreadyInCompany→ inline error (this account already owns a company it did
//                        not create here; no code is returned, so we can't advance).
//    • userRowMissing  → inline top-level error (retry-able — sync race).
//    • generic / noUserId → inline top-level error.
//  The idempotent owner re-run (RPC `already_existed: true`) is NOT an error — the
//  RPC returns the existing code, so the boundary resolves `.created(code:)` and
//  the screen advances to crewCode showing that code (the correct, safe path for a
//  killed-mid-flow owner re-creating).
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, zero shadows. Accent (`opsAccent`)
//      appears ONLY on the primary CTA (via the shared component).
//    • Built on the Task 3.1 components — `OPSOnboardingField`,
//      `OnboardingStepHeader`, `OnboardingPrimaryCTA`. Nothing re-rolled.
//    • Trade chips use the §4.3 chip visual: `chipRadius`, surfaceInput fill,
//      hairline border, 36pt min height (the one sanctioned sub-44pt target).
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact
//      haptic on the commit; success notification on company created.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Company-creation boundary (the testable seam)

/// What a company-creation attempt resolved to. The screen branches on these; the
/// gateway produces them from the live `OnboardingManager`. The `.created` payload
/// carries the DB-truth crew code the next screen renders.
enum CompanyCreationOutcome: Equatable {
    /// The company was created (or, idempotently, already existed and was reused).
    /// `code` is the DB-truth company/crew code — persisted into `generatedCrewCode`
    /// and shown on S5o.
    case created(code: String)

    /// The typed company name was empty/invalid — surface a FIELD error (the name
    /// field reads rose). `message` is the bare phrase the field prefixes.
    case invalidName(message: String)

    /// This account already belongs to a company it did NOT create here (the server
    /// raised `ALREADY_IN_COMPANY`, distinct from the idempotent reuse). No code is
    /// returned, so the screen surfaces an inline top-level error rather than
    /// advancing. `message` is the bare phrase the inline error prefixes.
    case alreadyInCompany(message: String)

    /// The attempt failed (sync race / server / network). Surface inline,
    /// top-level, never silent. `message` is the bare phrase.
    case failed(message: String)
}

/// The async boundary S4o funnels the company commit through. Implemented live by
/// the gateway (over `OnboardingManager.createCompanyViaRPC()`); stubbed in tests.
@MainActor
protocol CompanyCreationBoundary {
    /// Create the company. `name` is the validated, trimmed company name; `industries`
    /// is the (possibly empty) optional primary-trade selection. Returns the outcome
    /// the screen branches on — never throws (failures are mapped to `.failed` /
    /// typed cases).
    func createCompany(name: String, industries: [String]) async -> CompanyCreationOutcome
}

// MARK: - S4o screen

struct CompanyNameStepView: View {

    /// The async company-creation boundary. Injected so the screen never touches
    /// the RPC directly.
    let boundary: CompanyCreationBoundary

    /// Persist a collected field into the coordinator's form data. The gateway
    /// wires this to `coordinator.update`. Used to persist the company name as the
    /// user types (so a kill mid-flow resumes with it) and the selected trade.
    let onUpdateFormData: (@escaping (inout OnboardingFormData) -> Void) -> Void

    /// Company created → persist `generatedCrewCode` + advance to `.crewCode`.
    /// The gateway wires this with the returned DB-truth code.
    let onCreated: (String) -> Void

    /// Back → role pick (role uncommitted — the wrong-role escape). The gateway
    /// wires `coordinator.goBack()`.
    let onBack: () -> Void

    // MARK: Init

    init(
        boundary: CompanyCreationBoundary,
        onUpdateFormData: @escaping (@escaping (inout OnboardingFormData) -> Void) -> Void,
        onCreated: @escaping (String) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.boundary = boundary
        self.onUpdateFormData = onUpdateFormData
        self.onCreated = onCreated
        self.onBack = onBack
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture
    /// the error / loading / selected-trade states (otherwise only reachable after
    /// an async interaction). DEBUG-only; never used by the live gateway.
    init(
        boundary: CompanyCreationBoundary,
        previewCompanyName: String = "",
        previewSelectedTrade: String? = nil,
        previewDidAttemptSubmit: Bool = false,
        previewNameError: String? = nil,
        previewTopLevelError: String? = nil,
        previewIsCreating: Bool = false
    ) {
        self.boundary = boundary
        self.onUpdateFormData = { _ in }
        self.onCreated = { _ in }
        self.onBack = {}
        _companyName = State(initialValue: previewCompanyName)
        _selectedTrade = State(initialValue: previewSelectedTrade)
        _didAttemptSubmit = State(initialValue: previewDidAttemptSubmit)
        _nameError = State(initialValue: previewNameError)
        _topLevelError = State(initialValue: previewTopLevelError)
        _isCreating = State(initialValue: previewIsCreating)
        _hasAppeared = State(initialValue: true) // settle the entrance for snapshots
    }
    #endif

    // MARK: Field state

    @State private var companyName = ""

    /// The single selected primary trade (optional). Single-select: tapping a
    /// selected chip clears it. Persisted into `formData.industries` as a 0/1-element
    /// array on every change.
    @State private var selectedTrade: String?

    /// True once the user has tried to submit — gates whether the name field error
    /// renders (the form is clean before the first attempt).
    @State private var didAttemptSubmit = false

    /// A server-returned FIELD error for the name (invalidName) — rendered on the
    /// field. Distinct from the pre-submit local "enter a company name" gate.
    @State private var nameError: String?

    /// A surfaced top-level failure (alreadyInCompany / sync race / server) —
    /// rendered inline, never silent. Cleared on the next attempt.
    @State private var topLevelError: String?

    /// True while the create RPC is in flight — drives the CTA spinner + gate.
    @State private var isCreating = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nameFocused: Bool

    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                scrollContent
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onAppear {
            OnboardingHaptics.prepare()
            guard !hasAppeared else { return }
            if reduceMotion {
                hasAppeared = true
            } else {
                withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
            }
        }
    }

    /// The full vertical stack. Extracted so the DEBUG snapshot harness can render
    /// it WITHOUT the enclosing `ScrollView` (`ImageRenderer` reports zero intrinsic
    /// size for a `ScrollView`). The live screen always wraps this in the scroll view.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            instruction
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            nameBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            tradeBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            ctaBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        }
        .padding(.bottom, OPSStyle.Layout.spacing5)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: (hasAppeared || reduceMotion) ? 0 : OPSStyle.Layout.spacing3)
    }

    #if DEBUG
    /// A render of the screen with no `ScrollView`, for the snapshot harness only.
    /// Top-aligned on the canvas so the captured frame matches the live layout.
    var snapshotBody: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            scrollContent
        }
    }
    #endif

    // MARK: - Header (Back → role pick)

    private var header: some View {
        OnboardingStepHeader(
            title: "Name your company",
            backLabel: "Role",
            onBack: onBack
        )
    }

    // MARK: - Bracketed micro-instruction

    private var instruction: some View {
        Text("[ ONE TIME. DO IT RIGHT. ]")
            .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
            .foregroundColor(OPSStyle.Colors.text3)
            .tracking(1.4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true) // decorative; the title carries the label
    }

    // MARK: - Company-name field + reassurance subline

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            OPSOnboardingField(
                label: "Company name",
                text: $companyName,
                placeholder: "Your company",
                kind: .text,
                error: effectiveNameError,
                submitLabel: .go,
                onSubmit: { attemptCreate() }
            )
            .focused($nameFocused)
            .onChange(of: companyName) { _, newValue in
                // Persist as the user types (kill-mid-flow resume) and clear any
                // stale server name error once they edit.
                persistName(newValue)
                if nameError != nil { nameError = nil }
            }

            // Reassurance — Mohave body, tertiary. Hidden once the field shows an
            // error so the rose error line owns the slot.
            if effectiveNameError == nil {
                Text("This is how your crew finds you.")
                    .font(OPSStyle.Typography.smallBody) // Mohave Light 14pt
                    .foregroundColor(OPSStyle.Colors.text3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("This is how your crew finds you")
            }
        }
    }

    // MARK: - Optional primary-trade chips

    private var tradeBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// PRIMARY TRADE — OPTIONAL")
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(1.4)
                .accessibilityLabel("Primary trade, optional")

            // Wrap layout — single-select chips. Tapping a selected chip clears it.
            TradeChipFlow(
                trades: Self.primaryTrades,
                selected: selectedTrade,
                onSelect: { trade in
                    OnboardingHaptics.selection()
                    selectedTrade = (selectedTrade == trade) ? nil : trade
                    persistTrade(selectedTrade)
                }
            )
        }
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            // Top-level failure (alreadyInCompany / sync race / server) — inline,
            // above the CTA, never silent.
            if let topLevelError {
                Text("// ERROR — \(topLevelError.uppercased())")
                    .font(OPSStyle.Typography.metadata)
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error. \(topLevelError)")
            }

            OnboardingPrimaryCTA(
                title: "Create company",
                isEnabled: isFormValid,
                isLoading: isCreating
            ) {
                attemptCreate()
            }
        }
    }

    // MARK: - Validation

    /// The trimmed company name — the single source of truth for the gate + commit.
    private var trimmedName: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The CTA is live only when a non-empty name is present. The optional trade
    /// never gates. `internal` so the gate is unit-testable via the pure validator.
    var isFormValid: Bool {
        CompanyNameValidation(companyName: companyName).isFormValid
    }

    /// The name field error to render: the server-returned name error if present,
    /// else the local "enter a company name" gate but ONLY after a submit attempt.
    var effectiveNameError: String? {
        if let nameError { return nameError }
        guard didAttemptSubmit else { return nil }
        return CompanyNameValidation(companyName: companyName).nameError
    }

    // MARK: - Actions

    /// Company commit. Validates locally (the CTA gate already enforces this, but
    /// `didAttemptSubmit` lights the field error), then funnels through the boundary
    /// and branches on the outcome.
    func attemptCreate() {
        didAttemptSubmit = true
        topLevelError = nil
        nameError = nil
        guard isFormValid else { return }
        guard !isCreating else { return }

        nameFocused = false
        isCreating = true
        OnboardingHaptics.commit()

        let name = trimmedName
        let industries = selectedTrade.map { [$0] } ?? []
        persistName(name)
        persistTrade(selectedTrade)

        Task { @MainActor in
            let outcome = await boundary.createCompany(name: name, industries: industries)
            isCreating = false
            handle(outcome)
        }
    }

    /// Route a company-creation outcome to the right effect. The success case is the
    /// only navigation — delegated to the pure `CompanyCreationOutcomeRouter` so it
    /// is unit-testable; the error cases mutate local screen state here.
    func handle(_ outcome: CompanyCreationOutcome) {
        let navigated = CompanyCreationOutcomeRouter.route(
            outcome,
            onCreated: { code in
                OnboardingHaptics.success()
                onCreated(code)
            }
        )
        guard !navigated else { return }

        switch outcome {
        case .invalidName(let message):
            // Server rejected the name — surface as a FIELD error.
            nameError = message

        case .alreadyInCompany(let message), .failed(let message):
            // No code to advance with — surface a top-level inline error.
            topLevelError = message

        case .created:
            break // handled by the router
        }
    }

    // MARK: - Form-data persistence

    /// Persist the company name (trimmed → nil-if-blank) so a kill mid-flow resumes
    /// with it.
    private func persistName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.companyName = trimmed.isEmpty ? nil : trimmed }
    }

    /// Persist the selected trade as a 0/1-element industries array (nil when none).
    private func persistTrade(_ trade: String?) {
        onUpdateFormData { $0.industries = trade.map { [$0] } }
    }

    // MARK: - Primary trades (flow-local; the company's main line of work)

    /// The trade chip options. Ordered by trade frequency among OPS's audience.
    /// Sentence-case labels (Mohave chip voice). Persisted lowercased-as-typed.
    static let primaryTrades: [String] = [
        "Roofing",
        "Plumbing",
        "Electrical",
        "HVAC",
        "Landscaping",
        "Painting",
        "Carpentry",
        "Concrete",
        "Masonry",
        "Cleaning"
    ]
}

// MARK: - Trade chip flow (wrap layout, single-select)

/// A wrapping row of single-select trade chips. §4.3 chip visual: chipRadius,
/// surfaceInput fill, hairline border, 36pt min height (the one sanctioned sub-44pt
/// target). Selected chip brightens (surfaceActive + brighter border) — NO accent.
private struct TradeChipFlow: View {
    let trades: [String]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        // A simple wrapping flow built on `FlowLayout` so chips reflow to the next
        // line as needed — no horizontal scroll, every option visible at a glance.
        FlowLayout(spacing: OPSStyle.Layout.spacing2) {
            ForEach(trades, id: \.self) { trade in
                TradeChip(
                    label: trade,
                    isSelected: selected == trade,
                    action: { onSelect(trade) }
                )
            }
        }
    }
}

private struct TradeChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.smallBody) // Mohave Light 14pt
                .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.chipMinHeight) // §4.3 36pt chip exception
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                        .fill(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                        .stroke(
                            isSelected ? Color.white.opacity(0.18) : OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes the ONE host-navigating outcome (`.created`) and reports whether it
/// handled the outcome. The error cases are local-state-only and return `false` so
/// the caller applies them to `@State`. Extracted so the navigation branch is
/// testable without rendering.
enum CompanyCreationOutcomeRouter {
    /// - Returns: `true` when the outcome was the host-navigation effect (and the
    ///   `onCreated` closure was invoked with the DB-truth code); `false` for the
    ///   local-state-only error cases.
    @discardableResult
    static func route(
        _ outcome: CompanyCreationOutcome,
        onCreated: (String) -> Void
    ) -> Bool {
        switch outcome {
        case .created(let code):
            onCreated(code)
            return true
        case .invalidName, .alreadyInCompany, .failed:
            return false
        }
    }
}

// MARK: - Pure form validation (no SwiftUI, fully unit-testable)

/// The complete validation surface for S4o, derived purely from the typed company
/// name. Extracted from the view so the name-required gate is testable WITHOUT
/// rendering. The error string is the bare phrase (the field renders the
/// `// ERROR — ` prefix). Copy locked via ops-copywriter.
struct CompanyNameValidation: Equatable {
    let companyName: String

    var trimmedName: String { companyName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The name is required; the optional trade never gates.
    var nameError: String? { trimmedName.isEmpty ? "enter a company name" : nil }

    var isFormValid: Bool { !trimmedName.isEmpty }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed outcome.
private struct PreviewCompanyBoundary: CompanyCreationBoundary {
    var outcome: CompanyCreationOutcome = .created(code: "BR8K-90ZT")
    func createCompany(name: String, industries: [String]) async -> CompanyCreationOutcome { outcome }
}

#Preview("CompanyNameStepView — default") {
    CompanyNameStepView(
        boundary: PreviewCompanyBoundary(),
        onUpdateFormData: { _ in },
        onCreated: { _ in },
        onBack: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("CompanyNameStepView — error") {
    CompanyNameStepView(
        boundary: PreviewCompanyBoundary(),
        previewCompanyName: "",
        previewDidAttemptSubmit: true,
        previewTopLevelError: "this account already belongs to a company"
    )
    .preferredColorScheme(.dark)
}
#endif
