//
//  ProjectNoteMentionEditingField.swift
//  OPS
//
//  Selection-aware multiline editor and pure caret-scoped mention helpers
//  shared by Activity notes and photo comments.
//

import SwiftUI
import UIKit

struct ProjectNoteMentionMatch {
    let replacementRange: NSRange
    let suggestions: [TeamMember]
    let showAllTeam: Bool
}

struct ProjectNoteMentionReplacement: Equatable {
    let text: String
    let selectedRange: NSRange
    let mentionSpans: [ProjectNoteMentionSpan]
}

enum ProjectNoteMentionEditor {
    static func match(
        in text: String,
        selectedRange: NSRange,
        members: [TeamMember]
    ) -> ProjectNoteMentionMatch? {
        guard let active = activeMention(
            in: text,
            selectedRange: selectedRange
        ) else {
            return nil
        }

        let rawQuery = active.query
        let query = rawQuery.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        let endsWithWhitespace =
            rawQuery.last?.isWhitespace == true

        if endsWithWhitespace {
            let hasLongerMemberMatch = members.contains {
                let name = $0.fullName.lowercased()
                return name.hasPrefix(query) && name != query
            }
            let hasLongerAllTeamMatch =
                "all team".hasPrefix(query) && query != "all team"
            guard hasLongerMemberMatch || hasLongerAllTeamMatch else {
                return nil
            }
        }

        if query.isEmpty {
            return ProjectNoteMentionMatch(
                replacementRange: active.range,
                suggestions: members,
                showAllTeam: true
            )
        }

        let suggestions = members.filter {
            $0.fullName.lowercased().contains(query)
                || $0.firstName.lowercased().hasPrefix(query)
                || $0.lastName.lowercased().hasPrefix(query)
        }
        let showAllTeam = "all team".hasPrefix(query)
        guard !suggestions.isEmpty || showAllTeam else {
            return nil
        }

        return ProjectNoteMentionMatch(
            replacementRange: active.range,
            suggestions: suggestions,
            showAllTeam: showAllTeam
        )
    }

    static func replacingActiveMention(
        with name: String,
        in text: String,
        selectedRange: NSRange,
        mentionSpans: [ProjectNoteMentionSpan] = [],
        recipient: ProjectNoteMentionRecipient? = nil,
        visibleMentionText: String? = nil
    ) -> ProjectNoteMentionReplacement? {
        guard let active = activeMention(
            in: text,
            selectedRange: selectedRange
        ) else {
            return nil
        }

        let replacementRange = mentionSpans.first {
            $0.range.location == active.range.location
                && NSMaxRange(active.range) <= NSMaxRange($0.range)
        }?.range ?? active.range
        let utf16Text = text as NSString
        let suffixStart = NSMaxRange(replacementRange)
        var suffixStartsWithWhitespace = false
        var caretAdvanceIntoSuffix = 0
        if suffixStart < utf16Text.length {
            let suffixCharacterRange =
                utf16Text.rangeOfComposedCharacterSequence(
                    at: suffixStart
                )
            let suffixCharacter = utf16Text.substring(
                with: suffixCharacterRange
            )
            if suffixCharacter.allSatisfy({ $0.isWhitespace }) {
                suffixStartsWithWhitespace = true
                if !suffixCharacter.contains(where: { $0.isNewline }) {
                    caretAdvanceIntoSuffix = suffixCharacterRange.length
                }
            }
        }

        let mentionText = visibleMentionText ?? "@\(name)"
        let replacement = suffixStartsWithWhitespace
            ? mentionText
            : "\(mentionText) "
        let mutableText = NSMutableString(string: text)
        mutableText.replaceCharacters(
            in: replacementRange,
            with: replacement
        )
        let caretLocation =
            replacementRange.location + (replacement as NSString).length
                + caretAdvanceIntoSuffix
        var updatedSpans = adjustingMentionSpans(
            mentionSpans,
            replacing: replacementRange,
            with: replacement
        )
        if let recipient {
            updatedSpans.append(
                ProjectNoteMentionSpan(
                    range: NSRange(
                        location: replacementRange.location,
                        length: (mentionText as NSString).length
                    ),
                    displayText: mentionText,
                    recipient: recipient
                )
            )
            updatedSpans.sort { $0.range.location < $1.range.location }
        }
        return ProjectNoteMentionReplacement(
            text: mutableText as String,
            selectedRange: NSRange(location: caretLocation, length: 0),
            mentionSpans: updatedSpans
        )
    }

    /// Applies one UITextView edit to identity spans. Intact spans after the
    /// edit shift by the UTF-16 delta; any span whose visible token is touched
    /// is invalidated so a stale ID can never survive changed mention text.
    static func adjustingMentionSpans(
        _ spans: [ProjectNoteMentionSpan],
        replacing editedRange: NSRange,
        with replacementText: String
    ) -> [ProjectNoteMentionSpan] {
        let replacementLength = (replacementText as NSString).length
        let delta = replacementLength - editedRange.length
        let editedEnd = NSMaxRange(editedRange)

        return spans.compactMap { span in
            let spanEnd = NSMaxRange(span.range)
            var updated = span

            if editedRange.length == 0 {
                if editedRange.location < span.range.location {
                    updated.range.location += delta
                    return updated
                }
                if editedRange.location > spanEnd {
                    return updated
                }
                if editedRange.location == span.range.location {
                    guard replacementText.last.map(
                        ProjectNoteMentionParser.isMentionBoundary
                    ) ?? true else {
                        return nil
                    }
                    updated.range.location += delta
                    return updated
                }
                if editedRange.location == spanEnd {
                    guard replacementText.first.map(
                        ProjectNoteMentionParser.isMentionBoundary
                    ) ?? true else {
                        return nil
                    }
                    return updated
                }
                return nil
            }

            if editedEnd < span.range.location {
                updated.range.location += delta
                return updated
            }
            if editedRange.location > spanEnd {
                return updated
            }
            // Replacing or deleting text immediately adjacent to a mention can
            // remove its separating boundary. Invalidate conservatively; the
            // final parser independently enforces the same boundary rule.
            if editedEnd == span.range.location
                || editedRange.location == spanEnd {
                return nil
            }
            return nil
        }
    }

    private static func activeMention(
        in text: String,
        selectedRange: NSRange
    ) -> (range: NSRange, query: String)? {
        let utf16Text = text as NSString
        guard selectedRange.location != NSNotFound,
              selectedRange.location >= 0,
              selectedRange.length >= 0,
              NSMaxRange(selectedRange) <= utf16Text.length else {
            return nil
        }

        let activeEnd = NSMaxRange(selectedRange)
        let atRange = utf16Text.range(
            of: "@",
            options: .backwards,
            range: NSRange(location: 0, length: activeEnd)
        )
        guard atRange.location != NSNotFound else {
            return nil
        }

        if atRange.location > 0 {
            let precedingRange = utf16Text.rangeOfComposedCharacterSequence(
                at: atRange.location - 1
            )
            let precedingText = utf16Text.substring(with: precedingRange)
            if let precedingCharacter = precedingText.first,
               !isMentionBoundary(precedingCharacter) {
                return nil
            }
        }

        let queryStart = NSMaxRange(atRange)
        guard queryStart <= activeEnd else { return nil }
        let queryRange = NSRange(
            location: queryStart,
            length: activeEnd - queryStart
        )
        let query = utf16Text.substring(with: queryRange)
        guard !query.contains("\n"),
              !query.contains("\r"),
              !query.contains("@") else {
            return nil
        }

        return (
            NSRange(
                location: atRange.location,
                length: activeEnd - atRange.location
            ),
            query
        )
    }

    private static func isMentionBoundary(_ character: Character) -> Bool {
        ProjectNoteMentionParser.isMentionBoundary(character)
    }
}

struct ProjectNoteMentionEditingField: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var mentionSpans: [ProjectNoteMentionSpan]
    let placeholder: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            SelectionAwareMentionTextView(
                text: $text,
                selectedRange: $selectedRange,
                mentionSpans: $mentionSpans,
                accessibilityLabel: placeholder,
                isFocused: nil,
                onSubmit: nil
            )

            if text.isEmpty {
                Text(placeholder)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cornerRadius
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cornerRadius
            )
            .stroke(
                OPSStyle.Colors.inputFieldBorderFocus,
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
    }
}

struct ProjectNoteMentionComposerField: View {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var mentionSpans: [ProjectNoteMentionSpan]
    @Binding var isFocused: Bool
    let placeholder: String
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            SelectionAwareMentionTextView(
                text: $text,
                selectedRange: $selectedRange,
                mentionSpans: $mentionSpans,
                accessibilityLabel: placeholder,
                isFocused: $isFocused,
                onSubmit: onSubmit
            )

            if text.isEmpty {
                Text(placeholder)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }
}

private struct SelectionAwareMentionTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var selectedRange: NSRange
    @Binding var mentionSpans: [ProjectNoteMentionSpan]
    let accessibilityLabel: String
    let isFocused: Binding<Bool>?
    let onSubmit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = OPSStyle.Typography.uiBody
        textView.textColor = UIColor(OPSStyle.Colors.primaryText)
        textView.tintColor = UIColor(OPSStyle.Colors.primaryAccent)
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(
            top: OPSStyle.Layout.spacing2,
            left: OPSStyle.Layout.spacing2,
            bottom: OPSStyle.Layout.spacing2,
            right: OPSStyle.Layout.spacing2
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityLabel = accessibilityLabel
        if onSubmit != nil {
            textView.returnKeyType = .send
        }
        OPSKeyboardDoneAccessoryCoordinator.shared.prepare(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.isApplyingBindings = true
        defer { context.coordinator.isApplyingBindings = false }

        if textView.text != text {
            textView.text = text
        }
        let clampedSelection = Self.clamped(
            selectedRange,
            utf16Length: (text as NSString).length
        )
        if textView.selectedRange != clampedSelection {
            textView.selectedRange = clampedSelection
        }
        if let isFocused {
            if isFocused.wrappedValue, !textView.isFirstResponder {
                textView.becomeFirstResponder()
            } else if !isFocused.wrappedValue,
                      textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UITextView,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let measured = uiView.sizeThatFits(
            CGSize(
                width: width,
                height: .greatestFiniteMagnitude
            )
        )
        return CGSize(
            width: width,
            height: max(
                measured.height,
                OPSStyle.Layout.touchTargetMin
            )
        )
    }

    private static func clamped(
        _ range: NSRange,
        utf16Length: Int
    ) -> NSRange {
        let location = min(max(range.location, 0), utf16Length)
        let maximumLength = utf16Length - location
        return NSRange(
            location: location,
            length: min(max(range.length, 0), maximumLength)
        )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: SelectionAwareMentionTextView
        var isApplyingBindings = false

        init(parent: SelectionAwareMentionTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            publishState(from: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            publishState(from: textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused?.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused?.wrappedValue = false
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard !isApplyingBindings else { return true }
            if text == "\n", let onSubmit = parent.onSubmit {
                onSubmit()
                return false
            }
            parent.mentionSpans = ProjectNoteMentionEditor
                .adjustingMentionSpans(
                    parent.mentionSpans,
                    replacing: range,
                    with: text
                )
            return true
        }

        private func publishState(from textView: UITextView) {
            guard !isApplyingBindings else { return }
            if parent.text != textView.text {
                parent.text = textView.text
            }
            if parent.selectedRange != textView.selectedRange {
                parent.selectedRange = textView.selectedRange
            }
        }
    }
}
