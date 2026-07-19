//
//  ImagePicker.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//
//  Photo-library picker (PHPicker). Bug 56c37df2 — the camera source
//  this wrapper used to offer is gone: every capture flow now goes
//  through the standardized CameraBatchView, so this is a library
//  picker and nothing else.
//

import SwiftUI
import UIKit
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var images: [UIImage]
    var selectionLimit = 10 // Allow up to 10 photos by default
    var onSelectionComplete: (() -> Void)? = nil // Completion handler
    @Environment(\.presentationMode) private var presentationMode

    @MainActor
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit // Support multiple selections
        configuration.preferredAssetRepresentationMode = .current // Get full resolution

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        /// Bug 35c400c2 — tracks whether this picker session already
        /// delivered a result. PHPicker is not supposed to invoke its
        /// delegate twice, but several real-world edge cases (Done tap
        /// during slow iCloud fetch, presenting+rapid-dismiss races) have
        /// been known to do exactly that. The flag prevents the same
        /// selection from being appended to the host binding more than
        /// once.
        var hasFinished = false

        init(_ parent: ImagePicker) {
            self.parent = parent
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
