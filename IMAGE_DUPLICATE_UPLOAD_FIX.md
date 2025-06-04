# Image Duplicate on Upload Fix

## Problem
When adding a new photo to a project, it was appearing twice in the photo grid until the app re-synced. 

## Root Cause
Images were being added to the project twice:

1. **First addition**: Inside `ImageSyncManager.saveImages()` at line 191-194:
   ```swift
   var currentImages = project.getProjectImages()
   currentImages.append(contentsOf: savedURLs)
   project.setProjectImageURLs(currentImages)
   ```

2. **Second addition**: In the calling views (`ProjectDetailsView` and `ProjectPhotosGrid`) after `saveImages()` returned:
   ```swift
   let urls = await imageSyncManager.saveImages(selectedImages, for: project)
   // Then they were adding the URLs again:
   currentImages.append(contentsOf: urls)  // Duplicate!
   project.setProjectImageURLs(currentImages)
   ```

## Solution
Removed the duplicate image additions from the calling views:
- `ProjectDetailsView.swift` (line 826-833)
- `ProjectPhotosGrid.swift` (line 658-667)

Now the views only:
1. Call `imageSyncManager.saveImages()` 
2. Clear the UI state (selected images, loading indicators)
3. Let ImageSyncManager handle all the data updates

## Files Modified
- `/Views/Components/Project/ProjectDetailsView.swift` - Removed duplicate image addition
- `/Views/Components/Images/ProjectPhotosGrid.swift` - Removed duplicate image addition

## Result
- Images are now added only once by ImageSyncManager
- No duplicate images appear in the photo grid
- The ImageSyncManager handles all project updates and saves