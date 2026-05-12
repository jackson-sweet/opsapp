//
//  PnPSolver.swift
//  OPS
//
//  Direct Linear Transform (DLT) Perspective-n-Point solver for a planar
//  marker with exactly 4 corner correspondences. Pure Swift; no third-party
//  dependencies and no Accelerate / LAPACK calls — the 8×8 linear system is
//  solved by Gaussian elimination with partial pivoting.
//
//  Reference: Hartley & Zisserman, "Multiple View Geometry in Computer
//  Vision" (2nd ed.), Algorithm 7.1 (Normalized DLT for the Homography).
//
//  Convention: returned pose is the world-to-camera transform. The camera
//  frame is +X right, +Y down, +Z forward (standard pinhole). The marker's
//  z=0 plane is its surface; corner world coordinates are in marker-local
//  metres.
//

import Foundation
import simd

public enum PnPSolverError: Error, Equatable {
    case wrongCorrespondenceCount(Int)
    case mismatchedCounts(world: Int, image: Int)
    case degenerateConfiguration
    case singularSystem
}

public struct PnPSolver {

    /// Solve planar PnP for 4 corner correspondences.
    /// - Parameters:
    ///   - worldPoints: 4 corner positions of the marker in marker-local
    ///     coordinates (metres). The marker lies on the z=0 plane.
    ///   - imagePoints: 4 corresponding image points (photo-pixel coords).
    ///   - intrinsics: camera intrinsics.
    /// - Returns: world→camera 4×4 transform, or throws on degenerate input.
    public static func solvePlanarPose(
        worldPoints: [SIMD2<Double>],
        imagePoints: [SIMD2<Double>],
        intrinsics: DimensionsData.Intrinsics
    ) throws -> simd_double4x4 {
        guard worldPoints.count == 4 else {
            throw PnPSolverError.wrongCorrespondenceCount(worldPoints.count)
        }
        guard imagePoints.count == worldPoints.count else {
            throw PnPSolverError.mismatchedCounts(world: worldPoints.count,
                                                  image: imagePoints.count)
        }

        // Normalize image coords via K⁻¹ so the recovered homography is the
        // pose matrix [r1 r2 t] directly.
        let normalized = imagePoints.map { p -> SIMD2<Double> in
            SIMD2<Double>(
                (p.x - intrinsics.cx) / intrinsics.fx,
                (p.y - intrinsics.cy) / intrinsics.fy
            )
        }

        // Build the 8×9 DLT matrix, then fix h9 = 1 → 8×8 system A·h_partial = b.
        // Each correspondence i contributes 2 rows:
        //   row 2i:   [X, Y, 1, 0, 0, 0, -x*X, -x*Y,  -x]   ← drop col 9, b_i = x
        //   row 2i+1: [0, 0, 0, X, Y, 1, -y*X, -y*Y,  -y]   ← drop col 9, b_i = y
        var A = [[Double]](repeating: [Double](repeating: 0, count: 8), count: 8)
        var b = [Double](repeating: 0, count: 8)
        for i in 0..<4 {
            let X: Double = worldPoints[i].x
            let Y: Double = worldPoints[i].y
            let x: Double = normalized[i].x
            let y: Double = normalized[i].y

            var rowX = [Double](repeating: 0, count: 8)
            rowX[0] = X; rowX[1] = Y; rowX[2] = 1
            rowX[6] = -x * X; rowX[7] = -x * Y
            A[2*i] = rowX
            b[2*i] = x

            var rowY = [Double](repeating: 0, count: 8)
            rowY[3] = X; rowY[4] = Y; rowY[5] = 1
            rowY[6] = -y * X; rowY[7] = -y * Y
            A[2*i+1] = rowY
            b[2*i+1] = y
        }

        guard let h = try? gaussSolve(A: A, b: b) else {
            throw PnPSolverError.singularSystem
        }
        // h = [h1, h2, h3, h4, h5, h6, h7, h8], with h9 fixed at 1.
        // Homography H maps (X, Y, 1) world → (x, y, 1) normalized image.
        let r1 = SIMD3<Double>(h[0], h[3], h[6])
        let r2 = SIMD3<Double>(h[1], h[4], h[7])
        let tRaw = SIMD3<Double>(h[2], h[5], 1.0)

        // Recover scale λ = avg(|r1|, |r2|). Sign chosen so the marker is in
        // front of the camera (positive Z component in t).
        let n1 = simd_length(r1)
        let n2 = simd_length(r2)
        guard n1 > 1e-12, n2 > 1e-12 else {
            throw PnPSolverError.degenerateConfiguration
        }
        var lambda = 0.5 * (n1 + n2)
        var t = tRaw / lambda
        if t.z < 0 {
            lambda = -lambda
            t = tRaw / lambda
        }

        var r1n = r1 / lambda
        var r2n = r2 / lambda

        // Orthonormalize via Gram-Schmidt — small DLT noise tilts r1·r2 off zero.
        r1n = simd_normalize(r1n)
        r2n = r2n - simd_dot(r1n, r2n) * r1n
        r2n = simd_normalize(r2n)
        let r3n = simd_cross(r1n, r2n)

        // World-to-camera 4×4. simd_double4x4 is column-major; columns are
        // (r1, r2, r3, t) padded with the homogeneous row [0 0 0 1].
        let col0 = SIMD4<Double>(r1n.x, r1n.y, r1n.z, 0)
        let col1 = SIMD4<Double>(r2n.x, r2n.y, r2n.z, 0)
        let col2 = SIMD4<Double>(r3n.x, r3n.y, r3n.z, 0)
        let col3 = SIMD4<Double>(t.x,   t.y,   t.z,   1)
        return simd_double4x4(columns: (col0, col1, col2, col3))
    }

    /// Gaussian elimination with partial pivoting on a small square system.
    /// `A` is square `n×n`, `b` is length `n`. Returns the solution `x` such
    /// that A·x = b, or `nil` if the system is singular.
    @inline(__always)
    static func gaussSolve(A: [[Double]], b: [Double]) throws -> [Double] {
        let n = A.count
        precondition(b.count == n && A.allSatisfy { $0.count == n })
        // Build augmented matrix in-place.
        var M = [[Double]](repeating: [Double](repeating: 0, count: n + 1), count: n)
        for i in 0..<n {
            for j in 0..<n { M[i][j] = A[i][j] }
            M[i][n] = b[i]
        }

        // Forward elimination with partial pivoting.
        for col in 0..<n {
            // Find pivot row.
            var pivot = col
            var pivotMag = abs(M[col][col])
            for r in (col+1)..<n {
                let m = abs(M[r][col])
                if m > pivotMag {
                    pivotMag = m
                    pivot = r
                }
            }
            guard pivotMag > 1e-12 else {
                throw PnPSolverError.singularSystem
            }
            if pivot != col {
                M.swapAt(col, pivot)
            }
            // Eliminate below.
            for r in (col+1)..<n {
                let factor = M[r][col] / M[col][col]
                guard factor != 0 else { continue }
                for c in col...n {
                    M[r][c] -= factor * M[col][c]
                }
            }
        }

        // Back-substitution.
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var s = M[i][n]
            for j in (i+1)..<n {
                s -= M[i][j] * x[j]
            }
            x[i] = s / M[i][i]
        }
        return x
    }
}
