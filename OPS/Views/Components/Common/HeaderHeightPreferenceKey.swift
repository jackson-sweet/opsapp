//
//  HeaderHeightPreferenceKey.swift
//  OPS
//
//  Reports a measured header height up the view tree so peer overlays
//  (e.g. NavigationManeuverCard) can position themselves below the header
//  without relying on hardcoded magic numbers.
//

import SwiftUI

struct HeaderHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
