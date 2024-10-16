//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/14/24.
//

import Foundation

public struct DirContentUpload: Codable, Sendable {
    public var uuid: String
    public var metadata: String
    public var rm: String
    public var timestamp: Int
    public var chunks: Int
    public var size: Int
    public var bucket: String
    public var region: String
    public var parent: String
    public var version: Int
    public var favorited: Int
}

public struct DirContentFolder: Codable, Sendable {
    public var uuid: String
    public var name: String
    public var parent: String
    public var color: String?
    public var timestamp: Int
    public var favorited: Int
    public var is_sync: Int
    public var is_default: Int
}

public struct DirContentResponse: Codable, Sendable {
    public var uploads: [DirContentUpload]
    public var folders: [DirContentFolder]
}
