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
import os

final class ShareViewController: UIViewController {

    private static let log = Logger(subsystem: "co.opsapp.ops.share", category: "extension")

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
            await self.stageAndQueue(project: project, bridge: bridge, items: items)
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
    /// Downscales every shared image into the App Group inbox, appends a job to
    /// the shared manifest, and nudges a running app to drain. The app uploads
    /// each through its proven pipeline on next open / when back online — the
    /// extension never uploads, so this works offline and needs no auth token.
    private func stageAndQueue(project: ShareProjectRef, bridge: ShareSessionBridge?, items: [NSExtensionItem]) async {
        let fileNames = await ShareImageProcessor.stageImages(from: items)
        Self.log.info("share: staged \(fileNames.count, privacy: .public) image(s) for project \(project.id, privacy: .public); session=\(bridge != nil, privacy: .public)")
        guard !fileNames.isEmpty, let bridge else {
            Self.log.error("share: nothing staged (or no session) — aborting")
            return
        }

        let tokenUsable = bridge.isTokenUsable
        for fileName in fileNames {
            let jobId = (fileName as NSString).deletingPathExtension
            let job = ShareUploadJob(
                id: jobId,
                fileName: fileName,
                projectId: project.id,
                projectTitle: project.title,
                companyId: bridge.companyId,
                uploadedBy: bridge.userId,
                createdAt: Date()
            )
            ShareUploadManifestStore.append(job)

            // Best-effort INSTANT path: fire the photo at the server endpoint on a
            // background transfer so it can land even if OPS is never opened. The
            // queued job above is the guaranteed backstop; the endpoint is
            // idempotent by jobId so the app's drain won't double-upload it.
            if tokenUsable, let token = bridge.idToken, let fileURL = job.fileURL {
                ShareBackgroundUploader.shared.startUpload(
                    fileURL: fileURL,
                    projectId: project.id,
                    jobId: jobId,
                    idToken: token
                )
                Self.log.info("share: job \(jobId, privacy: .public) sent to instant endpoint")
            }
        }
        Self.log.info("share: queued \(fileNames.count, privacy: .public) job(s) for the app to upload")

        // Nudge a running app to drain immediately; otherwise it drains on next open.
        ShareDarwinNotifier.post()
    }

    // MARK: - Cancel

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "co.opsapp.ops.OPS.ShareExtension", code: 0)
        )
    }
}
