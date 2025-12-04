# OPS Component Library

**Purpose**: This document provides Claude (AI assistant) with a complete reference of all reusable UI components in the OPS app. Use these standardized components to maintain consistency and avoid creating duplicate implementations.

**Last Updated**: December 4, 2025

---

## Table of Contents
1. [Component Philosophy](#component-philosophy)
2. [Button Components](#button-components)
3. [Card Components](#card-components)
4. [Form Components](#form-components)
5. [List & Display Components](#list--display-components)
6. [Job Board Components](#job-board-components)
7. [Calendar Components](#calendar-components)
8. [Navigation Components](#navigation-components)
9. [Settings Components](#settings-components)
10. [Utility Components](#utility-components)

---

## Component Philosophy

### Key Principles

1. **Reuse Over Recreation**
   - Always use existing components
   - Never create custom styling for standard patterns
   - Consistency is paramount

2. **OPSStyle Compliance**
   - All components use OPSStyle constants
   - No hardcoded colors, fonts, or sizes
   - Centralized design system

3. **Field-Optimized**
   - Large touch targets (60×60pt preferred)
   - High contrast for outdoor visibility
   - Work with gloves

4. **Single Responsibility**
   - Each component does one thing well
   - Compose complex UIs from simple components
   - Easy to test and maintain

---

## Button Components

### PrimaryButton
Standard primary action button with OPS styling.

```swift
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isEnabled: Bool = true

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(isEnabled ? OPSStyle.Colors.primaryAccent : Color.gray)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .disabled(!isEnabled)
    }
}

// Usage
PrimaryButton(title: "Save Project", action: saveProject)
```

### SecondaryButton
Outlined button for alternative actions.

```swift
struct SecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.button)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(Color.black)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
        )
    }
}

// Usage
SecondaryButton(title: "Cancel", action: dismiss)
```

### DestructiveButton
Red button for dangerous actions.

```swift
struct DestructiveButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
        .background(OPSStyle.Colors.errorStatus)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Usage
DestructiveButton(title: "Delete Project", action: deleteProject)
```

### IconButton
Circular icon button for compact actions.

```swift
struct IconButton: View {
    let icon: String
    let action: () -> Void
    var size: CGFloat = 44
    var tint: Color = OPSStyle.Colors.primaryAccent

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4))
                .foregroundColor(tint)
                .frame(width: size, height: size)
        }
        .background(
            Circle()
                .fill(OPSStyle.Colors.cardBackground)
                .overlay(
                    Circle()
                        .stroke(tint, lineWidth: 1)
                )
        )
    }
}

// Usage
IconButton(icon: OPSStyle.Icons.plusCircle, action: addTask, size: 60)
```

---

## Card Components

### StandardCard
Basic card with OPS styling.

```swift
struct StandardCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(OPSStyle.Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            )
    }
}

// Usage
StandardCard {
    VStack {
        Text("Card Title")
        Text("Card content")
    }
}
```

### ElevatedCard
Card with shadow for emphasis.

```swift
struct ElevatedCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(OPSStyle.Layout.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .shadow(color: Color.black, radius: 4, x: 0, y: 2)
            )
    }
}
```

### InteractiveCard
Tappable card with subtle press animation.

```swift
struct InteractiveCard<Content: View>: View {
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .padding(OPSStyle.Layout.cardPadding)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

### AccentCard
Card with colored left border for emphasis.

```swift
struct AccentCard<Content: View>: View {
    let accentColor: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 4)

            content()
                .padding(OPSStyle.Layout.cardPadding)
        }
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Usage
AccentCard(accentColor: OPSStyle.Colors.primaryAccent) {
    Text("Important message")
}
```

### ClientInfoCard
Reusable card for displaying client information.

```swift
// Location: /Views/Cards/ClientInfoCard.swift
// Used in: ClientDetailsView, ProjectDetailsView

struct ClientInfoCard: View {
    let client: Client

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Client name and avatar
            HStack {
                if let avatarURL = client.avatar {
                    AsyncImage(url: URL(string: avatarURL)) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                }

                Text(client.name)
                    .font(OPSStyle.Typography.cardTitle)
            }

            // Contact info
            if let email = client.emailAddress {
                InfoRow(icon: OPSStyle.Icons.envelope, title: "Email", value: email)
            }

            if let phone = client.phoneNumber {
                InfoRow(icon: OPSStyle.Icons.phone, title: "Phone", value: phone)
            }

            // Address
            if let street = client.street {
                InfoRow(icon: OPSStyle.Icons.mapPin, title: "Address", value: formatAddress())
            }
        }
        .padding(16)
        .cardStyle()
    }
}
```

### LocationCard
Displays location with map preview.

```swift
// Location: /Views/Cards/LocationCard.swift
// Used in: ProjectDetailsView, TaskDetailsView

struct LocationCard: View {
    let street: String?
    let city: String?
    let state: String?
    let zipCode: String?
    let latitude: Double?
    let longitude: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Address text
            VStack(alignment: .leading, spacing: 4) {
                if let street = street {
                    Text(street)
                        .font(OPSStyle.Typography.body)
                }
                if let city = city, let state = state {
                    Text("\(city), \(state) \(zipCode ?? "")")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            // Map preview (if coordinates available)
            if let lat = latitude, let lon = longitude {
                Map(coordinateRegion: .constant(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                )))
                .frame(height: 120)
                .cornerRadius(8)
                .disabled(true)
            }
        }
        .padding(16)
        .cardStyle()
    }
}
```

### NotesCard
Expandable notes display.

```swift
// Location: /Views/Cards/NotesCard.swift
// Used in: ProjectDetailsView, TaskDetailsView

struct NotesCard: View {
    let notes: String
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse
            HStack {
                Text("NOTES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            // Notes content (only when expanded)
            if isExpanded {
                Text(notes.isEmpty ? "No notes" : notes)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(notes.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            }
        }
        .padding(16)
        .cardStyle()
    }
}
```

### TeamMembersCard
Display team member list.

```swift
// Location: /Views/Cards/TeamMembersCard.swift
// Used in: ProjectDetailsView, TaskDetailsView

struct TeamMembersCard: View {
    let teamMembers: [User]
    let onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("TEAM MEMBERS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                if let onEdit = onEdit {
                    Button("Edit") { onEdit() }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }

            // Team member list
            if teamMembers.isEmpty {
                Text("No team members assigned")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                ForEach(teamMembers) { member in
                    HStack {
                        UserAvatar(user: member, size: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(member.nameFirst) \(member.nameLast)")
                                .font(OPSStyle.Typography.body)
                            Text(member.role.displayName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .cardStyle()
    }
}
```

---

## Form Components

### FormTextField
Standard text field with OPS styling.

```swift
struct FormTextField: View {
    let title: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField(placeholder.isEmpty ? title : placeholder, text: $text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(12)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(8)
                .keyboardType(keyboardType)
        }
    }
}

// Usage
FormTextField(title: "Project Name", text: $projectName)
```

### FormTextEditor
Multi-line text input.

```swift
struct FormTextEditor: View {
    let title: String
    @Binding var text: String
    var height: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextEditor(text: $text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(height: height)
                .padding(8)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(8)
        }
    }
}

// Usage
FormTextEditor(title: "Notes", text: $notes, height: 150)
```

### FormToggle
Toggle switch with label.

```swift
struct FormToggle: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(OPSStyle.Colors.primaryAccent)
        }
        .padding(.vertical, 12)
    }
}

// Usage
FormToggle(
    title: "Enable Notifications",
    subtitle: "Receive project updates",
    isOn: $notificationsEnabled
)
```

### FormRadioOptions
Radio button group.

```swift
struct FormRadioOptions<T: Hashable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }) {
                    HStack {
                        Image(systemName: selection == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        Text(label(option))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()
                    }
                }
            }
        }
    }
}

// Usage
FormRadioOptions(
    title: "Project Status",
    options: Status.allCases,
    selection: $selectedStatus,
    label: { $0.displayName }
)
```

### AddressAutocompleteField
MapKit-powered address search.

```swift
// Location: /Views/Common/AddressAutocompleteField.swift
// 500ms debouncing to prevent keyboard lag

struct AddressAutocompleteField: View {
    @Binding var text: String
    @Binding var selectedPlace: MKPlacemark?
    @State private var searchResults: [MKPlacemark] = []
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search address...", text: $text)
                .font(OPSStyle.Typography.body)
                .padding(12)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(8)
                .onChange(of: text) { newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                        await searchAddress(newValue)
                    }
                }

            // Results list
            if !searchResults.isEmpty {
                VStack(spacing: 0) {
                    ForEach(searchResults, id: \.self) { place in
                        Button(action: { selectPlace(place) }) {
                            Text(formatAddress(place))
                                .font(OPSStyle.Typography.body)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                        }
                        Divider()
                    }
                }
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(8)
            }
        }
    }
}
```

### SearchBar
Standard search field.

```swift
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."

    var body: some View {
        HStack {
            Image(systemName: OPSStyle.Icons.magnifyingglass)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextField(placeholder, text: $text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: OPSStyle.Icons.xmark)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(12)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Usage
SearchBar(text: $searchText, placeholder: "Search projects...")
```

---

## List & Display Components

### InfoRow
Standard info row with icon, title, and value.

```swift
struct InfoRow: View {
    let icon: String
    let title: String
    let value: String?
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Image(systemName: icon)
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

// Usage
InfoRow(
    icon: OPSStyle.Icons.envelope,
    title: "Email",
    value: client.emailAddress,
    action: { /* open email */ }
)
```

### StatusBadge
Colored status indicator.

```swift
struct StatusBadge: View {
    let status: Status  // Or TaskStatus

    var body: some View {
        Text(status.displayName.uppercased())
            .font(OPSStyle.Typography.status)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(status.color)
            .cornerRadius(6)
    }
}

// Usage
StatusBadge(status: project.status)
```

### IconBadge
Small circular badge with icon.

```swift
struct IconBadge: View {
    let icon: String
    let color: Color
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.5))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(color)
            .clipShape(Circle())
    }
}

// Usage
IconBadge(icon: OPSStyle.Icons.checkmark, color: OPSStyle.Colors.successStatus)
```

### UserAvatar
User profile image or initials.

```swift
struct UserAvatar: View {
    let user: User
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let imageURL = user.profileImageURL {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image.resizable()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Text(user.initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(Color(user.userColor ?? "#59779F"))
            .clipShape(Circle())
    }
}
```

### CompanyAvatar
Company logo or initials.

```swift
struct CompanyAvatar: View {
    let company: Company
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let logoURL = company.logo {
                AsyncImage(url: URL(string: logoURL)) { image in
                    image.resizable()
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Text(company.name.prefix(2).uppercased())
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .background(OPSStyle.Colors.primaryAccent)
            .clipShape(Circle())
    }
}
```

### EmptyStateView
Placeholder for empty lists.

```swift
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

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
                PrimaryButton(title: actionTitle, action: action)
                    .frame(width: 200)
            }
        }
        .padding(40)
    }
}

// Usage
EmptyStateView(
    icon: "folder.badge.plus",
    title: "No Projects",
    message: "Create your first project to get started",
    actionTitle: "Create Project",
    action: createProject
)
```

---

## Job Board Components

### UniversalJobBoardCard
Reusable card for projects and tasks with swipe-to-change-status.

```swift
// Location: /Views/JobBoard/UniversalJobBoardCard.swift
// Used in: JobBoardProjectListView, JobBoardTasksView

struct UniversalJobBoardCard: View {
    let item: Either<Project, ProjectTask>  // Can be project OR task
    @State private var swipeOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Revealed status card (shown during swipe)
                if abs(swipeOffset) > 0 {
                    RevealedStatusCard(
                        status: nextStatus,
                        direction: swipeOffset > 0 ? .right : .left
                    )
                    .opacity(min(abs(swipeOffset) / (geometry.size.width * 0.4), 1.0))
                }

                // Main card content
                cardContent
                    .offset(x: swipeOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                handleDragChanged(value, cardWidth: geometry.size.width)
                            }
                            .onEnded { value in
                                handleDragEnded(value, cardWidth: geometry.size.width)
                            }
                    )
            }
        }
        .frame(height: 120)
    }

    private var cardContent: some View {
        HStack(spacing: 12) {
            // Status badge
            StatusBadge(status: currentStatus)

            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(item.name)
                    .font(OPSStyle.Typography.cardTitle)

                // Scheduling badge (PROJECT or X TASKS)
                if let project = item.project {
                    Text(project.tasks.count > 0 ? "\(project.tasks.count) TASKS" : "PROJECT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                // Metadata (client, address, date)
                HStack(spacing: 8) {
                    if let clientName = item.clientName {
                        Text(clientName)
                            .lineLimit(1)
                    }

                    Text("•")

                    if let address = item.address {
                        Text(formatAddressStreetOnly(address))
                            .lineLimit(1)
                            .frame(maxWidth: geometry.size.width * 0.4)
                    }

                    Text("•")

                    if let date = item.date {
                        Text(DateHelper.simpleDateString(date))
                    }
                }
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            // Quick action menu
            Button(action: showActionMenu) {
                Image(systemName: OPSStyle.Icons.ellipsis)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private func handleDragChanged(_ value: DragGesture.Value, cardWidth: CGFloat) {
        // Only horizontal drags
        if abs(value.translation.width) > abs(value.translation.height) {
            swipeOffset = value.translation.width

            // Haptic at 40% threshold
            if abs(swipeOffset) > cardWidth * 0.4 && !hasTriggeredHaptic {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                hasTriggeredHaptic = true
            }
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value, cardWidth: CGFloat) {
        if abs(swipeOffset) > cardWidth * 0.4 {
            // Trigger status change
            changeStatus()
        }

        // Animate back
        withAnimation(.spring(response: 0.3)) {
            swipeOffset = 0
            hasTriggeredHaptic = false
        }
    }
}
```

**Key Features**:
- Works for both projects and tasks
- 40% swipe threshold with haptic feedback
- Revealed status card animation
- Directional detection (horizontal vs vertical)
- Quick action menu
- Status badges and metadata display

### CollapsibleSection
Expandable section for closed/archived/cancelled items.

```swift
// Location: /Views/JobBoard/CollapsibleSection.swift
// Used in: JobBoardProjectListView (closed/archived), JobBoardTasksView (cancelled)

struct CollapsibleSection<Content: View>: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: [ CLOSED ] ------------------ [ 5 ]
            HStack(spacing: 12) {
                Text("[ \(title.uppercased()) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Rectangle()
                    .fill(OPSStyle.Colors.secondaryText)
                    .frame(height: 1)

                Text("[ \(count) ]")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            }

            // Content (only when expanded)
            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// Usage
@State private var showClosed = false
let closedProjects = projects.filter { $0.status == .closed }

CollapsibleSection(
    title: "Closed",
    count: closedProjects.count,
    isExpanded: $showClosed
) {
    ForEach(closedProjects) { project in
        UniversalJobBoardCard(item: .project(project))
    }
}
```

### FilterBadge
Active filter indicator with remove button.

```swift
// Location: /Views/JobBoard/FilterBadge.swift
// Used in: JobBoardProjectListView

struct FilterBadge: View {
    let text: String
    let color: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Button(action: onRemove) {
                Image(systemName: OPSStyle.Icons.xmark)
                    .font(.system(size: 10))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(16)
    }
}

// Usage in horizontal scrolling list
ScrollView(.horizontal, showsIndicators: false) {
    HStack(spacing: 8) {
        ForEach(activeFilters) { filter in
            FilterBadge(
                text: filter.displayName,
                color: filter.color,
                onRemove: { removeFilter(filter) }
            )
        }
    }
}
```

### ClientProjectBadges
Visual project status summary for clients.

```swift
// Location: /Views/JobBoard/ClientProjectBadges.swift
// Used in: ClientListView

struct ClientProjectBadges: View {
    let client: Client

    var body: some View {
        let statusCounts = Dictionary(grouping: client.projects, by: { $0.status })
            .mapValues { $0.count }
            .filter { $0.key != .closed && $0.key != .archived }

        HStack(spacing: 6) {
            ForEach(Status.displayOrder, id: \.self) { status in
                if let count = statusCounts[status], count > 0 {
                    Text("[\(count)]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(status.color)
                        .cornerRadius(4)
                }
            }
        }
    }
}

// Usage
HStack {
    Text(client.name)
    ClientProjectBadges(client: client)
}
```

**Performance**: Uses Dictionary grouping for O(n) complexity instead of multiple filter operations (O(6n)).

### AlphabetIndex
Touch-responsive alphabet navigation.

```swift
// Location: /Views/JobBoard/AlphabetIndex.swift
// Used in: ClientListView

struct AlphabetIndex: View {
    let onLetterSelected: (String) -> Void
    @State private var currentLetter: String?

    private let letters = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J",
                           "K", "L", "M", "N", "O", "P", "Q", "R", "S", "T",
                           "U", "V", "W", "X", "Y", "Z"]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(letters, id: \.self) { letter in
                Text(letter)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 20, height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if currentLetter != letter {
                                    currentLetter = letter
                                    onLetterSelected(letter)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                    )
                    .onTapGesture {
                        onLetterSelected(letter)
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
            }
        }
    }
}

// Usage
.overlay(
    AlphabetIndex { letter in
        scrollToSection(letter)
    }
    .padding(.trailing, 8),
    alignment: .trailing
)
```

**Features**:
- Tap letter to jump to section
- Drag gesture for scrollable navigation
- Haptic feedback when changing letters
- Positioned on trailing edge

---

## Calendar Components

### CalendarMonthView
Month grid with project counts.

**Features**:
- Snaps to months
- Visible month tracking
- Lazy loading
- Today card always visible
- Project/task count badges

### CalendarWeekView
Scrollable week strip.

**Features**:
- Monday-Sunday week
- Snaps to days
- Project counts as corner badges
- Today highlighting with blue background

### TodayCard
Always-visible today indicator.

**Styling**:
- Blue text (secondaryAccent)
- Light background (cardBackground.opacity(0.3))
- Prominent positioning

---

## Navigation Components

### AppHeader
Reusable header component.

### CustomTabBar
4-tab navigation (Home, Job Board, Schedule, Settings).

### SegmentedControl
Generic picker for view switching.

```swift
struct SegmentedControl<T: Hashable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button(action: { selection = option }) {
                    Text(label(option))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(selection == option ? .white : OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(selection == option ? OPSStyle.Colors.primaryAccent : Color.clear)
                }
            }
        }
        .background(Color.black)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Usage
SegmentedControl(
    options: [CalendarViewType.month, CalendarViewType.week],
    selection: $viewType,
    label: { $0.displayName }
)
```

---

## Settings Components

### SettingsHeader
Top section with profile and company info.

### SettingsCard
Grouped settings items.

### SettingsToggle
Setting with toggle switch.

### SettingsButton
Navigable settings item.

### SettingsCategoryButton
Large category navigation button.

All settings components follow OPS styling and are located in `/Views/Settings/Components/`.

---

## Utility Components

### RefreshIndicator
Pull-to-refresh indicator.

### LoadingView
Full-screen loading state.

```swift
struct LoadingView: View {
    let message: String

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
```

### ImagePicker
Photo selection interface.

### ContactDetailSheet
Unified contact display with phone/email/address actions.

### TabBarPadding
Consistent padding above tab bar.

```swift
extension View {
    func tabBarPadding(additional: CGFloat = 0) -> some View {
        self.padding(.bottom, 90 + additional)
    }
}

// Usage
ScrollView {
    // Content
}
.tabBarPadding()
```

### UnassignedRolesOverlay
**Location**: `Views/Components/Common/UnassignedRolesOverlay.swift`

Full-screen overlay for assigning roles to team members who don't have an employeeType set. Follows the tactical/minimalist overlay pattern.

**When shown**: On app launch for admin/office crew when company has users with `employeeType == nil`

**Features**:
- Expandable rows with role selection
- Role descriptions (Field Crew vs Office Crew)
- Auto-collapse after selection
- "REMIND ME LATER" dismisses for 24 hours
- Always checks on launch (no permanent dismiss)

**Usage**: Automatically triggered via `PINGatedView` → `DataController.checkForUnassignedEmployeeRoles()`

**Related components**:
- `SubscriptionLockoutView` - Same tactical styling pattern
- `SeatManagementView` - Same minimalist row pattern

---

**End of COMPONENTS.md**

This document provides Claude with a complete component library reference for building consistent UI across the OPS app. Always use these standardized components rather than creating custom implementations.
