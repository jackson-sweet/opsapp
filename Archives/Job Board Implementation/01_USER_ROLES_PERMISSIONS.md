# User Roles & Permissions

## Role Hierarchy

```
Admin (highest)
  ├── All Office Crew permissions
  ├── Billing/subscription management  
  ├── Team member termination
  └── Seat allocation management

Office Crew
  ├── Client management
  ├── Project management
  ├── Task management
  ├── Task type creation
  ├── Team member invites
  └── Analytics viewing

Field Crew (lowest)
  ├── View assigned projects
  ├── Update task status (limited)
  └── View team information
```

## Permission Matrix

| Feature | Admin | Office Crew | Field Crew |
|---------|-------|-------------|------------|
| **Tab Visibility** |
| View Job Board Tab | ✅ | ✅ | ❌ |
| **Client Management** |
| Create clients | ✅ | ✅ | ❌ |
| Edit clients | ✅ | ✅ | ❌ |
| Delete clients | ✅ | ✅ | ❌ |
| Create sub-clients | ✅ | ✅ | ❌ |
| **Project Management** |
| Create projects | ✅ | ✅ | ❌ |
| Edit projects | ✅ | ✅ | ❌ |
| Delete projects | ✅ | ✅ | ❌ |
| Change project status | ✅ | ✅ | ❌ |
| Convert scheduling mode | ✅ | ✅ | ❌ |
| **Task Management** |
| Create tasks | ✅ | ✅ | ❌ |
| Edit tasks | ✅ | ✅ | ❌ |
| Delete tasks | ✅ | ✅ | ❌ |
| Create task types | ✅ | ✅ | ❌ |
| Delete task types | ✅ | ✅ | ❌ |
| **Team Management** |
| Invite team members | ✅ | ✅ | ❌ |
| Remove team members | ✅ | ❌ | ❌ |
| Change member roles | ✅ | ❌ | ❌ |
| Manage seat allocation | ✅ | ❌ | ❌ |
| **Other Features** |
| View analytics | ✅ | ✅ | ❌ |
| Access billing | ✅ | ❌ | ❌ |
| Manage company settings | ✅ | ❌ | ❌ |

## Implementation Details

### Role Detection
```swift
// In MainTabView or AppState
var showJobBoard: Bool {
    guard let user = dataController.currentUser else { return false }
    return user.role == .admin || user.role == .officeCrew
}
```

### Tab Configuration
```swift
// Tab bar setup
if showJobBoard {
    tabs = [.home, .jobBoard, .schedule, .settings]
} else {
    tabs = [.home, .schedule, .settings]
}
```

### Permission Checks
```swift
// Example permission check
func canDeleteClient() -> Bool {
    guard let user = dataController.currentUser else { return false }
    return user.role == .admin || user.role == .officeCrew
}

func canManageBilling() -> Bool {
    guard let user = dataController.currentUser else { return false }
    return user.role == .admin
}
```

## Edge Cases

### Role Changes
- When a field crew member is promoted to office crew:
  - Tab visibility updates on next app launch or sync
  - No special handling required mid-session
  - User sees Job Board tab after role sync

### Permission Denied Handling
- If unauthorized access attempted (shouldn't happen with proper UI):
  - Show alert: "You don't have permission for this action"
  - Log attempt for debugging
  - Navigate back to previous view

### Offline Permissions
- Permission checks work offline using cached user role
- Role changes require sync to take effect
- Cached permissions expire after 24 hours offline

## Security Considerations

1. **Client-Side Validation**: All permission checks on device for UI
2. **Server-Side Validation**: Bubble API validates all requests
3. **No Permission Escalation**: Users cannot modify their own role
4. **Audit Trail**: All management actions logged with user ID