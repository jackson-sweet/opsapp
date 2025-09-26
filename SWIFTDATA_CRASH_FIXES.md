# SwiftData Model Invalidation Crash Prevention

## Summary
Implemented defensive measures to prevent SwiftData crashes when models are accessed after invalidation, particularly during logout or data deletion scenarios.

## Root Cause
The crash "This model instance was invalidated" occurs when:
1. A SwiftData model is deleted or its context is reset
2. Views or ViewModels still hold references to the invalidated model
3. The app tries to access properties of the invalidated model

## Implemented Fixes

### 1. DataController Changes
- **Added validation checks in `getProject()`**: Verifies models are still registered before returning
- **Added `getCalendarEvent()` method**: Similar validation for calendar events
- **Modified logout flow**: Clears AppState references before deleting data with a delay

### 2. TaskDetailsView Refactoring
- **Changed from storing models to storing IDs**: Now stores `taskId` and `projectId` instead of direct model references
- **Converted to computed properties**: `task` and `project` are now computed properties that fetch fresh models
- **Added graceful fallback**: Shows "Task no longer available" message if models are invalidated
- **Refactored all methods**: Updated to handle optional models and pass them as parameters

### 3. CalendarViewModel Protection
- **Store IDs instead of models**: Changed to store `projectIdsForSelectedDate` and `calendarEventIdsForSelectedDate`
- **Computed properties for models**: Fresh models fetched from DataController when accessed
- **Prevents stale references**: IDs remain valid even if models are invalidated

### 4. AppState Cleanup
- **Added `resetForLogout()` method**: Clears all project and task references on logout
- **Called during logout flow**: Ensures views dismiss before data deletion

## Pattern for Future Development

When working with SwiftData models in views or ViewModels:

1. **Store IDs, not models**:
```swift
// Bad
@State var project: Project

// Good  
let projectId: String
var project: Project? {
    dataController.getProject(id: projectId)
}
```

2. **Always validate before use**:
```swift
guard let project = project else {
    // Show fallback UI
    return
}
```

3. **Check model registration**:
```swift
guard context.registeredModel(for: model.persistentModelID) != nil else {
    return nil
}
```

## Testing Recommendations
1. Test logout flow thoroughly - ensure no crashes
2. Test switching between accounts rapidly
3. Test background app termination and restoration
4. Monitor for any remaining invalidation crashes in production

## Areas Still at Risk
- Other ViewModels that might store model arrays
- Background sync operations that hold model references
- Notification handlers that access models directly

These should be audited and updated to follow the same defensive patterns.