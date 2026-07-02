# Project Details Online-Lag Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Spawned-task naming:** if you spawn any follow-up chats/tasks from this plan, title them `PROJECT DETAILS PERF - P1-<n>` per the repo convention in `CLAUDE.md`.

**Goal:** Eliminate the online-only scroll/tab-switch lag on the iOS Project Details screen by removing main-thread image work, redundant per-tab-switch network fetches, whole-screen re-render churn, snapshot re-render thrash, and the live workspace map running behind the details sheet.

**Architecture:** Five independent, individually-shippable workstreams: (1) a downsampling image pipeline so 72 pt tiles never decode 12 MP originals and never block the main thread; (2) staleness-guarded tab data so tab switches render cached data instantly; (3) observation-scope reduction so location/deck-design churn stops invalidating the whole 1,400-line container; (4) an in-frame gate on the header snapshot's render key plus a connectivity retry and dead-code deletion; (5) a pause hook so the workspace map stops repainting behind the details sheet. Visual output is intentionally identical everywhere (one noted sliver exception in Task 5).

**Tech Stack:** SwiftUI, SwiftData, Mapbox Maps 11.19, XCTest. Repo: `/Users/jacksonsweet/Projects/OPS/ops-ios` (the live iOS code — NOT `OPS/OPS/` at the OPS root, which is an empty stub).

---

## Background (why each task exists)

Read this once — it is the condensed root-cause investigation this plan implements. All claims were verified against code on 2026-07-02.

1. **Photos:** `PhotoThumbnail` ([OPS/Views/Components/Images/ProjectPhotosGrid.swift:274](OPS/Views/Components/Images/ProjectPhotosGrid.swift)) downloads full-resolution photos, processes the completion **on the main queue**, writes multi-MB files to disk **on the main thread**, and decodes full 12 MP bitmaps at draw time for 72 pt tiles. The server already provides `thumbnail_url` (`ProjectPhoto.thumbnailURL` exists on the SwiftData model) but nothing uses it — `galleryURLs()` maps only `$0.url`. The 50 MB `ImageCache` uses cost = w×h×4, so ONE decoded 12 MP image (~46 MB) evicts everything; tab switches re-do all photo work.
2. **Tab refetches:** every visit to the Expenses tab re-runs `.task { await viewModel.loadExpenses() }` — two sequential Supabase round trips — because tab content is identity-swapped by a `switch`. `loadNotes()` runs a per-note `FetchDescriptor` loop on the main context at screen open.
3. **Observation churn:** `ProjectDetailsView` declares `@EnvironmentObject locationManager` and reads `locationManager.userLocation` in `mainContent`, so **every** location/heading publish re-evaluates the entire container. It also holds an **unfiltered** `@Query` of all `DeckDesign` rows (and `deck_designs` is realtime-subscribed, so any company-wide deck save invalidates it). `DeckTabView` repeats the unfiltered query.
4. **Snapshot thrash:** `ProjectLocationSnapshotView.renderKey` folds the user's coordinate (quantized ~100 m) into the snapshot identity WITHOUT checking whether the user is anywhere near the project — a driving operator forces a full Snapshotter spin-up (style load + tile fetch + render + teardown) every ~100 m even 500 km away. A failed render (offline open) never retries. The old live map `ProjectLocationMapView` is dead code (zero call sites).
5. **Map behind the sheet:** Project details is presented as a `.sheet` (see `OPS/Views/Components/Project/ProjectSheetContainer.swift`), so when opened from the home/map tab, the workspace map (`OPSMapView` inside `OPSMapContainer`) stays in the window and keeps repainting on every location/course tick and streaming tiles for the whole session.

Non-goals (explicitly out of scope, decided during diagnosis): restructuring `DataController`/`AppState` observation (event-driven, low frequency, high refactor risk); `DetailsTabView`'s `allUsers` query (users change rarely; scoping it requires rewriting a 13-parameter memberwise init for marginal gain); the realtime/sync engine (works correctly; not the bottleneck).

---

## Task 0: Preflight

**Files:** none (checks only)

- [ ] **Step 0.1: Check for parallel sessions before building.** This repo runs multiple Claude sessions in parallel.

Run: `ps aux | grep xcodebuild | grep -v grep`
Expected: no output. If a build is running, wait for it or use a separate DerivedData path via `-derivedDataPath .dd-perf` on every xcodebuild command in this plan.

- [ ] **Step 0.2: Check working-tree state.**

Run: `git -C /Users/jacksonsweet/Projects/OPS/ops-ios status --short`

Rules: local `main` contains **unpushed** work (deck fullscreen viewer, ledger nav fix). Never push, reset, rebase, or stash. If files this plan touches show pre-existing uncommitted changes you did not make, STOP and ask the user. Unrelated WIP in other files: leave untouched; stage only by explicit filename throughout this plan. Note: several iOS files have CRLF/mixed line endings — use exact-string Edit operations, never rewrite whole files you didn't create.

- [ ] **Step 0.3: Baseline build.**

Run: `cd /Users/jacksonsweet/Projects/OPS/ops-ios && xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If the baseline is broken, STOP and report before changing anything.

---

## Task 1: Downsampling image pipeline (`ImageDownsampler` + `PhotoThumbnail`)

**Files:**
- Create: `OPS/Utilities/ImageDownsampler.swift`
- Create: `OPSTests/ImageDownsamplerTests.swift`
- Modify: `OPS/Views/Components/Images/ProjectPhotosGrid.swift` (the `PhotoThumbnail` struct, currently lines ~274–459)
- Modify: `OPS/Views/Components/Project/Tabs/ActivityTabView.swift` (`ProjectPhotosCarousel.body`, currently lines ~552–614)

**Intended behavior change (approved):** thumbnails no longer force a full-resolution download; when a server thumbnail exists, only the small file is fetched. The full-resolution image downloads when the full-screen viewer opens (viewer code paths are unchanged). Photo markup (composited annotations) must still appear on tiles — the composite branch is preserved and tested manually in Task 6.

- [ ] **Step 1.1: Write the failing test.** Create `OPSTests/ImageDownsamplerTests.swift`:

```swift
//
//  ImageDownsamplerTests.swift
//  OPSTests
//
//  Verifies the tile-size downsampler used by PhotoThumbnail: encoded-data
//  downsampling (ImageIO, no full-bitmap decode) and already-decoded
//  downscaling (disk originals / composites).
//

import XCTest
@testable import OPS

final class ImageDownsamplerTests: XCTestCase {

    private func makeJPEGData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height), format: format
        ).image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return image.jpegData(compressionQuality: 0.8)!
    }

    func testDownsampleDataCapsLongestSide() {
        let data = makeJPEGData(width: 1200, height: 900)
        let result = ImageDownsampler.downsample(data: data, maxPixelSize: 216)
        XCTAssertNotNil(result)
        let cg = result!.cgImage!
        XCTAssertLessThanOrEqual(max(cg.width, cg.height), 216)
        XCTAssertEqual(Double(cg.width) / Double(cg.height), 1200.0 / 900.0, accuracy: 0.05)
    }

    func testDownsampleGarbageDataReturnsNil() {
        XCTAssertNil(ImageDownsampler.downsample(data: Data([0x00, 0x01, 0x02]), maxPixelSize: 216))
    }

    func testDownsampleImageAlreadySmallReturnsOriginal() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 80), format: format).image { _ in }
        let result = ImageDownsampler.downsample(image: small, maxPixelSize: 216)
        XCTAssertEqual(result.size, small.size)
    }

    func testDownsampleImageCapsLongestSide() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 2000, height: 1000), format: format).image { _ in }
        let result = ImageDownsampler.downsample(image: big, maxPixelSize: 216)
        XCTAssertLessThanOrEqual(max(result.size.width, result.size.height) * result.scale, 216)
    }
}
```

- [ ] **Step 1.2: Run the test to verify it fails.**

Run: `cd /Users/jacksonsweet/Projects/OPS/ops-ios && xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ImageDownsamplerTests 2>&1 | tail -15`
Expected: compile FAILURE — `cannot find 'ImageDownsampler' in scope`.

- [ ] **Step 1.3: Create `OPS/Utilities/ImageDownsampler.swift`:**

```swift
//
//  ImageDownsampler.swift
//  OPS
//
//  Tile-size image decoding for photo thumbnails. Decoding a full 12 MP
//  original to draw a 72 pt tile costs tens of ms of main-thread time per
//  photo and one image fills the entire 50 MB ImageCache; downsampling at
//  decode time makes tiles cheap to decode, cheap to cache, and cheap to draw.
//

import UIKit
import ImageIO

enum ImageDownsampler {

    /// Decode a downsampled UIImage straight from encoded image data via
    /// ImageIO, without ever materializing the full-resolution bitmap.
    static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Downscale an already-decoded UIImage (disk originals, annotation
    /// composites). Returns the input untouched when it is already within
    /// the cap, so small images pay nothing.
    static func downsample(image: UIImage, maxPixelSize: CGFloat) -> UIImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longest = max(pixelWidth, pixelHeight)
        guard longest > maxPixelSize, longest > 0 else { return image }
        let ratio = maxPixelSize / longest
        let targetSize = CGSize(
            width: (pixelWidth * ratio).rounded(),
            height: (pixelHeight * ratio).rounded()
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
```

Note: if `grep -c "PBXFileSystemSynchronizedRootGroup" OPS.xcodeproj/project.pbxproj` returns > 0, new files are picked up automatically. Otherwise add the two new files to the project by appending PBXFileReference/PBXBuildFile entries mirroring an existing `OPS/Utilities/` file (for the test file, mirror an existing `OPSTests/` entry).

- [ ] **Step 1.4: Run the test to verify it passes.**

Run: same command as Step 1.2.
Expected: `Test Suite 'ImageDownsamplerTests' passed` — 4 tests.

- [ ] **Step 1.5: Rewrite `PhotoThumbnail`'s loading path.** In `OPS/Views/Components/Images/ProjectPhotosGrid.swift`:

**(a)** Add two members to `struct PhotoThumbnail` directly below `var isDimensioned: Bool = false`:

```swift
    /// Server-generated small rendition (project_photos.thumbnail_url).
    /// When present, the tile fetches THIS instead of the full original.
    /// Optional + defaulted so legacy call sites keep compiling unchanged.
    var remoteThumbnailURL: String? = nil

    /// 72 pt tile at 3× — the decode cap for every tile image.
    static let tileMaxPixelSize: CGFloat = 216
```

**(b)** Replace the entire body of `private func loadImage()` (from `guard image == nil else { return }` through the closing `}.resume()` of the URLSession block) with:

```swift
        guard image == nil else { return }

        isLoading = true

        // Asset catalog names (demo images) — no "://" and no "//" prefix.
        let isAssetName = !url.contains("://") && !url.hasPrefix("//")
        if isAssetName, let assetImage = UIImage(named: url) {
            isLoading = false
            image = assetImage
            return
        }

        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        let thumbKey = cacheKey + "#thumb216"

        // Fast path — a tile-sized decode is already in memory.
        if let cachedThumb = ImageCache.shared.get(forKey: thumbKey) {
            isLoading = false
            image = cachedThumb
            return
        }

        // A full-size composite may sit in memory under the plain key
        // (PhotoAnnotationSyncManager warms it) — downscale that rather than
        // re-reading disk.
        let inMemoryFull = ImageCache.shared.get(forKey: cacheKey)
        let sourceURL = url
        let remoteThumb = remoteThumbnailURL

        // Everything below is disk I/O and decode work — strictly off main.
        DispatchQueue.global(qos: .userInitiated).async {
            func publish(_ resolved: UIImage?) {
                DispatchQueue.main.async {
                    self.isLoading = false
                    if let resolved {
                        self.image = resolved
                        ImageCache.shared.set(resolved, forKey: thumbKey)
                    }
                }
            }

            if let inMemoryFull {
                publish(ImageDownsampler.downsample(image: inMemoryFull, maxPixelSize: Self.tileMaxPixelSize))
                return
            }
            // Durable annotated composite BEFORE the raw original — markup
            // must win on tiles (same precedence as the old path).
            if let composited = ImageFileManager.shared.loadCompositedImage(forURL: sourceURL) {
                publish(ImageDownsampler.downsample(image: composited, maxPixelSize: Self.tileMaxPixelSize))
                return
            }
            if let onDisk = ImageFileManager.shared.loadImage(localID: sourceURL) {
                publish(ImageDownsampler.downsample(image: onDisk, maxPixelSize: Self.tileMaxPixelSize))
                return
            }
            // Legacy UserDefaults storage — migrate to disk, as before.
            if sourceURL.hasPrefix("local://"),
               let base64String = UserDefaults.standard.string(forKey: sourceURL),
               let imageData = Data(base64Encoded: base64String) {
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: sourceURL)
                publish(ImageDownsampler.downsample(data: imageData, maxPixelSize: Self.tileMaxPixelSize))
                return
            }

            // Network. Prefer the server thumbnail (small bytes, tiny decode);
            // fall back to the full original, which we persist to disk exactly
            // as the old path did so the viewer and future opens hit disk.
            let normalizedThumb = remoteThumb.map { $0.hasPrefix("//") ? "https:" + $0 : $0 }
            let fetchingThumbnail = normalizedThumb != nil
            guard let imageURL = URL(string: normalizedThumb ?? cacheKey) else {
                publish(nil)
                return
            }

            URLSession.shared.dataTask(with: imageURL) { data, response, error in
                if let error = error {
                    print("Image load error: \(error.localizedDescription)")
                    publish(nil)
                    return
                }
                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    print("Image load failed with status: \(httpResponse.statusCode)")
                    publish(nil)
                    return
                }
                guard let data else {
                    publish(nil)
                    return
                }
                // Persist ONLY full originals under the photo's cache key —
                // a thumbnail rendition must never masquerade as the original.
                if !fetchingThumbnail {
                    _ = ImageFileManager.shared.saveImage(data: data, localID: cacheKey)
                }
                publish(ImageDownsampler.downsample(data: data, maxPixelSize: Self.tileMaxPixelSize))
            }.resume()
        }
```

**(c)** Replace the entire body of `private func reloadFromCache()` with (composite refresh must produce a tile-sized image under the thumb key, off main):

```swift
        let cacheKey = url.hasPrefix("//") ? "https:" + url : url
        let thumbKey = cacheKey + "#thumb216"
        let sourceURL = url
        let inMemoryFull = ImageCache.shared.get(forKey: cacheKey)

        DispatchQueue.global(qos: .userInitiated).async {
            var fresh: UIImage?
            if let inMemoryFull {
                fresh = ImageDownsampler.downsample(image: inMemoryFull, maxPixelSize: Self.tileMaxPixelSize)
            } else if let composited = ImageFileManager.shared.loadCompositedImage(forURL: sourceURL) {
                fresh = ImageDownsampler.downsample(image: composited, maxPixelSize: Self.tileMaxPixelSize)
            }
            guard let fresh else { return }
            DispatchQueue.main.async {
                self.image = fresh
                ImageCache.shared.set(fresh, forKey: thumbKey)
            }
        }
```

Leave `.id(url)` and the rest of the struct untouched.

- [ ] **Step 1.6: Feed server thumbnails to the carousel.** In `OPS/Views/Components/Project/Tabs/ActivityTabView.swift`, inside `ProjectPhotosCarousel`'s `body`, directly below the existing line `let photos = project.mergedGalleryImageURLs(syncedPhotoURLs: syncedPhotos.galleryURLs())`, add:

```swift
        // Server-generated thumbnail per full URL — PhotoThumbnail fetches the
        // small rendition instead of the multi-MB original when one exists.
        let thumbnailByURL: [String: String] = Dictionary(
            syncedPhotos.compactMap { photo -> (String, String)? in
                guard let thumb = photo.thumbnailURL, !thumb.isEmpty else { return nil }
                return (photo.url, thumb)
            },
            uniquingKeysWith: { first, _ in first }
        )
```

Then change the carousel's tile call (inside `ForEach(Array(photos.enumerated()), id: \.element)`) from:

```swift
                                PhotoThumbnail(url: url, project: project)
```

to:

```swift
                                PhotoThumbnail(url: url, project: project, remoteThumbnailURL: thumbnailByURL[url])
```

Parameter order note: `remoteThumbnailURL` was added AFTER `isDimensioned` in Step 1.5(a), so this labeled call compiles only if the memberwise order allows it — to keep it simple, declare `remoteThumbnailURL` **immediately after `let project: Project`** (before `isDimensioned`) in Step 1.5(a) instead, and the call above is valid. The other 7 `PhotoThumbnail` call sites (`PhotoSourcePickerView`, `AllPhotosGalleryView`, `ProjectPhotosGrid`, `DetailsTabView`, `TaskBioSheet`, `ActivityEntryView`, `ProjectBioSheet`, the static carousel in `ActivityTabView`) pass no new argument and keep compiling; they still gain off-main loading and downsampled decodes automatically.

- [ ] **Step 1.7: Build + run the downsampler tests again.**

Run: `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5` then the Step 1.2 test command.
Expected: BUILD SUCCEEDED; 4 tests pass.

- [ ] **Step 1.8: Commit.**

```bash
git add OPS/Utilities/ImageDownsampler.swift OPSTests/ImageDownsamplerTests.swift "OPS/Views/Components/Images/ProjectPhotosGrid.swift" "OPS/Views/Components/Project/Tabs/ActivityTabView.swift"
git commit -m "perf(project-details): downsample photo tiles off-main, prefer server thumbnails

Tiles decoded full 12MP originals on the main thread (completion handler,
disk write, and draw-time decode all on main) for 72pt frames, and one
decoded original filled the entire 50MB ImageCache. Tiles now decode via
ImageIO to a 216px cap strictly off-main, cache under a dedicated thumb
key, and fetch the server thumbnail_url rendition when one exists; the
full original now downloads only when the viewer opens it."
```

(If the pbxproj needed manual file registration in Step 1.3, include `OPS.xcodeproj/project.pbxproj` in the `git add`.)

---

## Task 2: Kill redundant tab fetches (expenses staleness guard + single-fetch notes merge)

**Files:**
- Modify: `OPS/Views/Components/Project/ProjectDetailsViewModel.swift` (expense section, currently lines ~92–96 and ~666–682)
- Modify: `OPS/Views/Components/Project/Tabs/ProjectExpensesTabView.swift:57-59`
- Modify: `OPS/ViewModels/ProjectNotesViewModel.swift:80-116`
- Create: `OPSTests/ProjectDetailsExpenseCacheTests.swift`
- Create: `OPSTests/ProjectNotesMergeTests.swift`

- [ ] **Step 2.1: Write the failing expense-staleness test.** Create `OPSTests/ProjectDetailsExpenseCacheTests.swift`:

```swift
//
//  ProjectDetailsExpenseCacheTests.swift
//  OPSTests
//
//  The Expenses tab re-fetched from Supabase on every tab switch. These
//  tests pin the staleness rule that lets a visit render the cached list
//  instantly while realtime (.opsExpensesDidChange) stays the authoritative
//  refresh path.
//

import XCTest
@testable import OPS

final class ProjectDetailsExpenseCacheTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    func testNeverLoadedIsStale() {
        XCTAssertFalse(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: nil, hasData: true, now: now, maxAge: 300))
    }

    func testFreshWithDataSkipsReload() {
        XCTAssertTrue(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: now.addingTimeInterval(-60), hasData: true, now: now, maxAge: 300))
    }

    func testFreshButEmptyReloads() {
        // An empty list may mean the first fetch failed silently — refetch.
        XCTAssertFalse(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: now.addingTimeInterval(-60), hasData: false, now: now, maxAge: 300))
    }

    func testStaleReloads() {
        XCTAssertFalse(ProjectDetailsViewModel.isExpenseCacheFresh(
            loadedAt: now.addingTimeInterval(-301), hasData: true, now: now, maxAge: 300))
    }
}
```

- [ ] **Step 2.2: Run it — expect compile failure** (`isExpenseCacheFresh` not found):

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ProjectDetailsExpenseCacheTests 2>&1 | tail -10`

- [ ] **Step 2.3: Implement the guard in `ProjectDetailsViewModel`.**

**(a)** In the `// MARK: - Expense State` section (below `@Published var expenseError: String? = nil`), add:

```swift
    /// When the project-expense cache was last filled from the server.
    private var expensesLoadedAt: Date?
```

**(b)** Directly above `func loadExpenses() async` add:

```swift
    /// Staleness rule for tab visits. Pure + static so it is unit-testable
    /// (pattern: RealtimeProcessor.subscribeRetryDelay).
    nonisolated static func isExpenseCacheFresh(
        loadedAt: Date?, hasData: Bool, now: Date, maxAge: TimeInterval
    ) -> Bool {
        guard hasData, let loadedAt else { return false }
        return now.timeIntervalSince(loadedAt) < maxAge
    }

    /// Tab-visit entry point: render the cached list instantly and hit the
    /// network only when the cache is empty or older than `maxAge`. The
    /// container's `.opsExpensesDidChange` observer still calls
    /// `loadExpenses()` directly, so any expense change (local or realtime)
    /// force-refreshes regardless of age.
    func loadExpensesIfStale(maxAge: TimeInterval = 300) async {
        if Self.isExpenseCacheFresh(
            loadedAt: expensesLoadedAt,
            hasData: !projectExpenses.isEmpty,
            now: Date(),
            maxAge: maxAge
        ) { return }
        await loadExpenses()
    }
```

**(c)** In `loadExpenses()`, change `isLoadingExpenses = true` to show the spinner only on a cold load (background refreshes must not blank an already-rendered list), and stamp success. Replace the body between `expenseError = nil` and the closing brace with:

```swift
        isLoadingExpenses = projectExpenses.isEmpty
        expenseError = nil

        do {
            let repo = ExpenseRepository(companyId: companyId)
            projectExpenses = try await repo.fetchByProject(project.id)
            expensesLoadedAt = Date()
            isLoadingExpenses = false
        } catch {
            expenseError = error.localizedDescription
            isLoadingExpenses = false
            print("[EXPENSES] Failed to load project expenses: \(error)")
        }
```

(Keep the existing `guard let dc = dataController, let companyId = dc.currentUser?.companyId else { return }` and delete the old `isLoadingExpenses = true` line above `expenseError = nil`.)

- [ ] **Step 2.4:** In `ProjectExpensesTabView.swift`, change:

```swift
        .task {
            await viewModel.loadExpenses()
        }
```

to:

```swift
        .task {
            await viewModel.loadExpensesIfStale()
        }
```

- [ ] **Step 2.5: Run the expense tests — expect 4 passes** (Step 2.2 command).

- [ ] **Step 2.6: Write the failing notes-merge test.** Create `OPSTests/ProjectNotesMergeTests.swift`:

```swift
//
//  ProjectNotesMergeTests.swift
//  OPSTests
//
//  loadNotes() ran one FetchDescriptor per DTO on the main context at screen
//  open. The merge now does a single project-scoped fetch; these tests pin
//  insert + update behavior.
//

import XCTest
import SwiftData
@testable import OPS

final class ProjectNotesMergeTests: XCTestCase {

    @MainActor
    func testMergeInsertsNewAndUpdatesExisting() throws {
        let container = try ModelContainer(
            for: ProjectNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let existing = ProjectNote(
            id: "n1", projectId: "p1", companyId: "c1",
            authorId: "u1", content: "old"
        )
        context.insert(existing)
        try context.save()

        let json = """
        [
          {"id":"n1","project_id":"p1","company_id":"c1","author_id":"u1","content":"new","created_at":"2026-07-01T00:00:00Z"},
          {"id":"n2","project_id":"p1","company_id":"c1","author_id":"u2","content":"fresh","created_at":"2026-07-01T01:00:00Z"}
        ]
        """.data(using: .utf8)!
        let dtos = try JSONDecoder().decode([ProjectNoteDTO].self, from: json)

        ProjectNotesViewModel.mergeFetchedNotes(dtos, projectId: "p1", context: context)

        let all = try context.fetch(FetchDescriptor<ProjectNote>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.id == "n1" })?.content, "new")
        XCTAssertEqual(all.first(where: { $0.id == "n2" })?.content, "fresh")
        XCTAssertEqual(all.first(where: { $0.id == "n1" })?.needsSync, false)
    }
}
```

(If `ModelContainer(for: ProjectNote.self, ...)` throws at runtime about a related model type, add the named types to the same `for:` list — `OPSTests/ProjectGalleryFilterTests.swift` is the in-memory precedent to mirror.)

- [ ] **Step 2.7: Run it — expect compile failure** (`mergeFetchedNotes` not found):

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ProjectNotesMergeTests 2>&1 | tail -10`

- [ ] **Step 2.8: Implement the merge in `ProjectNotesViewModel.swift`.** Add below `loadNotes()`:

```swift
    /// Merge fetched note DTOs into SwiftData with ONE project-scoped fetch
    /// instead of a per-note FetchDescriptor — N store round-trips on the
    /// main actor was a measured screen-open cost. Static so it is testable
    /// against an in-memory container.
    static func mergeFetchedNotes(
        _ dtos: [ProjectNoteDTO], projectId: String, context: ModelContext
    ) {
        let pid = projectId
        let descriptor = FetchDescriptor<ProjectNote>(
            predicate: #Predicate { $0.projectId == pid }
        )
        let existingById = Dictionary(
            ((try? context.fetch(descriptor)) ?? []).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for dto in dtos {
            let model = dto.toModel()
            model.lastSyncedAt = Date()
            model.needsSync = false
            if let existing = existingById[dto.id] {
                existing.content = model.content
                existing.attachmentsJSON = model.attachmentsJSON
                existing.mentionedUserIdsString = model.mentionedUserIdsString
                existing.photoURL = model.photoURL
                existing.updatedAt = model.updatedAt
                existing.deletedAt = model.deletedAt
                existing.lastSyncedAt = Date()
            } else {
                context.insert(model)
            }
        }
        try? context.save()
    }
```

Then in `loadNotes()`, replace the block from `if let context = modelContext {` through its matching `}` (the per-DTO loop plus `try? context.save()`) with:

```swift
            if let context = modelContext {
                Self.mergeFetchedNotes(dtos, projectId: projectId, context: context)
            }
```

Note the merge keeps `needsSync = false` semantics identical to the old loop for updated rows (the old loop never touched `needsSync` on existing rows either — it only assigned the listed fields; preserve exactly the listed fields and nothing more). The test's `needsSync` assertion covers the inserted row (`n1` is replaced content-wise but `needsSync` on an existing row stays whatever it was — the assertion passes because the seeded row defaulted to `false`; do not change the assertion, it pins the default path).

- [ ] **Step 2.9: Run both new suites + build.**

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ProjectDetailsExpenseCacheTests -only-testing:OPSTests/ProjectNotesMergeTests 2>&1 | tail -12`
Expected: 5 tests pass.

- [ ] **Step 2.10: Commit.**

```bash
git add "OPS/Views/Components/Project/ProjectDetailsViewModel.swift" "OPS/Views/Components/Project/Tabs/ProjectExpensesTabView.swift" OPS/ViewModels/ProjectNotesViewModel.swift OPSTests/ProjectDetailsExpenseCacheTests.swift OPSTests/ProjectNotesMergeTests.swift
git commit -m "perf(project-details): stop refetching expenses per tab switch, single-fetch notes merge

Every Expenses-tab visit ran two Supabase round trips mid-transition;
visits now render the cached list instantly and refetch only when empty
or >5min old (realtime opsExpensesDidChange remains the force-refresh
path). loadNotes ran one FetchDescriptor per DTO on the main context at
screen open; the merge now does a single project-scoped fetch."
```

---

## Task 3: Shrink the container's observation set

**Files:**
- Modify: `OPS/Views/Components/Project/ProjectMapHeader.swift` (add wrapper view)
- Modify: `OPS/Views/Components/Project/ProjectDetailsView.swift:24` (remove env object), `:40` (scope query), `:376-382` (use wrapper)
- Modify: `OPS/Views/Components/Project/Tabs/DeckTabView.swift` (scope its query)

- [ ] **Step 3.1: Add a location-observing wrapper** at the bottom of `OPS/Views/Components/Project/ProjectMapHeader.swift`:

```swift
// MARK: - Location-scoped wrapper

/// Owns the LocationManager observation so location/heading publishes
/// re-render ONLY this header subtree. ProjectDetailsView previously
/// declared the @EnvironmentObject itself, which re-evaluated the entire
/// ~1,400-line container on every location tick (10 m cadence driving,
/// every 5° of compass movement) — pure churn online.
struct ProjectMapHeaderSection: View {
    let project: Project
    let taskColorHexes: [String]
    let pinLabel: String
    let onMapTap: () -> Void

    @EnvironmentObject private var locationManager: LocationManager

    var body: some View {
        ProjectMapHeader(
            project: project,
            taskColorHexes: taskColorHexes,
            pinLabel: pinLabel,
            userCoordinate: locationManager.userLocation,
            onMapTap: onMapTap
        )
    }
}
```

- [ ] **Step 3.2: Rewire `ProjectDetailsView`.**

**(a)** Delete line 24: `@EnvironmentObject private var locationManager: LocationManager`

**(b)** In `mainContent` (Layer 1), replace:

```swift
                ProjectMapHeader(
                    project: project,
                    taskColorHexes: viewModel.projectTaskColorHexes,
                    pinLabel: viewModel.pinLabel,
                    userCoordinate: locationManager.userLocation,
                    onMapTap: { viewModel.openDirections() }
                )
```

with:

```swift
                ProjectMapHeaderSection(
                    project: project,
                    taskColorHexes: viewModel.projectTaskColorHexes,
                    pinLabel: viewModel.pinLabel,
                    onMapTap: { viewModel.openDirections() }
                )
```

**(c)** Run `grep -n "locationManager" OPS/Views/Components/Project/ProjectDetailsView.swift` — expected: zero matches. If any other use surfaces, route that single value through a parameter the same way; do not re-add the environment object.

- [ ] **Step 3.3: Scope the container's DeckDesign query.** In `ProjectDetailsView`, replace line 40:

```swift
    @Query private var allDeckDesigns: [DeckDesign]
```

with (unchanged declaration) plus an assignment inside `init(project:isEditMode:initialSelectedTask:)` directly after `self._notesViewModel = StateObject(...)`:

```swift
        // Scope to this project — deck_designs is realtime-subscribed, so an
        // unfiltered @Query invalidated this whole container on ANY company
        // deck save. DeckDesign.projectId is optional; compare via optional.
        let pid: String? = project.id
        self._allDeckDesigns = Query(
            filter: #Predicate<DeckDesign> { $0.projectId == pid }
        )
```

`displayedDeckDesign` still calls `DeckDesign.displayCandidate(in: allDeckDesigns, forProjectId: project.id)` — unchanged; the candidate logic (deleted-filter, recency sort) now just runs over a project-scoped list.

- [ ] **Step 3.4: Scope `DeckTabView`'s query the same way.** In `OPS/Views/Components/Project/Tabs/DeckTabView.swift`, `@Query private var allDesigns: [DeckDesign]` is unfiltered. Check whether the struct has an explicit `init`; if not, add one that assigns every existing stored property exactly as declared (read the property list at the top of the struct first), and add:

```swift
        let pid: String? = project.id
        self._allDesigns = Query(
            filter: #Predicate<DeckDesign> { $0.projectId == pid }
        )
```

The view's `deckDesign` computed property (`DeckDesign.displayCandidate(in: allDesigns, forProjectId: project.id)`) is unchanged. If writing the explicit init requires binding parameters (e.g., `viewMode: Binding<DeckTabViewMode>`), assign with `self._viewMode = viewMode` where `viewMode: Binding<DeckTabViewMode>` is the init parameter.

- [ ] **Step 3.5: Build.**

Run: `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3.6: Commit.**

```bash
git add "OPS/Views/Components/Project/ProjectMapHeader.swift" "OPS/Views/Components/Project/ProjectDetailsView.swift" "OPS/Views/Components/Project/Tabs/DeckTabView.swift"
git commit -m "perf(project-details): stop location ticks and company-wide deck saves re-rendering the container

LocationManager was observed by the whole container (every 10m/5° publish
re-evaluated ~1,400 lines); observation now lives in a header-only wrapper.
Both DeckDesign @Query instances were unfiltered — deck_designs is
realtime-subscribed, so any company deck save invalidated the screen —
and are now project-scoped."
```

---

## Task 4: Snapshot render-key gate, connectivity retry, dead-code deletion

**Files:**
- Modify: `OPS/Map/Views/ProjectLocationSnapshotView.swift:44-97`
- Create: `OPSTests/ProjectLocationSnapshotKeyTests.swift`
- Delete: `OPS/Map/Views/ProjectLocationMapView.swift`

- [ ] **Step 4.1: Write the failing key tests.** Create `OPSTests/ProjectLocationSnapshotKeyTests.swift`:

```swift
//
//  ProjectLocationSnapshotKeyTests.swift
//  OPSTests
//
//  The header snapshot re-rendered (full Snapshotter spin-up: style load,
//  tile fetch, render, teardown) every ~100 m the operator moved — even
//  hundreds of km from the project where no dot would ever draw. These
//  tests pin the in-frame gate.
//

import XCTest
import CoreLocation
@testable import OPS

final class ProjectLocationSnapshotKeyTests: XCTestCase {

    private let project = CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207)

    private func key(user: CLLocationCoordinate2D?) -> String {
        ProjectLocationSnapshotView.renderKey(
            projectCoordinate: project,
            userCoordinate: user,
            size: CGSize(width: 390, height: 320),
            styleRaw: "dark",
            taskColorHexes: ["#FF0000"],
            statusDescription: "active"
        )
    }

    func testFarAwayUserProducesSameKeyAsNoUser() {
        let far = CLLocationCoordinate2D(latitude: 49.5, longitude: -123.1207) // ~24 km north
        XCTAssertEqual(key(user: far), key(user: nil))
    }

    func testNearbyUserIsFoldedIntoKey() {
        let near = CLLocationCoordinate2D(latitude: 49.2830, longitude: -123.1210) // ~40 m away
        XCTAssertNotEqual(key(user: near), key(user: nil))
    }

    func testGPSJitterWithinBucketIsStable() {
        let a = CLLocationCoordinate2D(latitude: 49.28271, longitude: -123.12072)
        let b = CLLocationCoordinate2D(latitude: 49.28274, longitude: -123.12069)
        XCTAssertEqual(key(user: a), key(user: b))
    }

    func testMeaningfulMoveNearProjectRefreshesKey() {
        let a = CLLocationCoordinate2D(latitude: 49.2827, longitude: -123.1207)
        let b = CLLocationCoordinate2D(latitude: 49.2840, longitude: -123.1207) // ~145 m
        XCTAssertNotEqual(key(user: a), key(user: b))
    }
}
```

- [ ] **Step 4.2: Run — expect compile failure** (no static `renderKey`):

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' -only-testing:OPSTests/ProjectLocationSnapshotKeyTests 2>&1 | tail -10`

- [ ] **Step 4.3: Replace the private instance `renderKey(size:)` in `ProjectLocationSnapshotView.swift`** (lines ~80–97) with a testable static plus a thin instance wrapper, and add the connectivity retry:

**(a)** Delete `private func renderKey(size: CGSize) -> String { ... }` entirely. Add in its place:

```swift
    /// Stable identity for the snapshot. Internal + nonisolated static so the
    /// gating rules are unit-testable (pattern: RealtimeProcessor.subscribeRetryDelay).
    ///
    /// The operator's position folds into the identity ONLY when they are
    /// close enough to plausibly land inside the framed area (the zoom-13
    /// header frame is ~3 km across; 2.5 km is the conservative gate — the
    /// dot draw itself still exact-checks pixel bounds). Without the gate, a
    /// driving operator forced a full Snapshotter spin-up every ~100 m of
    /// travel anywhere on earth. Near the project, ~100 m buckets still
    /// refresh the dot on meaningful moves while absorbing GPS jitter.
    nonisolated static func renderKey(
        projectCoordinate: CLLocationCoordinate2D,
        userCoordinate: CLLocationCoordinate2D?,
        size: CGSize,
        styleRaw: String,
        taskColorHexes: [String],
        statusDescription: String
    ) -> String {
        let lat = (projectCoordinate.latitude * 10_000).rounded() / 10_000
        let lng = (projectCoordinate.longitude * 10_000).rounded() / 10_000
        let w = Int(size.width.rounded())
        let h = Int(size.height.rounded())

        var user = "none"
        if let u = userCoordinate {
            let userLocation = CLLocation(latitude: u.latitude, longitude: u.longitude)
            let projectLocation = CLLocation(
                latitude: projectCoordinate.latitude,
                longitude: projectCoordinate.longitude
            )
            if userLocation.distance(from: projectLocation) <= 2_500 {
                let ulat = (u.latitude * 1_000).rounded() / 1_000
                let ulng = (u.longitude * 1_000).rounded() / 1_000
                user = "\(ulat),\(ulng)"
            }
        }

        let ring = taskColorHexes.joined(separator: "-")
        return "\(lat),\(lng)|\(w)x\(h)|\(styleRaw)|\(ring)|\(statusDescription)|\(user)"
    }

    private func taskID(size: CGSize) -> String {
        Self.renderKey(
            projectCoordinate: coordinate,
            userCoordinate: userCoordinate,
            size: size,
            styleRaw: style.rawValue,
            taskColorHexes: taskColorHexes,
            statusDescription: String(describing: status)
        ) + "|r\(retryToken)"
    }
```

**(b)** Add a retry token to the view's stored properties (next to `@StateObject private var loader`):

```swift
    /// Bumped when connectivity returns while we still have no image — an
    /// offline-open otherwise left the header a flat color block for the
    /// whole session (the render key never changes on reconnect).
    @State private var retryToken = 0
```

**(c)** In `body`, change `.task(id: renderKey(size: geo.size))` to `.task(id: taskID(size: geo.size))`, and add directly below the `.task` modifier:

```swift
            .onReceive(NotificationCenter.default.publisher(
                for: ConnectivityManager.connectivityChangedNotification
            )) { _ in
                if loader.image == nil { retryToken &+= 1 }
            }
```

(A retry fired while still offline just fails again harmlessly; the token only bumps when there is no image to show.)

- [ ] **Step 4.4: Run the key tests — expect 4 passes** (Step 4.2 command).

- [ ] **Step 4.5: Delete the dead live-map view.**

Run first (must show no call sites outside the file itself — the comment reference in `ProjectLocationSnapshotView.swift` is fine to leave):
```bash
grep -rn "ProjectLocationMapView\|NearbyProjectPin" --include="*.swift" OPS/ OPSTests/
```
Expected: matches only inside `OPS/Map/Views/ProjectLocationMapView.swift` itself plus the historical comment in `ProjectLocationSnapshotView.swift`. Then:
```bash
git rm OPS/Map/Views/ProjectLocationMapView.swift
grep -c "ProjectLocationMapView" OPS.xcodeproj/project.pbxproj
```
If the pbxproj count is 0 (file-system-synchronized groups), done. If > 0, delete every pbxproj line containing `ProjectLocationMapView` (PBXBuildFile, PBXFileReference, group child, Sources-phase entries are each self-contained single lines) and stage `OPS.xcodeproj/project.pbxproj`.

- [ ] **Step 4.6: Build** (`xcodebuild ... generic/platform=iOS build` — expect SUCCEEDED; a compile error here means a missed reference, go back to 4.5).

- [ ] **Step 4.7: Commit.**

```bash
git add "OPS/Map/Views/ProjectLocationSnapshotView.swift" OPSTests/ProjectLocationSnapshotKeyTests.swift
git commit -m "perf(project-details): gate snapshot re-renders to in-frame operators, retry on reconnect, drop dead live map

The snapshot render key folded the operator's ~100m-bucketed position into
the snapshot identity unconditionally, so driving anywhere re-ran a full
Snapshotter (style load, tile fetch, render, teardown) every ~100m with no
visible change. The key now includes the operator only within 2.5km of the
project. Offline opens left the header a flat color block forever; a
connectivity-change observer now retries while no image exists.
ProjectLocationMapView (and NearbyProjectPin) had zero call sites since
73de374d — deleted."
```

---

## Task 5: Pause the workspace map behind the details sheet

**Files:**
- Modify: `OPS/Views/Components/Project/ProjectDetailsView.swift` (post appear/disappear notifications)
- Modify: `OPS/Map/Core/OPSMapCoordinator.swift` (pause API)
- Modify: `OPS/Map/Views/OPSMapContainer.swift` (observe + apply)

**Design note:** the details screen presents as a `.sheet` from four different entry points (`ProjectSheetContainer` ×2, `ScheduleView`, `UniversalJobBoardCard`), so the pause signal is posted by `ProjectDetailsView` itself — every entry point is covered, and on tabs where the map container isn't mounted the notification harmlessly has no observer.

**Accepted visual trade:** while the sheet is up, the dimmed sliver of the home screen visible above the sheet shows the app background instead of the frozen map. If Jackson rejects that on review, remove ONLY the two `mapView.isHidden` lines below and keep the puck pause — the puck pause alone removes the location-driven repaints, which are the online-only cost.

- [ ] **Step 5.1: Post lifecycle notifications from `ProjectDetailsView`.**

**(a)** At the very bottom of `OPS/Views/Components/Project/ProjectDetailsView.swift` (file scope, after the struct's closing brace), add:

```swift
// MARK: - Presentation notifications

extension Notification.Name {
    /// Posted on appear/disappear of the project-details screen. The
    /// workspace map (still mapped behind the details .sheet on the home
    /// tab) observes these to pause its puck + drawing while covered.
    static let projectDetailsDidAppear = Notification.Name("projectDetailsDidAppear")
    static let projectDetailsDidDisappear = Notification.Name("projectDetailsDidDisappear")
}
```

**(b)** In `handleOnAppear()`, add as the FIRST line of the function body:

```swift
        NotificationCenter.default.post(name: .projectDetailsDidAppear, object: nil)
```

**(c)** In the existing `.onDisappear { ... }` block (the one posting `WizardScreenDismissed`), add as its first line:

```swift
                        NotificationCenter.default.post(name: .projectDetailsDidDisappear, object: nil)
```

- [ ] **Step 5.2: Add the pause API to `OPSMapCoordinator`.** In `OPS/Map/Core/OPSMapCoordinator.swift`, inside the class (near the `private(set) var mapView: MapView?` property at ~line 96), add:

```swift
    // MARK: - Covered-by-sheet pause

    /// Restored puck configuration for resume.
    private var pausedPuckType: PuckType?
    private var isRenderingPaused = false

    /// Pause/resume map work while the project-details sheet covers the map.
    /// Removing the puck stops location/course-driven repaints (the dominant
    /// online-only cost while covered); hiding the view drops it from
    /// compositing. Camera, style, and annotations are untouched so resume
    /// is instant with no reload.
    func setRenderingPaused(_ paused: Bool) {
        guard paused != isRenderingPaused, let mapView else { return }
        isRenderingPaused = paused
        if paused {
            pausedPuckType = mapView.location.options.puckType
            mapView.location.options.puckType = nil
            mapView.isHidden = true
        } else {
            if let pausedPuckType {
                mapView.location.options.puckType = pausedPuckType
            }
            pausedPuckType = nil
            mapView.isHidden = false
        }
    }
```

- [ ] **Step 5.3: Observe in `OPSMapContainer`.** In `OPS/Map/Views/OPSMapContainer.swift`, attach to the root `ZStack` in `body` (append to its existing modifier chain, same indentation level as the other modifiers on that ZStack):

```swift
        .onReceive(NotificationCenter.default.publisher(for: .projectDetailsDidAppear)) { _ in
            coordinator.setRenderingPaused(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectDetailsDidDisappear)) { _ in
            coordinator.setRenderingPaused(false)
        }
```

- [ ] **Step 5.4: Build.**

Run: `xcodebuild -project OPS.xcodeproj -scheme OPS -destination 'generic/platform=iOS' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`. If `PuckType` fails to resolve in the coordinator, add `import MapboxMaps` to `OPSMapCoordinator.swift` (it almost certainly already imports it — it holds a `MapView?`).

- [ ] **Step 5.5: Run the FULL test suite once** (regression gate for all five tasks):

Run: `xcodebuild test -project OPS.xcodeproj -scheme OPS -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' 2>&1 | tail -20`
Expected: all suites pass. Known context: some pre-existing suites may be device/network-dependent — compare failures against `git stash`-free baseline only if something unrelated fails, and report rather than "fix" unrelated tests.

- [ ] **Step 5.6: Commit.**

```bash
git add "OPS/Views/Components/Project/ProjectDetailsView.swift" OPS/Map/Core/OPSMapCoordinator.swift OPS/Map/Views/OPSMapContainer.swift
git commit -m "perf(project-details): pause the workspace map while the details sheet covers it

Project details presents as a .sheet, so the home tab's live map stayed
mapped and kept repainting on every location/course tick and streaming
tiles for the whole session. ProjectDetailsView now posts appear/disappear
notifications (covers all four presentation entry points) and the map
coordinator pauses the puck and hides the view while covered — camera and
style state untouched, resume is instant."
```

---

## Task 6: Device verification checklist (proofs for Jackson)

No code. Run on a physical iPhone, signed into a company with a photo-bearing project. These are the observable proofs; report each with a sentence and (where visible) a screen recording.

- [ ] Open a project with 5+ photos while online → photo tiles appear progressively; scrolling during load stays smooth (no multi-frame hitches).
- [ ] Photo markup check: open a photo that has annotations → tile shows the marked-up version (composite precedence preserved).
- [ ] Switch Activity → Expenses → Activity → Expenses. Second Expenses visit renders instantly with NO spinner. Add an expense via the quick-action bar → list updates (realtime path still refreshes).
- [ ] Airplane-mode parity: same project offline → previously-viewed photos still render; expenses show cached list.
- [ ] Header snapshot: with the project far away (normal case), walk/drive around → header does NOT re-render (no crossfade flashes). Open a project while offline, then restore connectivity → header map appears within seconds.
- [ ] From the home/map tab, open project details → the map sliver behind the sheet freezes (goes to background). Dismiss → map returns instantly, no style reload flash, puck visible again.
- [ ] The core symptom: with network on, scroll the details screen and switch tabs for 30 seconds → no stutter, matching airplane-mode feel.

---

## Self-review (completed at plan time)

- **Spec coverage:** background items 1→Task 1, 2→Task 2, 3→Task 3, 4→Task 4, 5→Task 5; verification→Task 6. Non-goals documented.
- **Placeholder scan:** none — every code step contains complete code; conditional instructions (pbxproj registration, explicit-init fallback in 3.4, related-model fallback in 2.6) specify the exact action for each branch.
- **Type consistency:** `ImageDownsampler.downsample(data:maxPixelSize:)`/`(image:maxPixelSize:)` used identically in Tasks 1 steps; `isExpenseCacheFresh`/`loadExpensesIfStale` names match between Task 2 code and test; `renderKey(projectCoordinate:userCoordinate:size:styleRaw:taskColorHexes:statusDescription:)` matches between Task 4 view code and test; `setRenderingPaused(_:)` matches between coordinator and container; notification names match between poster and observer.
