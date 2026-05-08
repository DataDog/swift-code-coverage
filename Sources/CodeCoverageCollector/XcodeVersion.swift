/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2024-Present Datadog, Inc.
 */

import Foundation

public enum XcodeVersion: Hashable, Equatable, Sendable {
    case xcode26
}

public extension XcodeVersion {
    static var compiledBy: XcodeVersion? {
    #if compiler(>=6.2)
        return .xcode26
    #else
        return nil
    #endif
    }
}

