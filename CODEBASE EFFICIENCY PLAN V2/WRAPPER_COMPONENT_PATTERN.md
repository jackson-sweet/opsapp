# Track W: Wrapper Component Pattern

**Track ID**: W (New in V2)
**Effort**: 4-6 hours
**Impact**: High - Reduces structural duplication across 50+ files
**Prerequisites**: None (independent track)

---

## Concept

Inspired by Apple's `FlowAction.svelte` pattern, wrapper components encapsulate common behaviors without the wrapped content needing to know about the behavior logic.

Instead of:
- 267 ZStacks with loading overlays
- 30+ files with error state handling
- 20+ files with empty state handling

Create universal wrappers that handle these patterns once.

---

## W1: TappableCard Wrapper

**Problem**: Cards throughout the app duplicate tap handling, haptic feedback, and navigation logic.

**Current Pattern** (duplicated 40+ times):
```swift
// In UniversalJobBoardCard, CalendarEventCard, ProjectCard, etc.
HStack { /* card content */ }
    .padding()
    .background(OPSStyle.Colors.cardBackground)
    .cornerRadius(OPSStyle.Layout.cornerRadius)
    .contentShape(Rectangle())
    .onTapGesture {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        onTap()
    }
```

**Solution**: Create `TappableCard` wrapper

### Implementation

**File**: `OPS/Styles/Components/TappableCard.swift`

```swift
import SwiftUI

/// Universal tappable card wrapper with consistent styling and haptics
///
/// Usage:
/// ```swift
/// TappableCard(onTap: { navigateToProject(project) }) {
///     ProjectCardContent(project: project)
/// }
/// ```
struct TappableCard<Content: View>: View {
    let onTap: () -> Void
    let hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle
    let showChevron: Bool
    @ViewBuilder let content: () -> Content

    init(
        onTap: @escaping () -> Void,
        hapticStyle: UIImpactFeedbackGenerator.FeedbackStyle = .light,
        showChevron: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onTap = onTap
        self.hapticStyle = hapticStyle
        self.showChevron = showChevron
        self.content = content
    }

    var body: some View {
        HStack {
            content()

            if showChevron {
                Spacer()
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            let generator = UIImpactFeedbackGenerator(style: hapticStyle)
            generator.impactOccurred()
            onTap()
        }
    }
}
```

### Migration Steps

1. Search for pattern: `\.contentShape\(Rectangle\(\)\).*\.onTapGesture`
2. For each file found:
   - Extract card content into the wrapper
   - Remove duplicate styling code
   - Keep card-specific content only

**Expected files to migrate**:
- UniversalJobBoardCard.swift (project cards)
- CalendarEventCard.swift
- TaskListView.swift (task rows)
- ClientListView.swift (client rows)
- HomeContentView.swift (carousel cards)
- ~35 more files

---

## W2: LoadableContent Wrapper

**Problem**: 267 ZStacks with loading overlay patterns. Track K created `.loadingOverlay()` modifier, but a wrapper pattern is more powerful.

**Current Pattern**:
```swift
ZStack {
    if isLoading {
        LoadingPlaceholder()
    } else if items.isEmpty {
        EmptyStateView()
    } else if let error = error {
        ErrorStateView(error: error)
    } else {
        ActualContent(items: items)
    }
}
```

**Solution**: Create `LoadableContent` wrapper that handles all states

### Implementation

**File**: `OPS/Styles/Components/LoadableContent.swift`

```swift
import SwiftUI

/// Wrapper that handles loading, empty, error, and content states consistently
///
/// Usage:
/// ```swift
/// LoadableContent(
///     isLoading: viewModel.isLoading,
///     isEmpty: projects.isEmpty,
///     error: viewModel.error,
///     emptyTitle: "No Projects",
///     emptyMessage: "Create your first project to get started",
///     emptyIcon: OPSStyle.Icons.project,
///     onRetry: { viewModel.refresh() }
/// ) {
///     ProjectListContent(projects: projects)
/// }
/// ```
struct LoadableContent<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    let error: Error?
    let emptyTitle: String
    let emptyMessage: String
    let emptyIcon: String
    let onRetry: (() -> Void)?
    @ViewBuilder let content: () -> Content

    init(
        isLoading: Bool,
        isEmpty: Bool = false,
        error: Error? = nil,
        emptyTitle: String = "No Items",
        emptyMessage: String = "Nothing to display",
        emptyIcon: String = OPSStyle.Icons.info,
        onRetry: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isLoading = isLoading
        self.isEmpty = isEmpty
        self.error = error
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.emptyIcon = emptyIcon
        self.onRetry = onRetry
        self.content = content
    }

    var body: some View {
        ZStack {
            if isLoading {
                loadingView
            } else if let error = error {
                errorView(error: error)
            } else if isEmpty {
                emptyView
            } else {
                content()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
        .animation(.easeInOut(duration: 0.2), value: isEmpty)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(OPSStyle.Colors.primaryAccent)
                .scaleEffect(1.2)

            Text("Loading...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyIcon)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text(emptyTitle)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(emptyMessage)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: OPSStyle.Icons.alert)
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.errorStatus)

            Text("Something went wrong")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(error.localizedDescription)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let onRetry = onRetry {
                Button(action: onRetry) {
                    HStack {
                        Image(systemName: OPSStyle.Icons.refresh)
                        Text("Try Again")
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

### Migration Priority

**P1 - High Traffic Views**:
1. HomeView.swift / HomeContentView.swift
2. JobBoardView.swift
3. CalendarViewModel views
4. ProjectDetailsView.swift

**P2 - Medium Traffic**:
5. ClientListView.swift
6. TaskListView.swift
7. Settings views

**P3 - Low Traffic**:
8. Debug views
9. Edge case views

---

## W3: EditableSection Wrapper

**Problem**: Forms have sections that switch between view/edit mode with duplicated logic.

**Current Pattern**:
```swift
if isEditing {
    TextField("Name", text: $name)
        .font(...)
        .padding(...)
        .background(...)
} else {
    Text(name)
        .font(...)
        .foregroundColor(...)
}
```

**Solution**: Create `EditableSection` that handles mode switching

### Implementation

**File**: `OPS/Styles/Components/EditableSection.swift`

```swift
import SwiftUI

/// Wrapper that switches between view and edit modes for form sections
///
/// Usage:
/// ```swift
/// EditableSection(
///     isEditing: $isEditing,
///     viewContent: {
///         Text(project.name)
///     },
///     editContent: {
///         FormField(title: "NAME", text: $projectName)
///     }
/// )
/// ```
struct EditableSection<ViewContent: View, EditContent: View>: View {
    @Binding var isEditing: Bool
    @ViewBuilder let viewContent: () -> ViewContent
    @ViewBuilder let editContent: () -> EditContent

    var body: some View {
        Group {
            if isEditing {
                editContent()
            } else {
                viewContent()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}

/// Modifier version for inline usage
extension View {
    func editableSection<EditContent: View>(
        isEditing: Binding<Bool>,
        @ViewBuilder editContent: @escaping () -> EditContent
    ) -> some View {
        EditableSection(
            isEditing: isEditing,
            viewContent: { self },
            editContent: editContent
        )
    }
}
```

---

## Verification Checklist

After completing Track W:

### Build Verification
```bash
xcodebuild -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 15' build
```

### Pattern Verification
```bash
# Count remaining ZStack loading patterns (should decrease significantly)
grep -r "ZStack" OPS/Views | grep -c "isLoading\|ProgressView"

# Count TappableCard usage (should be 40+)
grep -r "TappableCard" OPS/Views | wc -l

# Count LoadableContent usage (should be 20+)
grep -r "LoadableContent" OPS/Views | wc -l
```

### Manual Testing
1. Navigate through Job Board - verify card tap behavior
2. Force loading states - verify loading indicator
3. Empty states - verify empty message display
4. Error states - verify error + retry behavior

---

## Expected Impact

| Metric | Before | After |
|--------|--------|-------|
| Card tap implementations | 40+ duplicates | 1 TappableCard |
| Loading state patterns | 50+ ZStacks | 1 LoadableContent |
| Edit mode switching | 30+ duplicates | 1 EditableSection |
| Lines of code | ~800 duplicate | ~200 shared |

---

## Handover Notes

When completing Track W, document in LIVE_HANDOVER.md:

1. Which wrapper components were created
2. How many files were migrated
3. Any edge cases that couldn't use wrappers
4. Performance observations
5. Recommended next track

---

**Next**: After Track W, consider Track T (Type Guards) for validation consolidation.
