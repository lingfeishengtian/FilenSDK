// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Alamofire
import IkigaJSON

public class FilenClient {
    internal lazy var sessionConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.af.default
        
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        
        return configuration
    }()
    
    internal lazy var internalSessionManager: Alamofire.Session = {
        return Alamofire.Session(
            configuration: sessionConfiguration,
            rootQueue: DispatchQueue(label: "org.alamofire.sessionManager.rootQueue"),
            startRequestsImmediately: true,
            interceptor: nil,
            serverTrustManager: nil,
            redirectHandler: nil,
            cachedResponseHandler: nil
        )
    }()
    
    public var sessionManager: Alamofire.Session {
        return internalSessionManager
    }
    
    public var config: SDKConfiguration?
    private let tempPath: URL
    
    internal let jsonDecoder = IkigaJSONDecoder()
    internal let jsonEncoder = IkigaJSONEncoder()
    internal let downloadSemaphore = Semaphore(max: 10)
    internal let uploadSemaphore = Semaphore(max: 3)
    internal let transferSemaphore = Semaphore(max: 15)
    
    final let egestUrls = [
        "https://egest.filen.io",
        "https://egest.filen.net",
        "https://egest.filen-1.net",
        "https://egest.filen-2.net",
        "https://egest.filen-3.net",
        "https://egest.filen-4.net",
        "https://egest.filen-5.net",
        "https://egest.filen-6.net"
    ]
    
    func getTempPath () -> URL {
        return tempPath
    }
    
    public init(tempPath: URL, from config: SDKConfiguration? = nil) {
        self.config = config
        self.tempPath = tempPath
    }
    
    func masterKeys () -> [String]? {
        return config?.masterKeys
    }
        
    func apiRequestBaseAPI <T: Decodable>(endpoint: String, method: HTTPMethod, body: Encodable?, apiKey: String? = nil) async throws -> T {
//        let url = URL(string: "https://api.filen.io/")!.appendingPathComponent(endpoint)
        var url = URLComponents(string: "https://gateway.filen.io")
        url?.path = endpoint
        
        var headers = sessionConfiguration.headers
        if let unNilApiKey = (config?.apiKey ?? apiKey) {
            headers["Authorization"] = "Bearer \(unNilApiKey)"
            print("assigned \(unNilApiKey)")
        }
        headers["Accept"] = "application/json, text/plain"
        
        
//        guard let jsonString = FilenUtils.shared.orderedJSONString(from: body ?? []) else {
//            throw FilenError("Failed to create JSON string from body: \(body ?? [:])")
//        }
        var encoder: ParameterEncoder = JSONParameterEncoder.default
        switch method {
        case .post:
            encoder = JSONParameterEncoder.default
            break
        case .get:
            encoder = URLEncodedFormParameterEncoder.default
            break
        default:
            encoder = JSONParameterEncoder.default
        }
        
        let resp = body != nil ? try sessionManager.request(url!.asURL(), method: method, parameters: body!, encoder: encoder, headers: headers){ $0.timeoutInterval = 3600 }.validate() : try sessionManager.request(url!.asURL(), method: method, headers: headers){ $0.timeoutInterval = 3600 }.validate()
        print(try await resp.serializingString().value)
        return try await resp.serializingDecodable(T.self).value
    }
    
    func apiRequest <T: Decodable>(endpoint: String, method: HTTPMethod, body: Encodable?, apiKey: String? = nil) async throws -> T {
        let ret: FilenResponse<T> = try await apiRequestBaseAPI(endpoint: endpoint, method: method, body: body, apiKey: apiKey)
        guard let data = ret.data else {
            throw FilenError(ret.code)
        }
        return data
    }
}

final class FilenError : Error {
    let description: String
    
    init(_ description: String) {
        self.description = description
    }
}

/*
 {
     "email": "",
     "password": "",
     "masterKeys": [""],
     "apiKey": "",
     "publicKey": "",
     "privateKey": "",
     "authVersion": 2,
     "baseFolderUUID": "",
     "userId": 0
 }

 */
public struct SDKConfiguration : Decodable {
    let email: String
    let password: String
    let masterKeys: [String]
    let apiKey: String
    let publicKey: String
    let privateKey: String
    let authVersion: Int
    let baseFolderUUID: String
    let userId: Int
}

