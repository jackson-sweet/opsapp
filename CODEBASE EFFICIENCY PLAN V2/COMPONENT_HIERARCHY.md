# Component Hierarchy & Organization

**Purpose**: Define clear component organization following Atomic Design principles
**Reference When**: Creating new components, deciding component placement, refactoring

---

## Overview

Apple organizes components in a clear hierarchy: `item/` (individual units) → `shelf/` (collections). OPS should follow a similar pattern using Atomic Design:

1. **Atoms**: Smallest, indivisible UI elements
2. **Molecules**: Groups of atoms working together
3. **Organisms**: Complex UI sections with business logic
4. **Templates**: Page layouts without data
5. **Pages**: Complete views with real data

---

## Current OPS Component Inventory

### Atoms (OPS/Styles/Components/)

Single-purpose, style-only components:

| Component | File | Purpose |
|-----------|------|---------|
| `StatusBadge` | StatusBadge.swift | Status indicator pill |
| `IconBadge` | IconBadge.swift | Icon with background circle |
| `SectionHeader` | SectionHeader.swift | Uppercase section title |
| `FormField` | FormInputs.swift | Text input field |
| `FormTextEditor` | FormInputs.swift | Multi-line text input |
| `FormToggle` | FormInputs.swift | Boolean toggle |
| `FormPicker` | FormInputs.swift | Dropdown picker |
| `FormDatePicker` | FormInputs.swift | Date/time picker |
| `FormStepper` | FormInputs.swift | Number stepper |
| `SearchBar` | FormInputs.swift | Search input |
| `OPSButton` | ButtonStyles.swift | Primary/secondary buttons |
| `SegmentedControl` | SegmentedControl.swift | Tab-style selection |

### Molecules (OPS/Views/Components/Common/)

Combination of atoms with specific purpose:

| Component | File | Composition |
|-----------|------|-------------|
| `InfoRow` | InfoRow.swift | Icon + Label + Value + Chevron |
| `ContactRow` | ContactRow.swift | InfoRow + tap-to-action |
| `TappableCard` | TappableCard.swift | Content + tap behavior |
| `LoadableContent` | LoadableContent.swift | Loading/Empty/Error/Content states |
| `ExpandableSection` | ExpandableSection.swift | Header + collapsible content |
| `StandardSheetToolbar` | StandardSheetToolbar.swift | Cancel/Title/Action toolbar |
| `FilterSheet` | FilterSheet.swift | Generic filter UI |
| `DeletionSheet` | DeletionSheet.swift | Delete with reassignment |
| `SearchField` | SearchField.swift | Generic entity search |
| `NotificationBanner` | NotificationBanner.swift | Toast-style message |
| `LoadingOverlay` | LoadingOverlay.swift | Full-screen loading |
| `DeleteConfirmation` | DeleteConfirmation.swift | Delete alert dialog |

### Organisms (OPS/Views/Components/Cards/)

Complex sections with business logic:

| Component | File | Purpose |
|-----------|------|---------|
| `LocationCard` | LocationCard.swift | Address + map + navigate |
| `ClientInfoCard` | ClientInfoCard.swift | Client details + contact actions |
| `NotesCard` | NotesCard.swift | Expandable notes display |
| `TeamMembersCard` | TeamMembersCard.swift | Team list with avatars |
| `UniversalJobBoardCard` | UniversalJobBoardCard.swift | Project/task card for job board |
| `CalendarEventCard` | CalendarEventCard.swift | Event display for calendar |
| `ProjectCard` | ProjectCard.swift | Project summary card |

### Templates (OPS/Styles/Components/)

Layout patterns without data:

| Component | File | Purpose |
|-----------|------|---------|
| `DetailViewCardTemplate` | DetailViewCardTemplate.swift | Standard detail card layout |
| `FormSheetTemplate` | (proposed) | Standard form sheet layout |
| `ListViewTemplate` | (proposed) | Standard list layout |

### Pages (OPS/Views/)

Complete views with data binding:

| View | Location | Type |
|------|----------|------|
| `HomeView` | Views/Home/ | Dashboard |
| `JobBoardView` | Views/JobBoard/ | List/Grid |
| `CalendarView` | Views/Calendar Tab/ | Calendar |
| `MapView` | Views/Map/ | Map |
| `SettingsView` | Views/Settings/ | Settings |
| `ProjectDetailsView` | Views/Components/Project/ | Detail |
| `TaskDetailsView` | Views/Components/Tasks/ | Detail |

---

## Decision Matrix: When to Create What

### Create an Atom when:

- Component has **no business logic**
- Component is **purely visual/stylistic**
- Component will be used in **10+ places**
- Component has **no dependencies** on other components

Examples:
- ✅ StatusBadge - just shows a colored pill
- ✅ FormField - just styles a TextField
- ❌ ProjectCard - has navigation logic

### Create a Molecule when:

- Component **combines 2-4 atoms**
- Component has **simple interaction logic**
- Component is **reusable across features**
- Component **doesn't fetch data**

Examples:
- ✅ InfoRow - combines icon + text atoms
- ✅ ContactRow - InfoRow + tap action
- ❌ ClientInfoCard - has client-specific business logic

### Create an Organism when:

- Component has **business logic**
- Component may **fetch or mutate data**
- Component is **feature-specific** but reusable
- Component is **self-contained section** of a page

Examples:
- ✅ LocationCard - knows how to open Maps
- ✅ TeamMembersCard - knows about team members
- ❌ HomeView - that's a page, not a component

### Create a Template when:

- You have **3+ pages with same layout**
- Layout is **data-agnostic**
- Template defines **slots for content**

Examples:
- ✅ DetailViewCardTemplate - used by 4+ card types
- ✅ FormSheetTemplate - used by all form sheets
- ❌ ProjectFormSheet - that's a page with specific data

---

## File Organization

### Current Structure

```
OPS/
├── Styles/
│   ├── OPSStyle.swift          # Design tokens
│   ├── ButtonStyles.swift       # Button atoms
│   ├── FormInputs.swift         # Form atoms
│   └── Components/
│       ├── StatusBadge.swift    # Atom
│       ├── SectionHeader.swift  # Atom
│       ├── ExpandableSection.swift  # Molecule
│       └── StandardSheetToolbar.swift  # Molecule
│
├── Views/
│   └── Components/
│       ├── Common/
│       │   ├── InfoRow.swift    # Molecule
│       │   ├── ContactRow.swift # Molecule
│       │   ├── FilterSheet.swift    # Molecule
│       │   ├── DeletionSheet.swift  # Molecule
│       │   └── ...
│       ├── Cards/
│       │   ├── LocationCard.swift   # Organism
│       │   ├── ClientInfoCard.swift # Organism
│       │   └── ...
│       ├── Project/
│       ├── Tasks/
│       ├── Client/
│       └── ...
```

### Recommended Structure (Post-Refactor)

```
OPS/
├── Components/
│   ├── Atoms/
│   │   ├── StatusBadge.swift
│   │   ├── IconBadge.swift
│   │   ├── SectionHeader.swift
│   │   ├── FormField.swift
│   │   ├── FormTextEditor.swift
│   │   └── ...
│   │
│   ├── Molecules/
│   │   ├── InfoRow.swift
│   │   ├── ContactRow.swift
│   │   ├── TappableCard.swift
│   │   ├── LoadableContent.swift
│   │   ├── ExpandableSection.swift
│   │   └── ...
│   │
│   ├── Organisms/
│   │   ├── Cards/
│   │   │   ├── LocationCard.swift
│   │   │   ├── ClientInfoCard.swift
│   │   │   ├── NotesCard.swift
│   │   │   ├── TeamMembersCard.swift
│   │   │   └── UniversalJobBoardCard.swift
│   │   ├── Forms/
│   │   │   ├── AddressSearchField.swift
│   │   │   ├── ContactPicker.swift
│   │   │   └── CalendarSchedulerSheet.swift
│   │   └── Lists/
│   │       ├── TaskListView.swift
│   │       └── ClientListView.swift
│   │
│   └── Templates/
│       ├── DetailViewCardTemplate.swift
│       ├── FormSheetTemplate.swift
│       └── ListViewTemplate.swift
│
├── Features/
│   ├── Home/
│   ├── JobBoard/
│   ├── Calendar/
│   ├── Map/
│   └── Settings/
│
└── Styles/
    ├── OPSStyle.swift
    └── Fonts.swift
```

---

## Composition Guidelines

### Use ViewModifiers when:

- Adding **styling/behavior** that wraps existing content
- Modifier is **stateless** or uses only bindings
- Examples: `.loadingOverlay()`, `.standardSheetToolbar()`

### Use Generic Containers with @ViewBuilder when:

- Creating **layout patterns**
- Content is **entirely provided by caller**
- Examples: `TappableCard`, `LoadableContent`, `ExpandableSection`

### Use Concrete Components when:

- Component has **specific, known content**
- Component has **business logic** tied to entity type
- Examples: `LocationCard`, `ClientInfoCard`

---

## Component Checklist

Before creating a new component, verify:

- [ ] Does similar component already exist?
- [ ] Which layer (Atom/Molecule/Organism) is appropriate?
- [ ] Is it truly reusable, or is it view-specific?
- [ ] Does it follow OPSStyle for colors/fonts/spacing?
- [ ] Is it documented with usage example?
- [ ] Is it added to COMPONENTS.md?

Before using a raw SwiftUI element, check:

- [ ] Is there a FormField/FormPicker/FormDatePicker?
- [ ] Is there a TappableCard wrapper?
- [ ] Is there a LoadableContent wrapper?
- [ ] Is there a standardized modifier?

---

## Anti-Patterns

### ❌ Don't: Create one-off components

```swift
// Bad: Component only used in one place
struct ProjectFormHeaderView: View { ... }
```

### ❌ Don't: Mix business logic in atoms

```swift
// Bad: StatusBadge fetches data
struct StatusBadge: View {
    @Query var projects: [Project]  // Don't do this
}
```

### ❌ Don't: Duplicate styling in organisms

```swift
// Bad: Card has inline styling
struct LocationCard: View {
    var body: some View {
        VStack {
            // ...
        }
        .padding()
        .background(Color(hex: "#0D0D0D"))  // Use OPSStyle!
        .cornerRadius(12)  // Use OPSStyle.Layout!
    }
}
```

### ✅ Do: Use templates for consistency

```swift
// Good: Card uses template
struct LocationCard: View {
    var body: some View {
        DetailViewCardTemplate(
            icon: OPSStyle.Icons.mapPin,
            title: "Location"
        ) {
            // Content only
        }
    }
}
```

---

## Migration Notes

When refactoring existing components:

1. **Identify layer**: Is this an atom, molecule, or organism?
2. **Extract styling**: Move hardcoded values to OPSStyle
3. **Extract patterns**: If layout is reused, create template
4. **Document**: Add to COMPONENTS.md with usage example
5. **Update imports**: Ensure all usage sites can find component

---

**Last Updated**: November 24, 2025
