//
//  ImagePicker.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI
import UIKit
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    var allowsEditing = true
    var sourceType: SourceType = .photoLibrary // Default directly to photo library for simplicity
    var selectionLimit = 10 // Allow up to 10 photos by default
    var onSelectionComplete: (() -> Void)? = nil // Completion handler
    @Environment(\.presentationMode) private var presentationMode
    
    enum SourceType {
        case camera
        case photoLibrary
        case both
    }
    
    @MainActor
    func makeUIViewController(context: Context) -> UIViewController {
        // Go directly to appropriate picker based on source type
        switch sourceType {
        case .camera:
            guard Self.nativeCameraIsAvailable else {
                return makePHPickerController(context: context)
            }
            return makeImagePickerController(context: context)
        case .photoLibrary:
            return makePHPickerController(context: context)
        case .both:
            // Create action sheet controller
            let actionController = UIViewController()
            actionController.view.backgroundColor = .clear
            
            // Show camera/library choice after controller appears
            DispatchQueue.main.async {
                self.showSourceSelectionSheet(on: actionController, context: context)
            }
            
            return actionController
        }
    }
    
    @MainActor
    private func showSourceSelectionSheet(on controller: UIViewController, context: Context) {
        // Create action sheet
        let actionSheet = UIAlertController(title: "Choose Source", message: nil, preferredStyle: .actionSheet)
        
        // Configure for iPad
        if let popoverController = actionSheet.popoverPresentationController {
            popoverController.sourceView = controller.view
            popoverController.sourceRect = CGRect(x: controller.view.bounds.midX, 
                                              y: controller.view.bounds.midY, 
                                              width: 0, height: 0)
            popoverController.permittedArrowDirections = []
        }
        
        // Camera option
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            actionSheet.addAction(UIAlertAction(title: "Take Photo", style: .default) { _ in
                let picker = self.makeImagePickerController(sourceType: .camera, context: context)
                controller.present(picker, animated: true)
            })
        }
        
        // Photo Library option
        actionSheet.addAction(UIAlertAction(title: "Choose from Library", style: .default) { _ in
            let picker = self.makePHPickerController(context: context)
            controller.present(picker, animated: true)
        })
        
        // Cancel option
        actionSheet.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.presentationMode.wrappedValue.dismiss()
        })
        
        controller.present(actionSheet, animated: true)
    }

    private static var nativeCameraIsAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Create UIImagePickerController for camera access
    @MainActor
    private func makeImagePickerController(sourceType: UIImagePickerController.SourceType = .camera, context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        let resolvedSourceType: UIImagePickerController.SourceType = {
            guard sourceType == .camera else { return sourceType }
            return Self.nativeCameraIsAvailable ? .camera : .photoLibrary
        }()

        picker.sourceType = resolvedSourceType
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        
        // Only set camera device related properties if using camera
        if resolvedSourceType == .camera {
            picker.cameraCaptureMode = .photo
            // Use default camera device settings
            // Don't specify any specific camera device to avoid compatibility issues
        }
        
        return picker
    }
    
    // Create PHPickerViewController for photo library access
    @MainActor
    private func makePHPickerController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit // Support multiple selections
        configuration.preferredAssetRepresentationMode = .current // Get full resolution
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        /// Bug 35c400c2 — tracks whether this picker session already
        /// delivered a result. PHPicker / UIImagePickerController are not
        /// supposed to invoke their delegate twice, but several real-world
        /// edge cases (Done tap during slow iCloud fetch, presenting+rapid-
        /// dismiss races) have been known to do exactly that. The flag
        /// prevents the same selection from being appended to the host
        /// binding more than once.
        var hasFinished = false

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        // UIImagePickerController delegate method
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            guard !hasFinished else { return }
            hasFinished = true

            let key = parent.allowsEditing ? UIImagePickerController.InfoKey.editedImage : UIImagePickerController.InfoKey.originalImage

            if let image = info[key] as? UIImage {
                // Add the new image to the array
                DispatchQueue.main.async {
                    self.parent.images.append(image)

                    // Call completion handler before dismissing
                    if let completion = self.parent.onSelectionComplete {
                        completion()
                    }
                }
            }

            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            guard !hasFinished else { return }
            hasFinished = true
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        // PHPickerViewController delegate method
        // Bug 35c400c2 — fix gallery selections being added twice on Done.
        //
        // Root cause: `NSItemProvider.loadObject(ofClass: UIImage.self)` can
        // invoke its completion handler more than once for the same asset
        // (e.g. iCloud-backed shared photos sometimes deliver a low-res
        // proxy and then the full UIImage as a second callback). Each
        // callback was appending to the same array, so a single Done click
        // produced 2× the picked photos.
        //
        // The fix loads the raw image bytes via `loadDataRepresentation`
        // (which fires exactly once per result) and reconstructs a UIImage
        // from the returned Data, slot-indexed so order is preserved.
        // We also guard with `hasFinished` so reentrant delegate calls cannot
        // double-append, and gate dismissal so the SwiftUI binding only
        // receives one append per picker session.
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Reentrancy guard — PHPicker is supposed to call this exactly
            // once per session, but defending against double-fire is cheap
            // and removes a whole class of duplicate-append bugs.
            guard !hasFinished else { return }
            hasFinished = true

            // No selections — just dismiss.
            if results.isEmpty {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }

            // Pre-size a slot array so loaded images land in the user's
            // original selection order regardless of which result resolves
            // first.
            var loadedImages: [UIImage?] = Array(repeating: nil, count: results.count)
            let dispatchGroup = DispatchGroup()
            let imageTypeIdentifier = "public.image"

            for (index, result) in results.enumerated() {
                guard result.itemProvider.hasItemConformingToTypeIdentifier(imageTypeIdentifier) else {
                    continue
                }

                dispatchGroup.enter()
                // loadDataRepresentation fires exactly once with the full
                // asset bytes — no preview/full callback duplication.
                result.itemProvider.loadDataRepresentation(forTypeIdentifier: imageTypeIdentifier) { data, _ in
                    defer { dispatchGroup.leave() }
                    guard let data = data, let image = UIImage(data: data) else { return }
                    loadedImages[index] = image
                }
            }

            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                let orderedImages = loadedImages.compactMap { $0 }

                // Append new images to existing ones (single append per
                // picker session — see hasFinished guard above).
                self.parent.images.append(contentsOf: orderedImages)

                // Notify the host view that selection completed.
                if let completion = self.parent.onSelectionComplete {
                    completion()
                }

                // Dismiss the picker.
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
