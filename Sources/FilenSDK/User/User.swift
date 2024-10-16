//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/13/24.
//

import Foundation

extension FilenClient {
    func userInfo(apiKey apiKeyParam: String?) async throws -> UserInfoResponse {
        guard let apiKey = (apiKeyParam == nil) ? config?.apiKey : apiKeyParam else {
            throw FilenError("Not logged in")
        }
        return try await apiRequest(endpoint: "/v3/user/info", method: .get, body: nil, apiKey: apiKey)
    }
    
    public func baseFolder() async throws -> UserBaseFolderResponse {
        guard let apiKey = config?.apiKey else {
            throw FilenError("Not logged in")
        }
        return try await apiRequest(endpoint: "/v3/user/baseFolder", method: .get, body: nil, apiKey: apiKey)
    }
}
