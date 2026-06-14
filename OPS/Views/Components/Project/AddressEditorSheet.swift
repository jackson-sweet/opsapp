//
//  AddressEditorSheet.swift
//  OPS
//
//  Address editor with inline predictive autocomplete via MapKit.
//

import SwiftUI
import MapKit

struct AddressEditorSheet: View {
    @Binding var address: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var draft: String = ""
    @StateObject private var completer = AddressCompleterModel()
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                Text("PROJECT ADDRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, OPSStyle.Layout.spacing2)

                // Address input field
                TextField("Start typing an address...", text: $draft, axis: .vertical)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(3...6)
                    .focused($isFieldFocused)
                    .padding(14)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(isFieldFocused
                                    ? OPSStyle.Colors.primaryAccent
                                    : OPSStyle.Colors.inputFieldBorder,
                                    lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .onChange(of: draft) { _, newValue in
                        completer.search(newValue)
                    }

                // Autocomplete suggestions
                if !completer.results.isEmpty && isFieldFocused {
                    VStack(spacing: 0) {
                        ForEach(completer.results, id: \.self) { result in
                            Button(action: {
                                selectCompletion(result)
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.title)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                            .lineLimit(1)
                                        if !result.subtitle.isEmpty {
                                            Text(result.subtitle)
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            if result != completer.results.last {
                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorderSubtle)
                                    .frame(height: 1)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .transition(.opacity)
                }

                Spacer()
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .standardSheetToolbar(
                title: "Edit Address",
                actionText: "Save",
                isActionEnabled: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                onCancel: { onCancel() },
                onAction: {
                    address = draft
                    onSave()
                }
            )
        }
        .onAppear {
            draft = address
            isFieldFocused = true
        }
    }

    private func selectCompletion(_ result: MKLocalSearchCompletion) {
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: result))
        search.start { response, _ in
            if let mapItem = response?.mapItems.first,
               let placemark = mapItem.placemark.formattedAddress {
                draft = placemark
                completer.clear()
            } else {
                // Fallback: concatenate title + subtitle
                draft = [result.title, result.subtitle]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                completer.clear()
            }
        }
    }
}

// MARK: - Address Completer Model

private class AddressCompleterModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
    }

    func search(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 3 {
            results = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        results = []
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = Array(completer.results.prefix(5))
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Silently handle — suggestions just won't appear
    }
}

// MARK: - CLPlacemark Extension

private extension CLPlacemark {
    var formattedAddress: String? {
        let parts = [
            subThoroughfare,
            thoroughfare,
            locality,
            administrativeArea,
            postalCode,
            country
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
