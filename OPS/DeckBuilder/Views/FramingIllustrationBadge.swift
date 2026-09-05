import SwiftUI

/// A quiet stamp in the corner of any viewport showing generated deck framing.
///
/// Why this exists: the framing preview is laid out from published span tables,
/// so it now looks like a real frame. A believable structural drawing that says
/// nothing about its own standing is the one genuinely dangerous thing this
/// viewport can produce. The mark is what keeps a better picture from becoming
/// a worse liability.
///
/// Why this presentation: the viewport already owns floating chrome in its top
/// corner. A second, quieter mark diagonally opposite reads as a stamp on the
/// drawing rather than a warning banner, never collides with the title, and
/// inherits the same fade so it never obscures geometry. A blocking modal on
/// every 3D open would be punitive by the twentieth deck of the day, and a
/// full-width banner would take permanent prime space for a once-noticed fact.
///
/// It appears only while framing is on screen and disappears otherwise. No
/// toggle, no setup, nothing to dismiss.
struct FramingIllustrationBadge: View {
    /// The drawing on screen. Used only to decide whether the layout fell
    /// outside the published tables, which adds one line to the detail.
    let drawingData: DeckDrawingData

    @State private var isShowingDetail = false

    /// Wide enough for the detail to break into short lines, narrow enough to
    /// stay a note rather than a page.
    private static let detailWidth: CGFloat = 280

    var body: some View {
        Button {
            isShowingDetail = true
        } label: {
            Text("ILLUSTRATION ONLY")
                .font(OPSStyle.Typography.smallCaption)
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .glassDense(cornerRadius: OPSStyle.Layout.chipRadius)
                // The tap area meets the 44pt minimum without inflating the
                // pill: the frame grows up and inboard of the mark itself.
                .frame(
                    minWidth: OPSStyle.Layout.touchTargetMin,
                    minHeight: OPSStyle.Layout.touchTargetMin,
                    alignment: .bottomTrailing
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Illustration only")
        .accessibilityHint("Explains what the framing drawing is")
        .popover(isPresented: $isShowingDetail) {
            detail
        }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("ILLUSTRATION ONLY")
                .font(OPSStyle.Typography.smallCaption)
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("Framing is laid out from published Hem-Fir span tables to show a plausible structure. It is not an engineered design. Build from a stamped drawing.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !DeckFramingPreviewPlanner.generatedFramingIsPrescriptive(for: drawingData) {
                Text("This deck is outside the published tables. The frame shown is a sketch only.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(width: Self.detailWidth, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}
