# Component Architecture

## Overview
Comprehensive guide to reusable components and architectural patterns for the Job Board feature, ensuring consistency with OPS design language.

## Component Hierarchy

```
JobBoardTab
├── JobBoardView (✅ Implemented)
│   ├── JobBoardProjectListView (✅ Implemented)
│   │   ├── SearchBar (✅ Implemented)
│   │   ├── ProjectFilterBar (✅ Implemented)
│   │   ├── FilterBadges (✅ Implemented)
│   │   ├── ProjectListFilterSheet (✅ Implemented)
│   │   ├── UniversalJobBoardCard (project) (✅ Implemented)
│   │   └── CollapsibleSection (closed/archived) (✅ Implemented)
│   └── JobBoardTasksView (✅ Implemented)
│       ├── SearchBar (✅ Implemented)
│       ├── UniversalJobBoardCard (task) (✅ Implemented)
│       └── CollapsibleSection (cancelled) (✅ Implemented)
├── UniversalJobBoardCard (✅ Implemented)
│   ├── Swipe-to-Change-Status System (✅ Implemented)
│   │   ├── DragGesture with directional detection (✅ Implemented)
│   │   ├── RevealedStatusCard component (✅ Implemented)
│   │   ├── 40% threshold with haptic feedback (✅ Implemented)
│   │   └── Multi-phase animation sequence (✅ Implemented)
│   ├── Quick Action Menu (✅ Implemented)
│   │   ├── TaskManagementSheets (✅ Implemented)
│   │   └── ProjectManagementSheets (✅ Implemented)
│   └── Status badge with OPSStyle.Icons (✅ Implemented)
├── ClientManagement (✅ Implemented)
│   ├── ClientListView (✅ Implemented with status badges & alphabet index)
│   ├── ClientDetailsView (✅ Implemented with project creation)
│   └── ClientFormSheet (✅ Created, needs integration)
├── ProjectManagement (Partial)
│   └── ProjectFormSheet (✅ Exists, needs Job Board integration)
└── TaskManagement (Implemented)
    ├── TaskDetailsView (✅ Implemented)
    ├── TaskFormSheet (✅ Implemented)
    └── TaskTypeManagementView (✅ Implemented)
```

## Existing Components to Reuse

### From Common Components
```swift
// Search functionality
SearchBar // From ProjectSearchSheet
AddressSearchField // From Common folder
AddressAutocompleteField // From Common folder

// Cards and display
ClientInfoCard // From Cards folder
LocationCard // From Cards folder
NotesCard // From Cards folder
TeamMembersCard // From Cards folder

// User interface
UserAvatar // From Components folder
CompanyAvatar // From Components folder
StatusBadge // From Components folder

// Navigation
AppHeader // Modify to support Job Board
CustomTabBar // Update for 4 tabs

// Utilities
RefreshIndicator // For pull-to-refresh
ImagePicker // For project photos
ProjectImagesSection // For photo management
```

### Style Components
```swift
// From OPSStyle and Components
extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            )
    }

    func sectionHeaderStyle() -> some View {
        self
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .textCase(.uppercase)
    }
}

// Border Color Constants (Added 2025-10-01)
// OPSStyle.Colors.cardBorder = Color.white.opacity(0.1)        // Standard card border
// OPSStyle.Colors.cardBorderSubtle = Color.white.opacity(0.05) // Subtle border for less prominent cards
// ALWAYS use these constants instead of hardcoding Color.white.opacity() values
```

## New Reusable Components

### Implemented Components (v1.2.0)

#### CollapsibleSection
```swift
struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    // Format: [ CLOSED ] ------------------ [ 5 ]
    // Spring animation with 0.3s response time
    // Used for closed/archived projects and cancelled tasks
}
```

#### RevealedStatusCard
```swift
struct RevealedStatusCard: View {
    let status: Any // Status or TaskStatus
    let direction: SwipeDirection

    // Displays behind swiping card during swipe-to-change-status
    // Fades in based on swipe progress: min(abs(swipeOffset) / threshold, 1.0)
    // Shows target status with appropriate color and opacity
}
```

#### FilterBadge
```swift
struct FilterBadge: View {
    let text: String
    let color: Color
    let onRemove: () -> Void

    // Displays active filters with color dot, text, and X button
    // Used in horizontal scrolling filter badge list
    // Capsule shape with cardBackgroundDark background
}
```

#### ClientProjectBadges
```swift
struct ClientProjectBadges: View {
    let client: Client

    // Displays project status counts as colored badges
    // Format: [2] [1] [3] [5] (one badge per status with projects)
    // Only shows statuses with active projects (excludes closed/archived)
    // Performance optimized with Dictionary grouping (O(n) instead of O(6n))
}
```

#### AlphabetIndex
```swift
// Touch-responsive alphabet index for ClientListView
// Features:
// - Tap letter to jump to section
// - Drag gesture for scrollable navigation
// - Haptic feedback when changing letters during drag
// - Visual feedback with frame and contentShape
// - Positioned on trailing edge of screen
```

### Dashboard Card Base
```swift
struct DashboardCard<Content: View>: View {
    let title: String?
    let icon: String?
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if title != nil || icon != nil {
                HStack {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    if let title = title {
                        Text(title)
                            .sectionHeaderStyle()
                    }
                    
                    Spacer()
                    
                    if let action = action {
                        Button("SEE ALL") {
                            action()
                        }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            
            content()
        }
        .padding(16)
        .cardStyle()
    }
}
```

### Info Row Component

**Note**: Use `OPSStyle.Icons` constants instead of hardcoded SF Symbol strings.

```swift
struct InfoRow: View {
    let icon: String // Use OPSStyle.Icons.iconName
    let title: String
    let value: String?
    let action: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: icon) // Pass OPSStyle.Icons constant
                .font(.system(size: 16))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                
                if let value = value {
                    Text(value)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                } else {
                    Text("Not set")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .italic()
                }
            }
            
            Spacer()
            
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            action?()
        }
    }
}
```

### Empty State Component
```swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text(message)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
            
            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
        .padding(40)
    }
}
```

### Warning Card Component
```swift
struct WarningCard: View {
    let message: String
    let type: WarningType = .warning
    
    enum WarningType {
        case info, warning, error
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 20))
                .foregroundColor(type.color)
            
            Text(message)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(type.color.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(type.color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}
```

### Button Styles
```swift
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isEnabled ? OPSStyle.Colors.primaryAccent : Color.gray)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color.red)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
```

### Form Components
```swift
struct FormSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .sectionHeaderStyle()
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                content()
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}

struct FormTextField: View {
    let title: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextAutocapitalization = .sentences
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            TextField(title, text: $text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(12)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(8)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
```

### Loading States
```swift
struct LoadingView: View {
    let message: String = "Loading..."
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.2)
            
            Text(message)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OPSStyle.Colors.background.opacity(0.9))
    }
}

struct ShimmerCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .fill(OPSStyle.Colors.cardBackgroundDark)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.0),
                                Color.white.opacity(0.1),
                                Color.white.opacity(0.0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    isAnimating = true
                }
            }
    }
}
```

## Navigation Components

### Navigation Card
```swift
struct NavigationCard: View {
    let icon: String
    let title: String
    let count: Int?
    let subtitle: String?
    let destination: NavigationDestination
    
    var body: some View {
        NavigationLink(value: destination) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Spacer()
                    
                    if let count = count {
                        Text("\(count)")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(PlainButtonStyle())
    }
}
```

## Sheet Presentation Patterns

### Consistent Sheet Wrapper
```swift
struct FormSheetWrapper<Content: View>: View {
    let title: String
    let saveAction: () async throws -> Void
    let isValid: Bool
    @Environment(\.dismiss) var dismiss
    @ViewBuilder let content: () -> Content
    
    @State private var isSaving = false
    @State private var error: Error?
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                
                content()
            }
            .navigationTitle(title.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: save) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("SAVE")
                        }
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(!isValid || isSaving)
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                }
            } message: {
                if let error = error {
                    Text(error.localizedDescription)
                }
            }
        }
    }
    
    private func save() {
        isSaving = true
        
        Task {
            do {
                try await saveAction()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    isSaving = false
                }
            }
        }
    }
}
```

## Performance Optimizations

### Lazy Loading Pattern
```swift
struct LazyLoadedList<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let batchSize: Int = 20
    @ViewBuilder let content: (Item) -> Content
    
    @State private var visibleItemCount: Int = 20
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items.prefix(visibleItemCount)) { item in
                    content(item)
                    
                    if item.id == items.prefix(visibleItemCount).last?.id {
                        // Load more trigger
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                loadMore()
                            }
                    }
                }
            }
        }
    }
    
    private func loadMore() {
        visibleItemCount = min(visibleItemCount + batchSize, items.count)
    }
}
```

## Accessibility

### VoiceOver Support
```swift
extension View {
    func accessibleCard(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }
}
```

## Testing Utilities

### Preview Helpers
```swift
struct PreviewDataController {
    static func mock() -> DataController {
        let controller = DataController(inMemory: true)
        // Add mock data
        return controller
    }
}

#Preview("Dashboard") {
    JobBoardDashboard()
        .environmentObject(PreviewDataController.mock())
}
```