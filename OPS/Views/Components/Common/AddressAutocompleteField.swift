//
//  AddressAutocompleteField.swift
//  OPS
//
//  Created for providing address autocomplete functionality using MapKit
//

import SwiftUI
import MapKit
import Combine

struct AddressAutocompleteField: View {
    @Binding var address: String
    let placeholder: String
    let onAddressSelected: ((String, CLLocationCoordinate2D?) -> Void)?
    
    @State private var searchText = ""
    @State private var searchResults: [MKLocalSearchCompletion] = []
    @State private var showingResults = false
    @State private var completer = MKLocalSearchCompleter()
    @StateObject private var searchCompleterDelegate = SearchCompleterDelegate()
    @State private var searchDebouncer = PassthroughSubject<String, Never>()
    
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
                TextField(placeholder, text: $searchText)
                    .font(.body)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
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
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(showingResults ? 1.0 : 0.5), lineWidth: 1)
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
                                    .font(.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .font(.caption)
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
    }
    
    private func setupCompleter() {
        completer.delegate = searchCompleterDelegate
        completer.resultTypes = .address
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Default to SF
            span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 50) // Wide search area
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