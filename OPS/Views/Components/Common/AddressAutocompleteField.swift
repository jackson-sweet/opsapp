//
//  AddressAutocompleteField.swift
//  OPS
//
//  Created for providing address autocomplete functionality using MapKit
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
            HStack {
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

                // Use My Location button
                Button(action: {
                    useCurrentLocation()
                }) {
                    if isGettingLocation {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .disabled(isGettingLocation)

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        address = ""
                        searchResults = []
                        showingResults = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isFocused ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
            )
            
            // Search results
            if showingResults && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults.prefix(5), id: \.self) { result in
                        Button(action: {
                            selectAddress(result)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
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
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .background(OPSStyle.Colors.cardBackground)
                        
                        if result != searchResults.prefix(5).last {
                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
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
                // Check if we already have a location available
                if let location = locationManager.currentLocation {
                    reverseGeocode(location: location)
                }
                // If no location yet, the onChange handler will catch it when it arrives
            } else {
                DispatchQueue.main.async {
                    isGettingLocation = false
                    // Location permission denied - could show alert here
                }
            }
        }
    }

    private func reverseGeocode(location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard let placemark = placemarks?.first else {
                DispatchQueue.main.async {
                    isGettingLocation = false
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

