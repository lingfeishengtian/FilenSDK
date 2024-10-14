//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/13/24.
//

import Foundation

// export type AuthVersion = 1 | 2;
enum AuthVersion: Int, Decodable {
    case v1 = 1
    case v2 = 2
}

/*
 export type AuthInfoResponse = {
     email: string
     authVersion: AuthVersion
     salt: string
     id: number
 }
 */
struct AuthInfoResponse : Decodable {
    let email: String
    let authVersion: AuthVersion
    let salt: String
    let id: Int
}

/*
 export type LoginResponse = {
     apiKey: string
     masterKeys: string
     publicKey: string
     privateKey: string
 }
 */
struct LoginResponse : Decodable {
    let apiKey: String
    let masterKeys: String
    let publicKey: String
    let privateKey: String
}

struct FilenResponse<T: Decodable> : Decodable {
    let status: Bool
    let message: String
    let code: String
    let data: T?
}

