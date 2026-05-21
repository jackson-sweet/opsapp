//
//  LeadFormView.swift
//  OPS
//
//  Shared form view consumed by AddLeadSheet and EditLeadSheet. Phase 4 of the
//  LEADS tab rebuild (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md
//  §8.2). The form primitives (LeadField, LeadTextInput, LeadTextArea,
//  LeadChipPicker, SheetCTAButton, FlowLayout) are intentionally private to
//  this file — they exist only to compose lead sheets. If JobBoard or another
//  surface needs them later, lift to `Styles/Components/SheetFormPrimitives.swift`.
//
//  Field order matches `prototypes/app/sheets.jsx` § LeadForm:
//
//    1. CONTACT NAME (required text)
//    2. PHONE + EMAIL (paired, optional)
//    3. SITE ADDRESS
//    4. JOB DESCRIPTION → maps to Opportunity.title
//    5. ESTIMATED VALUE (leading $)
//    6. SOURCE (chip group)
//    7. STAGE (chip group, 6 open stages, default newLead)
//    8. PRIORITY (chip group, LOW/MEDIUM/HIGH, default MEDIUM)
//    9. NOTES (textarea, 3 rows)
//   10. DANGER ZONE (Edit-only — archive + delete buttons)
//

import SwiftUI

// MARK: - Form state

/// Mutable form state shared by Add + Edit. Source / stage / priority are
/// stored as the canonical lower-snake-case strings so the same struct serializes
/// straight to the DTO without re-encoding.
struct LeadForm {
    var contactName: String = ""
    var phone: String = ""
    var email: String = ""
    var address: String = ""
    var title: String = ""                 // job description → Opportunity.title
    var estimatedValue: String = ""        // string for input handling; parsed on save
    var source: String = "web_form"
    var stage: PipelineStage = .newLead
    var priority: String = "med"
    var notes: String = ""

    /// Hydrate from an existing opportunity for the Edit path.
    init(from opportunity: Opportunity? = nil) {
        guard let opportunity else { return }
        contactName = opportunity.contactName
        phone = opportunity.contactPhone ?? ""
        email = opportunity.contactEmail ?? ""
        address = opportunity.address ?? ""
        title = opportunity.title ?? ""
        if let v = opportunity.estimatedValue {
            estimatedValue = LeadForm.formatValueInput(v)
        }
        source = opportunity.source ?? "web_form"
        stage = opportunity.stage.isTerminal ? .newLead : opportunity.stage
        priority = opportunity.priority ?? "med"
        notes = opportunity.descriptionText ?? ""
    }

    /// Strip non-digits-and-dot from the value string, return a Double.
    /// Returns nil for empty input so the DTO can carry through a null instead
    /// of writing zero (which would be a real value).
    var estimatedValueDouble: Double? {
        let stripped = estimatedValue
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return nil }
        return Double(stripped)
    }

    /// Format a Double back into the input string. Whole numbers render without
    /// trailing `.0`; cents round-trip via locale-free string interpolation.
    static func formatValueInput(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        }
        return String(value)
    }
}

// MARK: - LeadFormView

struct LeadFormView: View {
    @Binding var form: LeadForm

    var isEdit: Bool = false
    var onArchive: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LeadField(label: "CONTACT NAME") {
                LeadTextInput(
                    placeholder: "Helen Calloway",
                    text: $form.contactName,
                    keyboard: .default,
                    textContentType: .name
                )
            }

            HStack(alignment: .top, spacing: 10) {
                LeadField(label: "PHONE") {
                    LeadTextInput(
                        placeholder: "604-555-0142",
                        text: $form.phone,
                        keyboard: .phonePad,
                        textContentType: .telephoneNumber
                    )
                }
                LeadField(label: "EMAIL") {
                    LeadTextInput(
                        placeholder: "—",
                        text: $form.email,
                        keyboard: .emailAddress,
                        textContentType: .emailAddress,
                        autocapitalization: .never
                    )
                }
            }

            LeadField(label: "SITE ADDRESS") {
                LeadTextInput(
                    placeholder: "3185 Fairview Rd",
                    text: $form.address,
                    keyboard: .default,
                    textContentType: .fullStreetAddress
                )
            }

            LeadField(label: "JOB DESCRIPTION") {
                LeadTextInput(
                    placeholder: "Tear-off + reshingle, 28 sq",
                    text: $form.title
                )
            }

            LeadField(label: "ESTIMATED VALUE") {
                LeadTextInput(
                    placeholder: "14,200",
                    text: $form.estimatedValue,
                    keyboard: .decimalPad,
                    leading: "$"
                )
            }

            LeadField(label: "SOURCE") {
                LeadChipPicker(
                    selection: $form.source,
                    options: LeadFormView.sourceOptions
                )
            }

            LeadField(label: "STAGE") {
                LeadChipPicker(
                    selection: stageBinding,
                    options: LeadFormView.stageOptions
                )
            }

            LeadField(label: "PRIORITY") {
                LeadChipPicker(
                    selection: $form.priority,
                    options: LeadFormView.priorityOptions
                )
            }

            LeadField(label: "NOTES", hint: "[OPTIONAL]") {
                LeadTextArea(
                    placeholder: "Roof access notes, gate codes, owner preferences…",
                    text: $form.notes,
                    rows: 3
                )
            }

            if isEdit {
                dangerZone
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - Stage binding

    /// Stage chip group serialises to PipelineStage. Convert via raw value.
    private var stageBinding: Binding<String> {
        Binding(
            get: { form.stage.rawValue },
            set: { newValue in
                form.stage = PipelineStage(rawValue: newValue) ?? .newLead
            }
        )
    }

    // MARK: - Chip option sets

    static let sourceOptions: [LeadChipOption] = [
        .init(id: "manual",       label: "MANUAL"),
        .init(id: "web_form",     label: "WEB FORM"),
        .init(id: "referral",     label: "REFERRAL"),
        .init(id: "inbound_call", label: "INBOUND CALL"),
        .init(id: "email",        label: "EMAIL"),
    ]

    static let stageOptions: [LeadChipOption] = [
        PipelineStage.newLead, .qualifying, .quoting,
        .quoted, .followUp, .negotiation,
    ].map { stage in
        LeadChipOption(id: stage.rawValue, label: stage.displayName)
    }

    static let priorityOptions: [LeadChipOption] = [
        .init(id: "low",  label: "LOW"),
        .init(id: "med",  label: "MEDIUM"),
        .init(id: "high", label: "HIGH"),
    ]

    // MARK: - Danger zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .background(OPSStyle.Colors.line)
                .padding(.bottom, 6)

            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("DANGER ZONE")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(1.6)
            .textCase(.uppercase)

            HStack(spacing: 8) {
                SheetCTAButton(
                    label: "ARCHIVE",
                    icon: "archivebox",
                    variant: .outline,
                    action: { onArchive?() }
                )
                .frame(maxWidth: .infinity)

                SheetCTAButton(
                    label: "DELETE",
                    icon: "trash",
                    variant: .destructive,
                    action: { onDelete?() }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Field wrapper

/// Mono caps label + optional bracketed hint sitting above any input. Per the
/// prototype's `Field` primitive (sheets.jsx:133-144) and `mobile/MOBILE.md`
/// §9 form inputs.
struct LeadField<Content: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                if let hint {
                    Text(hint)
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .kerning(1.6)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .textCase(.uppercase)
                }
            }
            content()
        }
    }
}

// MARK: - Text input

/// 48pt-tall single-line input with optional leading character (e.g. `$`).
/// Mirrors `sheets.jsx`'s `TextInput`: 0.04 white fill, 0.10 hairline, focus
/// brightens border to 0.20 (no accent on focus per OPS spec).
struct LeadTextInput: View {
    let placeholder: String
    @Binding var text: String

    var keyboard: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var leading: String? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            if let leading {
                Text(leading)
                    .font(.custom("JetBrainsMono-Regular", size: 13))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
            TextField("", text: $text, prompt:
                Text(placeholder)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.textMute)
            )
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.text)
            .tint(OPSStyle.Colors.text)
            .keyboardType(keyboard)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled(textContentType == .emailAddress)
            .focused($isFocused)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.white.opacity(0.20) : OPSStyle.Colors.line,  // no exact token
                    lineWidth: 1
                )
        )
        .animation(OPSStyle.Animation.standard, value: isFocused)
    }
}

// MARK: - Text area

/// Multi-line input. 12pt vertical padding per mobile/MOBILE.md §9.
struct LeadTextArea: View {
    let placeholder: String
    @Binding var text: String
    var rows: Int = 3

    @FocusState private var isFocused: Bool

    private var minHeight: CGFloat {
        // Mohave 16 at 1.4 line height → ~22pt per line + 24pt vertical padding
        CGFloat(rows) * 22 + 24
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Native TextEditor — strip its background, fill via our own surface
            TextEditor(text: $text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .tint(OPSStyle.Colors.text)
                .focused($isFocused)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: minHeight, alignment: .topLeading)

            if text.isEmpty {
                Text(placeholder)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(
                    isFocused ? Color.white.opacity(0.20) : OPSStyle.Colors.line,  // no exact token
                    lineWidth: 1
                )
        )
        .animation(OPSStyle.Animation.standard, value: isFocused)
    }
}

// MARK: - Chip picker

/// Option model for a single chip in a chip-picker group.
struct LeadChipOption: Identifiable, Hashable {
    let id: String
    let label: String
}

/// Single-select chip group. Renders as a wrap layout (multiple rows) — unlike
/// the existing `FilterChipRow`, which scrolls horizontally. Chips inherit the
/// FilterChipRow visual treatment: 0.04/0.10 inactive, 0.10/0.20 active, no
/// accent on active state per OPS spec.
struct LeadChipPicker: View {
    @Binding var selection: String
    let options: [LeadChipOption]

    var body: some View {
        ChipWrap(spacing: 6) {
            ForEach(options) { option in
                let isActive = option.id == selection
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selection = option.id
                } label: {
                    Text(option.label)
                        .font(.custom("JetBrainsMono-Medium", size: 10))
                        .kerning(1.4)
                        .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                        .textCase(.uppercase)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .fill(isActive ? OPSStyle.Colors.line : OPSStyle.Colors.surfaceInput)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .strokeBorder(
                                    isActive ? Color.white.opacity(0.20) : OPSStyle.Colors.line,  // no exact token
                                    lineWidth: 1
                                )
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isActive ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Flow layout (chip wrap)

/// Minimal flow layout — items pack left-to-right; overflow wraps to a new
/// line. Used by the chip picker so 6 stage chips can wrap onto two rows on
/// narrow phones without forcing a horizontal scroll.
struct ChipWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = makeRows(maxWidth: maxWidth, subviews: subviews)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let totalWidth = rows.map(\.width).max() ?? 0
        return CGSize(width: totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = makeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func makeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let currentRow = rows.count - 1
            let candidateWidth = rows[currentRow].width
                + (rows[currentRow].items.isEmpty ? 0 : spacing)
                + size.width
            if candidateWidth > maxWidth, !rows[currentRow].items.isEmpty {
                rows.append(Row())
                let newRow = rows.count - 1
                rows[newRow].items.append((index, size))
                rows[newRow].width = size.width
                rows[newRow].height = size.height
            } else {
                let row = rows.count - 1
                if !rows[row].items.isEmpty { rows[row].width += spacing }
                rows[row].items.append((index, size))
                rows[row].width += size.width
                rows[row].height = max(rows[row].height, size.height)
            }
        }
        return rows
    }
}

// MARK: - Sheet CTA button

/// Footer / danger-zone button. Four variants:
///
///   .primary      — opsAccent fill, black text, no border (the canonical save)
///   .secondary    — surfaceInput fill, text color, line border (cancel)
///   .destructive  — roseFillM fill, roseTextM text, roseLineM border (delete / confirm lost)
///   .outline      — transparent fill, text2 color, line border (archive)
///
/// All variants are 48pt tall, 5pt radius, Cake Mono Light 14, uppercase.
/// Action is wrapped in a light haptic and runs even when the parent disables
/// the button via `.disabled(true)` — disable the button when wiring up the
/// async save, not in this view.
struct SheetCTAButton: View {
    enum Variant { case primary, secondary, destructive, outline }

    let label: String
    var icon: String? = nil
    var variant: Variant = .primary
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(foreground)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .regular))
                }
                Text(label)
                    .font(OPSStyle.Typography.buttonLabel)
                    .kerning(0.6)
                    .textCase(.uppercase)
            }
            .frame(minHeight: 48)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .foregroundColor(foreground)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var foreground: Color {
        switch variant {
        case .primary:     return OPSStyle.Colors.invertedText
        case .secondary:   return OPSStyle.Colors.text
        case .destructive: return OPSStyle.Colors.roseTextM
        case .outline:     return OPSStyle.Colors.text2
        }
    }

    private var fill: Color {
        switch variant {
        case .primary:     return OPSStyle.Colors.opsAccent
        case .secondary:   return OPSStyle.Colors.surfaceInput
        case .destructive: return OPSStyle.Colors.roseFillM
        case .outline:     return .clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary:     return .clear
        case .secondary:   return OPSStyle.Colors.line
        case .destructive: return OPSStyle.Colors.roseLineM
        case .outline:     return OPSStyle.Colors.line
        }
    }

    private var borderWidth: CGFloat {
        variant == .primary ? 0 : 1
    }
}

// MARK: - Sheet footer button row

/// Footer CTA pair for lead sheets — `CANCEL` at one-third width, the primary
/// action at two-thirds, separated by an 8pt gap. The 1:2 ratio is computed
/// explicitly via GeometryReader: `.frame(maxWidth: .infinity * 2)` collapses
/// to plain `.infinity` in CGFloat math, so both buttons would otherwise
/// render equal width. Mirrors the split in `StickyActionBar.actionPair`.
struct SheetFooterButtonRow<Cancel: View, Primary: View>: View {
    @ViewBuilder var cancel: () -> Cancel
    @ViewBuilder var primary: () -> Primary

    var body: some View {
        GeometryReader { geo in
            // 1 : 2 split — total width = unit + 8pt gap + 2·unit.
            let unit = (geo.size.width - 8) / 3
            HStack(spacing: 8) {
                cancel()
                    .frame(width: unit, height: 48)
                primary()
                    .frame(width: unit * 2, height: 48)
            }
        }
        .frame(height: 48)
    }
}

// MARK: - Sheet chrome helpers

/// Top-right close affordance used by the four full-detent sheets. 44pt square
/// tap target, no border, `text2` icon. Half-detent sheets use the SwiftUI
/// drag indicator instead (set by `LeadsTabView`).
struct SheetCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Close")
    }
}

/// Display title for a lead sheet's header — Cake Mono Light, uppercase,
/// left-aligned. Sized per mobile/MOBILE.md §6.2 (half sheet) and §6.3
/// (full sheet).
struct SheetTitleLabel: View {
    /// Sheet-detent variant — sets the type size per MOBILE.md §6.2 / §6.3.
    enum Size {
        case full   // full-detent sheet — 22pt
        case half   // half-detent sheet — 18pt

        var pointSize: CGFloat {
            switch self {
            case .full: return 22
            case .half: return 18
            }
        }
    }

    let title: String
    var size: Size = .full

    var body: some View {
        Text(title)
            .font(.custom("CakeMono-Light", size: size.pointSize))
            .foregroundColor(OPSStyle.Colors.text)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Inline `// SYNCING…` / `// ERROR — <reason>` status line for save-in-flight
/// feedback. Sits above the footer CTA strip.
struct SheetStatusLine: View {
    enum Mode {
        case syncing
        case error(String)
    }

    let mode: Mode

    var body: some View {
        HStack(spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            switch mode {
            case .syncing:
                Text("SYNCING…")
                    .foregroundColor(OPSStyle.Colors.text3)
            case .error(let reason):
                Text("ERROR — ")
                    .foregroundColor(OPSStyle.Colors.roseTextM)
                Text(reason.uppercased())
                    .foregroundColor(OPSStyle.Colors.roseTextM)
            }
        }
        .font(.custom("JetBrainsMono-Medium", size: 11))
        .kerning(1.4)
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
