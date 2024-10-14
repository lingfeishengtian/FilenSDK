//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/14/24.
//

import Foundation

struct DirContentUpload: Codable {
    var uuid: String
    var metadata: String
    var rm: String
    var timestamp: Int
    var chunks: Int
    var size: Int
    var bucket: String
    var region: String
    var parent: String
    var version: Int
    var favorited: Int
}

struct DirContentFolder: Codable {
    var uuid: String
    var name: String
    var parent: String
    var color: String?
    var timestamp: Int
    var favorited: Int
    var is_sync: Int
    var is_default: Int
}

struct DirContentResponse: Codable {
    var uploads: [DirContentUpload]
    var folders: [DirContentFolder]
}
