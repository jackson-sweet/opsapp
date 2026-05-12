# OPS Reference Marker — Geometry Spec

Companion to `ReferenceObjectCalibrator.swift`. The marker is the
contract-grade alternative to a credit card for sub-cm calibrated
measurements.

## Marker geometry

| Property | Value | Rationale |
|---|---|---|
| Width | **100 mm** | Round metric, easy to verify with any ruler |
| Height | **100 mm** | Square aspect (1.0) — distinguishes from credit card (1.586) in `VNDetectRectanglesRequest` |
| Border | **10 mm solid black** on white | High-contrast outline for rectangle detection in low light |
| Centre artwork | OPS `//` wordmark + 4 corner registration squares (8 mm each) | Wordmark identifies the marker visually; registration squares give Phase D sub-pixel corner refinement targets |
| Print medium | Matte cardstock or vinyl sticker | Matte avoids specular highlights that confuse Vision rectangle detection |

The marker is designed to live on a tradesperson's tool case / clipboard /
truck — a kit item, not a thing they have to remember to bring.

## Detection contract

```swift
ReferenceObjectCalibrator.calibrate(
    image: cgImage,
    intrinsics: intrinsics,
    marker: .opsMarker,
    hasLiDAR: hasLiDAR
)
```

Detection runs `VNDetectRectanglesRequest` with:

| Parameter | Value |
|---|---|
| `minimumAspectRatio` | 0.95 |
| `maximumAspectRatio` | 1.05 |
| `minimumSize` | 0.05 (5 % of frame) |
| `minimumConfidence` | 0.6 |
| `maximumObservations` | 8 |

The highest-confidence rectangle is taken; if its aspect ratio falls outside
the band the call throws `rectangleAspectOutOfBounds` rather than producing
a wrong-sized calibration.

## Compared with credit card

| Property | Credit card (CR-80) | OPS marker |
|---|---|---|
| Width × height | 85.60 × 53.98 mm | 100 × 100 mm |
| Aspect | 1.586 | 1.000 |
| Vision band | 1.55 – 1.62 | 0.95 – 1.05 |
| Availability | Universal (every wallet) | Requires OPS to ship one |
| Trade context | "Stick a card on the wall" | "Stick the OPS marker on the wall" |
| Edge contrast | Variable (card design, lighting) | Engineered for high contrast |

## Status

Geometry locked here. Physical artwork (the `//` wordmark + registration
squares + print template) is owned by the design system at
`ops-design-system/project/assets/measurement-marker/` and is to be designed
before the feature flips ON in production.

## Honest limitation

On non-LiDAR devices, calibration using either marker produces a result with
`coplanarOnly = true`. Measurements taken outside the marker's plane are not
accurate. The UI (Phase E) surfaces this as the `COPLANAR ONLY` chip beside
the accuracy badge. See spec §3.8.
