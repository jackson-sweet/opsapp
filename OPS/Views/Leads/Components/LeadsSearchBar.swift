//
//  LeadsSearchBar.swift
//  OPS
//
//  The LEADS console's inline search field (console redesign 2026-08-05,
//  spec §5.1). Persistent and per-keystroke — pure in-memory filtering, no
//  debounce, no sheet, no "filters" door to open first.
//
//  Visual is the house input treatment (DESIGN.md §9 / MOBILE.md §9):
//  `surfaceInput` fill, `line` hairline, and a focus that BRIGHTENS the border
//  (`inputFieldBorderFocus`) — inputs are the one control that never takes the
//  accent on focus. Same stroke swap and `Animation.hover` timing as
//  `OPSProfileInput`, at the console band's tighter 40pt height.
//

import SwiftUI

struct LeadsSearchBar: View {
    @Binding var query: String
    /// Fires on every focus transition. The console uses the gained edge to
    /// scroll the command band away (addendum §15.3); it deliberately ignores
    /// the lost edge, so dismissing the keyboard leaves the operator exactly
    /// where he was reading.
    var onFocusChange: (Bool) -> Void = { _ in }

    @FocusState private var isFocused: Bool

    /// 40pt visual per spec §5.1 — between the 36pt chip tier and the 48pt form
    /// field, because this row sits inside a sticky band and every point above
    /// the queue is rent. The 44pt target comes from the outer frame below.
    private static let fieldHeight: CGFloat = 40

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(OPSStyle.Colors.text3)
                .accessibilityHidden(true)

            TextField("", text: $query)
                .placeholder(when: query.isEmpty) {
                    Text("Search leads")
                        .font(.custom("Mohave-Regular", size: 15))
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .font(.custom("Mohave-Regular", size: 15))
                .foregroundColor(OPSStyle.Colors.text)
                .tint(OPSStyle.Colors.text)
                .focused($isFocused)
                .submitLabel(.search)
                .autocorrectionDisabled(true)
                .textInputAutocapitalization(.never)
                .accessibilityLabel("Search leads")

            if !query.isEmpty {
                Button {
                    // Clears the query only. Focus stays put, so correcting a
                    // mistyped name never costs a second tap.
                    query = ""
                    isFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(width: OPSStyle.Layout.chipMinHeight, height: Self.fieldHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, OPSStyle.Layout.spacing2_5)
        .padding(.trailing, query.isEmpty ? OPSStyle.Layout.spacing2_5 : OPSStyle.Layout.spacing1)
        .frame(height: Self.fieldHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.sidebarHoverRadius, style: .continuous)
                .strokeBorder(
                    isFocused ? OPSStyle.Colors.inputFieldBorderFocus : OPSStyle.Colors.line,
                    lineWidth: 1
                )
        )
        .animation(OPSStyle.Animation.hover, value: isFocused)
        .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
        // The visual field is 40pt; the target is the sanctioned 44pt floor,
        // and a tap anywhere in it lands in the field.
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
    }
}

// MARK: - Previews

#if DEBUG
/// Live host — the canvas is interactive, so tapping the field shows the real
/// focus treatment (the brightened border) that a static preview cannot force.
private struct LeadsSearchBarPreviewHost: View {
    @State private var empty = ""
    @State private var typed = "dana"

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            LeadsSearchBar(query: $empty)
            LeadsSearchBar(query: $typed)
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(OPSStyle.Colors.background)
    }
}

#Preview("LeadsSearchBar / rest + typed") {
    LeadsSearchBarPreviewHost()
        .preferredColorScheme(.dark)
}
#endif
