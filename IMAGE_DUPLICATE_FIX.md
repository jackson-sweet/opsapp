# Image Duplicate Display Fix

## Problem
All project images were showing the same content despite having unique URLs. The issue was caused by the `ImageFileManager` truncating long base64-encoded URLs to 200 characters, causing all images with similar paths to have the same cache key.

## Root Cause
In `ImageFileManager.encodeRemoteURL()`, the code was:
```swift
if base64.count > 200 {
    return "remote_\(base64.prefix(200))"
}
```

Since all images shared the same base path:
`https://ops-app-files-prod.s3.us-west-2.amazonaws.com/company-{id}/project-{id}/photos/`

They all got truncated to the same 200 characters, resulting in the same filename for all cached images.

## Solution
1. **Changed to SHA256 Hashing**: Instead of truncating, we now use SHA256 hash to create unique identifiers:
   ```swift
   let hash = SHA256.hash(data: data)
   let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
   return "remote_\(hashString.prefix(32))\(filenameSuffix)"
   ```

2. **Added Cache Clearing**: Added a one-time cache clear on app launch to remove incorrectly cached images:
   - Clears all "remote_*" files from the file system cache
   - Clears the in-memory image cache
   - Sets a flag to prevent repeated clearing

3. **Fixed View Recycling**: Previously fixed ForEach issues in `ProjectImagesSimple.swift`

## Testing
After applying this fix:
1. The app will clear the cached images on next launch
2. Images will be re-downloaded with unique cache keys
3. Each image will display its correct content

## Files Modified
- `/Utilities/ImageFileManager.swift` - Fixed the encoding function and added cache clear method
- `/OPSApp.swift` - Added one-time cache clearing on app launch
- `/Views/Components/Images/ProjectImagesSimple.swift` - Fixed ForEach view recycling

## Verification
To verify the fix works:
1. Force quit and restart the app
2. Open a project with multiple images
3. Each image should now show different content
4. Check console logs - you should no longer see "Invalid local ID format" with truncated base64