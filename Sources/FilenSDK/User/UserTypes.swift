//
//  File.swift
//  FilenSDK
//
//  Created by Hunter Han on 10/13/24.
//

import Foundation

/*
 export type UserInfoResponse = {
     id: number
     email: string
     isPremium: 0 | 1
     maxStorage: number
     storageUsed: number
     avatarURL: string
     baseFolderUUID: string
 }
 */

enum isPremium : Int, Decodable {
    case no
    case yes
}

struct UserInfoResponse : Decodable {
    let id: Int
    let email: String
    let isPremium: isPremium
    let maxStorage: Int
    let storageUsed: Int
    let avatarURL: String
    let baseFolderUUID: String
}

/*
 export type UserBaseFolderResponse = {
     uuid: string;
 };
 */
struct UserBaseFolderResponse : Decodable {
    let uuid: String
}
