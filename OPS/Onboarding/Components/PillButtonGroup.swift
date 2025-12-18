//
//  PillButtonGroup.swift
//  OPS
//
//  Horizontal pill button group for single selection.
//  Used for Company Size and Company Age selection in onboarding.
//

import SwiftUI

// MARK: - Pill Button Group

/// A horizontal group of pill-style buttons for single selection
struct PillButtonGroup<T: Hashable>: View {
    let options: [PillOption<T>]
    @Binding var selection: T?
    let wrap: Bool // Whether to wrap to multiple lines

    init(
        options: [PillOption<T>],
        selection: Binding<T?>,
        wrap: Bool = true
    ) {
        self.options = options
        self._selection = selection
        self.wrap = wrap
    }

    var body: some View {
        if wrap {
            wrappingLayout
        } else {
            scrollingLayout
        }
    }

    private var wrappingLayout: some View {
        OnboardingFlowLayout(spacing: 8) {
            ForEach(options) { option in
                PillButton(
                    title: option.title,
                    isSelected: selection == option.value
                ) {
                    selection = option.value
                }
            }
        }
    }

    private var scrollingLayout: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options) { option in
                    PillButton(
                        title: option.title,
                        isSelected: selection == option.value
                    ) {
                        selection = option.value
                    }
                }
            }
        }
    }
}

// MARK: - Pill Option

struct PillOption<T: Hashable>: Identifiable {
    let id: String
    let title: String
    let value: T

    init(id: String = UUID().uuidString, title: String, value: T) {
        self.id = id
        self.title = title
        self.value = value
    }
}

// MARK: - Individual Pill Button

struct PillButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .black : OPSStyle.Colors.primaryText)
                .tracking(0.5)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isSelected ? Color.white : OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Flow Layout

/// A layout that wraps items to the next line when they don't fit
struct OnboardingFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                     y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to the next line
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))

            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, currentX - spacing)
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Convenience Extensions for Enums

extension PillButtonGroup where T == CompanySize {
    /// Creates a PillButtonGroup for CompanySize enum
    static func companySize(selection: Binding<CompanySize?>) -> PillButtonGroup {
        let options = CompanySize.allCases.map { size in
            PillOption(id: size.rawValue, title: size.rawValue, value: size)
        }
        return PillButtonGroup(options: options, selection: selection)
    }
}

extension PillButtonGroup where T == CompanyAge {
    /// Creates a PillButtonGroup for CompanyAge enum
    static func companyAge(selection: Binding<CompanyAge?>) -> PillButtonGroup {
        let options = CompanyAge.allCases.map { age in
            PillOption(id: age.rawValue, title: age.rawValue, value: age)
        }
        return PillButtonGroup(options: options, selection: selection)
    }
}

// MARK: - Labeled Pill Button Group

/// Pill button group with a label above it
struct LabeledPillButtonGroup<T: Hashable>: View {
    let label: String
    let options: [PillOption<T>]
    @Binding var selection: T?
    let wrap: Bool

    init(
        label: String,
        options: [PillOption<T>],
        selection: Binding<T?>,
        wrap: Bool = true
    ) {
        self.label = label
        self.options = options
        self._selection = selection
        self.wrap = wrap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            PillButtonGroup(
                options: options,
                selection: $selection,
                wrap: wrap
            )
        }
    }
}

// MARK: - Previews

#Preview("Company Size") {
    struct PreviewWrapper: View {
        @State private var selection: CompanySize?

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("Selected: \(selection?.rawValue ?? "none")")
                    .foregroundColor(.white)

                LabeledPillButtonGroup(
                    label: "COMPANY SIZE",
                    options: CompanySize.allCases.map { PillOption(id: $0.rawValue, title: $0.rawValue, value: $0) },
                    selection: $selection
                )
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OPSStyle.Colors.background)
        }
    }

    return PreviewWrapper()
}

#Preview("Company Age") {
    struct PreviewWrapper: View {
        @State private var selection: CompanyAge?

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("Selected: \(selection?.rawValue ?? "none")")
                    .foregroundColor(.white)

                LabeledPillButtonGroup(
                    label: "COMPANY AGE",
                    options: CompanyAge.allCases.map { PillOption(id: $0.rawValue, title: $0.rawValue, value: $0) },
                    selection: $selection
                )
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OPSStyle.Colors.background)
        }
    }

    return PreviewWrapper()
}

#Preview("Custom Options") {
    struct PreviewWrapper: View {
        @State private var selection: String?

        let options = [
            PillOption(title: "Daily", value: "daily"),
            PillOption(title: "Weekly", value: "weekly"),
            PillOption(title: "Monthly", value: "monthly"),
            PillOption(title: "Yearly", value: "yearly")
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("Selected: \(selection ?? "none")")
                    .foregroundColor(.white)

                PillButtonGroup(
                    options: options,
                    selection: $selection
                )
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(OPSStyle.Colors.background)
        }
    }

    return PreviewWrapper()
}
