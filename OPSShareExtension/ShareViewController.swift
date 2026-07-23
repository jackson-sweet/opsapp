//
//  ShareViewController.swift
//  OPSShareExtension
//
//  Principal class for the "Add to OPS" share extension. Hosts the SwiftUI
//  picker and, on confirm, downscales the shared photos into the App Group
//  inbox, enqueues them in the shared manifest, and — when the bridged token is
//  usable — starts the same idempotent server request the app will retry from
//  the durable queue. The sheet only celebrates once every selected photo is
//  durably represented in that queue.
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
        view.backgroundColor = UIColor(ShareTheme.Color.background)

        ShareFontRegistrar.registerIfNeeded()

        let bridge = ShareSessionBridgeStore.read()
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let photoCount = ShareImageProcessor.imageProviderCount(in: items)
        let content = resolveContent(bridge: bridge, photoCount: photoCount)

        let model = SharePickerModel(content: content, photoCount: photoCount)
        model.onCancel = { [weak self] in self?.cancel() }
        model.onClose = { [weak self] in self?.close() }
        model.onConfirm = { [weak self] project in
            self?.confirm(project: project, bridge: bridge, items: items)
        }
        self.model = model

        let host = UIHostingController(rootView: SharePickerView(model: model))
        host.view.backgroundColor = UIColor(ShareTheme.Color.background)
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
            let outcome = await self.stageAndQueue(
                project: project,
                bridge: bridge,
                items: items
            )
            switch outcome {
            case .queued(let count):
                self.model.confirmedTitle = project.title
                self.model.confirmedPhotoCount = count
                self.model.phase = .done
                ShareHaptics.success()
                // Let the success state read before dismissing.
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                self.extensionContext?.completeRequest(
                    returningItems: [],
                    completionHandler: nil
                )
            case .failed:
                self.model.phase = .failed
                ShareHaptics.failure()
            case .retainedForRecovery:
                self.model.phase = .retainedForRecovery
                ShareHaptics.failure()
            }
        }
    }

    /// Downscales every selected image and commits an immutable recovery record
    /// for the complete batch before any network request starts. The mutable
    /// manifest is then a fast-path index; even if that second write fails, the
    /// app can reconstruct every job from the recovery record. Partial capture is
    /// rolled back before either record is attempted.
    private func stageAndQueue(
        project: ShareProjectRef,
        bridge: ShareSessionBridge?,
        items: [NSExtensionItem]
    ) async -> ShareCaptureOutcome {
        let selectedCount = ShareImageProcessor.imageProviderCount(in: items)
        let fileNames = await ShareImageProcessor.stageImages(from: items)
        Self.log.info("share: staged \(fileNames.count, privacy: .public) image(s) for project \(project.id, privacy: .public); session=\(bridge != nil, privacy: .public)")
        guard selectedCount > 0,
              fileNames.count == selectedCount,
              let bridge else {
            Self.deleteStagedFiles(named: fileNames)
            Self.log.error(
                "share: capture incomplete (\(fileNames.count, privacy: .public)/\(selectedCount, privacy: .public)) or session unavailable — nothing queued"
            )
            return .failed
        }

        let capturedAt = Date()
        let jobs = fileNames.map { fileName in
            ShareUploadJob(
                id: (fileName as NSString).deletingPathExtension,
                fileName: fileName,
                projectId: project.id,
                projectTitle: project.title,
                companyId: bridge.companyId,
                uploadedBy: bridge.userId,
                createdAt: capturedAt
            )
        }
        let recoveryResult = ShareUploadRecoveryStore.save(jobs)
        let outcome = ShareCaptureOutcome(
            selectedCount: selectedCount,
            persistedCount: jobs.count,
            recoveryResult: recoveryResult
        )
        if outcome.shouldDiscardStagedFiles {
            Self.deleteStagedFiles(named: fileNames)
            Self.log.error(
                "share: atomic recovery record failed before commit — staged files rolled back and no success shown"
            )
            return .failed
        }
        if outcome == .retainedForRecovery {
            // The recovery-record write was attempted but its acknowledgement
            // was ambiguous. Never delete or offer a duplicate-producing retry.
            // Nudge the app: if the record landed, it can safely drain it.
            Self.log.error(
                "share: recovery-record acknowledgement uncertain — photo bytes retained for app inspection"
            )
            ShareDarwinNotifier.post()
            return .retainedForRecovery
        }

        let appendResult = ShareUploadManifestStore.append(jobs)
        if appendResult != .committed {
            // The immutable recovery record is the durable source of truth, so
            // the app can still drain this accepted share without a manifest row.
            Self.log.error(
                "share: mutable manifest unavailable (\(String(describing: appendResult), privacy: .public)); recovery record will drive upload"
            )
        }

        let tokenUsable = bridge.isTokenUsable
        for job in jobs {
            // Best-effort INSTANT path: fire the photo at the server endpoint on a
            // background transfer so it can land even if OPS is never opened. The
            // durable queue is the guaranteed backstop; both paths use this job ID.
            if tokenUsable, let token = bridge.idToken, let fileURL = job.fileURL {
                let started = ShareBackgroundUploader.shared.startUpload(
                    fileURL: fileURL,
                    projectId: project.id,
                    jobId: job.id,
                    takenAt: job.createdAt,
                    idToken: token
                )
                Self.log.info(
                    "share: instant endpoint for \(job.id, privacy: .public) started=\(started, privacy: .public)"
                )
            }
        }
        Self.log.info(
            "share: durably queued \(jobs.count, privacy: .public) job(s)"
        )

        // Nudge a running app to drain immediately; otherwise it drains on next open.
        ShareDarwinNotifier.post()
        return outcome
    }

    private static func deleteStagedFiles(named fileNames: [String]) {
        guard let inbox = AppGroupConfig.inboxDirectoryURL else { return }
        for fileName in fileNames {
            let fileURL = inbox.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    // MARK: - Cancel

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "co.opsapp.ops.OPS.ShareExtension", code: 0)
        )
    }

    private func close() {
        extensionContext?.completeRequest(
            returningItems: [],
            completionHandler: nil
        )
    }
}
