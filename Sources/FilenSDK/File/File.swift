//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/16/24.
//

import Foundation

extension FilenClient
{
    public func fileInfo(uuid: String) async throws -> FileGetResponse {
        return try await apiRequest(endpoint: "/v3/file", method: .post, body: [
            "uuid": uuid
        ])
    }
}
