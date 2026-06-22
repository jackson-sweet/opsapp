# "Add to OPS Project" Share Extension + in-app multi-add (item 1e3c6fa8)

**Status:** In-app multi-add ALREADY SHIPPED. Share Extension spec'd for a focused build session (needs an Apple Developer portal step only Jackson can do).

## Part 2 — in-app PHPicker multi-add — ALREADY SHIPPED

`ImagePicker` (`OPS/Views/Components/Images/ImagePicker.swift`) is a `PHPickerViewController` with `selectionLimit = 10`. ProjectDetails' quick-action `onPhotoLibrary` opens it (`viewModel.showingImagePicker`) and `ProjectDetailsViewModel.addPhotosToProject` uploads the **whole** `selectedImages: [UIImage]` array in one pass via `imageSyncManager.saveImages`. So "pull one or more photos straight from the camera roll and attach them all in one pass" is done. No work needed beyond optionally raising the limit.

## Part 1 — the Share Extension (new app-extension target)

### Current state
- `OPS.entitlements` has **no App Group**; there is **no existing `.appex` target** in `OPS.xcodeproj` (Xcode-16 synchronized-group project).
- Upload contract: `PresignedURLUploadService.uploadProjectImages` / `uploadImageData(_:filename:folder:)` → `AppConfiguration.apiBaseURL + /api/uploads/presign` → S3, authed by the **Firebase ID token** (`FirebaseAuthService.getIDToken`). The app holds **no AWS creds** — all S3 mediated by ops-web. After upload, a `project_photos` row is inserted (`ImageSyncManager.insertProjectPhotoRows`) and the legacy `projects.project_images` CSV is updated.
- Notifications via `NotificationManager`/`NotificationRepository`.

### Design
1. **New Share Extension target** (`OPSShareExtension.appex`), `NSExtensionPointIdentifier = com.apple.share-services`, activation rule accepting images (`public.image`, N items). In an Xcode-16 synchronized-group project, add: a `PBXNativeTarget` (app-extension product type) with Sources/Resources/Frameworks build phases + Debug/Release configs, a product reference, a `PBXFileSystemSynchronizedRootGroup` for the extension folder, and an **"Embed App Extensions"** copy-files phase on the OPS app target. (Hand-editing `project.pbxproj` is fragile — do this in a throwaway worktree and build-verify before committing.)
2. **App Group** (`group.co.opsapp.shared` or the existing bundle prefix) entitlement on **both** app + extension.
3. **Session bridge (avoid Firebase-in-extension).** The main app writes to the App Group container, on login + company-switch + token refresh: the current **Firebase ID token + expiry**, the **company id/user id**, and a **lightweight cache of the user's editable projects** (`[{id, title}]`, filtered to projects the user can edit — respect `projects.edit`/photo permission so the picker only offers attachable projects). The extension reads these; it never runs the Firebase SDK.
4. **Upload from the extension.** The extension presents a searchable project picker over the cached list, multi-select confirm, per-file progress. For each selected image: if the stored ID token is unexpired, call `/api/uploads/presign` → S3 → then write the `project_photos` row + project_images CSV (via the same authed REST the app uses). **If the token is expired or offline, write the image + target project to a shared App Group upload queue**; the main app drains the queue on next launch (reusing/extending `ImageSyncManager`'s pending-upload machinery), so the extension never needs to refresh tokens. Use a **background `URLSession` with `sharedContainerIdentifier`** so uploads survive the extension closing.
5. **Completion notification.** On success post an OPS notification "N photos added to <project>" with `actionUrl` deep-linking to the project gallery (`ops://projects/<id>`), via `NotificationRepository`. For queued-offline, the app posts it when the drain completes.
6. **Permission gating.** The cached project list already excludes non-editable projects; the app re-checks `projects.edit`/photo permission on drain as defense-in-depth (mirror `ClientVisibilityButton`/photo-delete gating).

### Manual Apple Developer portal steps (Jackson only — external gate)
- Register the **App Group identifier**; enable the App Group capability on the app's App ID and a **new App ID for the extension**.
- Create/refresh provisioning profiles for both (the extension needs its own). Add the App Group entitlement file to the extension target.
- (All Swift compiles with `CODE_SIGNING_ALLOWED=NO`; device install + TestFlight need the above.)

### Risks
- pbxproj target surgery is the highest-risk step — isolate + build-verify.
- Share-extension memory ceiling (~120 MB) — downscale before upload; stream via background session.
- Token expiry in the extension — the queue-and-drain design sidesteps refresh entirely; verify the offline path end-to-end.

Note: the design workflow for this item stalled under load; this spec is derived from direct recon of `ImagePicker`, `PresignedURLUploadService`, `ImageSyncManager`, `FirebaseAuthService`, `OPS.entitlements`, and the pbxproj.
