//
//  ImagePickerView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import SwiftUI
import PhotosUI

struct ImagePickerView: View {
    var onImageSelected: (UIImage?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImage: UIImage?
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Select Profile Image")
                .font(.title2)
                .bold()
                .padding(.top)
            
            if let selectedImage = selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
            
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.on.rectangle")
                    Text("Select Photo")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OPSStyle.Colors.primaryAccent)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
            }
            
            Button(action: {
                // Use the selected image
                onImageSelected(selectedImage)
                dismiss()
            }) {
                Text("Use This Photo")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedImage != nil ? OPSStyle.Colors.primaryAccent : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.horizontal)
            }
            .disabled(selectedImage == nil)
            
            Button(action: {
                dismiss()
            }) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.clear)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                    )
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .onChange(of: selectedItem) { oldItem, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    print("ImagePickerView: New image selected with size: \(image.size.width)x\(image.size.height)")
                }
            }
        }
    }
}

#Preview {
    ImagePickerView(onImageSelected: { _ in })
}