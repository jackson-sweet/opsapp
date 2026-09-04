import SwiftUI
import UniformTypeIdentifiers
import VisionKit
import PDFKit

struct SupplierBillsLedger: View {
    @ObservedObject var viewModel: SupplierBillIntakeViewModel
    let stage: SupplierBillStage

    @State private var selectedBill: SupplierBillIntake?

    private var rows: [SupplierBillIntake] {
        viewModel.bills
            .filter(stage.matches)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.bills.isEmpty {
                ProgressView()
                    .tint(OPSStyle.Colors.text2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.emptyStatePadding)
            } else if rows.isEmpty {
                BooksLedgerEmpty(
                    value: "—",
                    label: emptyLabel,
                    hint: emptyHint
                )
            } else {
                LazyVStack(spacing: 0) {
                    if viewModel.isUsingCachedData {
                        SupplierBillOfflineStrip()
                    }
                    ForEach(rows) { bill in
                        SupplierBillLedgerRow(bill: bill) {
                            selectedBill = bill
                        }
                    }
                    BooksLedgerEndMarker(text: "\(rows.count) BILLS")
                }
            }
        }
        .sheet(item: $selectedBill, onDismiss: viewModel.clearDetail) { bill in
            SupplierBillDetailSheet(bill: bill, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var emptyLabel: String {
        switch stage {
        case .review: return "NOTHING TO REVIEW"
        case .toPay: return "NOTHING TO PAY"
        case .paid: return "NO PAID BILLS"
        case .held: return "NO HELD BILLS"
        case .payroll: return "NO PAYROLL INVOICES"
        }
    }

    private var emptyHint: String {
        switch stage {
        case .review: return "CAPTURE A SUPPLIER PDF TO START"
        case .toPay: return "APPROVED BILLS LAND HERE"
        case .paid: return "PAYMENT HISTORY LANDS HERE"
        case .held: return "EXCEPTIONS STAY VISIBLE HERE"
        case .payroll: return "EMPLOYEE INVOICES ROUTE HERE"
        }
    }
}

private struct SupplierBillOfflineStrip: View {
    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(OPSStyle.Colors.tan)
                .frame(width: OPSStyle.Layout.spacing1, height: OPSStyle.Layout.spacing1)
            Text("OFFLINE COPY")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tan)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: OPSStyle.Layout.hairlineWidth)
        }
        .accessibilityLabel("Offline copy. Bill updates may be delayed.")
    }
}

private struct SupplierBillLedgerRow: View {
    let bill: SupplierBillIntake
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
                    Text(bill.displaySupplier)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(SupplierBillPresentation.money(bill.total, currency: bill.currency))
                        .font(OPSStyle.Typography.dataValue)
                        .foregroundColor(bill.reviewStage.color)
                        .monospacedDigit()
                }

                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(bill.displayInvoiceNumber)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)

                    BooksPillView(pill: BooksPill(
                        text: bill.reviewStage.label,
                        color: bill.reviewStage.color
                    ))

                    Spacer(minLength: 0)

                    Text(SupplierBillPresentation.dueLabel(bill.dueDate))
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(bill.dueDate == nil ? OPSStyle.Colors.text3 : OPSStyle.Colors.text2)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(OPSStyle.Colors.lineSoft)
                    .frame(height: OPSStyle.Layout.hairlineWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(bill.displaySupplier), \(bill.displayInvoiceNumber), "
                + "\(SupplierBillPresentation.money(bill.total, currency: bill.currency)), "
                + bill.reviewStage.label
        )
        .accessibilityHint("Opens the supplier bill review")
    }
}

struct SupplierBillCaptureSheet: View {
    @ObservedObject var viewModel: SupplierBillIntakeViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var documentKind: SupplierDocumentKind = .material
    @State private var showImporter = false
    @State private var showScanner = false
    @State private var isSaving = false
    @State private var resultText: String?
    @State private var captureError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OPSScreenHeader("CAPTURE BILL") {
                    EmptyView()
                } trailing: {
                    OPSHeaderCloseButton { dismiss() }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("// BILL TYPE")
                                .font(OPSStyle.Typography.panelTitle)
                                .foregroundColor(OPSStyle.Colors.text3)

                            Text("Choose where this invoice belongs before OPS reads it.")
                                .font(OPSStyle.Typography.smallBody)
                                .foregroundColor(OPSStyle.Colors.text2)
                        }

                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(SupplierDocumentKind.allCases) { kind in
                                SupplierBillKindButton(
                                    kind: kind,
                                    isSelected: documentKind == kind
                                ) {
                                    documentKind = kind
                                    resultText = nil
                                }
                            }
                        }

                        if let resultText {
                            SupplierBillCaptureNotice(
                                text: resultText,
                                tone: resultText.contains("DEVICE")
                                    ? OPSStyle.Colors.tan
                                    : OPSStyle.Colors.olive
                            )
                        } else if viewModel.pendingCaptureCount > 0 {
                            SupplierBillCaptureNotice(
                                text: "\(viewModel.pendingCaptureCount) SAVED ON DEVICE · SYNCING WHEN ONLINE",
                                tone: OPSStyle.Colors.tan
                            )
                        }

                        Button {
                            showImporter = true
                        } label: {
                            if isSaving {
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    ProgressView()
                                        .tint(OPSStyle.Colors.opsAccent)
                                    Text("SAVING BILL")
                                }
                            } else {
                                Text("CHOOSE PDF")
                            }
                        }
                        .opsPrimaryButtonStyle(isDisabled: isSaving)
                        .disabled(isSaving)

                        if VNDocumentCameraViewController.isSupported {
                            Button {
                                showScanner = true
                            } label: {
                                Text("SCAN PAPER")
                            }
                            .opsSecondaryButtonStyle()
                            .disabled(isSaving)
                        }

                        Text("Original PDFs only · 20 MB max · 25 offline captures per device")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .multilineTextAlignment(.center)
                    }
                    .padding(OPSStyle.Layout.spacing3_5)
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                save(url)
            case .failure(let error):
                captureError = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            SupplierBillDocumentScanner { images in
                saveScannedPages(images)
            } onFailure: { error in
                captureError = error.localizedDescription
            }
            .ignoresSafeArea()
        }
        .errorToast($captureError, label: "BILL NOT SAVED")
    }

    private func save(_ url: URL, removeAfterSave: Bool = false) {
        let hasSecurityScope = url.startAccessingSecurityScopedResource()
        isSaving = true
        resultText = nil
        Task {
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
                if removeAfterSave { try? FileManager.default.removeItem(at: url) }
                isSaving = false
            }
            do {
                let result = try await viewModel.capture(
                    sourceURL: url,
                    originalFilename: url.lastPathComponent,
                    documentKind: documentKind
                )
                switch result {
                case .uploaded:
                    resultText = documentKind == .employee
                        ? "SAVED TO OPS · ROUTED TO PAYROLL"
                        : "SAVED TO OPS · READY FOR REVIEW"
                case .queued:
                    resultText = "SAVED ON DEVICE · SYNCING WHEN ONLINE"
                case .needsAttention(let reason):
                    resultText = "SAVED ON DEVICE · REVIEW REQUIRED"
                    captureError = reason
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                captureError = error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func saveScannedPages(_ images: [UIImage]) {
        guard !images.isEmpty else {
            captureError = "No invoice pages were captured."
            return
        }

        let document = PDFDocument()
        for image in images {
            guard let page = PDFPage(image: image) else {
                captureError = "A scanned invoice page could not be saved."
                return
            }
            document.insert(page, at: document.pageCount)
        }
        guard let data = document.dataRepresentation() else {
            captureError = "The scanned invoice could not be saved as a PDF."
            return
        }

        let filename = "supplier-bill-\(UUID().uuidString.lowercased()).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            save(url, removeAfterSave: true)
        } catch {
            captureError = "The scanned invoice could not be saved on this device."
        }
    }
}

private struct SupplierBillDocumentScanner: UIViewControllerRepresentable {
    let onComplete: ([UIImage]) -> Void
    let onFailure: (Error) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(
        _ uiViewController: VNDocumentCameraViewController,
        context: Context
    ) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let parent: SupplierBillDocumentScanner

        init(parent: SupplierBillDocumentScanner) {
            self.parent = parent
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let images = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            parent.dismiss()
            parent.onComplete(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.dismiss()
            parent.onFailure(error)
        }
    }
}

private struct SupplierBillKindButton: View {
    let kind: SupplierDocumentKind
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text3)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(kind.label)
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                    Text(kind.detail)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetLarge)
            .background(isSelected ? OPSStyle.Colors.surfaceSelected : OPSStyle.Colors.surfaceInput)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            .overlay {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .strokeBorder(
                        isSelected ? OPSStyle.Colors.activeSegmentBorder : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.hairlineWidth
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.label), \(kind.detail)\(isSelected ? ", selected" : "")")
    }
}

private struct SupplierBillCaptureNotice: View {
    let text: String
    let tone: Color

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Circle()
                .fill(tone)
                .frame(width: OPSStyle.Layout.spacing1, height: OPSStyle.Layout.spacing1)
            Text(text)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(tone)
                .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .strokeBorder(tone.opacity(OPSStyle.Colors.StatusTagM.border), lineWidth: OPSStyle.Layout.hairlineWidth)
        }
    }
}

private struct SupplierBillDetailSheet: View {
    let bill: SupplierBillIntake
    @ObservedObject var viewModel: SupplierBillIntakeViewModel

    @Environment(\.dismiss) private var dismiss

    private var detail: SupplierBillIntakeDetail? {
        guard viewModel.selectedDetail?.intake.id == bill.id else { return nil }
        return viewModel.selectedDetail
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                OPSScreenHeader("BILL REVIEW") {
                    EmptyView()
                } trailing: {
                    OPSHeaderCloseButton { dismiss() }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        summary

                        if viewModel.isLoadingDetail && detail == nil {
                            ProgressView()
                                .tint(OPSStyle.Colors.text2)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OPSStyle.Layout.emptyStatePadding)
                        } else if let detail {
                            canproChecks(detail.checks)
                            invoiceLines(detail.lines)
                            sourceDocument(detail.document)
                        }

                        SupplierBillCaptureNotice(
                            text: bill.documentKind == .employee
                                ? "PAYROLL HANDOFF STAYS IN OPS WEB"
                                : "APPROVAL + PAYMENT STAY IN OPS WEB",
                            tone: OPSStyle.Colors.text2
                        )
                    }
                    .padding(OPSStyle.Layout.spacing3_5)
                }
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .task { await viewModel.loadDetail(intakeId: bill.id) }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text(bill.displaySupplier)
                    .font(OPSStyle.Typography.section)
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(SupplierBillPresentation.money(bill.total, currency: bill.currency))
                    .font(OPSStyle.Typography.dataValueLg)
                    .foregroundColor(bill.reviewStage.color)
                    .monospacedDigit()
            }

            SupplierBillDetailRow(label: "INVOICE", value: bill.displayInvoiceNumber)
            SupplierBillDetailRow(label: "TYPE", value: bill.documentKind.label)
            SupplierBillDetailRow(label: "INVOICE DATE", value: SupplierBillPresentation.shortDate(bill.invoiceDate))
            SupplierBillDetailRow(label: "DUE", value: SupplierBillPresentation.shortDate(bill.dueDate))
            SupplierBillDetailRow(label: "PO", value: bill.purchaseOrder)

            if let holdReason = bill.holdReason, !holdReason.isEmpty {
                SupplierBillDetailRow(label: "HOLD", value: holdReason, tone: OPSStyle.Colors.rose)
            }
            if let nextAction = bill.nextAction, !nextAction.isEmpty {
                SupplierBillDetailRow(label: "NEXT", value: nextAction, tone: OPSStyle.Colors.tan)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private func canproChecks(_ checks: [SupplierBillIntakeCheck]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            PanelSectionHeader(label: "CANPRO CHECKS", count: checks.count)

            if checks.isEmpty {
                Text(bill.documentKind == .employee
                     ? "EMPLOYEE INVOICE · OUTSIDE PAYABLES"
                     : "CHECKS PENDING")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
            } else {
                VStack(spacing: 0) {
                    ForEach(checks) { check in
                        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                Text(check.checkKey.label)
                                    .font(OPSStyle.Typography.category)
                                    .foregroundColor(OPSStyle.Colors.text)
                                if let note = check.note, !note.isEmpty {
                                    Text(note)
                                        .font(OPSStyle.Typography.smallBody)
                                        .foregroundColor(OPSStyle.Colors.text2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            BooksPillView(pill: BooksPill(
                                text: check.statusLabel,
                                color: check.color
                            ))
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(OPSStyle.Colors.lineSoft)
                                .frame(height: OPSStyle.Layout.hairlineWidth)
                        }
                    }
                }
            }
        }
    }

    private func invoiceLines(_ lines: [SupplierBillIntakeLine]) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            PanelSectionHeader(label: "INVOICE LINES", count: lines.count)

            if lines.isEmpty {
                Text("EXTRACTION PENDING")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
            } else {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                                Text(line.description.uppercased())
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(SupplierBillPresentation.money(line.total, currency: bill.currency))
                                    .font(OPSStyle.Typography.dataValue)
                                    .foregroundColor(OPSStyle.Colors.text)
                                    .monospacedDigit()
                            }

                            Text(SupplierBillPresentation.lineMeta(line, currency: bill.currency))
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.text3)
                                .monospacedDigit()

                            Text(line.jobHint?.uppercased() ?? "JOB NOT CONFIRMED")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(line.matchedProjectId == nil
                                                 ? OPSStyle.Colors.tan
                                                 : OPSStyle.Colors.olive)
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(OPSStyle.Colors.lineSoft)
                                .frame(height: OPSStyle.Layout.hairlineWidth)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sourceDocument(_ document: SupplierBillIntakeDocument?) -> some View {
        if let document, let url = URL(string: document.publicUrl) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                PanelSectionHeader(label: "SOURCE")
                Link(destination: url) {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text(document.originalFilename.uppercased())
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("VIEW PDF →")
                    }
                }
                .opsSecondaryButtonStyle()
            }
        }
    }
}

private struct SupplierBillDetailRow: View {
    let label: String
    let value: String?
    var tone: Color = OPSStyle.Colors.text2

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing3) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
            Spacer(minLength: 0)
            Text(displayValue)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(displayValue == "—" ? OPSStyle.Colors.text3 : tone)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }

    private var displayValue: String {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "—"
        }
        return value.uppercased()
    }
}

private enum SupplierBillPresentation {
    static func money(_ raw: String, currency: String) -> String {
        guard let amount = Double(raw) else { return BooksFormat.emptyCurrency }
        return BooksFormat.exact(amount, code: currency)
    }

    static func dueLabel(_ raw: String?) -> String {
        guard raw != nil else { return "DUE —" }
        return "DUE \(shortDate(raw))"
    }

    static func shortDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "—" }
        let source = DateFormatter()
        source.locale = Locale(identifier: "en_US_POSIX")
        source.dateFormat = "yyyy-MM-dd"
        guard let date = source.date(from: String(raw.prefix(10))) else {
            return raw.uppercased()
        }
        let output = DateFormatter()
        output.locale = BooksFormat.locale
        output.dateFormat = "MMM d, yyyy"
        return output.string(from: date).uppercased()
    }

    static func lineMeta(_ line: SupplierBillIntakeLine, currency: String) -> String {
        let quantity = Double(line.invoicedQuantity).map {
            $0.formatted(.number.precision(.fractionLength(0...2)).locale(BooksFormat.locale))
        } ?? line.invoicedQuantity
        let unit = line.unitOfMeasure?.uppercased() ?? "EA"
        return "\(quantity) \(unit) · \(money(line.unitPrice, currency: currency))/\(unit)"
    }
}
