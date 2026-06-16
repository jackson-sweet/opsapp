//
//  EmergencyContactStepView.swift
//  OPS
//
//  Onboarding rebuild P5 — S7c (Emergency contact): the FINAL crew-onboarding
//  screen. Truly OPTIONAL — the worker can SKIP it entirely (advance to the
//  completion gate WITHOUT saving), or fill it in and FINISH. Both paths land on
//  `.completionGate`; Back returns to `.profile` (`emergencyContact.backEdge=profile`).
//
//  Design spec §4.2 S7c:
//    • A visible SKIP secondary action → advance(.completionGate) with NO save.
//    • Contact name + phone fields + relationship CHIPS (PARENT / SPOUSE / SIBLING /
//      FRIEND / OTHER — single-select). Selecting a chip deselects the others;
//      tapping the selected chip clears it.
//    • Copy benchmark kept verbatim: "In case something happens on the job."
//    • FINISH primary CTA: medium commit haptic ON TAP; saves the emergency fields via
//      the boundary (`saveEmployeeProfile`), then advance(.completionGate). The SUCCESS
//      notification haptic fires AT the completion gate (its design) — FINISH is a
//      COMMIT haptic, not a success.
//
//  SAVE CONTRACT — the screen owns NO data logic and reaches NO singletons. The save
//  funnels through an injected `EmergencyContactBoundary` returning an
//  `EmergencyContactSaveOutcome`; the navigation decision is the pure
//  `EmergencyContactOutcomeRouter`. On `.saved` → onFinish (gateway advances to
//  `.completionGate`). On `.failed` → an inline retry-able error, NO nav. The boundary
//  wraps `OnboardingManager.saveEmployeeProfile` (carrying the names/phone S6c already
//  persisted, plus the emergency fields).
//
//  Design-system conformance (`DESIGN.md` + `mobile/MOBILE.md`):
//    • Pure-black canvas, glass + hairlines, ZERO shadows. Accent (`opsAccent`) appears
//      ONLY on the one primary CTA (FINISH, via the shared component). The chips,
//      fields, SKIP, and error lines are all neutral / rose — never accent.
//    • Relationship chips use the §4.3 chip visual: `chipRadius` (4pt), surfaceInput
//      fill, hairline border, 36pt min height (the one sanctioned sub-44pt target).
//      NEVER a Capsule / pill.
//    • One easing curve; honored only when Reduce Motion is off. Medium-impact haptic
//      on FINISH; light selection tick on a chip / SKIP.
//  Every literal traces to an `OPSStyle` token. Copy locked via ops-copywriter.
//

import SwiftUI

// MARK: - Emergency-contact boundary (the testable seam)

/// What an emergency-contact save resolved to. The screen branches on these; the
/// gateway produces them from the live `OnboardingManager`. Never thrown — a failure
/// maps to `.failed` so the screen always has an outcome to surface.
enum EmergencyContactSaveOutcome: Equatable {
    /// The emergency fields were written. The gateway advances to `.completionGate`.
    case saved

    /// The save failed. Surface inline, retry-able, never silent. `message` is the
    /// bare phrase the view prefixes with `// ERROR — ` and uppercases.
    case failed(message: String)
}

/// The async boundary S7c funnels the OPTIONAL save through. Implemented live by the
/// gateway (over `OnboardingManager.saveEmployeeProfile`); stubbed in tests.
/// `@MainActor` because the live manager is main-actor isolated. The SKIP path does
/// NOT touch this boundary at all (it advances without saving).
@MainActor
protocol EmergencyContactBoundary {
    /// Persist the emergency contact (name / phone / relationship — any of which may be
    /// empty). Returns `.saved` on success, `.failed(message:)` on any error.
    func saveEmergencyContact(name: String, phone: String, relationship: String) async -> EmergencyContactSaveOutcome
}

// MARK: - S7c screen

struct EmergencyContactStepView: View {

    /// The async boundary. Injected so the screen never touches an RPC. Unused on the
    /// SKIP path (skip advances without saving).
    let boundary: EmergencyContactBoundary

    /// Persist a collected field into the coordinator's form data. The gateway wires
    /// this to `coordinator.update`. Persists name/phone/relationship as the user types
    /// / selects (resume after a kill).
    let onUpdateFormData: (@escaping (inout OnboardingFormData) -> Void) -> Void

    /// FINISH save committed → the gateway advances to `.completionGate`.
    let onFinish: () -> Void

    /// SKIP → the gateway advances to `.completionGate` WITHOUT saving.
    let onSkip: () -> Void

    /// Header Back → profile (`emergencyContact.backEdge=profile`). The gateway wires
    /// `coordinator.goBack()`.
    let onBack: () -> Void

    // MARK: Init

    init(
        boundary: EmergencyContactBoundary,
        onUpdateFormData: @escaping (@escaping (inout OnboardingFormData) -> Void) -> Void,
        onFinish: @escaping () -> Void,
        onSkip: @escaping () -> Void,
        onBack: @escaping () -> Void
    ) {
        self.boundary = boundary
        self.onUpdateFormData = onUpdateFormData
        self.onFinish = onFinish
        self.onSkip = onSkip
        self.onBack = onBack
    }

    #if DEBUG
    /// Snapshot/preview seam — seeds the visual `@State` so a renderer can capture the
    /// default / filled / saving / error states a renderer can't otherwise drive.
    /// DEBUG-only; never used by the live gateway.
    init(
        boundary: EmergencyContactBoundary,
        previewContactName: String = "",
        previewContactPhone: String = "",
        previewRelationship: EmergencyRelationship? = nil,
        previewSaveError: String? = nil,
        previewIsSaving: Bool = false
    ) {
        self.boundary = boundary
        self.onUpdateFormData = { _ in }
        self.onFinish = {}
        self.onSkip = {}
        self.onBack = {}
        _contactName = State(initialValue: previewContactName)
        _contactPhone = State(initialValue: previewContactPhone)
        _relationship = State(initialValue: previewRelationship)
        _saveError = State(initialValue: previewSaveError)
        _isSaving = State(initialValue: previewIsSaving)
        _hasAppeared = State(initialValue: true) // settle the entrance for snapshots
    }
    #endif

    // MARK: Field state

    @State private var contactName = ""
    @State private var contactPhone = ""

    /// The single selected relationship (optional). Single-select: tapping the selected
    /// chip clears it. Persisted into `formData.emergencyContactRelationship`.
    @State private var relationship: EmergencyRelationship?

    /// A surfaced save failure — rendered inline above the CTA, never silent. Cleared
    /// on the next attempt.
    @State private var saveError: String?

    /// True while the save is in flight — drives the CTA spinner + gate.
    @State private var isSaving = false

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
            runEntrance()
        }
    }

    /// The full vertical stack. Extracted so the DEBUG snapshot harness can render it
    /// WITHOUT the enclosing `ScrollView` (`ImageRenderer` reports zero intrinsic size
    /// for a `ScrollView`). The live screen always wraps this in the scroll view.
    private var scrollContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            header

            subline
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            fieldsBlock
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            relationshipBlock
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

    // MARK: - Header (Back → profile)

    private var header: some View {
        OnboardingStepHeader(
            title: "Emergency contact",
            backLabel: "Profile",
            onBack: onBack
        )
    }

    // MARK: - Subline (the benchmark copy, kept verbatim)

    private var subline: some View {
        Text("In case something happens on the job.")
            .font(OPSStyle.Typography.body) // Mohave 16pt
            .foregroundColor(OPSStyle.Colors.text2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("In case something happens on the job")
    }

    // MARK: - Contact fields (all optional)

    private var fieldsBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            OPSOnboardingField(
                label: "Contact name",
                text: $contactName,
                placeholder: "Their name",
                kind: .name,
                submitLabel: .next
            )
            .onChange(of: contactName) { _, newValue in persistName(newValue) }

            OPSOnboardingField(
                label: "Contact phone",
                text: $contactPhone,
                placeholder: "Their number",
                kind: .phone,
                submitLabel: .done
            )
            .onChange(of: contactPhone) { _, newValue in persistPhone(newValue) }
        }
    }

    // MARK: - Relationship chips (single-select)

    private var relationshipBlock: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// RELATIONSHIP — OPTIONAL")
                .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                .foregroundColor(OPSStyle.Colors.text3)
                .tracking(1.4)
                .accessibilityLabel("Relationship, optional")

            RelationshipChipFlow(
                options: EmergencyRelationship.allCases,
                selected: relationship,
                onSelect: { option in
                    OnboardingHaptics.selection()
                    relationship = (relationship == option) ? nil : option
                    persistRelationship(relationship)
                }
            )
        }
    }

    // MARK: - CTA block (FINISH primary + SKIP secondary + inline error)

    private var ctaBlock: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            if let saveError {
                Text("// ERROR — \(saveError.uppercased())")
                    .font(OPSStyle.Typography.metadata) // JetBrains Mono 11pt
                    .tracking(1.4)
                    .foregroundColor(OPSStyle.Colors.rose)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Error. \(saveError)")
            }

            OnboardingPrimaryCTA(
                title: "Finish",
                trailingArrow: false,
                isLoading: isSaving
            ) {
                attemptFinish()
            }

            OnboardingSecondaryCTA(title: "Skip") {
                guard !isSaving else { return }
                onSkip()
            }
        }
    }

    // MARK: - Finish (the optional save)

    /// The FINISH commit. Medium haptic ON TAP, loading state during the async, then
    /// branch on the outcome via the pure router: `.saved` → onFinish (gateway advances
    /// to `.completionGate`); `.failed` → inline error, NO nav. The completion gate
    /// fires the success haptic — FINISH is a COMMIT haptic only.
    func attemptFinish() {
        guard !isSaving else { return }
        saveError = nil

        let name = contactName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = contactPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let rel = relationship?.rawValue ?? ""

        persistName(name)
        persistPhone(phone)
        persistRelationship(relationship)

        isSaving = true
        OnboardingHaptics.commit() // medium impact ON TAP

        Task { @MainActor in
            let outcome = await boundary.saveEmergencyContact(name: name, phone: phone, relationship: rel)
            isSaving = false
            handle(outcome)
        }
    }

    /// Route a save outcome. `.saved` is the only navigation — delegated to the pure
    /// `EmergencyContactOutcomeRouter` so it is unit-testable; the error case sets
    /// local state here.
    func handle(_ outcome: EmergencyContactSaveOutcome) {
        let navigated = EmergencyContactOutcomeRouter.route(outcome, onFinish: onFinish)
        guard !navigated else { return }

        if case .failed(let message) = outcome {
            saveError = message
        }
    }

    // MARK: - Entrance

    private func runEntrance() {
        guard !hasAppeared else { return }
        if reduceMotion {
            hasAppeared = true
        } else {
            withAnimation(OPSStyle.Animation.page) { hasAppeared = true }
        }
    }

    // MARK: - Form-data persistence (trimmed → nil-if-blank)

    private func persistName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.emergencyContactName = trimmed.isEmpty ? nil : trimmed }
    }

    private func persistPhone(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        onUpdateFormData { $0.emergencyContactPhone = trimmed.isEmpty ? nil : trimmed }
    }

    private func persistRelationship(_ value: EmergencyRelationship?) {
        onUpdateFormData { $0.emergencyContactRelationship = value?.rawValue }
    }
}

// MARK: - Relationship (the single-select option set, unit-testable)

/// The emergency-contact relationship options. Persisted as the raw (sentence-case)
/// value into `formData.emergencyContactRelationship`; the chip renders it uppercased.
/// `CaseIterable` so the chip flow renders all options in a stable order.
enum EmergencyRelationship: String, CaseIterable, Equatable {
    case parent = "Parent"
    case spouse = "Spouse"
    case sibling = "Sibling"
    case friend = "Friend"
    case other = "Other"
}

// MARK: - Pure outcome routing (no SwiftUI, fully unit-testable)

/// Routes the ONE host-navigating outcome (`.saved`) and reports whether it handled
/// the outcome. The error case is local-state-only and returns `false` so the caller
/// applies it to `@State`. The house pattern (see `ProfileSaveOutcomeRouter`).
enum EmergencyContactOutcomeRouter {
    /// - Returns: `true` when the outcome was the host-navigation effect (and the
    ///   `onFinish` closure was invoked); `false` for the local-state-only error case.
    @discardableResult
    static func route(_ outcome: EmergencyContactSaveOutcome, onFinish: () -> Void) -> Bool {
        switch outcome {
        case .saved:
            onFinish()
            return true
        case .failed:
            return false
        }
    }
}

// MARK: - Relationship chip flow (wrap layout, single-select)

/// A wrapping row of single-select relationship chips. §4.3 chip visual: `chipRadius`,
/// surfaceInput fill, hairline border, 36pt min height (the one sanctioned sub-44pt
/// target). Selected chip brightens (surfaceActive + brighter border) — NO accent,
/// NEVER a Capsule. Mirrors the trade-chip pattern from `CompanyNameStepView`.
private struct RelationshipChipFlow: View {
    let options: [EmergencyRelationship]
    let selected: EmergencyRelationship?
    let onSelect: (EmergencyRelationship) -> Void

    var body: some View {
        FlowLayout(spacing: OPSStyle.Layout.spacing2) {
            ForEach(options, id: \.self) { option in
                RelationshipChip(
                    label: option.rawValue,
                    isSelected: selected == option,
                    action: { onSelect(option) }
                )
            }
        }
    }
}

private struct RelationshipChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.miniLabel) // JetBrains Mono 10pt — tactical tag voice
                .tracking(1.0)
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

// MARK: - Previews

#if DEBUG
/// A preview/stub boundary — no network. Returns a fixed outcome.
private struct PreviewEmergencyBoundary: EmergencyContactBoundary {
    var outcome: EmergencyContactSaveOutcome = .saved
    func saveEmergencyContact(name: String, phone: String, relationship: String) async -> EmergencyContactSaveOutcome { outcome }
}

#Preview("EmergencyContactStepView — default") {
    EmergencyContactStepView(
        boundary: PreviewEmergencyBoundary(),
        onUpdateFormData: { _ in },
        onFinish: {},
        onSkip: {},
        onBack: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("EmergencyContactStepView — filled") {
    EmergencyContactStepView(
        boundary: PreviewEmergencyBoundary(),
        previewContactName: "Mara Sweet",
        previewContactPhone: "778-535-7941",
        previewRelationship: .spouse
    )
    .preferredColorScheme(.dark)
}
#endif
