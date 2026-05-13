//
//  DepthMapLoader.swift
//  OPS
//
//  Loads the standalone FP32 LiDAR depth asset written by CaptureAssetWriter.
//

import Foundation

public enum DepthMapLoader {
    public static let lidarDepthWidth = 768

    public static func load(from url: URL?) -> DepthMap? {
        guard let url,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard data.count % MemoryLayout<Float>.size == 0 else {
            return nil
        }
        let count = data.count / MemoryLayout<Float>.size
        guard count > 0, count % lidarDepthWidth == 0 else {
            return nil
        }
        let height = count / lidarDepthWidth
        let values = data.withUnsafeBytes { raw -> [Float] in
            let pointer = raw.bindMemory(to: Float.self)
            return Array(pointer)
        }
        return DepthMap(width: lidarDepthWidth, height: height, values: values)
    }
}
