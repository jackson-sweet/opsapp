//
//  LeadFieldEdit.swift
//  OPS
//
//  Hold-to-edit for the lead dossier (bug b1d30fe8). Long-pressing a fact on
//  LeadDetailView turns it into its editor in place, instead of making the
//  operator hunt for an edit affordance and re-read a whole form to fix one
//  wrong field.
//
//  This EXTENDS two shipped patterns rather than inventing a third:
//
//    · bug c0ed9969 (ContactDetailView) — the inline-edit shape: a row swaps
//      to its input with check / cancel + a spinner while the write lands,
//      gated so an operator without edit rights never sees the affordance.
//    · bug a093d9cc (DaySheetLeadRow) — the gesture shape: ONE exclusive
//      gesture, `LongPress.exclusively(before: Tap)`, so a successful hold
//      consumes the release and editing can never also launch Maps or open
//      the client behind it.
//
//  THE GESTURE CONTRACT, stated once:
//
//      lead CARD long-press  = COPY   (unchanged — bug a093d9cc)
//      lead DOSSIER long-press = EDIT (here)
//
//  Different context, different job. The card is a scan surface you skim and
//  lift facts off; the dossier is the record you correct. Nothing on the card
//  changes.
//
//  THE FIELD SET — the correction set, not every field that exists: client,
//  address, contact (phone/email), job value, assigned-to. These are what a
//  person fixes when a lead arrives wrong or the email agent guessed badly.
//  STAGE and STATUS are deliberately absent: they carry real side effects
//  (conversion, won/lost, the auto-win trigger) and must not become casually
//  long-pressable.
//
//  HONEST FAILURE. Leads are network-only; every write here goes out over the
//  wire and can fail. When it does, the editor STAYS OPEN with the operator's
//  input intact and says so, with a retry. It never reverts silently, never
//  drops what was typed, and never repaints from the local guess — a save
//  repaints the field from the SERVER's returned row, so a write that landed
//  differently than intended is visible rather than assumed.
//

import SwiftUI
import CoreLocation

// MARK: - The correction set

/// A dossier fact the operator can correct in place.
///
/// Deliberately NOT the full column list. Stage and status are excluded: they
/// have their own guarded flows and side effects, and a casual hold must never
/// reach them.
enum LeadEditableField: String, Identifiable, CaseIterable {
    case client
    case address
    case contact
    case value
    case assignee

    var id: String { rawValue }

    /// VoiceOver action name. A long press is unreachable with VoiceOver on, so
    /// every hold-editable field also publishes the same capability as a named
    /// accessibility action.
    var accessibilityActionName: String {
        switch self {
        case .client:   return "Change client"
        case .address:  return "Edit address"
        case .contact:  return "Edit contact details"
        case .value:    return "Edit estimated value"
        case .assignee: return "Change assignee"
        }
    }
}

// MARK: - Press resolution (pure)

/// Which half of the exclusive gesture fired.
enum LeadFieldGesture: Equatable {
    case hold
    case tap
}

/// What a press on a dossier field resolves to. Exactly one effect per press —
/// the a093d9cc guarantee, restated for editing.
enum LeadFieldPressEffect: Equatable {
    /// Open this field's editor.
    case edit
    /// Run the field's own tap meaning (directions, open client, contact sheet).
    case activate
    /// Nothing to do.
    case ignore
}

/// Resolves a press into exactly one effect.
///
/// `offersEdit` is deliberately NOT a bare permission flag — every call site
/// feeds it `InfoRowEdit.offersLongPressEdit(canEdit:hasValue:isEditing:)`, the
/// same gate the project-details document already uses for its own CLIENT /
/// ADDRESS / NOTES rows. One rule answers both documents, so the two cannot
/// drift apart, and it carries the empty-field decision with it: a blank field
/// is NOT hold-editable, because a long press on nothing is undiscoverable. A
/// blank field shows an explicit ADD / ASSIGN chip instead.
///
/// A populated field is data being READ, so a tap keeps its own meaning —
/// directions, the client sheet, the contact dialog — and only a deliberate
/// hold corrects it. Popping a keyboard under a reading finger is hostile.
enum LeadFieldPress {
    static func resolve(
        _ gesture: LeadFieldGesture,
        offersEdit: Bool,
        hasTapAction: Bool
    ) -> LeadFieldPressEffect {
        switch gesture {
        case .hold:
            // The hold half is only ever attached when `offersEdit`; the guard
            // is restated here so the resolver is honest standalone.
            return offersEdit ? .edit : .ignore

        case .tap:
            return hasTapAction ? .activate : .ignore
        }
    }

    /// Whether the field is an interactive element AT ALL for this operator —
    /// what drives the VoiceOver button trait.
    ///
    /// A dossier fact that neither edits nor activates is prose, not a control,
    /// and must not announce itself as a button. This is why a viewer reading
    /// an estimated value hears a value, while an operator who can correct it
    /// hears a button.
    static func isInteractive(offersEdit: Bool, hasTapAction: Bool) -> Bool {
        offersEdit || hasTapAction
    }
}

// MARK: - Failure vocabulary (pure)

/// Why a field write did not land, in the app's existing error vocabulary
/// (the same classification `EditLeadSheet.simplifyError` uses, so one failure
/// reads the same wherever the operator meets it).
///
/// Rendered in the MOBILE.md §10 error shape: a `// ERROR — …` mono label, one
/// line of plain language, and a retry where retrying can actually help.
enum LeadFieldSaveFailure: Equatable {
    case offline
    case notAllowed
    case failed

    static func classify(_ error: Error) -> LeadFieldSaveFailure {
        let description = String(describing: error).lowercased()
        if description.contains("network")
            || description.contains("offline")
            || description.contains("connection")
            || description.contains("timed out")
            || description.contains("timeout") {
            return .offline
        }
        if description.contains("permission")
            || description.contains("denied")
            || description.contains("not authorized")
            || description.contains("unauthorized")
            || description.contains("row-level security") {
            return .notAllowed
        }
        return .failed
    }

    var label: String {
        switch self {
        case .notAllowed: return "// ERROR — NOT ALLOWED"
        case .offline, .failed: return "// ERROR — NOT SAVED"
        }
    }

    /// One line: what happened, and the reassurance that matters most here —
    /// the operator's typing is still on screen.
    var message: String {
        switch self {
        case .offline:    return "No signal. Nothing was lost."
        case .notAllowed: return "You do not have rights to change this."
        case .failed:     return "The change did not land. Nothing was lost."
        }
    }

    /// Retrying a permission refusal just fails again — offering it would be a
    /// lie. Offer it where it can actually work.
    var canRetry: Bool {
        switch self {
        case .offline, .failed: return true
        case .notAllowed:       return false
        }
    }
}

// MARK: - The change being written

/// One field's worth of correction, ready for the wire. Each case maps to a
/// narrow patch that emits explicit nulls for its OWN keys only, so clearing a
/// field persists and no concurrent edit to a neighbouring column is clobbered.
enum LeadFieldChange: Equatable {
    case address(String?, latitude: Double?, longitude: Double?)
    case contact(phone: String?, email: String?)
    case value(Double?)
    case client(id: String)
}

// MARK: - Value normalisation (pure)

/// Turns raw editor text into what actually goes on the wire.
enum LeadFieldValue {
    /// Trimmed-empty normalises to nil so the operator can CLEAR a field by
    /// saving it blank — the c0ed9969 rule.
    static func normalised(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Money in, money out. Shares `LeadForm`'s exact parse — including its
    /// numeric(12,2) ceiling guard — so the inline editor and the full edit
    /// sheet can never disagree about what a valid job value is.
    static func money(_ raw: String) -> Double? {
        var form = LeadForm()
        form.estimatedValue = raw
        return form.estimatedValueDouble
    }

    /// True when the text carries digits the parser then refused. A blank field
    /// is a deliberate clear, not a mistake; `$abc` or a 13-figure number is a
    /// mistake, and the operator should be told before the write goes out.
    static func moneyIsMalformed(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return money(raw) == nil
    }
}
// MARK: - Controller

/// Owns which editor is open, the write in flight, and the last failure.
/// One field at a time — nobody corrects two facts at once.
///
/// Deliberately NOT the owner of the typed text. Each editor holds its own
/// draft in local `@State`, for two reasons that both matter here:
///
///   1. Publishing every keystroke would re-render the whole dossier — map
///      hero, timeline, photo strip — on each character typed.
///   2. Local state is what makes the failure contract free rather than
///      engineered: a failed save leaves the editor mounted, so the operator's
///      input is simply still there. Nothing has to be "restored".
///
/// The write is injected so the failure path is testable without a network:
/// production hands in a closure over `OpportunityRepository`, a test hands in
/// one that throws.
@MainActor
final class LeadFieldEditController: ObservableObject {

    /// Which field's editor is open, or whose write is in flight.
    @Published private(set) var editing: LeadEditableField?
    @Published private(set) var isSaving = false
    @Published private(set) var failure: LeadFieldSaveFailure?

    /// Set once the operator completes any correction. The discovery hint
    /// retires on this — it has done its job.
    @Published private(set) var didCompleteAnEdit = false

    /// The client the picker handed back, held so RETRY re-attempts the
    /// operator's actual choice instead of asking them to pick again.
    @Published private(set) var pendingClientName: String?

    /// The exact change last attempted, so RETRY resends it byte for byte.
    private var lastChange: LeadFieldChange?

    let opportunity: Opportunity
    private let write: (LeadFieldChange) async throws -> Opportunity

    /// - Parameter write: performs the network write and returns the server's
    ///   authoritative row. Injected for testability.
    init(
        opportunity: Opportunity,
        write: @escaping (LeadFieldChange) async throws -> Opportunity
    ) {
        self.opportunity = opportunity
        self.write = write
    }

    /// Production wiring — every write goes through `OpportunityRepository`.
    /// Leads are network-only; there is no local store to fall back on, which
    /// is exactly why the failure path below has to be honest.
    convenience init(opportunity: Opportunity) {
        let companyId = opportunity.companyId
        let opportunityId = opportunity.id
        self.init(opportunity: opportunity) { change in
            let repository = OpportunityRepository(companyId: companyId)
            let dto: OpportunityDTO
            switch change {
            case let .address(address, latitude, longitude):
                dto = try await repository.update(
                    opportunityId,
                    patch: LeadAddressPatch(
                        address: address,
                        latitude: latitude,
                        longitude: longitude
                    )
                )
            case let .contact(phone, email):
                dto = try await repository.update(
                    opportunityId,
                    patch: LeadContactPatch(contactPhone: phone, contactEmail: email)
                )
            case let .value(amount):
                dto = try await repository.update(
                    opportunityId,
                    patch: LeadValuePatch(estimatedValue: amount)
                )
            case let .client(id):
                dto = try await repository.update(
                    opportunityId,
                    patch: LeadClientPatch(clientId: id)
                )
            }
            return dto.toModel()
        }
    }

    // MARK: Editor lifecycle

    /// Opens a field's editor. The editor seeds itself from the lead's CURRENT
    /// value — a correction starts from what is there, because the operator is
    /// fixing a character, not retyping a record.
    func begin(_ field: LeadEditableField) {
        guard editing != field else { return }
        failure = nil
        lastChange = nil
        pendingClientName = nil
        editing = field
    }

    func cancel() {
        editing = nil
        failure = nil
        isSaving = false
        lastChange = nil
        pendingClientName = nil
    }

    func isEditing(_ field: LeadEditableField) -> Bool { editing == field }

    func isSaving(_ field: LeadEditableField) -> Bool {
        editing == field && isSaving
    }

    /// The failure to render against a given field, scoped so one field's error
    /// can never appear under another.
    func failure(for field: LeadEditableField) -> LeadFieldSaveFailure? {
        editing == field ? failure : nil
    }

    // MARK: Committing

    /// ADDRESS. Clearing the street clears the pin with it — a coordinate with
    /// no address is a map hero pointing at nothing.
    func saveAddress(_ raw: String, latitude: Double?, longitude: Double?) async {
        let address = LeadFieldValue.normalised(raw)
        await commit(.address(
            address,
            latitude: address == nil ? nil : latitude,
            longitude: address == nil ? nil : longitude
        ))
    }

    /// PHONE + EMAIL together — one "how do I reach this person" fact.
    func saveContact(phone: String, email: String) async {
        await commit(.contact(
            phone: LeadFieldValue.normalised(phone),
            email: LeadFieldValue.normalised(email)
        ))
    }

    /// ESTIMATED VALUE. A refused parse never leaves the device: an honest
    /// block here beats a generic server error the operator cannot act on.
    func saveValue(_ raw: String) async {
        guard !LeadFieldValue.moneyIsMalformed(raw) else {
            failure = .failed
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        await commit(.value(LeadFieldValue.money(raw)))
    }

    /// The client picker handed back a choice. The row goes to work
    /// immediately; the picker has already closed behind it.
    func commitClient(id: String, name: String?) async {
        editing = .client
        pendingClientName = name
        await commit(.client(id: id))
    }

    /// RETRY from a failure line — resends the exact same change with the exact
    /// same input. The operator retypes nothing.
    func retry() async {
        guard let change = lastChange else { return }
        await commit(change)
    }

    private func commit(_ change: LeadFieldChange) async {
        guard !isSaving else { return }
        isSaving = true
        failure = nil
        lastChange = change

        do {
            let fresh = try await write(change)
            // Repaint from the SERVER's row, never from the local guess. If the
            // write landed differently than intended, the operator sees the
            // truth instead of a hopeful echo of their own typing.
            opportunity.apply(fresh)
            isSaving = false
            editing = nil
            lastChange = nil
            pendingClientName = nil
            didCompleteAnEdit = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // The app's standing lead-write contract: every surface holding
            // this lead hears that it changed. Skipping it because the shared
            // instance was already mutated in place is exactly how a stale
            // card outlives a correction.
            NotificationCenter.default.post(
                name: Notification.Name("LeadUpdatedSuccess"),
                object: nil,
                userInfo: ["leadId": opportunity.id]
            )
        } catch {
            // Editor stays open. Input stays put. The failure is stated, with a
            // retry that reuses what is already on screen.
            isSaving = false
            failure = LeadFieldSaveFailure.classify(error)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - The gesture

/// Attaches the dossier's hold-to-edit gesture to a field.
///
/// A real Button owns taps while a simultaneous hold opens editing. The hold
/// marks its release so the Button cannot also activate. When the operator has
/// no edit rights the hold is not attached at all — they keep the plain tap
/// rather than a dead affordance that teases.
private struct HoldToEditModifier: ViewModifier {
    let field: LeadEditableField
    /// `InfoRowEdit.offersLongPressEdit(...)` — permission AND a value to
    /// correct AND not already editing. See `LeadFieldPress`.
    let offersEdit: Bool
    /// Radius of the press tint. Must match the surface the field sits on, or
    /// a squarer tint peeks past a rounder card's clipped corners.
    let cornerRadius: CGFloat
    let onEdit: () -> Void
    let onActivate: (() -> Void)?

    /// Press-in feedback. The row tints the instant a finger lands, so a stray
    /// press REVEALS that the field is live — the quietest discovery channel
    /// there is, and it costs no chrome when nobody is touching the screen.
    @GestureState private var isPressing = false
    @State private var suppressNextActivation = false

    private var hasTapAction: Bool { onActivate != nil }

    func body(content: Content) -> some View {
        decorated(content)
            .accessibilityElement(children: .combine)
            .modifier(EditAffordanceAccessibility(
                offersEdit: offersEdit,
                isInteractive: LeadFieldPress.isInteractive(
                    offersEdit: offersEdit,
                    hasTapAction: hasTapAction
                ),
                actionName: field.accessibilityActionName,
                onEdit: onEdit
            ))
    }

    /// Press tint + hit shape, then exactly the gesture this operator is
    /// entitled to. Without edit rights the hold half is never attached: a
    /// viewer keeps the plain tap they have today, and a hold does nothing
    /// rather than dangling a disabled editor in front of them.
    @ViewBuilder
    private func decorated(_ content: Content) -> some View {
        let painted = content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isPressing ? OPSStyle.Colors.fillNeutralDim : Color.clear)
            )
            .animation(OPSStyle.Animation.hover, value: isPressing)
            .contentShape(Rectangle())

        if offersEdit, hasTapAction {
            Button(action: activateFromButton) {
                painted
            }
            .buttonStyle(.plain)
            .simultaneousGesture(longPressGesture)
        } else if offersEdit {
            painted.gesture(longPressGesture)
        } else if hasTapAction {
            Button(action: activateFromButton) {
                painted
            }
            .buttonStyle(.plain)
        } else {
            painted
        }
    }

    /// A real Button owns ordinary activation. The prior exclusive gesture
    /// waited on a long-press recognizer before considering the tap and could
    /// swallow the release entirely on physical devices. The long press now
    /// runs alongside the Button and suppresses only the activation generated
    /// by that same completed press.
    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: OPSStyle.Animation.longPressHold)
            .updating($isPressing) { value, state, _ in
                state = value
            }
            .onChanged { _ in
                suppressNextActivation = true
            }
            .onEnded { _ in
                perform(.hold)
                DispatchQueue.main.async {
                    suppressNextActivation = false
                }
            }
    }

    private func activateFromButton() {
        guard !suppressNextActivation else { return }
        perform(.tap)
    }

    private func perform(_ gesture: LeadFieldGesture) {
        switch LeadFieldPress.resolve(
            gesture,
            offersEdit: offersEdit,
            hasTapAction: hasTapAction
        ) {
        case .edit:
            // Medium impact: a commit, per the app's haptic contract. It is
            // also the signal that the hold WORKED, before the editor paints.
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onEdit()
        case .activate:
            onActivate?()
        case .ignore:
            break
        }
    }
}

/// Publishes the edit affordance to VoiceOver ONLY where it actually exists.
///
/// The permission rule has to hold for assistive technology too. Listing "Edit
/// address" in the rotor for an operator who cannot edit is the same broken
/// promise as a greyed-out button — worse, because the action appears to be
/// offered and then silently does nothing. A viewer gets the button trait only
/// where the field genuinely does something on tap, and no edit action at all.
private struct EditAffordanceAccessibility: ViewModifier {
    let offersEdit: Bool
    let isInteractive: Bool
    let actionName: String
    let onEdit: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if offersEdit {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Touch and hold to edit.")
                .accessibilityAction(named: Text(actionName), onEdit)
        } else if isInteractive {
            content.accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}

extension View {
    /// Dossier field: tap keeps its meaning, hold corrects it.
    ///
    /// - Parameters:
    ///   - offersEdit: pass `InfoRowEdit.offersLongPressEdit(canEdit:hasValue:
    ///     isEditing:)` — the shared gate the project-details document uses for
    ///     the same job. Blank fields are excluded by design; they carry an
    ///     explicit ADD / ASSIGN chip instead of a hidden gesture.
    ///   - cornerRadius: radius of the press tint — match the surface the
    ///     field sits on (an L2 nested card is `cardRadius`, a bare row is
    ///     `cornerRadius`).
    ///   - onActivate: the field's own tap meaning, or nil when it has none.
    func holdToEdit(
        _ field: LeadEditableField,
        offersEdit: Bool,
        cornerRadius: CGFloat = OPSStyle.Layout.cornerRadius,
        onEdit: @escaping () -> Void,
        onActivate: (() -> Void)? = nil
    ) -> some View {
        modifier(HoldToEditModifier(
            field: field,
            offersEdit: offersEdit,
            cornerRadius: cornerRadius,
            onEdit: onEdit,
            onActivate: onActivate
        ))
    }
}

// MARK: - Discovery hint

/// The one-time teach for hold-to-edit.
///
/// A gesture nobody knows about is a feature nobody has. This is the smallest
/// honest fix: ONE mono line on the DETAILS header, shown to an operator who
/// can actually edit, for their first few dossiers — and gone forever the
/// moment they complete a correction. No setting, no dismiss button, no
/// announcement. It teaches once and then gets out of the way.
enum LeadHoldHint {
    static let storageKey = "leads_hold_to_edit_hint"
    /// Openings the hint survives before retiring on its own, for an operator
    /// who never tries the gesture.
    static let showLimit = 5

    static let label = "HOLD TO EDIT"

    static func shouldShow(state: Int, canEdit: Bool) -> Bool {
        canEdit && state < showLimit
    }

    /// Advance on a dossier open.
    static func advanced(_ state: Int) -> Int {
        min(state + 1, showLimit)
    }

    /// The operator corrected something — the hint has done its job.
    static func retired() -> Int { showLimit }
}

// MARK: - Editor chrome

/// The shared foot of every inline editor: cancel / confirm, the saving
/// spinner, and the failure line. One anatomy so all three inline editors
/// behave identically under the operator's thumb.
struct LeadInlineEditControls: View {
    let isSaving: Bool
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .tint(OPSStyle.Colors.text2)
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
            } else {
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.sm,
                            weight: .semibold
                        ))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel edit")

                Button(action: onSave) {
                    Image(systemName: "checkmark")
                        .font(.system(
                            size: OPSStyle.Layout.IconSize.sm,
                            weight: .semibold
                        ))
                        .foregroundColor(
                            canSave ? OPSStyle.Colors.text : OPSStyle.Colors.textMute
                        )
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .accessibilityLabel("Save")
            }
        }
    }
}

/// The failure line under an open editor — MOBILE.md §10 error shape.
///
/// This is the load-bearing half of the honest-failure contract: the editor is
/// still open above it with the operator's input untouched, and this states
/// what happened and hands back a retry that reuses that input.
struct LeadInlineEditError: View {
    let failure: LeadFieldSaveFailure
    let onRetry: () -> Void

    static let accessibilityID = "lead-inline-edit-error"

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(failure.label)
                .font(OPSStyle.Typography.miniLabelBold)
                .kerning(1.4)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.roseTextM)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(failure.message)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                if failure.canRetry {
                    Button(action: onRetry) {
                        Text("RETRY")
                            .font(OPSStyle.Typography.miniLabelBold)
                            .kerning(1.4)
                            .textCase(.uppercase)
                            .foregroundColor(OPSStyle.Colors.text)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Retry save")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, OPSStyle.Layout.spacing2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(Self.accessibilityID)
    }
}

// MARK: - Money input

/// Money the operator types. JetBrains Mono, tabular — a job value is a number
/// and numbers are mono on every OPS surface. Chrome matches the lead form's
/// 48pt input exactly so the inline editor and the full sheet feel like one
/// app.
struct LeadMoneyInput: View {
    @Binding var text: String
    var isMalformed: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("$")
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.textMute)

            TextField("", text: $text, prompt:
                Text("14,200")
                    .font(OPSStyle.Typography.dataValueLg)
                    .foregroundColor(OPSStyle.Colors.textMute)
            )
            .font(OPSStyle.Typography.dataValueLg)
            .monospacedDigit()
            .foregroundColor(OPSStyle.Colors.text)
            .tint(OPSStyle.Colors.text)
            .keyboardType(.decimalPad)
            .focused($isFocused)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(height: OPSStyle.Layout.inputHeight)
        .background(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.buttonRadius,
                style: .continuous
            )
            .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.buttonRadius,
                style: .continuous
            )
            .strokeBorder(borderColor, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .animation(OPSStyle.Animation.hover, value: isFocused)
        .onAppear { isFocused = true }
        .accessibilityLabel("Estimated value in dollars")
    }

    /// Focus brightens the hairline; a refused parse turns it rose. No accent
    /// on focus — accent is CTA-only (DESIGN.md §9).
    private var borderColor: Color {
        if isMalformed { return OPSStyle.Colors.roseLineM }
        return isFocused ? OPSStyle.Colors.inputFieldBorderFocus : OPSStyle.Colors.line
    }
}

// MARK: - Inline editors

// Each editor holds its OWN draft. That is what makes the failure contract
// free rather than engineered: a failed write leaves the editor mounted, so
// what the operator typed is simply still on screen. Nothing is restored,
// because nothing was ever thrown away.

/// ADDRESS — the shared MapKit autocomplete every other address input in the
/// app uses (projects, clients, site visits, company setup). A lead address is
/// captured exactly the way every other address is, coordinates included, so
/// the map hero and directions keep working after a correction.
struct LeadAddressInlineEditor: View {
    @ObservedObject var controller: LeadFieldEditController

    @State private var draft: String
    @State private var latitude: Double?
    @State private var longitude: Double?
    /// The string the coordinates belong to. Any divergence nulls them, so
    /// stale geo can never outlive a hand-typed street — `LeadForm`'s rule.
    @State private var resolvedAddress: String?

    init(controller: LeadFieldEditController) {
        self.controller = controller
        _draft = State(initialValue: controller.opportunity.address ?? "")
        _latitude = State(initialValue: controller.opportunity.latitude)
        _longitude = State(initialValue: controller.opportunity.longitude)
        _resolvedAddress = State(initialValue: controller.opportunity.address)
    }

    private var isSaving: Bool { controller.isSaving(.address) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                AddressAutocompleteField(
                    address: $draft,
                    placeholder: "3185 Fairview Rd",
                    autofocus: true,
                    onAddressSelected: { resolved, coordinate in
                        resolvedAddress = resolved
                        latitude = coordinate?.latitude
                        longitude = coordinate?.longitude
                    }
                )
                .frame(minHeight: OPSStyle.Layout.inputHeight)
                .disabled(isSaving)

                LeadInlineEditControls(
                    isSaving: isSaving,
                    canSave: true,
                    onCancel: { controller.cancel() },
                    onSave: { save() }
                )
            }
            .onChange(of: draft) { _, newValue in
                guard newValue != resolvedAddress else { return }
                latitude = nil
                longitude = nil
            }

            if let failure = controller.failure(for: .address) {
                LeadInlineEditError(failure: failure) { save() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        Task {
            await controller.saveAddress(
                draft,
                latitude: latitude,
                longitude: longitude
            )
        }
    }
}

/// CONTACT — phone and email, side by side, exactly as the lead form pairs
/// them. They travel together because they are one fact: how this person is
/// reached. Correcting one without seeing the other is how you end up with a
/// good phone and a dead email.
struct LeadContactInlineEditor: View {
    @ObservedObject var controller: LeadFieldEditController

    @State private var phone: String
    @State private var email: String

    init(controller: LeadFieldEditController) {
        self.controller = controller
        _phone = State(initialValue: controller.opportunity.contactPhone ?? "")
        _email = State(initialValue: controller.opportunity.contactEmail ?? "")
    }

    private var isSaving: Bool { controller.isSaving(.contact) }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(alignment: .bottom, spacing: OPSStyle.Layout.spacing2_5) {
                LeadField(label: "PHONE") {
                    LeadTextInput(
                        placeholder: "604-555-0142",
                        text: $phone,
                        keyboard: .phonePad,
                        textContentType: .telephoneNumber
                    )
                }
                LeadField(label: "EMAIL") {
                    LeadTextInput(
                        placeholder: "—",
                        text: $email,
                        keyboard: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )
                }
            }
            .disabled(isSaving)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Spacer(minLength: 0)
                LeadInlineEditControls(
                    isSaving: isSaving,
                    canSave: true,
                    onCancel: { controller.cancel() },
                    onSave: { save() }
                )
            }

            if let failure = controller.failure(for: .contact) {
                LeadInlineEditError(failure: failure) { save() }
            }
        }
        // Deliberately no autofocus. Two fields means no single obvious
        // target, and a keyboard that guesses wrong covers the field the
        // operator actually came to fix.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        Task { await controller.saveContact(phone: phone, email: email) }
    }
}

/// ESTIMATED VALUE — a full-width money input that opens BENEATH the KPI strip
/// rather than inside it.
///
/// The strip is a three-column scan surface; one of its cells is ~110pt wide,
/// which is a poor place to type a number and a worse place to watch the other
/// two columns reflow around a keyboard. The strip stays whole, so the operator
/// keeps the context they were reading (value next to next-touch and source),
/// and the editor opens under it with room to work.
struct LeadValueInlineEditor: View {
    @ObservedObject var controller: LeadFieldEditController

    @State private var draft: String

    init(controller: LeadFieldEditController) {
        self.controller = controller
        _draft = State(initialValue: controller.opportunity.estimatedValue
            .map(LeadForm.formatValueInput) ?? "")
    }

    private var isSaving: Bool { controller.isSaving(.value) }
    private var isMalformed: Bool { LeadFieldValue.moneyIsMalformed(draft) }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            LeadField(label: "ESTIMATED VALUE") {
                HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                    LeadMoneyInput(text: $draft, isMalformed: isMalformed)
                        .disabled(isSaving)

                    LeadInlineEditControls(
                        isSaving: isSaving,
                        canSave: !isMalformed,
                        onCancel: { controller.cancel() },
                        onSave: { save() }
                    )
                }
            }

            if isMalformed {
                Text("Numbers only.")
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.roseTextM)
            }

            if let failure = controller.failure(for: .value) {
                LeadInlineEditError(failure: failure) { save() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func save() {
        Task { await controller.saveValue(draft) }
    }
}
