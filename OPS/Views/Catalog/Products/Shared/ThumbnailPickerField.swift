//
//  ThumbnailPickerField.swift
//  OPS
//
//  Reusable PhotosPicker tile. Empty state is a full-width tap target
//  ("// + ADD THUMBNAIL"); picked state shows a 72x72 preview with
//  REPLACE + REMOVE controls. The parent owns the upload flow — this
//  view just maintains the picker → UIImage binding so the form has
//  something to render before save.
//

import SwiftUI
import PhotosUI

struct ThumbnailPickerField: View {
    @Binding var pickerItem: PhotosPickerItem?
    @Binding var image: UIImage?
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if let image {
                pickedState(image: image)
            } else {
                emptyState
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.errorText)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        image = img
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pickedState(image: UIImage) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder,
                                lineWidth: OPSStyle.Layout.Border.standard)
                )

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Text("// REPLACE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                }
                .accessibilityLabel("Replace thumbnail")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    self.image = nil
                    pickerItem = nil
                } label: {
                    Text("// REMOVE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.errorText)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin / 2)
                }
                .accessibilityLabel("Remove thumbnail")
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        PhotosPicker(
            selection: $pickerItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image("ops.add")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Text("// + ADD THUMBNAIL")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .accessibilityLabel("Add thumbnail")
    }
}
