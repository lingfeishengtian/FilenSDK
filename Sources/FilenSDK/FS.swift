//
//  FS.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/13/24.
//

import Foundation
import Alamofire
import UniformTypeIdentifiers

extension FilenClient: @unchecked Sendable
{
    public func createFolder (name: String, parent: String) async throws -> String {
        guard let masterKeys = self.masterKeys() else {
            throw FilenError.masterKeyMissing
        }
        
        let encryptedName = try FilenCrypto.shared.encryptFolderName(name: FolderMetadata(name: name), masterKeys: masterKeys)
        let nameHashed = try FilenCrypto.shared.hashFn(message: name.lowercased())
        
        let uuid = UUID().uuidString.lowercased()
        
        let response: CreateFolder = try await self.apiRequest(
            endpoint: "/v3/dir/create",
            method: .post,
            body: [
                "uuid": uuid,
                "name": encryptedName,
                "nameHashed": nameHashed,
                "parent": parent
            ]
        )
        
        try await checkIfItemParentIsShared(
            type: "folder",
            parent: parent,
            itemMetadata: CheckIfItemParentIsSharedMetadata(
                uuid: uuid,
                name: name
            )
        )
        
        return response.uuid
    }
    
    func uploadChunk (url: URL, fileURL: URL, checksum: String) async throws -> (region: String, bucket: String) {
        guard let apiKey = config?.apiKey else {
            throw FilenError.apiKeyMissing
        }
        
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Accept": "application/json",
            "Checksum": checksum
        ]
        
        let r = sessionManager.upload(fileURL, to: url, headers: headers){ $0.timeoutInterval = 3600 }.validate()
        guard let response = try await r.serializingDecodable(FilenResponse<UploadChunk>.self).value.data else {
            throw FilenError.failedSerialization
        }
        
        return (region: response.region, bucket: response.bucket)
    }
    
    
    func encryptAndUploadChunk (url: String, chunkSize: Int, uuid: String, index: Int, uploadKey: String, parent: String, key: String) async throws -> (region: String, bucket: String) {
        let fileURL = self.getTempPath().appendingPathComponent(UUID().uuidString.lowercased() + "." + uuid + "." + String(index), isDirectory: false)
        
        guard let inputURL = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url) else {
            throw NSError(domain: "encryptAndUploadChunk", code: 1, userInfo: nil)
        }
        
        let dateNow = Date()
        let (_, checksum: chunkChecksum) = try FilenCrypto.shared.streamEncryptData(input: inputURL, output: fileURL, key: key, version: 2, index: index)
        
        // We need to serialize it to JSON this way to ensure correct ordering of parameters
        let queryItemsJSONString = #"{"uuid":"\#(uuid.lowercased())","index":"\#(index)","uploadKey":"\#(uploadKey)","parent":"\#(parent.lowercased())","hash":"\#(chunkChecksum.lowercased())"}"#
        
        let queryItemsChecksum = try FilenCrypto.shared.hash(message: queryItemsJSONString, hash: .sha512)
        
        guard let urlWithComponents = URL(string: "\(igestUrls.randomElement()!)/v3/upload?uuid=\(uuid.lowercased())&index=\(index)&uploadKey=\(uploadKey)&parent=\(parent.lowercased())&hash=\(chunkChecksum)") else {
            throw NSError(domain: "encryptAndUploadChunk", code: 2, userInfo: nil)
        }
        
        //        try await self.transferSemaphore.acquire()
        print("Uploading chunk \(index) for \(uuid)")
        let result = try await self.uploadChunk(url: urlWithComponents, fileURL: fileURL, checksum: queryItemsChecksum)
        print("Took \(Date().timeIntervalSince(dateNow)) to encrypt and upload")
        //        transferSemaphore.release()
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(atPath: fileURL.path)
        }
        
        return result
    }
    
    //TODO: Better way of identifying
    private func fileExtension(from name: String) -> String? {
        autoreleasepool {
            let components = name.components(separatedBy: ".")
            
            guard components.count > 1 else {
                return nil
            }
            
            return components.last
        }
    }
    
    public func uploadFile (url: String, parent: String, with name: String? = nil, progress: Progress = Progress()) async throws -> ItemJSON {
        if (!FileManager.default.fileExists(atPath: url)) {
            throw FilenError.noSuchFile
        }
        
        guard let masterKeys = self.masterKeys(), let lastMasterKey = masterKeys.last else {
            throw FilenError.unauthorized
        }
        
        try await self.uploadSemaphore.acquire()
        
        defer {
            self.uploadSemaphore.release()
        }
        
        let stat = try FileManager.default.attributesOfItem(atPath: url)
        
        guard let fileSize = stat[.size] as? Int, let fileURL = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url), let lastModified = stat[.modificationDate] as? Date else {
            throw FilenError.noSuchFile
        }
        
        let key = try FilenCrypto.shared.generateRandomString(length: 32)
        let lastModifiedInt = Int(lastModified.timeIntervalSince1970 * 1000)
        
        if (fileSize <= 0) { // We do not support 0 Byte files yet
            throw FilenError.zeroByteFile
        }
        
        let uuid = UUID().uuidString.lowercased()
        let fileName = name ?? fileURL.lastPathComponent
        var dummyOffset = 0
        var fileChunks = 0
        let chunkSizeToUse = 1024 * 1024
        let ext = self.fileExtension(from: fileName) ?? ""
        let mimeType = UTType(filenameExtension: ext)?.preferredMIMEType ?? ""
        
        while (dummyOffset < fileSize) {
            fileChunks += 1
            dummyOffset += chunkSizeToUse
        }
        
        let metadataJSON = try self.jsonEncoder.encode(
            FileMetadata(
                name: fileName,
                size: fileSize,
                mime: mimeType,
                key: key,
                lastModified: lastModifiedInt
            )
        )
        
        guard let metadataJSONString = String(data: metadataJSON, encoding: .utf8) else {
            throw FilenError.noSuchFile
        }
        
        let rm = try FilenCrypto.shared.generateRandomString(length: 32)
        let uploadKey = try FilenCrypto.shared.generateRandomString(length: 32)
        let nameEnc = try FilenCrypto.shared.encryptMetadata(metadata: fileName, key: key)
        let mimeEnc = try FilenCrypto.shared.encryptMetadata(metadata: mimeType, key: key)
        let nameHashed = try FilenCrypto.shared.hashFn(message: fileName.lowercased())
        let sizeEnc = try FilenCrypto.shared.encryptMetadata(metadata: String(fileSize), key: key)
        let metadata = try FilenCrypto.shared.encryptMetadata(metadata: metadataJSONString, key: lastMasterKey)
        
        let uploadFileResult = UploadFileResult()
        
        let maxUploadTasks = 50
        
        progress.totalUnitCount = Int64(fileChunks)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<fileChunks {
                if index >= maxUploadTasks {
                    try await group.next()
                }
                
                group.addTask { @Sendable in
                    let result = try await self.encryptAndUploadChunk(url: url, chunkSize: chunkSizeToUse, uuid: uuid, index: index, uploadKey: uploadKey, parent: parent, key: key)
                    
                    if (result.bucket.count > 0 && result.region.count > 0) {
                        await uploadFileResult.set(bucket: result.bucket, region: result.region)
                    }
                    
                    progress.completedUnitCount += 1
                }
            }
            
            for try await _ in group {}
        }
        
        let bucket = await uploadFileResult.bucket
        let region = await uploadFileResult.region
        
        let done = try await self.markUploadAsDone(
            uuid: uuid,
            name: nameEnc,
            nameHashed: nameHashed,
            size: sizeEnc,
            chunks: fileChunks,
            mime: mimeEnc,
            rm: rm,
            metadata: metadata,
            version: 2,
            uploadKey: uploadKey
        )
        
        try await checkIfItemParentIsShared(
            type: "file",
            parent: parent,
            itemMetadata: CheckIfItemParentIsSharedMetadata(
                uuid: uuid,
                name: fileName,
                size: fileSize,
                mime: mimeType,
                key: key,
                lastModified: lastModifiedInt
            )
        )
        
        return ItemJSON(
            uuid: uuid,
            parent: parent,
            name: fileName,
            type: "file",
            mime: mimeType,
            size: fileSize,
            timestamp: Int(Date().timeIntervalSince1970),
            lastModified: lastModifiedInt,
            key: key,
            chunks: done.chunks,
            region: region,
            bucket: bucket,
            version: 2
        )
    }
    
    func markUploadAsDone (uuid: String, name: String, nameHashed: String, size: String, chunks: Int, mime: String, rm: String, metadata: String, version: Int, uploadKey: String) async throws -> MarkUploadAsDone {
        let response: MarkUploadAsDone = try await self.apiRequest(
            endpoint: "/v3/upload/done",
            method: .post,
            //        body: [
            //          "uuid": uuid,
            //          "name": name,
            //          "nameHashed": nameHashed,
            //          "size": size,
            //          "chunks": chunks,
            //          "mime": mime,
            //          "rm": rm,
            //          "metadata": metadata,
            //          "version": version,
            //          "uploadKey": uploadKey
            //        ]
            body: MarkUploadAsDoneBody(uuid: uuid, name: name, nameHashed: nameHashed, size: size, chunks: chunks, mime: mime, rm: rm, metadata: metadata, version: version, uploadKey: uploadKey)
        )
        
        
        
        return response
    }
    
    func isSharingFolder (uuid: String) async throws -> IsSharingFolder {
        let response: IsSharingFolder = try await self.apiRequest(
            endpoint: "/v3/dir/shared",
            method: .post,
            body: [
                "uuid": uuid
            ]
        )
        
        return response
    }
    
    func isLinkingFolder (uuid: String) async throws -> IsLinkingFolder {
        let response: IsLinkingFolder = try await self.apiRequest(
            endpoint: "/v3/dir/linked",
            method: .post,
            body: [
                "uuid": uuid
            ]
        )
        
        return response
    }
    
    func shareItem (uuid: String, parent: String, email: String, type: String, metadata: String) async throws -> Void {
        let response: BaseAPIResponse = try await self.apiRequestBaseAPI(
            endpoint: "/v3/item/share",
            method: .post,
            body: [
                "uuid": uuid,
                "parent": parent,
                "email": email,
                "type": type,
                "metadata": metadata
            ]
        )
    }
    
    func addItemToPublicLink (uuid: String, parent: String, linkUUID: String, type: String, metadata: String, key: String, expiration: String) async throws -> Void {
        let response: BaseAPIResponse = try await self.apiRequestBaseAPI(
            endpoint: "/v3/dir/link/add",
            method: .post,
            body: [
                "uuid": uuid,
                "parent": parent,
                "linkUUID": linkUUID,
                "type": type,
                "metadata": metadata,
                "key": key,
                "expiration": expiration
            ]
        )
        
        
    }
    
    func renameSharedItem (uuid: String, receiverId: Int, metadata: String) async throws -> Void {
        let response: BaseAPIResponse = try await self.apiRequestBaseAPI(
            endpoint: "/v3/item/shared/rename",
            method: .post,
            body: RenameSharedItemBody(uuid: uuid, receiverId: receiverId, metadata: metadata)
        )
    }
    
    func renameItemInPublicLink (uuid: String, linkUUID: String, metadata: String) async throws -> Void {
        let response: BaseAPIResponse = try await self.apiRequestBaseAPI(
            endpoint: "/v3/item/linked/rename",
            method: .post,
            body: [
                "uuid": uuid,
                "linkUUID": linkUUID,
                "metadata": metadata
            ]
        )
        
        
    }
    
    func isSharingItem (uuid: String) async throws -> IsSharingItem {
        let response: IsSharingItem = try await self.apiRequest(
            endpoint: "/v3/item/shared",
            method: .post,
            body: [
                "uuid": uuid
            ]
        )
        
        return response
    }
    
    func isLinkingItem (uuid: String) async throws -> IsLinkingItem {
        let response: IsLinkingItem = try await self.apiRequest(
            endpoint: "/v3/item/linked",
            method: .post,
            body: [
                "uuid": uuid
            ]
        )
        
        return response
    }
    
    func getFolderContents (uuid: String, type: String = "normal", linkUUID: String?, linkHasPassword: Bool?, linkPassword: String?, linkSalt: String?) async throws -> GetFolderContents {
        let response: GetFolderContents = try await self.apiRequest(
            endpoint: type == "shared" ? "/v3/dir/download/shared" : type == "linked" ? "/v3/dir/download/link" : "/v3/dir/download",
            method: .post,
            body: type == "shared" ? [
                "uuid": uuid
            ] : type == "linked" ? [
                "uuid": linkUUID!,
                "parent": uuid,
                "password": linkHasPassword! && linkSalt != nil && linkPassword != nil ? linkSalt!.count == 32 ? FilenCrypto.shared.deriveKeyFromPassword(password: linkPassword!, salt: linkSalt!, bitLength: 512, hash: .sha512, rounds: 200000) : FilenCrypto.shared.hashFn(message: linkPassword!.count == 0 ? "empty": linkPassword!) : FilenCrypto.shared.hashFn(message: "empty")
            ] : [
                "uuid": uuid
            ]
        )
        
        return response
    }
    
    func checkIfItemIsSharedForRename (uuid: String, type: String, itemMetadata: CheckIfItemParentIsSharedMetadata) async throws -> Void {
        guard let masterKeys = self.masterKeys() else {
            throw FilenError.notLoggedIn
        }
        
        let isSharingItem = try await self.isSharingItem(uuid: uuid)
        let isLinkingItem = try await self.isLinkingItem(uuid: uuid)
        
        if !isSharingItem.sharing && !isLinkingItem.link {
            return
        }
        
        if let metadata = type == "folder" ? String(data: try self.jsonEncoder.encode(FolderMetadata(name: itemMetadata.name!)), encoding: .utf8) : String(data: try self.jsonEncoder.encode(FileMetadata(name: itemMetadata.name!, size: itemMetadata.size!, mime: itemMetadata.mime!, key: itemMetadata.key!, lastModified: itemMetadata.lastModified!)), encoding: .utf8) {
            if isSharingItem.sharing {
                for user in isSharingItem.users! {
                    if let encryptedMetadata = FilenCrypto.shared.encryptMetadataPublicKey(metadata: metadata, publicKey: user.publicKey) {
                        try await self.renameSharedItem(
                            uuid: uuid,
                            receiverId: user.id,
                            metadata: encryptedMetadata
                        )
                    }
                }
            }
            
            if isLinkingItem.link {
                for link in isLinkingItem.links! {
                    if let key = try FilenCrypto.shared.decryptFolderLinkKey(metadata: link.linkKey, masterKeys: masterKeys) {
                        let encryptedMetadata = try FilenCrypto.shared.encryptMetadata(metadata: metadata, key: key)
                        
                        try await self.renameItemInPublicLink(
                            uuid: uuid,
                            linkUUID: link.linkUUID,
                            metadata: encryptedMetadata
                        )
                    }
                }
            }
        }
    }
    
    func checkIfItemParentIsShared (type: String, parent: String, itemMetadata: CheckIfItemParentIsSharedMetadata) async throws -> Void {
        guard let masterKeys = self.masterKeys() else {
            throw FilenError.notLoggedIn
        }
        
        let isSharingParent = try await self.isSharingFolder(uuid: parent)
        let isLinkingParent = try await self.isLinkingFolder(uuid: parent)
        
        if !isSharingParent.sharing && !isLinkingParent.link {
            return
        }
        
        if isSharingParent.sharing {
            var filesToShare: [ItemToShareFile] = []
            var foldersToShare: [ItemToShareFolder] = []
            
            if type == "file" {
                filesToShare.append(
                    ItemToShareFile(
                        uuid: itemMetadata.uuid,
                        parent: parent,
                        metadata: FileMetadata(
                            name: itemMetadata.name!,
                            size: itemMetadata.size!,
                            mime: itemMetadata.mime!,
                            key: itemMetadata.key!,
                            lastModified: itemMetadata.lastModified!
                        )
                    )
                )
            } else {
                foldersToShare.append(
                    ItemToShareFolder(
                        uuid: itemMetadata.uuid,
                        parent: parent,
                        metadata: FolderMetadata(name: itemMetadata.name!)
                    )
                )
                
                let contents = try await self.getFolderContents(uuid: itemMetadata.uuid, type: "normal", linkUUID: nil, linkHasPassword: nil, linkPassword: nil, linkSalt: nil)
                
                for file in contents.files {
                    if let decryptedMetadata = FilenCrypto.shared.decryptFileMetadata(metadata: file.metadata, masterKeys: masterKeys) {
                        filesToShare.append(
                            ItemToShareFile(
                                uuid: file.uuid,
                                parent: file.parent,
                                metadata: decryptedMetadata
                            )
                        )
                    }
                }
                
                for i in 0..<contents.folders.count {
                    let folder = contents.folders[i]
                    
                    if folder.uuid != itemMetadata.uuid && folder.parent != "base" {
                        if let decryptedName = FilenCrypto.shared.decryptFolderName(metadata: folder.name, masterKeys: masterKeys) {
                            foldersToShare.append(
                                ItemToShareFolder(
                                    uuid: folder.uuid,
                                    parent: i == 0 ? "none" : folder.parent,
                                    metadata: FolderMetadata(name: decryptedName)
                                )
                            )
                        }
                    }
                }
            }
            
            for file in filesToShare {
                if let metadata = String(data: try self.jsonEncoder.encode(file.metadata), encoding: .utf8) {
                    for user in isSharingParent.users! {
                        if let publicKeyEncryptedMetadata = FilenCrypto.shared.encryptMetadataPublicKey(metadata: metadata, publicKey: user.publicKey) {
                            try await self.shareItem(
                                uuid: file.uuid,
                                parent: file.parent,
                                email: user.email,
                                type: "file",
                                metadata: publicKeyEncryptedMetadata
                            )
                        }
                    }
                }
            }
            
            for folder in foldersToShare {
                if let metadata = String(data: try self.jsonEncoder.encode(folder.metadata), encoding: .utf8) {
                    for user in isSharingParent.users! {
                        if let publicKeyEncryptedMetadata = FilenCrypto.shared.encryptMetadataPublicKey(metadata: metadata, publicKey: user.publicKey) {
                            try await self.shareItem(
                                uuid: folder.uuid,
                                parent: folder.parent,
                                email: user.email,
                                type: "folder",
                                metadata: publicKeyEncryptedMetadata
                            )
                        }
                    }
                }
            }
        }
        
        if isLinkingParent.link {
            var filesToShare: [ItemToShareFile] = []
            var foldersToShare: [ItemToShareFolder] = []
            
            if type == "file" {
                filesToShare.append(
                    ItemToShareFile(
                        uuid: itemMetadata.uuid,
                        parent: parent,
                        metadata: FileMetadata(
                            name: itemMetadata.name!,
                            size: itemMetadata.size!,
                            mime: itemMetadata.mime!,
                            key: itemMetadata.key!,
                            lastModified: itemMetadata.lastModified!
                        )
                    )
                )
            } else {
                foldersToShare.append(
                    ItemToShareFolder(
                        uuid: itemMetadata.uuid,
                        parent: parent,
                        metadata: FolderMetadata(name: itemMetadata.name!)
                    )
                )
                
                let contents = try await self.getFolderContents(uuid: itemMetadata.uuid, type: "normal", linkUUID: nil, linkHasPassword: nil, linkPassword: nil, linkSalt: nil)
                
                for file in contents.files {
                    if let decryptedMetadata = FilenCrypto.shared.decryptFileMetadata(metadata: file.metadata, masterKeys: masterKeys) {
                        filesToShare.append(
                            ItemToShareFile(
                                uuid: file.uuid,
                                parent: file.parent,
                                metadata: decryptedMetadata
                            )
                        )
                    }
                }
                
                for i in 0..<contents.folders.count {
                    let folder = contents.folders[i]
                    
                    if let decryptedName = FilenCrypto.shared.decryptFolderName(metadata: folder.name, masterKeys: masterKeys) {
                        if folder.uuid != itemMetadata.uuid && folder.parent != "base" {
                            foldersToShare.append(
                                ItemToShareFolder(
                                    uuid: folder.uuid,
                                    parent: i == 0 ? "none" : folder.parent,
                                    metadata: FolderMetadata(name: decryptedName)
                                )
                            )
                        }
                    }
                }
            }
            
            for file in filesToShare {
                if let metadata = String(data: try self.jsonEncoder.encode(file.metadata), encoding: .utf8) {
                    for link in isLinkingParent.links! {
                        if let key = try FilenCrypto.shared.decryptFolderLinkKey(metadata: link.linkKey, masterKeys: masterKeys) {
                            let encryptedMetadata = try FilenCrypto.shared.encryptMetadata(metadata: metadata, key: key)
                            
                            try await self.addItemToPublicLink(
                                uuid: file.uuid,
                                parent: file.parent,
                                linkUUID: link.linkUUID,
                                type: "file",
                                metadata: encryptedMetadata,
                                key: link.linkKey,
                                expiration: "never"
                            )
                        }
                    }
                }
            }
            
            for folder in foldersToShare {
                if let metadata = String(data: try self.jsonEncoder.encode(folder.metadata), encoding: .utf8) {
                    for link in isLinkingParent.links! {
                        if let key = try FilenCrypto.shared.decryptFolderLinkKey(metadata: link.linkKey, masterKeys: masterKeys) {
                            let encryptedMetadata = try FilenCrypto.shared.encryptMetadata(metadata: metadata, key: key)
                            
                            try await self.addItemToPublicLink(
                                uuid: folder.uuid,
                                parent: folder.parent,
                                linkUUID: link.linkUUID,
                                type: "folder",
                                metadata: encryptedMetadata,
                                key: link.linkKey,
                                expiration: "never"
                            )
                        }
                    }
                }
            }
        }
    }
    
    func downloadChunk (uuid: String, region: String, bucket: String, index: Int, key: String, version: Int) async throws -> (downloadedFileURL: URL, shouldTempFileURL: URL) {
        guard let downloadURL = URL(string: "\(egestUrls.randomElement()!)/\(region)/\(bucket)/\(uuid)/\(index)") else {
            throw FilenError.serverUnreachable
        }
        
        let tempFileURL = self.getTempPath().appendingPathComponent(UUID().uuidString.lowercased() + "." + uuid + "." + String(index), isDirectory: false)
        let downloadedFileURL = try await sessionManager.download(downloadURL){ $0.timeoutInterval = 3600 }.validate().serializingDownloadedFileURL().value
        
        return (downloadedFileURL: downloadedFileURL, shouldTempFileURL: tempFileURL)
    }
    
    public func downloadFile(fileGetResponse: FileGetResponse, url: String) async throws -> (didDownload: Bool, url: String) {
        let fileInfo = DirContentUpload(uuid: fileGetResponse.uuid, metadata: fileGetResponse.metadata, rm: "file", timestamp: 0, chunks: Int(ceil(Double(fileGetResponse.size) / 1024.0 / 1024.0)), size: fileGetResponse.size, bucket: fileGetResponse.bucket, region: fileGetResponse.region, parent: fileGetResponse.parent, version: fileGetResponse.version, favorited: 0)
        return try await downloadFile(fileInfo: fileInfo, url: url)
    }
    
    public func downloadFile (fileInfo: DirContentUpload, url: String) async throws -> (didDownload: Bool, url: String) {
        guard let masterkeys = masterKeys() else {
            throw FilenError.masterKeyMissing
        }
        
        guard let metadata = FilenCrypto.shared.decryptFileMetadata(metadata: fileInfo.metadata, masterKeys: masterkeys) else {
            throw FilenError.noSuchFile
        }
        
        let itemJSON = ItemJSON(uuid: fileInfo.uuid, parent: fileInfo.parent, name: metadata.name, type: "file", mime: metadata.mime ?? "", size: metadata.size ?? 0, timestamp: fileInfo.timestamp, lastModified: metadata.lastModified ?? 0, key: metadata.key, chunks: fileInfo.chunks, region: fileInfo.region, bucket: fileInfo.bucket, version: fileInfo.version)
        
        return try await downloadFile(itemJSON: itemJSON, url: url)
    }
    
    public func downloadFile(itemJSON: ItemJSON, url: String, maxChunks: Int? = nil, progress: Progress = Progress()) async throws -> (didDownload: Bool, url: String) {
        let maxChunks = maxChunks ?? itemJSON.chunks
        if (maxChunks <= 0) {
            return (didDownload: false, url: "")
        }
        
        guard let destinationURL = URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url) else {
            throw FilenError.noSuchFile
        }
        let destinationBaseURL = destinationURL.deletingLastPathComponent()
        
        print(destinationBaseURL.path)
        print(url)
        if !FileManager.default.fileExists(atPath: destinationBaseURL.path) {
            try FileManager.default.createDirectory(at: destinationBaseURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        if FileManager.default.fileExists(atPath: url) {
            return (didDownload: false, url: url)
        }
        
        let tempFileURL = self.getTempPath().appendingPathComponent(UUID().uuidString.lowercased(), isDirectory: false)
        
        try await self.downloadSemaphore.acquire()
        
        defer {
            do {
                self.downloadSemaphore.release()
                
                if FileManager.default.fileExists(atPath: tempFileURL.path) {
                    try FileManager.default.removeItem(at: tempFileURL)
                }
            } catch {
                print(error)
            }
        }
        
        let chunksToDownload = maxChunks >= itemJSON.chunks ? itemJSON.chunks : maxChunks
        
        var status = 0
        let dIo = DispatchIO(type: .random, path: tempFileURL.path, oflag: O_CREAT | O_WRONLY, mode: S_IRUSR | S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH, queue: DispatchQueue(label: "io.filenSDK"), cleanupHandler: { (err) in
            status = Int(err)
        })
        if status != 0 {
            return (didDownload: false, url: url)
        }
        
        progress.totalUnitCount = Int64(chunksToDownload)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<chunksToDownload {
                autoreleasepool {
                    group.addTask { @Sendable in
                        try await self.transferSemaphore.acquire()
                        
                        let downloadedChunkInfo = try await self.downloadChunk(
                            uuid: itemJSON.uuid,
                            region: itemJSON.region,
                            bucket: itemJSON.bucket,
                            index: index,
                            key: itemJSON.key,
                            version: itemJSON.version
                        )
                        
                        self.transferSemaphore.release()
                        
                        let decryptedChunkURL = downloadedChunkInfo.shouldTempFileURL
                        _ = try FilenCrypto.shared.streamDecryptData(input: downloadedChunkInfo.downloadedFileURL, output: downloadedChunkInfo.shouldTempFileURL, key: itemJSON.key, version: itemJSON.version)
                        if FileManager.default.fileExists(atPath: downloadedChunkInfo.downloadedFileURL.path) {
                            try FileManager.default.removeItem(at: downloadedChunkInfo.downloadedFileURL)
                        }
                        
                        defer {
                            do {
                                if FileManager.default.fileExists(atPath: decryptedChunkURL.path) {
                                    try FileManager.default.removeItem(at: decryptedChunkURL)
                                }
                            } catch {
                                print(error)
                            }
                        }
                        
                        guard let readStream = InputStream(fileAtPath: decryptedChunkURL.path) else {
                            throw NSError(domain: "Could not open read stream", code: 1, userInfo: nil)
                        }
                        defer {
                            readStream.close()
                        }
                        readStream.open()
                        
                        let bufferSize = 1024
                        var buffer = [UInt8](repeating: 0, count: bufferSize)
                        var tmpOffset: Int64 = 0
                        
                        autoreleasepool {
                            let dispatch = DispatchGroup()
                            while readStream.hasBytesAvailable {
                                let bytesRead:Int64 = Int64(readStream.read(&buffer, maxLength: bufferSize))
                                
                                if bytesRead > 0 {
                                    let data1 = Data(buffer)
                                    
                                    data1.withUnsafeBytes {
                                        dispatch.enter()
                                        dIo?.write(offset: 1024 * 1024 * Int64(index) + tmpOffset, data: DispatchData(bytes: UnsafeRawBufferPointer(start: $0, count: Int(bytesRead))), queue: DispatchQueue(label: "io.filenSDK"), ioHandler: { (done, data, err) in
                                            if (done){
                                                //                                            print("Finished with \(1024 * 1024 * Int64(index) + tmpOffset)")
                                            } else if (err != 0) {
                                                print("ERROR \(err) at \(1024 * 1024 * Int64(index) + tmpOffset)")
                                            }
                                            
                                            dispatch.leave()
                                        })
                                        tmpOffset += bytesRead
                                    }
                                    //                                    }
                                }
                            }
                            dispatch.wait()
                            progress.completedUnitCount = Int64(index + 1)
                        }
                    }
                }
            }
            for try await _ in group {}
        }
        
        dIo?.close()
        
        if !FileManager.default.fileExists(atPath: tempFileURL.path) {
            throw FilenError.serverUnreachable
        }
        
        try FileManager.default.moveItem(atPath: tempFileURL.path, toPath: destinationURL.path)
        
        return (didDownload: true, url: url)
    }
}

actor DownloadFileCurrentWriteIndex {
    var index = 0
    
    func increase() -> Void {
        index += 1
    }
}

actor UploadFileResult {
    var bucket = ""
    var region = ""
    
    func set(bucket b: String, region r: String) -> Void {
        bucket = b
        region = r
    }
}
