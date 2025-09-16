# Google Sign-In Setup Instructions

## SDK Installation

The Google Sign-In functionality has been implemented in the code, but you need to add the Google Sign-In SDK dependency through Xcode:

1. Open `OPS.xcodeproj` in Xcode
2. Select the OPS project in the navigator
3. Select the OPS target
4. Go to the "General" tab
5. Scroll to "Frameworks, Libraries, and Embedded Content"
6. Click the "+" button
7. Select "Add Package Dependency..."
8. Enter the Google Sign-In SDK URL: `https://github.com/google/GoogleSignIn-iOS`
9. Click "Add Package"
10. Select version 7.1.0 or later (required for Apple's Privacy Manifest requirements)
11. Click "Add Package"
12. Select "GoogleSignIn" and "GoogleSignInSwift" libraries
13. Click "Add Package"

## Google Logo Images

You need to add the Google logo images to the Assets catalog:

1. Download the official Google "G" logo from: https://developers.google.com/identity/branding-guidelines
2. Create three versions:
   - google_logo.png (20x20 pixels)
   - google_logo@2x.png (40x40 pixels)
   - google_logo@3x.png (60x60 pixels)
3. Add these images to: `/OPS/Assets.xcassets/Images/google_logo.imageset/`

## Testing the Implementation

1. Build and run the app
2. On the login screen, tap "LOG INTO ACCOUNT"
3. You should see a "Continue with Google" button below the password field
4. Tap the Google Sign-In button
5. Complete the Google authentication flow
6. If the user exists in Bubble, they will be logged in
7. If the user doesn't exist, they will see an error message

## Troubleshooting

If you encounter issues:

1. Verify the Client ID in Info.plist matches your Google Cloud Console configuration
2. Ensure the URL scheme is correctly configured (reversed client ID)
3. Check that the Bubble endpoint 'login_google' is properly configured
4. Verify the Google Cloud project has the iOS app properly configured with the correct bundle ID

## Implementation Details

The Google Sign-In implementation includes:

- `GoogleSignInManager.swift` - Manages the Google Sign-In flow
- `AuthManager.swift` - Updated with `signInWithGoogle` method
- `DataController.swift` - Updated with `loginWithGoogle` method
- `LoginView.swift` - Updated with Google Sign-In button and handler
- `AppDelegate.swift` - Updated to handle Google Sign-In URL callbacks
- `Info.plist` - Updated with Google OAuth configuration