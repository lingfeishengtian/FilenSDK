//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/16/24.
//

import Foundation

public struct FileGetResponse: Codable, Sendable {
    let uuid: String
    let region: String
    let bucket: String
    let nameEncrypted: String
    let nameHashed: String
    let sizeEncrypted: String
    let mimeEncrypted: String
    let metadata: String
    let size: Int
    let parent: String
    let versioned: Bool
    let trash: Bool
    let version: Int
}
