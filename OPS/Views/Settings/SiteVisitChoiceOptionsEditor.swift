import SwiftUI

struct SiteVisitChoiceOptionsEditor: View {
    @Binding var choice: SiteVisitSingleChoice

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("CHOOSE ONE ANSWER ON SITE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(Array(choice.options.enumerated()), id: \.element.id) { index, option in
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    HStack {
                        Text("OPTION \(index + 1)")
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Spacer()
                        moveButton(option: option, offset: -1, icon: OPSStyle.Icons.chevronUp)
                        moveButton(option: option, offset: 1, icon: OPSStyle.Icons.chevronDown)
                        Button {
                            choice.options.removeAll { $0.id == option.id }
                        } label: {
                            Image(systemName: OPSStyle.Icons.trash)
                                .foregroundColor(OPSStyle.Colors.roseTextM)
                                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        }
                        .buttonStyle(.plain)
                        .disabled(choice.options.count <= SiteVisitSingleChoice.minimumOptions)
                        .accessibilityLabel("Remove option \(index + 1)")
                    }
                    FormField(title: "ANSWER OPTION", placeholder: "Option label", text: Binding(
                        get: { choice.options.first { $0.id == option.id }?.label ?? "" },
                        set: { label in
                            guard let current = choice.options.firstIndex(where: { $0.id == option.id }) else { return }
                            choice.options[current].label = label
                        }
                    ))
                }
            }

            Button {
                guard choice.options.count < SiteVisitSingleChoice.maximumOptions else { return }
                choice.options.append(.init(label: ""))
            } label: {
                Label("ADD OPTION", systemImage: OPSStyle.Icons.plus)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
            }
            .buttonStyle(.plain)
            .disabled(choice.options.count >= SiteVisitSingleChoice.maximumOptions)
        }
    }

    private func moveButton(option: SiteVisitSingleChoice.Option, offset: Int, icon: String) -> some View {
        let index = choice.options.firstIndex { $0.id == option.id }
        let enabled = index.map { choice.options.indices.contains($0 + offset) } ?? false
        return Button {
            guard let current = choice.options.firstIndex(where: { $0.id == option.id }),
                  choice.options.indices.contains(current + offset) else { return }
            choice.options.swapAt(current, current + offset)
        } label: {
            Image(systemName: icon)
                .foregroundColor(enabled ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Move option \((index ?? 0) + 1) \(offset < 0 ? "up" : "down")")
    }
}
