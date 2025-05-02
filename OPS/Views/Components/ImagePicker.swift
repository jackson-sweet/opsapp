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
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Create UIImagePickerController for camera access
    @MainActor
    private func makeImagePickerController(sourceType: UIImagePickerController.SourceType = .camera, context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        picker.allowsEditing = allowsEditing
        picker.delegate = context.coordinator
        
        // Only set camera device related properties if using camera
        if sourceType == .camera {
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
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        // UIImagePickerController delegate method
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
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
            parent.presentationMode.wrappedValue.dismiss()
        }
        
        // PHPickerViewController delegate method
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // No selections, just dismiss
            if results.isEmpty {
                parent.presentationMode.wrappedValue.dismiss()
                return
            }
            
            // Process multiple selections
            let dispatchGroup = DispatchGroup()
            var selectedImages: [UIImage] = []
            
            for result in results {
                guard result.itemProvider.canLoadObject(ofClass: UIImage.self) else { continue }
                
                dispatchGroup.enter()
                
                result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                    defer { dispatchGroup.leave() }
                    
                    if let image = image as? UIImage {
                        selectedImages.append(image)
                    }
                }
            }
            
            // When all images are loaded, update the binding and dismiss
            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                
                // Append new images to existing ones
                self.parent.images.append(contentsOf: selectedImages)
                
                // Call completion handler
                if let completion = self.parent.onSelectionComplete {
                    completion()
                }
                
                // Dismiss the picker
                self.parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
