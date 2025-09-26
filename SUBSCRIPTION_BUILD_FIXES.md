# Subscription System Build Fixes

## Fixed Compilation Errors

### 1. StripeConfiguration.swift
- **Error**: `Value of type 'PaymentSheet.Appearance.Colors' has no member 'error'`
- **Fix**: Commented out the error color setting as it's not available in current SDK version
- **Error**: `Cannot assign value of type 'Float' to type 'CGFloat'`  
- **Fix**: Changed `Float(OPSStyle.Layout.cornerRadius)` to `CGFloat(OPSStyle.Layout.cornerRadius)`

### 2. PlanSelectionView.swift
- **Error**: PaymentSheet presentation issues
- **Fix**: Changed from direct `.present()` call to SwiftUI sheet presentation
- Added `PaymentSheetView` wrapper using `UIViewControllerRepresentable`
- Changed to use `@State` for `presentingPaymentSheet` flag

### 3. Property Name Mismatches
- **Error**: References to `trialEndsAt` and `gracePeriodEndsAt`
- **Fix**: Updated to use correct property names:
  - `trialEndsAt` → `trialEndDate`
  - `gracePeriodEndsAt` → Removed (using `daysRemainingInGracePeriod` computed property)

### 4. GracePeriodBanner.swift
- **Error**: Using `DataController.shared` singleton
- **Fix**: Changed to use `@EnvironmentObject` for DataController
- Added DataController to environment in modifier

### 5. Data Model Updates
- Added `subscriptionIdsJson` field to Company model for multiple subscriptions
- Updated grace period calculation to work without dedicated field
- Added computed property for payment client secret in BubbleSubscriptionService

## Build Instructions

1. **Clean Build Folder**: 
   - Xcode: Product → Clean Build Folder (⇧⌘K)

2. **Resolve Package Dependencies**:
   - File → Packages → Resolve Package Versions

3. **Build Project**:
   - Product → Build (⌘B)

## Remaining Tasks

If you still see errors:

1. **Check Stripe SDK Version**: 
   - Ensure you have a compatible version of StripePaymentSheet
   - Current code assumes SDK version 23.x or later

2. **Import Statements**:
   - Verify all files have proper imports:
   ```swift
   import StripePaymentSheet  // For payment views
   import SwiftUI             // For UI components
   import Foundation          // For basic types
   ```

3. **Environment Objects**:
   - Ensure all views have required environment objects:
   ```swift
   .environmentObject(subscriptionManager)
   .environmentObject(dataController)
   ```

## Testing After Build

1. Run the app in simulator
2. Check console for any runtime errors
3. Test subscription flow with test user
4. Verify payment sheet appears correctly

## Known Limitations

- Stripe error color customization not available
- PaymentSheet must be presented via SwiftUI sheet
- Grace period relies on Bubble's recurring workflow