//  Types.swift
//  FileProviderExt
//
//  Created by Jan Lenczyk on 02.10.23.
//

struct FetchFolderContentsFile: Decodable, Sendable {
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

struct FetchFolderContentsFolder: Decodable, Sendable {
  var uuid: String
  var name: String
  var parent: String
  var color: String?
  var timestamp: Int
  var favorited: Int
  var is_sync: Int?
  var is_default: Int?
}

struct FetchFolderContents: Decodable, Sendable {
  var uploads: [FetchFolderContentsFile]
  var folders: [FetchFolderContentsFolder]
}

struct CreateFolder: Decodable {
  var uuid: String
}

struct APIError: Error {
  var code: String
  var message: String
}

enum ItemType {
  case file
  case folder
}

struct Item {
  var uuid: String
  var parent: String
  var name: String
  var type: ItemType
  var mime: String
  var size: Int
  var timestamp: Int
  var lastModified: Int
  var key: String
  var chunks: Int
  var region: String
  var bucket: String
  var version: Int
}

public struct ItemJSON: Codable, Sendable {
    public var uuid: String
    public var parent: String
    public var name: String
    public var type: String
    public var mime: String
    public var size: Int
    public var timestamp: Int
    public var lastModified: Int
    public var key: String
    public var chunks: Int
    public var region: String
    public var bucket: String
    public var version: Int
    
    public init(uuid: String, parent: String, name: String, type: String, mime: String, size: Int, timestamp: Int, lastModified: Int, key: String, chunks: Int, region: String, bucket: String, version: Int) {
        self.uuid = uuid
        self.parent = parent
        self.name = name
        self.type = type
        self.mime = mime
        self.size = size
        self.timestamp = timestamp
        self.lastModified = lastModified
        self.key = key
        self.chunks = chunks
        self.region = region
        self.bucket = bucket
        self.version = version
    }
}

struct UploadChunk: Decodable {
  var bucket: String
  var region: String
}

struct MarkUploadAsDone: Decodable {
  var chunks: Int
  var size: Int
}


struct IsSharingFolderDataUser: Decodable {
  var email: String
  var publicKey: String
}

struct IsSharingFolder: Decodable {
  var sharing: Bool
  var users: [IsSharingFolderDataUser]?
}

struct IsLinkingFolderLink: Decodable {
  var linkUUID: String
  var linkKey: String
}

struct IsLinkingFolder: Decodable {
  var link: Bool
  var links: [IsLinkingFolderLink]?
}

struct IsSharingItemDataUser: Decodable {
  var email: String
  var publicKey: String
  var id: Int
}

struct IsSharingItem: Decodable {
  var sharing: Bool
  var users: [IsSharingItemDataUser]?
}

struct IsLinkingItemLink: Decodable {
  var linkUUID: String
  var linkKey: String
}

struct IsLinkingItem: Decodable {
  var link: Bool
  var links: [IsLinkingItemLink]?
}

struct CheckIfItemParentIsSharedMetadata: Codable {
  var uuid: String
  var name: String?
  var size: Int?
  var mime: String?
  var key: String?
  var lastModified: Int?
  var hash: String?
}

struct GetFolderContentsDataFiles: Decodable {
  var uuid: String
  var bucket: String
  var region: String
  var name: String?
  var size: String?
  var mime: String?
  var chunks: Int
  var parent: String
  var metadata: String
  var version: Int
  var chunksSize: Int?
}

struct GetFolderContentsDataFolders: Decodable {
 var uuid: String
 var name: String
 var parent: String
}

struct GetFolderContents: Decodable {
  var files: [GetFolderContentsDataFiles]
  var folders: [GetFolderContentsDataFolders]
}

struct ItemToShareFolder: Codable {
  var uuid: String
  var parent: String
  var metadata: FolderMetadata
}

struct ItemToShareFile: Codable {
  var uuid: String
  var parent: String
  var metadata: FileMetadata
}

struct BaseAPIResponse: Decodable {
  var status: Bool
  var code: String
  var message: String
}

/*
 "uuid": uuid,
 "name": name,
 "nameHashed": nameHashed,
 "size": size,
 "chunks": chunks,
 "mime": mime,
 "rm": rm,
 "metadata": metadata,
 "version": version,
 "uploadKey": uploadKey
 
 func markUploadAsDone (uuid: String, name: String, nameHashed: String, size: String, chunks: Int, mime: String, rm: String, metadata: String, version: Int, uploadKey: String) async throws -> MarkUploadAsDone {

 */
struct MarkUploadAsDoneBody: Encodable {
    let uuid: String
    let name: String
    let nameHashed: String
    let size: String
    let chunks: Int
    let mime: String
    let rm: String
    let metadata: String
    let version: Int
    let uploadKey: String
}

/*
 renameSharedItem (uuid: String, receiverId: Int, metadata: String
 */
struct RenameSharedItemBody: Encodable {
    let uuid: String
    let receiverId: Int
    let metadata: String
}
