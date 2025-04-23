//
//  ArrayTransformer.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


//
//  ArrayTransformer.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//

import Foundation

class ArrayTransformer: ValueTransformer {
    override class func transformedValueClass() -> AnyClass {
        return NSArray.self
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override func transformedValue(_ value: Any?) -> Any? {
        guard let array = value as? [String] else { return nil }
        return NSArray(array: array)
    }
    
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let nsArray = value as? NSArray else { return nil }
        return nsArray as? [String]
    }
}

// Extension to register the transformer
extension ArrayTransformer {
    static let name = NSValueTransformerName(rawValue: "ArrayTransformer")
    
    public static func register() {
        let transformer = ArrayTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}