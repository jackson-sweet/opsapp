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
    @EnvironmentObject private var locationManager: LocationManager
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
                .font(OPSStyle.Layout.SearchField.textFont)
                .foregroundColor(OPSStyle.Layout.SearchField.textColor)
                .padding(OPSStyle.Layout.SearchField.inputPadding)
                .background(OPSStyle.Layout.SearchField.inputBackground)
                .cornerRadius(OPSStyle.Layout.SearchField.inputCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.SearchField.inputCornerRadius)
                        .stroke(
                            OPSStyle.Layout.SearchField.inputBorderColor,
                            lineWidth: OPSStyle.Layout.SearchField.inputBorderWidth
                        )
                )
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
                    ForEach(searchResults.prefix(OPSStyle.Layout.SearchField.dropdownMaxResults), id: \.self) { item in
                        Button(action: {
                            selectAddress(item)
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let name = item.name {
                                    Text(name)
                                        .font(OPSStyle.Layout.SearchField.rowTitleFont)
                                        .foregroundColor(OPSStyle.Layout.SearchField.rowTitleColor)
                                        .lineLimit(1)
                                }

                                let placemark = item.placemark
                                Text(formatAddress(placemark))
                                    .font(OPSStyle.Layout.SearchField.rowSubtitleFont)
                                    .foregroundColor(OPSStyle.Layout.SearchField.rowSubtitleColor)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, OPSStyle.Layout.SearchField.rowPaddingHorizontal)
                            .padding(.vertical, OPSStyle.Layout.SearchField.rowPaddingVertical)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())

                        if item != searchResults.prefix(OPSStyle.Layout.SearchField.dropdownMaxResults).last {
                            Divider()
                                .background(OPSStyle.Layout.SearchField.dividerColor)
                        }
                    }
                }
                .background(OPSStyle.Layout.SearchField.dropdownBackground)
                .cornerRadius(OPSStyle.Layout.SearchField.dropdownCornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.SearchField.dropdownCornerRadius)
                        .stroke(
                            OPSStyle.Layout.SearchField.dropdownBorderColor,
                            lineWidth: OPSStyle.Layout.SearchField.dropdownBorderWidth
                        )
                )
                .shadow(
                    color: OPSStyle.Layout.SearchField.dropdownShadowColor,
                    radius: OPSStyle.Layout.SearchField.dropdownShadowRadius,
                    x: OPSStyle.Layout.SearchField.dropdownShadowOffset.width,
                    y: OPSStyle.Layout.SearchField.dropdownShadowOffset.height
                )
                .padding(.top, OPSStyle.Layout.SearchField.dropdownTopPadding)
                .transition(OPSStyle.Layout.SearchField.transition)
            }
        }
        .animation(OPSStyle.Layout.SearchField.animationCurve, value: showingSuggestions)
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
        if let userCoordinate = locationManager.userLocation {
            let span = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5) // ~50km radius
            request.region = MKCoordinateRegion(center: userCoordinate, span: span)
            request.resultTypes = [.address, .pointOfInterest]
        }

        let search = MKLocalSearch(request: request)

        search.start { response, error in
            Task { @MainActor in
                self.isSearching = false

                if let response = response {
                    // Sort results by distance if we have location
                    if let currentLocation = locationManager.currentLocation {
                        self.searchResults = response.mapItems.sorted { item1, item2 in
                            let distance1 = item1.placemark.location?.distance(from: currentLocation) ?? Double.infinity
                            let distance2 = item2.placemark.location?.distance(from: currentLocation) ?? Double.infinity
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