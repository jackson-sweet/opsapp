//
//  CodeEntryStepView.swift
//  OPS
//
//  Onboarding rebuild P5 — S4c-code (Crew code entry): the CREW-path screen where
//  the worker types the code their boss gave them to find — and confirm — their
//  company. Reached two ways: from S4c when there were zero invites
//  (`provenance: .zeroInvites`), or from the invite picker's "Enter a different
//  code" (`provenance: .fromPicker`). The provenance the screen was entered with is
//  CARRIED FORWARD so the confirm-company back-edge returns to the right origin.
//
//  Design spec §4.2 S4c-code. The code input is the SHARED `OnboardingCodeEntry`
//  (the entry mode of `OnboardingCodeDisplay`) — the IDENTICAL bracketed JetBrains-
//  Mono glyph the owner's share screen renders, so the same code reads the same on
//  both ends of the flow.
//
//  NO CLIENT FORMAT REJECTION — legacy `PREFIX-XXXXXX` codes must be accepted.
//  Validation is server lookup-ONLY: the only client gate is "is the field non-
//  empty" (so an empty submit doesn't hit the network). The server decides
//  found / not-found.
//
//  LOOKUP CONTRACT — the screen owns NO flow logic and reaches NO singletons. The
//  lookup is funnelled through an injected `CodeEntryBoundary` returning a
//  `CodeEntryOutcome`; the navigation decision is the pure `CodeEntryOutcomeRouter`.
//  On `.found` the screen persists the company (id / name / code / logo) + the typed
//  code into form data and advances to `.confirmCompany(source: .codeEntry(prov))`,
//  carrying the provenance. `.notFound` and `.failed` are inline errors with NO nav.
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`)
//      appears ONLY on the one primary CTA (JOIN CREW, via the shared component).
//      The code glyph is neutral — never accent.
//    • Built on the shared `OnboardingCodeEntry` / `OnboardingStepHeader` /
//      `OnboardingPrimaryCTA`. Nothing re-rolled.
//    • Header Back per the back map (zeroInvites → role, fromPicker → invite
//      picker), plus a SIGN OUT escape — NEVER the sole exit.
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact
//      haptic on submit; success on a found company, error on not-found / failure.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Code-entry boundary (the testable seam)

/// A company resolved from a crew code. Carries everything the confirm-company
/// screen (P5 part 2) needs to render + the join to write — persisted into form
/// data on `.found`.
struct FoundCompany: Equatable {
    let companyId: String
    let companyName: String
    let companyCode: String?
    let companyLogoUrl: String?
}

/// What a crew-code lookup resolved to. The screen branches on these; the gateway
/// produces them from the live `OnboardingManager`. Never thrown — failures map to
/// typed cases so the screen always has an outcome to branch on.
enum CodeEntryOutcome: Equatable {
    /// The code matched a company. `company` carries the id / name / code / logo for
    /// the confirm screen + the join.
    case found(FoundCompany)

    /// No company matched the code. Inline "check with your boss" error; NO nav.
    case notFound

    /// The lookup failed (network / server) — distinct from not-found so the copy is
    /// honest. Inline retry-able error; NO nav.
    case failed
}

/// The async boundary S4c-code funnels the lookup through. Implemented live by the
/// gateway (over `OnboardingManager.lookupCompanyByCode(_:)`); stubbed in tests.
@MainActor
protocol CodeEntryBoundary {
    /// Look up a company by crew code. `code` is whatever the user typed (the
    /// boundary / manager owns sanitisation — NO client format rejection).
    func lookUpCompany(code: String) async -> CodeEntryOutcome
}

// MARK: - S4c-code screen

struct CodeEntryStepView: View {

    /// The provenance the screen was entered with. Carried into the confirm advance
    /// so the confirm-company back-edge returns to the right origin (role pick vs
    /// the invite picker). The gateway reads it off the coordinator's current step.
    let provenance: CodeEntryProvenance

    /// The async lookup boundary. Injected so the screen never touches the RPC.
    let boundary: CodeEntryBoundary

    /// Persist a collected field into the coordinator's form data. The gateway wires
    /// this to `coordinator.update` — used to persist the typed code (kill-mid-flow
    /// resume) and the resolved company on `.found`.
    let onUpdateFormData: (@escaping (inout OnboardingFormData) -> Void) -> Void

    /// Company found → persist it + advance to `.confirmCompany(source:)`. The
    /// gateway wires the advance, carrying `provenance`.
    let onFound: (FoundCompany) -> Void

    /// Header Back per the back map. The gateway wires `coordinator.goBack()`
    /// (zeroInvites → role pick; fromPicker → invite picker).
    let onBack: () -> Void

    /// SIGN OUT escape — NEVER the sole exit (Back is always present too). The
    /// gateway wires the real auth signout.
    let onSignOut: () -> Void

    // MARK: Init

    init(
        provenance: CodeEntryProvenance,
        boundary: CodeEntryBoundary,
        onUpdateFormData: @escaping (@escaping (inout OnboardingFormData) -> Void) -> Void,
        onFound: @escaping (FoundCompany) -> Void,
        onBack: @escaping () -> Void,
        onSignOut: @escaping () -> Void
    ) {
        self.provenance = provenance
        self.boundary = boundary
        self.onUpdateFormData = onUpdateFormData
        self.onFound = onFound
        self.onBack = onBack
        self.onSignOut = onSignOut
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture
    /// the entered / loading / error states (otherwise only reachable after an async
    /// interaction). DEBUG-only; never used by the live gateway.
    init(
        provenance: CodeEntryProvenance = .zeroInvites,
        boundary: CodeEntryBoundary,
        previewCode: String = "",
        previewIsLooking: Bool = false,
        previewError: String? = nil
    ) {
        self.provenance = provenance
        self.boundary = boundary
        self.onUpdateFormData = { _ in }
        self.onFound = { _ in }
        self.onBack = {}
        self.onSignOut = {}
        _code = State(initialValue: previewCode)
        _isLooking = State(initialValue: previewIsLooking)
        _errorMessage = State(initialValue: previewError)
        _hasAppeared = State(initialValue: true)
    }
    #endif

    // MARK: Field state

    @State private var code = ""

    /// An inline error (not-found / failure). Cleared on the next attempt or edit.
    @State private var errorMessage: String?

    /// True while the lookup is in flight — drives the CTA spinner + gate.
    @State private var isLooking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    /// it WITHOUT the enclosing `ScrollView`.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            instruction
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            codeBlock
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
    var snapshotBody: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()
            scrollContent
        }
    }
    #endif

    // MARK: - Header (Back per back map + SIGN OUT escape)

    private var header: some View {
        OnboardingStepHeader(
            title: "Join your crew",
            backLabel: backLabel,
            onBack: onBack,
            onSignOut: onSignOut
        )
    }

    /// The previous-screen short name for the Back control — depends on provenance
    /// (matches the back map: zeroInvites → role pick; fromPicker → the picker).
    private var backLabel: String {
        switch provenance {
        case .zeroInvites: return "Role"
        case .fromPicker:  return "Invites"
        }
    }

    // MARK: - Instruction

    private var instruction: some View {
        Text("Enter the code your boss gave you.")
            .font(OPSStyle.Typography.body) // Mohave 16pt
            .foregroundColor(OPSStyle.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Enter the code your boss gave you")
    }

    // MARK: - Code input (shared bracketed entry glyph)

    private var codeBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// CREW CODE")
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(1.4)
                .accessibilityHidden(true) // the entry component carries the label

            // The SHARED entry glyph — identical bracketed treatment to the owner's
            // share screen. Auto-uppercases + strips whitespace (canonical code).
            OnboardingCodeEntry(
                code: $code,
                placeholder: "ENTER CODE",
                submitLabel: .join,
                onSubmit: { attemptLookup() }
            )
            .onChange(of: code) { _, newValue in
                // Persist as the user types (kill-mid-flow resume) and clear any
                // stale error once they edit.
                persistCode(newValue)
                if errorMessage != nil { errorMessage = nil }
            }

            if let errorMessage {
                Text("// ERROR — \(errorMessage.uppercased())")
                    .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error. \(errorMessage)")
            }
        }
    }

    // MARK: - CTA

    private var ctaBlock: some View {
        OnboardingPrimaryCTA(
            title: "Join crew",
            isEnabled: isFormValid,
            isLoading: isLooking
        ) {
            attemptLookup()
        }
    }

    // MARK: - Validation (non-empty ONLY — no client format rejection)

    /// The trimmed code — the single source of truth for the gate + lookup.
    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The CTA is live only when a non-empty code is present. The ONLY client gate
    /// (server lookup decides validity). `internal` so the gate is unit-testable.
    var isFormValid: Bool {
        CodeEntryValidation(code: code).isFormValid
    }

    // MARK: - Actions

    /// Crew-code lookup. Gates on non-empty (the CTA gate already enforces this),
    /// then funnels through the boundary and branches on the outcome via the pure
    /// router. No client format rejection — whatever was typed goes to the server.
    func attemptLookup() {
        errorMessage = nil
        guard isFormValid else { return }
        guard !isLooking else { return }

        isLooking = true
        OnboardingHaptics.commit()

        let typed = trimmedCode
        persistCode(typed)

        Task { @MainActor in
            let outcome = await boundary.lookUpCompany(code: typed)
            isLooking = false
            handle(outcome)
        }
    }

    /// Route a lookup outcome. The `.found` case is the only navigation — delegated
    /// to the pure `CodeEntryOutcomeRouter` so it is unit-testable; the error cases
    /// set local state here.
    func handle(_ outcome: CodeEntryOutcome) {
        let navigated = CodeEntryOutcomeRouter.route(
            outcome,
            onFound: { company in
                OnboardingHaptics.success()
                persistCompany(company)
                onFound(company)
            }
        )
        guard !navigated else { return }

        OnboardingHaptics.error()
        switch outcome {
        case .notFound:
            errorMessage = "no company found with that code. check with your boss"
        case .failed:
            errorMessage = "couldn't reach the server — try again"
        case .found:
            break // handled by the router
        }
    }

    // MARK: - Form-data persistence

    /// Persist the typed code (trimmed → nil-if-blank) so a kill mid-flow resumes.
    private func persistCode(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.enteredCrewCode = trimmed.isEmpty ? nil : trimmed }
    }

    /// Persist the resolved company so the confirm screen renders it WITHOUT a
    /// re-fetch and a kill mid-flow resumes with it. This path is a manually entered
    /// code (no invitation), so `joinInvitationId` is cleared.
    private func persistCompany(_ company: FoundCompany) {
        onUpdateFormData {
            $0.joinCompanyId = company.companyId
            $0.joinCompanyName = company.companyName
            $0.joinCompanyCode = company.companyCode
            $0.joinCompanyLogoUrl = company.companyLogoUrl
            $0.joinInvitationId = nil
        }
    }
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes the ONE host-navigating outcome (`.found`) and reports whether it
/// handled the outcome. The error cases are local-state-only and return `false` so
/// the caller applies them to `@State`. Extracted so the navigation branch is
/// testable without rendering.
enum CodeEntryOutcomeRouter {
    /// - Returns: `true` when the outcome was the host-navigation effect (and the
    ///   `onFound` closure was invoked with the resolved company); `false` for the
    ///   local-state-only error cases.
    @discardableResult
    static func route(
        _ outcome: CodeEntryOutcome,
        onFound: (FoundCompany) -> Void
    ) -> Bool {
        switch outcome {
        case .found(let company):
            onFound(company)
            return true
        case .notFound, .failed:
            return false
        }
    }
}

// MARK: - Pure validation (no SwiftUI, fully unit-testable)

/// The complete validation surface for S4c-code: a NON-EMPTY code is the ONLY
/// client gate. There is deliberately NO format rule — legacy `PREFIX-XXXXXX` codes
/// must be accepted; the server lookup decides validity.
struct CodeEntryValidation: Equatable {
    let code: String

    var trimmedCode: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isFormValid: Bool { !trimmedCode.isEmpty }
}

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed outcome.
private struct PreviewCodeEntryBoundary: CodeEntryBoundary {
    var outcome: CodeEntryOutcome = .found(
        FoundCompany(companyId: "c1", companyName: "Sweet Deck & Rail", companyCode: "BR8K90ZT", companyLogoUrl: nil)
    )
    func lookUpCompany(code: String) async -> CodeEntryOutcome { outcome }
}

#Preview("CodeEntryStepView — default") {
    CodeEntryStepView(
        provenance: .zeroInvites,
        boundary: PreviewCodeEntryBoundary(),
        onUpdateFormData: { _ in },
        onFound: { _ in },
        onBack: {},
        onSignOut: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("CodeEntryStepView — not found") {
    CodeEntryStepView(
        provenance: .fromPicker,
        boundary: PreviewCodeEntryBoundary(),
        previewCode: "BR8K90ZT",
        previewError: "no company found with that code. check with your boss"
    )
    .preferredColorScheme(.dark)
}
#endif
