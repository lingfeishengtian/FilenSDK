//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/13/24.
//

import Foundation

extension FilenClient {
    func getAuthInfo(email: String) async throws -> AuthInfoResponse {
        try await apiRequest(endpoint: "/v3/auth/info", method: .post, body: [
            "email": email
        ])
    }
    
    func login(email: String, password: String, twoFactorCode: String = "XXXXXX") async throws {
        let authInfo = try await getAuthInfo(email: email)
        let authVersion = authInfo.authVersion
        let derivedInfo = try FilenCrypto.shared.generatePasswordAndMasterKeysBasedOnAuthVersion(authVersion: authVersion.rawValue, rawPassword: password, salt: authInfo.salt)
        let loginResponse: LoginResponse = try await apiRequest(endpoint: "/v3/login", method: .post, body: LoginRequestBody(email: email, password: derivedInfo.derivedPassword, twoFactorCode: twoFactorCode, authVersion: authVersion.rawValue))
        let userInfo = try await userInfo(apiKey: loginResponse.apiKey)
        
        // TODO: Support multiple keys!!!
        
        config = SDKConfiguration(email: email, password: derivedInfo.derivedPassword, masterKeys: [derivedInfo.derivedMasterKeys], apiKey: loginResponse.apiKey, publicKey: loginResponse.publicKey, privateKey: loginResponse.privateKey, authVersion: authVersion.rawValue, baseFolderUUID: userInfo.baseFolderUUID, userId: userInfo.id)
    }
}

struct LoginRequestBody: Encodable {
    let email: String
    let password: String
    let twoFactorCode: String
    let authVersion: Int
}
