//
//  AddressAutocompleteField.swift
//  OPS
//
//  MapKit-backed address autocomplete with a "use my location" reverse-
//  geocode affordance. Shared by every address input in the app (profile,
//  company setup, org details, clients, projects, site visits).
//

import SwiftUI
import MapKit
import Combine
import CoreLocation

struct AddressAutocompleteField: View {
    @Binding var address: String
    let placeholder: String
    let onAddressSelected: ((String, CLLocationCoordinate2D?) -> Void)?

    @State private var searchText = ""
    @State private var searchResults: [MKLocalSearchCompletion] = []
    @State private var showingResults = false
    @State private var completer = MKLocalSearchCompleter()
    @StateObject private var searchCompleterDelegate = SearchCompleterDelegate()
    @StateObject private var locationManager = LocationManager()
    @State private var searchDebouncer = PassthroughSubject<String, Never>()
    @State private var isGettingLocation = false
    @State private var locationTimeoutTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    init(address: Binding<String>,
         placeholder: String = "Enter Address",
         onAddressSelected: ((String, CLLocationCoordinate2D?) -> Void)? = nil) {
        self._address = address
        self.placeholder = placeholder
        self.onAddressSelected = onAddressSelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Input field
            HStack(spacing: OPSStyle.Layout.spacing1) {
                TextField("", text: $searchText)
                    .placeholder(when: searchText.isEmpty) {
                        Text(placeholder)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .focused($isFocused)
                    .onChange(of: searchText) { _, newValue in
                        if newValue.isEmpty {
                            searchResults = []
                            showingResults = false
                        } else {
                            showingResults = true
                            // Send to debouncer instead of immediate search
                            searchDebouncer.send(newValue)
                        }
                    }

                // Use my location — reverse-geocodes the current position into
                // the field. Monochrome per the icon rules; accent is CTA-only.
                Button(action: {
                    useCurrentLocation()
                }) {
                    Group {
                        if isGettingLocation {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
                    .contentShape(Rectangle())
                }
                .disabled(isGettingLocation)
                .accessibilityLabel("Use my location")

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        address = ""
                        searchResults = []
                        showingResults = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(
                                width: OPSStyle.Layout.touchTargetMin,
                                height: OPSStyle.Layout.touchTargetMin
                            )
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Clear address")
                }
            }
            .padding(.leading, OPSStyle.Layout.spacing3)
            .padding(.trailing, OPSStyle.Layout.spacing1)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                // Focus brightens the hairline — never accent (DESIGN.md §9).
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        isFocused ? OPSStyle.Colors.inputFieldBorderFocus : OPSStyle.Colors.inputFieldBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )

            // Search results
            if showingResults && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults.prefix(5), id: \.self) { result in
                        Button(action: {
                            selectAddress(result)
                        }) {
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                Text(result.title)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)

                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .padding(.vertical, OPSStyle.Layout.spacing2_5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if result != searchResults.prefix(5).last {
                            Divider()
                                .background(OPSStyle.Colors.line)
                        }
                    }
                }
                .glassDense()
                .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .onAppear {
            setupCompleter()
            // Initialize with current address if available
            if !address.isEmpty {
                searchText = address
            }
        }
        .onChange(of: address) { _, newValue in
            // Sync binding changes to searchText (e.g., when "USE BILLING ADDRESS" is clicked)
            if searchText != newValue {
                searchText = newValue
            }
        }
        .onDisappear {
            completer.delegate = nil
            locationTimeoutTask?.cancel()
        }
        .onReceive(
            searchDebouncer
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        ) { searchQuery in
            // Perform search after debounce delay
            completer.queryFragment = searchQuery
        }
        .onChange(of: locationManager.currentLocation) { _, newLocation in
            // When location arrives and we're waiting for it, reverse geocode
            if isGettingLocation, let location = newLocation {
                reverseGeocode(location: location)
            }
        }
    }

    private func setupCompleter() {
        completer.delegate = searchCompleterDelegate
        completer.resultTypes = .address

        // Use wide search region for address autocomplete
        // This works well for any location in North America
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of US
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50)
        )

        searchCompleterDelegate.onResultsUpdated = { results in
            searchResults = results
        }
    }

    private func selectAddress(_ result: MKLocalSearchCompletion) {
        // Update the search text and bound address
        let fullAddress = result.title + (result.subtitle.isEmpty ? "" : ", " + result.subtitle)
        searchText = fullAddress
        address = fullAddress
        showingResults = false
        searchResults = []

        // Try to get coordinates for the selected address
        geocodeAddress(result) { coordinate in
            onAddressSelected?(fullAddress, coordinate)
        }

        // Dismiss keyboard
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func geocodeAddress(_ completion: MKLocalSearchCompletion,
                               completionHandler: @escaping (CLLocationCoordinate2D?) -> Void) {
        let searchRequest = MKLocalSearch.Request(completion: completion)
        let search = MKLocalSearch(request: searchRequest)

        search.start { response, error in
            guard let response = response,
                  let item = response.mapItems.first else {
                completionHandler(nil)
                return
            }

            completionHandler(item.placemark.coordinate)
        }
    }

    private func useCurrentLocation() {
        isGettingLocation = true

        // Request permission and check if we already have a location
        locationManager.requestPermissionIfNeeded(requestAlways: false) { granted in
            if granted {
                // Already have a fix → geocode immediately; otherwise the
                // onChange(currentLocation) handler catches the first fix.
                if let location = locationManager.currentLocation {
                    reverseGeocode(location: location)
                } else {
                    startLocationTimeout()
                }
            } else {
                DispatchQueue.main.async {
                    isGettingLocation = false
                    // Permission denied — name the problem and hand the user
                    // the path to fix it. Never a silent no-op.
                    ToastCenter.shared.present(Toast(
                        label: "// LOCATION OFF — ENABLE IN SETTINGS",
                        tone: .warning,
                        action: ToastAction(label: "SETTINGS") {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            UIApplication.shared.open(url)
                        }
                    ))
                }
            }
        }
    }

    /// GPS can dither indefinitely indoors — don't spin forever. After 10s
    /// without a fix, stop and say so.
    private func startLocationTimeout() {
        locationTimeoutTask?.cancel()
        locationTimeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, isGettingLocation else { return }
            isGettingLocation = false
            ToastCenter.shared.present(Toast(
                label: "// LOCATION UNAVAILABLE — TRY AGAIN",
                tone: .error
            ))
        }
    }

    private func reverseGeocode(location: CLLocation) {
        locationTimeoutTask?.cancel()
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first else {
                DispatchQueue.main.async {
                    isGettingLocation = false
                    ToastCenter.shared.present(Toast(
                        label: "// LOCATION UNAVAILABLE — TRY AGAIN",
                        tone: .error
                    ))
                }
                return
            }

            // Build address string from placemark
            var addressComponents: [String] = []

            if let streetNumber = placemark.subThoroughfare {
                addressComponents.append(streetNumber)
            }
            if let street = placemark.thoroughfare {
                if addressComponents.isEmpty {
                    addressComponents.append(street)
                } else {
                    addressComponents[0] += " " + street
                }
            }
            if let city = placemark.locality {
                addressComponents.append(city)
            }
            if let state = placemark.administrativeArea {
                addressComponents.append(state)
            }
            if let postalCode = placemark.postalCode {
                addressComponents.append(postalCode)
            }

            let fullAddress = addressComponents.joined(separator: ", ")

            DispatchQueue.main.async {
                isGettingLocation = false
                searchText = fullAddress
                address = fullAddress
                showingResults = false
                searchResults = []
                onAddressSelected?(fullAddress, location.coordinate)
            }
        }
    }
}

// Delegate to handle search completer results
class SearchCompleterDelegate: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    var onResultsUpdated: (([MKLocalSearchCompletion]) -> Void)?

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        onResultsUpdated?(completer.results)
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    }
}
