//
//  MapTapGestureTest.swift
//  OPS
//
//  Test file to verify map annotation tap handling
//

import SwiftUI
import MapKit

struct MapTapGestureTest: View {
    @State private var tapLog: [String] = []
    @State private var selectedMarker: String? = nil
    @State private var showingPopup: String? = nil
    
    let testProjects = [
        TestProject(id: "1", title: "Project A", coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
        TestProject(id: "2", title: "Project B", coordinate: CLLocationCoordinate2D(latitude: 37.7849, longitude: -122.4094)),
        TestProject(id: "3", title: "Project C", coordinate: CLLocationCoordinate2D(latitude: 37.7649, longitude: -122.4294))
    ]
    
    var body: some View {
        VStack {
            // Map with different gesture configurations
            Map {
                ForEach(testProjects) { project in
                    Annotation(project.title, coordinate: project.coordinate) {
                        TestMarker(
                            project: project,
                            isSelected: selectedMarker == project.id,
                            showingPopup: showingPopup == project.id
                        )
                        .onTapGesture {
                            logTap("Standard onTapGesture: \(project.title)")
                            handleMarkerTap(project)
                        }
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded { _ in
                                    logTap("Simultaneous gesture: \(project.title)")
                                }
                        )
                        .highPriorityGesture(
                            TapGesture()
                                .onEnded { _ in
                                    logTap("High priority gesture: \(project.title)")
                                }
                        )
                    }
                }
            }
            .onTapGesture { location in
                // Map background tap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if showingPopup != nil {
                        logTap("Map background tap - dismissing popup")
                        showingPopup = nil
                    } else {
                        logTap("Map background tap")
                    }
                }
            }
            .frame(height: 400)
            
            // Log display
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(tapLog, id: \.self) { log in
                        Text(log)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .frame(maxHeight: 200)
            
            // Clear button
            Button("Clear Log") {
                tapLog.removeAll()
                selectedMarker = nil
                showingPopup = nil
            }
            .padding()
        }
    }
    
    private func logTap(_ message: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        tapLog.append("[\(timestamp)] \(message)")
    }
    
    private func handleMarkerTap(_ project: TestProject) {
        selectedMarker = project.id
        if showingPopup == project.id {
            showingPopup = nil
        } else {
            showingPopup = project.id
        }
    }
}

struct TestProject: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
}

struct TestMarker: View {
    let project: TestProject
    let isSelected: Bool
    let showingPopup: Bool
    
    var body: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Color.blue : Color.gray)
                .frame(width: 30, height: 30)
            
            if showingPopup {
                VStack {
                    Text(project.title)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                }
                .offset(y: 40)
            }
        }
    }
}

#Preview {
    MapTapGestureTest()
}