# ProjectFormSheet.swift - Authority Document

**📖 Document Type**: REFERENCE - STYLING AUTHORITY
**🎯 Purpose**: Defines the authoritative styling patterns that all implementations MUST follow
**👉 Read This**: Before implementing any tracks that involve UI consolidation

---

**Date**: November 19, 2025
**Authority File**: `/OPS/Views/JobBoard/ProjectFormSheet.swift`
**Last Updated**: November 16, 2025 (Progressive Disclosure Design Overhaul)

## Critical Notice

**ProjectFormSheet.swift is the AUTHORITY** for all styling patterns listed below. When consolidating duplicate implementations, **ProjectFormSheet's patterns take precedence**.

⚠️ **MANDATORY RULE FOR AGENTS**: If you find conflicting implementations between ProjectFormSheet and another file, **ALWAYS KEEP ProjectFormSheet's version** and migrate the other file to match it.

---

## Table of Contents

1. [Section Card Styling](#section-card-styling)
2. [Navigation Bar Styling](#navigation-bar-styling)
3. [Input Field Styling](#input-field-styling)
4. [TextEditor Styling with Cancel/Save](#texteditor-styling-with-cancelsave)
5. [ExpandableSection Component](#expandablesection-component)

---

## Section Card Styling

### Authority Pattern (ProjectFormSheet.swift lines 1716-1780)

**ExpandableSection Component Definition**:

```swift
struct ExpandableSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    let onDelete: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                // Header with icon and title inside the border
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    if let onDelete = onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Content area
                content()
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
            }
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
    }
}
```

### Authority Specifications

| Property | Authority Value | Notes |
|----------|-----------------|-------|
| **Header Icon Size** | `.font(.system(size: 14))` | Fixed size, not relative |
| **Header Icon Color** | `OPSStyle.Colors.primaryText` | NOT primaryAccent |
| **Title Font** | `OPSStyle.Typography.captionBold` | Uppercase enforced by usage |
| **Title Color** | `OPSStyle.Colors.primaryText` | NOT secondaryText |
| **Delete Icon** | `"minus.circle.fill"` | Red error color when present |
| **Delete Icon Size** | `.font(.system(size: 20))` | Larger than header icon |
| **Delete Icon Color** | `OPSStyle.Colors.errorStatus` | NOT errorText |
| **Header Padding Vertical** | `12` | Consistent spacing |
| **Header Padding Horizontal** | `16` | Consistent spacing |
| **Divider** | `Color.white.opacity(0.1)` | Between header and content |
| **Content Padding Vertical** | `14` | Slightly more than header |
| **Content Padding Horizontal** | `16` | Matches header |
| **Background** | `OPSStyle.Colors.cardBackgroundDark.opacity(0.8)` | Semi-transparent |
| **Corner Radius** | `OPSStyle.Layout.cornerRadius` | Standard 5.0 |
| **Border** | `Color.white.opacity(0.1), lineWidth: 1` | Subtle white border |
| **Spacing** | `VStack(alignment: .leading, spacing: 0)` | No spacing, handled by padding |

### Usage Example (Authority)

```swift
ExpandableSection(
    title: "DESCRIPTION",  // Uppercase enforced
    icon: "text.alignleft",
    isExpanded: $isDescriptionExpanded,
    onDelete: {
        description = ""
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isDescriptionExpanded = false
        }
    }
) {
    // Content goes here
}
```

---

## Navigation Bar Styling

### Authority Pattern (ProjectFormSheet.swift lines 226-256)

```swift
.navigationBarTitleDisplayMode(.inline)
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {
        Button("CANCEL") {
            dismiss()
        }
        .font(OPSStyle.Typography.bodyBold)
        .foregroundColor(OPSStyle.Colors.secondaryText)
        .disabled(isSaving)
    }

    ToolbarItem(placement: .principal) {
        Text(mode.isCreate ? "CREATE PROJECT" : "EDIT PROJECT")
            .font(OPSStyle.Typography.bodyBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
    }

    ToolbarItem(placement: .navigationBarTrailing) {
        Button(action: saveProject) {
            if isSaving {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    .scaleEffect(0.8)
            } else {
                Text(mode.isCreate ? "CREATE" : "SAVE")
                    .font(OPSStyle.Typography.bodyBold)
            }
        }
        .foregroundColor(isValid ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
        .disabled(!isValid || isSaving)
    }
}
```

### Authority Specifications

| Property | Authority Value | Notes |
|----------|-----------------|-------|
| **Title Display Mode** | `.inline` | Always inline for sheets |
| **Cancel Text** | `"CANCEL"` | ALL CAPS |
| **Cancel Font** | `OPSStyle.Typography.bodyBold` | Bold body text |
| **Cancel Color** | `OPSStyle.Colors.secondaryText` | NOT primaryAccent |
| **Title Text** | Dynamic based on mode, ALL CAPS | "CREATE PROJECT" vs "EDIT PROJECT" |
| **Title Font** | `OPSStyle.Typography.bodyBold` | Matches buttons |
| **Title Color** | `OPSStyle.Colors.primaryText` | White on dark |
| **Action Text** | `"CREATE"` or `"SAVE"` | ALL CAPS, mode-dependent |
| **Action Font** | `OPSStyle.Typography.bodyBold` | Matches cancel |
| **Action Color (Enabled)** | `OPSStyle.Colors.primaryAccent` | Blue when valid |
| **Action Color (Disabled)** | `OPSStyle.Colors.tertiaryText` | Gray when invalid |
| **Action Disabled State** | `!isValid \|\| isSaving` | Disabled during save or invalid |
| **Loading Indicator** | `ProgressView()` with `.progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))` | Replaces text during save |
| **Loading Scale** | `.scaleEffect(0.8)` | Slightly smaller than full size |

---

## Input Field Styling

### Authority Patterns

ProjectFormSheet contains multiple input field types. Each has specific styling:

#### 1. Standard TextField (Project Name)

**Authority Pattern** (ProjectFormSheet.swift lines 472-483):

```swift
TextField("Enter project name", text: $title)
    .font(OPSStyle.Typography.body)
    .foregroundColor(OPSStyle.Colors.primaryText)
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(Color.clear)
    .cornerRadius(OPSStyle.Layout.cornerRadius)
    .overlay(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
```

**Specifications**:
- Font: `OPSStyle.Typography.body`
- Text Color: `OPSStyle.Colors.primaryText`
- Padding Vertical: `12`
- Padding Horizontal: `16`
- Background: `Color.clear` (transparent)
- Border: `Color.white.opacity(0.2), lineWidth: 1`
- Border Radius: `OPSStyle.Layout.cornerRadius`

#### 2. Search TextField (Client Picker)

**Authority Pattern** (ProjectFormSheet.swift lines 390-410):

```swift
TextField("Search or create client...", text: $clientSearchText)
    .font(OPSStyle.Typography.body)
    .foregroundColor(OPSStyle.Colors.primaryText)
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(Color.clear)
    .cornerRadius(OPSStyle.Layout.cornerRadius)
    .overlay(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
```

**Specifications**: Identical to standard TextField

#### 3. Address Input Field

**Authority Pattern** (ProjectFormSheet.swift lines 524-530):

```swift
TextField("Enter address", text: $address)
    .font(OPSStyle.Typography.body)
    .foregroundColor(OPSStyle.Colors.primaryText)
    .padding(.vertical, 12)
    .padding(.horizontal, 16)
    .background(Color.clear)
    .cornerRadius(OPSStyle.Layout.cornerRadius)
    .overlay(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(Color.white.opacity(0.2), lineWidth: 1)
    )
```

**Specifications**: Identical to standard TextField

### Common TextField Pattern

All TextFields in ProjectFormSheet follow this exact pattern:
- Clear background (not white, not cardBackground)
- White border with 0.2 opacity
- 12pt vertical padding, 16pt horizontal padding
- OPSStyle.Typography.body font
- OPSStyle.Colors.primaryText color
- 1pt border width

---

## TextEditor Styling with Cancel/Save

### Authority Pattern (ProjectFormSheet.swift lines 664-704)

This is the **authoritative pattern** for multi-line text editing with inline save/cancel buttons.

```swift
TextEditor(text: focusedField == .description ? $tempDescription : $description)
    .font(OPSStyle.Typography.body)
    .foregroundColor(OPSStyle.Colors.primaryText)
    .frame(minHeight: 100)
    .padding(12)
    .background(Color.clear)
    .cornerRadius(OPSStyle.Layout.cornerRadius)
    .scrollContentBackground(.hidden)
    .focused($focusedField, equals: .description)
    .overlay(
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
            .stroke(
                focusedField == .description ? OPSStyle.Colors.primaryAccent : Color.white.opacity(0.2),
                lineWidth: 1
            )
    )
    .onChange(of: focusedField) { oldValue, newValue in
        if newValue == .description && oldValue != .description {
            tempDescription = description
        }
    }

if focusedField == .description {
    HStack(spacing: 16) {
        Spacer()

        Button("CANCEL") {
            tempDescription = ""
            focusedField = nil
        }
        .font(OPSStyle.Typography.caption)
        .foregroundColor(OPSStyle.Colors.secondaryText)

        Button("SAVE") {
            description = tempDescription
            focusedField = nil
        }
        .font(OPSStyle.Typography.caption)
        .foregroundColor(OPSStyle.Colors.primaryAccent)
    }
}
```

### Authority Specifications

| Property | Authority Value | Notes |
|----------|-----------------|-------|
| **Font** | `OPSStyle.Typography.body` | Same as TextField |
| **Text Color** | `OPSStyle.Colors.primaryText` | White on dark |
| **Min Height** | `100` | Minimum 100pt tall |
| **Padding** | `12` | All sides (not vertical/horizontal split) |
| **Background** | `Color.clear` | Transparent |
| **Scroll Background** | `.scrollContentBackground(.hidden)` | Hides default TextEditor background |
| **Border (Unfocused)** | `Color.white.opacity(0.2), lineWidth: 1` | Matches TextField |
| **Border (Focused)** | `OPSStyle.Colors.primaryAccent, lineWidth: 1` | **Blue accent border when focused** |
| **Temp State Management** | Uses `tempDescription` binding when focused | Changes only saved on "SAVE" |
| **Cancel Button Text** | `"CANCEL"` | ALL CAPS |
| **Cancel Button Font** | `OPSStyle.Typography.caption` | Smaller than editor text |
| **Cancel Button Color** | `OPSStyle.Colors.secondaryText` | Gray |
| **Save Button Text** | `"SAVE"` | ALL CAPS |
| **Save Button Font** | `OPSStyle.Typography.caption` | Matches cancel |
| **Save Button Color** | `OPSStyle.Colors.primaryAccent` | Blue |
| **Button Spacing** | `16` | Between cancel and save |
| **Button Alignment** | `Spacer()` on left | Buttons right-aligned |
| **Visibility** | Buttons only shown when `focusedField == .description` | Conditional rendering |

### Required State Management Pattern

```swift
// Required @FocusState
@FocusState private var focusedField: FormField?

// Required enum
enum FormField: Hashable {
    case description
    case notes
    // ... other fields
}

// Required temporary state
@State private var tempDescription: String = ""

// Required onChange handler
.onChange(of: focusedField) { oldValue, newValue in
    if newValue == .description && oldValue != .description {
        tempDescription = description  // Load current value into temp
    }
}
```

**Critical**: The TextEditor uses **temporary state** when focused. This allows the user to cancel edits without affecting the actual data. Only when "SAVE" is pressed does `tempDescription` get copied to `description`.

---

## ExpandableSection Component

### Complete Authority Definition (ProjectFormSheet.swift lines 1716-1780)

See [Section Card Styling](#section-card-styling) above for full implementation.

### When to Use

ExpandableSection should be used for:
- ✅ Optional form sections (description, notes, photos, dates)
- ✅ Progressive disclosure in forms
- ✅ Any collapsible content with a header
- ✅ Sections that can be deleted (pass `onDelete` closure)

Do NOT use for:
- ❌ Required fields (should always be visible)
- ❌ Single-field sections (just use regular card styling)
- ❌ Navigation lists (use different component)

---

## Migration Checklist

When migrating another file to match ProjectFormSheet authority:

### For Navigation Bars:
- [ ] Cancel button uses `OPSStyle.Colors.secondaryText` (not primaryAccent)
- [ ] All text is uppercase (CANCEL, CREATE, SAVE, etc.)
- [ ] All fonts are `OPSStyle.Typography.bodyBold`
- [ ] Title uses `OPSStyle.Colors.primaryText`
- [ ] Action button conditionally colored (primaryAccent when enabled, tertiaryText when disabled)
- [ ] Loading state shows ProgressView with `.scaleEffect(0.8)`

### For TextFields:
- [ ] Clear background (`Color.clear`)
- [ ] White border with 0.2 opacity
- [ ] 12pt vertical padding, 16pt horizontal padding
- [ ] `OPSStyle.Typography.body` font
- [ ] `OPSStyle.Colors.primaryText` color

### For TextEditors:
- [ ] Uses temporary state binding when focused
- [ ] Border changes to `primaryAccent` when focused (NOT when unfocused)
- [ ] Cancel/Save buttons appear ONLY when focused
- [ ] Cancel button is `secondaryText`, Save is `primaryAccent`
- [ ] Both buttons use `OPSStyle.Typography.caption`
- [ ] `.scrollContentBackground(.hidden)` to remove default background
- [ ] `onChange` handler loads current value into temp state on focus

### For ExpandableSection:
- [ ] Extract ProjectFormSheet's ExpandableSection to shared component
- [ ] All section cards use shared ExpandableSection
- [ ] Header icon is size 14, primaryText color
- [ ] Title is captionBold, primaryText color
- [ ] Delete icon (if present) is size 20, errorStatus color
- [ ] Padding matches specification (12 vertical, 16 horizontal for header)
- [ ] Border is `Color.white.opacity(0.1), lineWidth: 1`
- [ ] Background is `cardBackgroundDark.opacity(0.8)`

---

## Conflict Resolution Rules

### When Two Versions Exist

**⚠️ CRITICAL RULE**: If you find TWO implementations of any pattern above:

1. **STOP** - Do not proceed with migration
2. **ASK THE USER** which version to keep
3. **DOCUMENT** both versions with file paths and line numbers
4. **WAIT** for user decision before deleting ANY code

**Example User Question Format**:
```
⚠️ DUPLICATE PATTERN FOUND

I found two different implementations of [PATTERN NAME]:

VERSION A (AUTHORITY): ProjectFormSheet.swift lines X-Y
[Show code snippet]

VERSION B: [OtherFile.swift] lines X-Y
[Show code snippet]

DIFFERENCES:
- [List specific differences]

RECOMMENDATION: Keep Version A (ProjectFormSheet is the authority)

Do you want me to:
1. Keep Version A and migrate Version B to match it (recommended)
2. Keep Version B and update this authority document
3. Keep both and explain why they differ

Please confirm before I delete any code.
```

### Default Assumption

If you MUST make a decision without user input (not recommended):
- **ALWAYS KEEP** ProjectFormSheet's version
- **ALWAYS MIGRATE** the other file to match ProjectFormSheet
- **NEVER DELETE** ProjectFormSheet's code
- **DOCUMENT** the assumption in your commit message

---

## Version History

| Date | Change | Updated By |
|------|--------|------------|
| Nov 16, 2025 | Progressive Disclosure Design Overhaul | Assistant |
| Nov 19, 2025 | Authority Document Created | Claude Code |

---

## Questions?

If you're unsure whether ProjectFormSheet's pattern applies to your situation:

1. **Check this document first** - Is the pattern documented here?
2. **Read ProjectFormSheet.swift** - Look at actual usage in context
3. **Ask the user** - When in doubt, ASK before making changes
4. **Document your decision** - Explain why you chose a particular approach

**Remember**: ProjectFormSheet was overhauled on November 16, 2025 and represents the **latest, most polished** styling patterns in the codebase.
