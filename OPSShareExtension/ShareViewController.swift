//
//  ShareViewController.swift
//  OPSShareExtension
//
//  Principal class for the "Add to OPS" share extension. Hosts the SwiftUI
//  picker and, on confirm, downscales the shared photos into the App Group
//  inbox, enqueues them in the shared manifest, and — when the bridged token is
//  usable — presigns + kicks off a background S3 upload that survives this
//  extension being dismissed. The main app finalizes the database rows.
//

import UIKit
import SwiftUI
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {

    private var model: SharePickerModel!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        ShareFontRegistrar.registerIfNeeded()

        let bridge = ShareSessionBridgeStore.read()
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let photoCount = ShareImageProcessor.imageProviderCount(in: items)
        let content = resolveContent(bridge: bridge, photoCount: photoCount)

        let model = SharePickerModel(content: content, photoCount: photoCount)
        model.onCancel = { [weak self] in self?.cancel() }
        model.onConfirm = { [weak self] project in
            self?.confirm(project: project, bridge: bridge, items: items)
        }
        self.model = model

        let host = UIHostingController(rootView: SharePickerView(model: model))
        host.view.backgroundColor = .black
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Content resolution

    private func resolveContent(bridge: ShareSessionBridge?, photoCount: Int) -> SharePickerContent {
        guard photoCount > 0 else { return .noImages }
        guard let bridge, bridge.hasSession else { return .noSession }
        guard bridge.canEditProjects else { return .noPermission }
        guard !bridge.editableProjects.isEmpty else { return .noProjects }
        return .ready(bridge.editableProjects)
    }

    // MARK: - Confirm / capture

    private func confirm(project: ShareProjectRef, bridge: ShareSessionBridge?, items: [NSExtensionItem]) {
        Task { @MainActor in
            await self.stageAndUpload(project: project, bridge: bridge, items: items)
            self.model.confirmedTitle = project.title
            self.model.phase = .done
            ShareHaptics.success()
            // Let the success state read before dismissing.
            try? await Task.sleep(nanoseconds: 900_000_000)
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }
    }

    /// Stages every shared image into the App Group inbox + manifest. For each,
    /// if the bridged token is usable it presigns and starts a background S3
    /// upload; otherwise it leaves the job pending for the app to upload on its
    /// next drain. Posts a Darwin nudge so a foregrounded app drains immediately.
    private func stageAndUpload(project: ShareProjectRef, bridge: ShareSessionBridge?, items: [NSExtensionItem]) async {
        let fileNames = await ShareImageProcessor.stageImages(from: items)
        guard !fileNames.isEmpty, let bridge else { return }

        let folder = "projects/\(bridge.companyId)/\(project.id)"

        for fileName in fileNames {
            let jobId = (fileName as NSString).deletingPathExtension
            var job = ShareUploadJob(
                id: jobId,
                fileName: fileName,
                projectId: project.id,
                projectTitle: project.title,
                companyId: bridge.companyId,
                uploadedBy: bridge.userId,
                createdAt: Date(),
                state: .pendingPresign
            )

            if bridge.isTokenUsable,
               let fileURL = job.fileURL,
               let presigned = await SharePresignClient.presign(filename: fileName, folder: folder, idToken: bridge.idToken),
               let uploadURL = URL(string: presigned.uploadUrl) {
                job.s3PublicUrl = presigned.publicUrl
                job.s3UploadUrl = presigned.uploadUrl
                job.state = .uploadingS3
                ShareUploadManifestStore.append(job)
                ShareBackgroundUploader.shared.startUpload(fileURL: fileURL, uploadURL: uploadURL, jobId: jobId)
            } else {
                // No usable token / offline / presign failed — the app uploads it.
                ShareUploadManifestStore.append(job)
            }
        }

        ShareDarwinNotifier.post()
    }

    // MARK: - Cancel

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "co.opsapp.ops.OPS.ShareExtension", code: 0)
        )
    }
}
