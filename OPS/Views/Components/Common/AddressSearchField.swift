//
//  AddressSearchField.swift
//  OPS
//
//  Address field with predictive autocomplete using MapKit
//

import SwiftUI
import MapKit
import CoreLocation

struct AddressSearchField: View {
    @Binding var address: String
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var showingSuggestions = false
    @StateObject private var locationProvider = AddressLocationProvider()
    @FocusState private var isFocused: Bool
    
    let placeholder: String
    
    init(address: Binding<String>, placeholder: String = "Enter address") {
        self._address = address
        self.placeholder = placeholder
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Address input field
            TextField(placeholder, text: $address)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .focused($isFocused)
                .onChange(of: address) { newValue in
                    if !newValue.isEmpty && isFocused {
                        searchForAddress(newValue)
                    } else {
                        searchResults = []
                        showingSuggestions = false
                    }
                }
                .onTapGesture {
                    if !address.isEmpty {
                        searchForAddress(address)
                    }
                }
            
            // Suggestions dropdown
            if showingSuggestions && !searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(searchResults.prefix(5), id: \.self) { item in
                        Button(action: {
                            selectAddress(item)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = item.name {
                                    Text(name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .lineLimit(1)
                                }
                                
                                let placemark = item.placemark
                                Text(formatAddress(placemark))
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        if item != searchResults.prefix(5).last {
                            Divider()
                                .background(OPSStyle.Colors.tertiaryText.opacity(0.3))
                        }
                    }
                }
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showingSuggestions)
    }
    
    private func searchForAddress(_ query: String) {
        guard !query.isEmpty else {
            searchResults = []
            showingSuggestions = false
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        
        // Prioritize nearby addresses if location is available
        if let location = locationProvider.lastLocation {
            let span = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            request.region = MKCoordinateRegion(center: location.coordinate, span: span)
            request.resultTypes = [.address, .pointOfInterest]
        }
        
        let search = MKLocalSearch(request: request)
        
        search.start { response, error in
            Task { @MainActor in
                self.isSearching = false
                
                if let response = response {
                    // Sort results by distance if we have location
                    if let userLocation = locationProvider.lastLocation {
                        self.searchResults = response.mapItems.sorted { item1, item2 in
                            let distance1 = item1.placemark.location?.distance(from: userLocation) ?? Double.infinity
                            let distance2 = item2.placemark.location?.distance(from: userLocation) ?? Double.infinity
                            return distance1 < distance2
                        }
                    } else {
                        self.searchResults = response.mapItems
                    }
                    self.showingSuggestions = true
                } else {
                    self.searchResults = []
                    self.showingSuggestions = false
                }
            }
        }
    }
    
    private func selectAddress(_ mapItem: MKMapItem) {
        let placemark = mapItem.placemark
        address = formatAddress(placemark)
        searchResults = []
        showingSuggestions = false
        isFocused = false
    }
    
    private func formatAddress(_ placemark: CLPlacemark) -> String {
        var components: [String] = []
        
        // Build address from components
        if let streetNumber = placemark.subThoroughfare {
            components.append(streetNumber)
        }
        if let street = placemark.thoroughfare {
            components.append(street)
        }
        
        let streetAddress = components.joined(separator: " ")
        components = streetAddress.isEmpty ? [] : [streetAddress]
        
        if let city = placemark.locality {
            components.append(city)
        }
        if let state = placemark.administrativeArea {
            components.append(state)
        }
        if let postalCode = placemark.postalCode {
            components.append(postalCode)
        }
        
        return components.joined(separator: ", ")
    }
}

// MARK: - Location Provider

class AddressLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        requestLocationPermission()
    }
    
    func requestLocationPermission() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }
}