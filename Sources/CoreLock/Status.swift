//
//  Status.swift
//  Lock
//
//  Created by Alsey Coleman Miller on 4/16/16.
//  Copyright © 2016 ColemanCDA. All rights reserved.
//

import SwiftFoundation

/// Lock status
public enum Status: UInt8 {
    
    /// Initial Status
    case Setup
    
    /// Idle / Unlock Mode status
    case Unlock
    
    /// New Key being added to database status
    case NewKey
    
    /// Lock software updating
    case Update
}

extension Status: DataConvertible {
    
    public init?(data: Data) {
        
        guard data.byteValue.count == 1
            else { return nil }
        
        self.init(rawValue: data.byteValue[0])
    }
    
    public func toData() -> Data {
        
        return Data(byteValue: [rawValue])
    }
}