//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/14/24.
//

import Foundation

extension FilenClient
{
    func dirContent(uuid: String) async throws -> DirContentResponse {
        return try await apiRequest(endpoint: "/v3/dir/content", method: .post, body: [
            "uuid": uuid
        ])
    }
}
