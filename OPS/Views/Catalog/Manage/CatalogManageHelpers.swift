//
//  CatalogManageHelpers.swift
//  OPS
//
//  Shared form/section helpers used by the catalog kebab manage sheets.
//  Kept narrow on purpose — Section / Field labels and a common
//  text-field style that all four sheets need.
//
//  Also hosts the inline "+ NEW CATEGORY…" / "+ NEW UNIT…" sheets that
//  are reused from BOTH the Add Product flow and the Product detail
//  edit flow. Lifting them out of QuickAddProductSheet means the same
//  two-tap inline creation works wherever a CatalogCategory / CatalogUnit
//  picker lives.
//

import SwiftUI
import SwiftData

@ViewBuilder
func CatalogSectionHeader(_ title: String) -> some View {
    Text("// \(title)")
        .font(OPSStyle.Typography.panelTitle)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}

@ViewBuilder
func CatalogFieldLabel(_ title: String) -> some View {
    Text(title)
        .font(OPSStyle.Typography.category)
        .foregroundColor(OPSStyle.Colors.tertiaryText)
}

struct CatalogTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}

// MARK: - Inline Create Category Sheet

/// Minimal "+ NEW CATEGORY…" sheet — name only. The full Categories
/// management screen handles parent nesting, sort order, color, and
/// thresholds; this sheet is for the user who realized mid-product-create
/// (or mid-edit) that they need a new category and wants it in two taps.
///
/// Shared between QuickAddProductSheet and ProductDetailView.
struct InlineCreateCategorySheet: View {
    let companyId: String
    let onCreated: (String) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allCategories: [CatalogCategory]

    @State private var name: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    /// Sort order for the new row — append to the end of the company's
    /// existing categories so the picker keeps a stable order.
    private var nextSortOrder: Int {
        let local = allCategories.filter { $0.companyId == companyId && $0.deletedAt == nil }
        let max = local.map(\.sortOrder).max() ?? 0
        return max + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            CatalogSectionHeader("CATEGORY")
                            CatalogFieldLabel("Name")
                            TextField("e.g. Hardware", text: $name)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($nameFocused)
                                .submitLabel(.done)
                                .onSubmit { Task { await save() } }
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .catalogNavigationTitle("NEW CATEGORY")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(canSave
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    nameFocused = true
                }
            }
        }
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let dto = CreateCatalogCategoryDTO(
            companyId: companyId,
            name: trimmed,
            parentId: nil,
            sortOrder: nextSortOrder,
            colorHex: nil,
            defaultWarningThreshold: nil,
            defaultCriticalThreshold: nil
        )

        do {
            let repo = CatalogRepository(companyId: companyId)
            let created = try await repo.createCategory(dto)
            // Insert into local store so the parent picker sees the new row
            // before the next sync round.
            let model = created.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(created.id)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Inline Create Unit Sheet

/// Minimal "+ NEW UNIT…" sheet — display + dimension. Abbreviation,
/// default flag, and sort order can be edited later from the full Units
/// management screen.
///
/// Shared between QuickAddProductSheet and ProductDetailView.
struct InlineCreateUnitSheet: View {
    let companyId: String
    let onCreated: (String) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allUnits: [CatalogUnit]

    @State private var display: String = ""
    @State private var dimension: String = "count"
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    @FocusState private var displayFocused: Bool

    /// The six dimension values match the Postgres check constraint on
    /// catalog_units.dimension. Display labels are user-friendly; the
    /// raw value goes to Supabase.
    private static let dimensions: [(raw: String, label: String)] = [
        ("count",  "Count"),
        ("length", "Length"),
        ("area",   "Area"),
        ("volume", "Volume"),
        ("mass",   "Mass"),
        ("time",   "Time"),
    ]

    private var canSave: Bool {
        !display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    private var nextSortOrder: Int {
        let local = allUnits.filter { $0.companyId == companyId && $0.deletedAt == nil }
        let max = local.map(\.sortOrder).max() ?? 0
        return max + 1
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            CatalogSectionHeader("UNIT")
                            CatalogFieldLabel("Display")
                            TextField("e.g. BOARD FT", text: $display)
                                .textFieldStyle(CatalogTextFieldStyle())
                                .focused($displayFocused)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .submitLabel(.done)
                                .onSubmit { Task { await save() } }

                            CatalogFieldLabel("Dimension")
                            dimensionPicker
                        }
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .catalogNavigationTitle("NEW UNIT")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(canSave
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    displayFocused = true
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private var dimensionPicker: some View {
        Picker("Dimension", selection: $dimension) {
            ForEach(Self.dimensions, id: \.raw) { entry in
                Text(entry.label).tag(entry.raw)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: dimension) { _, _ in
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    @MainActor
    private func save() async {
        let trimmed = display.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let dto = CreateCatalogUnitDTO(
            companyId: companyId,
            display: trimmed,
            abbreviation: nil,
            dimension: dimension,
            isDefault: false,
            sortOrder: nextSortOrder
        )

        do {
            let repo = CatalogRepository(companyId: companyId)
            let created = try await repo.createUnit(dto)
            let model = created.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            modelContext.insert(model)
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCreated(created.id)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Pricing-unit ↔ CatalogUnit dimension mapping

/// Maps a CatalogUnit to the closest ProductPricingUnit enum case.
/// The enum is what drives display formatting elsewhere in the app
/// (estimate line items, product list price suffix). nil unit means
/// flat-rate. The mapping is best-effort by dimension because the
/// enum's six cases don't cover every possible custom unit display.
///
/// Shared between create and edit flows so the two paths stay in sync.
func pricingUnit(for unit: CatalogUnit?) -> ProductPricingUnit {
    guard let unit = unit else { return .flatRate }

    let display = unit.display.lowercased()
    let dimension = unit.dimension.lowercased()

    if display.contains("hour") || display == "hr" { return .hour }
    if display.contains("day")  { return .day }

    switch dimension {
    case "length": return .linearFoot
    case "area":   return .sqft
    case "time":
        // Generic "time" without an obvious hour/day signal — fall
        // back to flatRate rather than guess wrong.
        return .flatRate
    case "count":  return .each
    default:       return .flatRate
    }
}
