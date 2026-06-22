//
//  ShareViewController.swift
//  OPSShareExtension
//
//  Principal class for the "Add to OPS" share extension. Skeleton — the full
//  picker UI + capture/enqueue pipeline is wired in a later step.
//

import UIKit

final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Skeleton placeholder: complete immediately so the extension dismisses.
        // Replaced by the hosted SwiftUI picker in the full implementation.
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
