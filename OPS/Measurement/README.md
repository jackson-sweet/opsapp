# Measurement — LiDAR Dimensioned Photo Capture

Phase B of the LiDAR Dimensioned Photo Capture initiative. Owns the on-device
capture pipeline: ARKit live-aim → AVFoundation `builtInLiDARDepthCamera`
shutter handoff → HEIC + standalone depth + sidecar JSON persistence.

**Spec:** `ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md`
**Plan:** `ops-software-bible/specs/plans/2026-05-10-lidar-dimensioned-photo-capture-plan.md`

This directory contains the coordinator + capability detection + persistence
only. The capture UI (`DimensionedCaptureView`) and annotation UI
(`DimensionedAnnotationView`) live in `OPS/Views/Measurement/` (Phase D/E).
The measurement engine (`DepthRaycaster`, `PnPSolver`, `OpeningClassifier`,
`ReferenceObjectCalibrator`) is Phase C.

## Public API

### `LiDARCaptureCoordinator`

`@MainActor`, `ObservableObject`. The view layer instantiates one per capture
session, binds the SwiftUI preview to its AR session, and calls `startLiveAim()`
on appear and `capture()` on shutter tap.

```swift
let coordinator = LiDARCaptureCoordinator()
coordinator.startLiveAim()   // configures + warms AR + AVCapture
// ... user aims at opening ...
await coordinator.capture()  // resolves to .captured(CapturedAssets) or .failed(_)
```

#### Published state

```swift
@Published var state: CaptureState
```

```
.idle                       coordinator constructed, no AR session yet
.warmingUp                  startLiveAim() called; AR session initializing (~800 ms)
.ready                      AR tracking achieved
.searching                  Plane detection running
.wallDetected               Vertical plane detected — capture allowed
.openingLocked              Phase C: classifier promoted to a rectangular opening
.capturing                  Shutter pressed; ARKit→AVCapture handoff in progress
.captured(CapturedAssets)   Three assets on disk; payload carries URLs + intrinsics
.failed(CaptureError)       Pipeline aborted; see error case
```

#### `CaptureError`

```
.capabilityInsufficient     Device returns .noDepth from CaptureCapability.detect()
.cameraPermissionDenied     NSCameraUsageDescription path
.arSessionFailed(reason)    ARSession delegate reported failure
.avCaptureFailed(reason)    AVCapturePhotoOutput delegate reported failure
.persistenceFailed(reason)  HEIC / depth / sidecar write failure
.noActiveSession            capture() called without prior startLiveAim()
```

#### Capability detection

```swift
public enum CaptureCapability { case lidar, visual, noDepth }

struct CaptureCapabilityReport {
    let capability: CaptureCapability
    let supportsAutoDetect: Bool   // true only when mesh-with-classification is supported
}

CaptureCapability.detect()                              // live (production)
CaptureCapability.detect(lidarSupported:                // injectable (tests)
                        arSupported:
                        meshSupported:)
```

Capability mapping per spec §3.8:

| `lidarSupported` | `arSupported` | `meshSupported` | capability | supportsAutoDetect |
|---|---|---|---|---|
| true  | true  | true  | `.lidar`   | true  |
| true  | true  | false | `.lidar`   | false |
| false | true  | —     | `.visual`  | false |
| —     | false | —     | `.noDepth` | false |

## On-disk asset format

Three files per capture, stored under `<Documents>/lidar-captures/<uuid>.*`:

### `<uuid>.heic`

HEIC photo with embedded `kCGImageAuxiliaryDataTypeDisparity` aux channel. The
primary asset — uploads to `project_photos.url` with `source = 'measurement'`.
The embedded aux channel stays disparity for HEIC compatibility; the separate
standalone asset is FP32 depth in meters for high-precision re-rendering.

### `<uuid>.depth.fp32`

Standalone raw FP32 depth grid in meters, tightly packed (no row padding).
Exact size: 768 × 576 × 4 bytes = ~1.7 MB. Per spec §7, this file is
lifecycled out after 90 days; HEIC + sidecar are kept indefinitely.

Read with:

```swift
let data = try Data(contentsOf: url)
let pointer = data.withUnsafeBytes { $0.bindMemory(to: Float.self) }
let width = 768
let height = 576
```

### `<uuid>.metadata.json`

Sidecar containing the ARKit state snapshot at shutter. Snake-case keys to
match the Postgres `dimensions` jsonb conventions. Shape:

```json
{
  "mesh_anchors": [
    {
      "identifier": "uuid",
      "transform": [16 floats — 4×4 column-major world transform],
      "vertex_count": 1024,
      "face_count": 2048,
      "classifications": { "wall": 800, "window": 200 }
    }
  ],
  "camera_intrinsics": {
    "fx": 1593.4, "fy": 1593.4, "cx": 1015.5, "cy": 762.0,
    "image_width": 4032, "image_height": 3024
  },
  "device_pose": [16 floats],
  "timestamp": "2026-05-11T16:08:00Z"
}
```

`mesh_anchors[].classifications` is a histogram of `ARMeshClassification` vertex
counts. Phase C's `OpeningClassifier` reads this without re-parsing the mesh
geometry; vertex counts are sufficient to gate "this anchor is mostly wall and
contains some window vertices" heuristics.

## Capture pipeline (spec §3.2)

```
startLiveAim()
  └── ARWorldTrackingConfiguration
        .planeDetection = [.horizontal, .vertical]
        .frameSemantics = .smoothedSceneDepth (fallback: .sceneDepth)
        .sceneReconstruction = .meshWithClassification (if supported)
  └── AVCaptureSession (pre-configured, NOT started)
        builtInLiDARDepthCamera input
        AVCapturePhotoOutput (depthDataDelivery on, embedsDepthInPhoto on)
        activeDepthDataFormat = exact 768×576 DepthFloat32
        AVCaptureDepthDataOutput attached only to advertise LiDAR depth support

capture()
  1. Full ARFrame snapshot — anchors, mesh faces, intrinsics, pose
  2. arSession.pause()
  3. avSession.startRunning()
  4. photoOutput.capturePhoto(...) → AVCapturePhoto.depthData
  5. CaptureAssetWriter.write(...) → HEIC + depth + JSON on disk
  6. avSession.stopRunning()
  7. transition(.captured(assets))
```

Target shutter latency (steps 2 + 3 + 4): **< 250 ms**.
Total cold-start to first capture: **< 1.05 s** (≈ 800 ms warm-up + 250 ms shutter).

## Testing

**Host-runnable (CI + simulator):**

- `CapabilityDetectionTests` — pure capability truth table (5 cases) +
  live `detect()` returns one of the three documented states.
- `CapturedAssetsTests` — URL conventions, sidecar Codable round-trip,
  snake-case key encoding, transform-array length invariants.
- `LiDARCaptureCoordinatorTests` — state machine transitions, capability
  surfacing, `startLiveAim()` idempotency, `capture()` failure surfacing,
  `.captured(_)` payload equality, `reset()` behavior.
- `CaptureAssetWriterTests` — sidecar write + read round-trip from disk,
  atomic overwrite semantics.

**Hardware-required (manual, real iPhone with LiDAR):**

- HEIC + embedded disparity round-trip
- FP32 raw depth-in-meters file shape (768 × 576 × 4)
- Shutter latency profiling — target <250 ms (steps 2-4) and <750 ms end-to-end
  (acceptance gate, spec §10.2)
- Memory ceiling during capture — target <250 MB resident
- Cold-start AR session warm-up — target ~800 ms typical

Hardware tests are mechanically the same as the host tests but exercise the
real `AVCaptureDevice.builtInLiDARDepthCamera`. They should be added under
`OPSTests/Measurement/Hardware/` once a CI runner with LiDAR exists (or run
manually on dev devices). The current Phase B PR does not include them; they
will land alongside the Phase D capture view so the full path can be exercised
end-to-end on real hardware.

## Out of scope (Phase B)

- Capture UI / annotation UI (Phase D, E)
- Measurement math (`DepthRaycaster`, `PnPSolver`) (Phase C)
- Vision-based opening classification (Phase C)
- Reference-object calibration (Phase C)
- Upload manager (Phase F)
- Bible updates for the implemented surface (Phase I)
