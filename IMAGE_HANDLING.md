# OPS App - Image Handling System

## Overview

The OPS app implements a sophisticated multi-tier image handling system designed for reliability in poor connectivity conditions. The system seamlessly switches between online and offline modes, ensuring field workers can always capture and view project images.

## Architecture

### Storage Tiers
1. **AWS S3** - Primary remote storage
2. **Local File System** - Offline storage and cache
3. **Memory Cache** - Fast re-display
4. **UserDefaults** - Legacy (being migrated)

### Key Components
- `ImageSyncManager` - Orchestrates upload/sync operations
- `S3UploadService` - Handles AWS S3 uploads
- `PresignedURLUploadService` - Alternative upload via Lambda
- `ImageFileManager` - Local file system operations
- `ImageCache` - In-memory caching
- `ProjectImageView` - Display component

## Complete System Overview

### End-to-End Image Flow

1. **User Captures/Selects Images**
   - Camera or photo library (max 10 at once)
   - Images compressed to JPEG 0.7 quality
   - Filenames generated: `{StreetAddress}_IMG_{timestamp}_{index}.jpg`

2. **Duplicate Check**
   - Extract existing filenames from project
   - Generate unique names if conflicts found
   - Add suffixes (_1, _2) for duplicates

3. **Upload Decision**
   - **Online**: Direct to S3 or via presigned URL
   - **Offline**: Save locally with `local://` prefix

4. **Storage & Registration**
   - S3: Upload with AWS v4 signatures
   - Bubble: Register URLs with project
   - Local: Add to project and pending queue

5. **Display & Caching**
   - SHA256 hash for unique cache keys
   - Multi-tier cache check (memory → file → network)
   - Unsynced indicator for offline images

6. **Background Sync**
   - Triggered on app launch/network restore
   - Upload pending images to S3
   - Register with Bubble
   - Replace local URLs with S3 URLs

7. **Deletion Sync**
   - Compare local vs server image sets
   - Remove deleted images from caches
   - Update project to match server state

## Image Saving Flow

### 1. User Selection
```
ProjectDetailsView → "ADD PHOTOS" → ImagePicker
├── Camera capture
└── Photo library (multi-select, max 10)
```

### 2. Processing
- JPEG compression (0.7 quality)
- Filename generation: `{StreetAddress}_IMG_{timestamp}_{index}.jpg`
- Processing indicator shown

### 3. Storage Decision
```
Network Available?
├── YES → Online Path
│   ├── Direct S3 Upload (default)
│   └── Presigned URL Upload (optional)
└── NO → Offline Path
    └── Local Storage
```

### 4A. Online Path - Direct S3 Upload
```swift
1. Generate AWS v4 signature
2. PUT to S3:
   - Bucket: ops-app-files-prod
   - Region: us-west-2
   - Path: company-{companyId}/{projectId}/photos/{filename}
3. Register with Bubble:
   - POST /api/1.1/wf/upload_project_images
   - Body: {"project_id": "...", "images": ["url1", "url2"]}
4. Update project:
   - Add S3 URLs to projectImagesString
   - Mark needsSync = true
```

### 4B. Online Path - Presigned URL Upload
```swift
1. Request presigned URL from Lambda
2. Upload to S3 using presigned URL
3. Register with Bubble (same as above)
4. Update project
```

### 4C. Offline Path
```swift
1. Save to Documents/ProjectImages/
2. Generate local URL: local://project_images/{filename}
3. Add to pendingUploads queue
4. Track in project.unsyncedImagesString
5. Update project with local URLs
```

### 5. Background Sync
Automatic sync triggers:
- App launch
- Network connectivity restored
- ImageSyncManager initialization

Sync process:
```swift
1. Load pendingUploads from UserDefaults
2. Group by project
3. For each project:
   - Upload to S3
   - Register with Bubble
   - Replace local URLs with S3 URLs
   - Clear from pending queue
```

## Image Fetching Flow

### 1. Display Request
Components that display images:
- `ProjectImageView`
- `PhotoThumbnail`
- `ZoomablePhotoView`
- `ProjectImagesSection`

### 2. Multi-Tier Cache Check
```
1. Memory Cache (ImageCache)
   ├── NSCache with 100 image limit
   ├── 50MB total size limit
   └── Returns immediately if found
   
2. File System (ImageFileManager)
   ├── Documents/ProjectImages/{hashedFilename}
   ├── Handles both local:// and https:// URLs
   └── Returns UIImage from disk
   
3. UserDefaults (Legacy)
   ├── Check for Base64 image data
   ├── Migrate to file system if found
   └── Remove from UserDefaults
   
4. Network Fetch
   ├── Normalize URL (// → https://)
   ├── Download with URLSession
   ├── Save to file system
   ├── Add to memory cache
   └── Return UIImage
```

### 3. Display
- Loading states with progress indicators
- Error states with retry capability
- Unsynced indicator (cloud-slash icon)

## Storage Details

### S3 Storage
```
URL Format: https://ops-app-files-prod.s3.us-west-2.amazonaws.com/company-{companyId}/{projectId}/photos/{filename}
Permissions: Private with signed URLs
Content-Type: image/jpeg
```

### Local File System
```swift
// Storage path
Documents/ProjectImages/{hashedFilename}

// Filename hashing
filename = Base64(urlString)
    .replacingOccurrences("/", with: "+")
    .replacingOccurrences("=", with: "")
    .prefix(50)
```

### Memory Cache
```swift
class ImageCache {
    private let cache = NSCache<NSString, UIImage>()
    
    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
}
```

### Pending Uploads Storage
```swift
// UserDefaults key
"pendingImageUploads"

// Structure
struct PendingImageUpload: Codable {
    let localURL: String
    let projectId: String
    let companyId: String
    let timestamp: Date
}
```

## Project Model Integration

### Image Tracking Fields
```swift
class Project {
    // All image URLs (comma-separated)
    var projectImagesString: String = ""
    
    // Unsynced local URLs (comma-separated)
    var unsyncedImagesString: String = ""
    
    // Sync flags
    var needsSync: Bool = false
    var syncPriority: Int = 1 // 2 for images
}
```

### Helper Methods
```swift
// Get all images
func getProjectImages() -> [String]
func setProjectImageURLs(_ urls: [String])

// Track sync state
func addUnsyncedImage(_ imageURL: String)
func markImageAsSynced(_ imageURL: String)
func isImageSynced(_ imageURL: String) -> Bool
```

## Configuration

### Enable/Disable Presigned URLs
```swift
// In ImageSyncManager.swift
private let usePresignedURLs = false // Set to true for Lambda uploads
```

### AWS Configuration
```swift
// In S3UploadService.swift
private let accessKeyId = "..." // TODO: Move to secure config
private let secretAccessKey = "..." // TODO: Move to secure config
private let bucketName = "ops-app-files-prod"
private let region = "us-west-2"
```

## Error Handling

### Upload Failures
1. **S3 Upload Fails**
   - Falls back to local storage
   - Queues for retry
   - Shows error to user

2. **Bubble Registration Fails**
   - Deletes S3 images (cleanup)
   - Keeps local copy
   - Retries on next sync

3. **Network Errors**
   - Automatic offline mode
   - All operations queued
   - Syncs when connected

### Display Failures
1. **Image Not Found**
   - Shows placeholder
   - Allows retry

2. **Corrupt Image**
   - Removes from cache
   - Re-downloads

## Security Considerations

### AWS Credentials
⚠️ **Current Issue**: Credentials are hardcoded
- Should use secure configuration service
- Consider using temporary credentials via STS
- Implement credential rotation

### Image Access
- S3 bucket is private
- Images accessed via signed URLs
- Local images protected by iOS sandbox

## Performance Optimizations

### Compression
- JPEG quality: 0.7 (balanced quality/size)
- Average compressed size: 200-500KB
- Original images not stored

### Caching Strategy
- Memory cache for session
- File cache for persistence
- Automatic cache eviction

### Batch Operations
- Multiple images uploaded together
- Grouped by project for sync
- Parallel uploads when possible

## Migration from UserDefaults

### Background
- Legacy system stored Base64 images in UserDefaults
- Caused "attempting to store >= 4194304 bytes" errors
- Automatic migration on app launch

### Migration Process
```swift
1. Check UserDefaults for image keys
2. Extract Base64 data
3. Save to file system
4. Remove from UserDefaults
5. Update references
```

## Testing Considerations

### Offline Testing
1. Enable airplane mode
2. Capture images
3. Verify local storage
4. Re-enable network
5. Verify sync

### Performance Testing
1. Upload 10 images at once
2. Monitor memory usage
3. Check upload progress
4. Verify all images synced

### Edge Cases
- Very large images
- No storage space
- Corrupt image data
- Network timeout during upload
- App termination during sync

## Recent Fixes and Improvements

### 1. Image Deletion Sync Fix
**Problem:** Deleted images on web weren't removed from iOS app
**Solution:** Enhanced `SyncManager` to:
- Compare local and remote image sets
- Clean up file cache and memory cache for deleted images  
- Handle empty image arrays from server
- Log all image sync operations

### 2. Cache Key Truncation Fix
**Problem:** All images showed same content due to truncated cache keys
**Solution:** 
- Changed from truncation to SHA256 hashing for unique keys
- Added one-time cache clear on app launch
- Fixed filename generation: `remote_{32-char-hash}{suffix}`

### 3. Duplicate Upload Prevention
**Problem:** Same image could be uploaded multiple times
**Solution:** Enhanced upload services to:
- Check existing filenames before upload
- Generate unique names with suffixes (_1, _2, etc.)
- Track filenames during batch uploads
- Maximum 100 attempts for unique naming

### 4. Duplicate Display Fix  
**Problem:** Images appeared twice after upload
**Solution:**
- Removed duplicate additions in views
- Let ImageSyncManager handle all updates
- Single source of truth for image management

## Future Improvements

### Planned Enhancements
1. Image compression options
2. Thumbnail generation
3. HEIC support
4. Background upload tasks
5. Upload progress callbacks
6. Retry configuration
7. S3 multipart uploads for large files

### Potential Optimizations
1. WebP format support
2. Progressive image loading
3. Smart prefetching
4. CDN integration
5. Image resizing options