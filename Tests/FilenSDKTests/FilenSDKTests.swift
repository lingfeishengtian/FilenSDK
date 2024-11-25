import Testing
import Foundation
@testable import FilenSDK

struct Credentials: Decodable {
    let email: String
    let password: String
    let twoFactorCode: String?
}

struct FilenSDKTests {
    let client: FilenClient
    
    init() async throws {
        do {
            guard let url = Bundle.module.url(forResource: "config", withExtension: "json") else {
                throw FilenError.missingConfigFile
            }
            let serialized = try JSONDecoder().decode(SDKConfiguration.self, from: try Data(contentsOf: url))
            client = FilenClient(tempPath: FileManager.default.temporaryDirectory, from: serialized)
        } catch {
            print(error)
            print("Starting login test")
            
            guard let url = Bundle.module.url(forResource: "credentials", withExtension: "json") else {
                throw FilenError.missingConfigFile
            }
            let credentials = try JSONDecoder().decode(Credentials.self, from: try Data(contentsOf: url))
            
            client = FilenClient(tempPath: FileManager.default.temporaryDirectory)
            try await client.login(email: credentials.email, password: credentials.password, twoFactorCode: credentials.twoFactorCode ?? "")
        }
    }
    
    @Test func testGenerateMasterKey() throws {
        let keys = (try FilenCrypto.shared.generatePasswordAndMasterKeysBasedOnAuthVersion(authVersion: 2, rawPassword: "test", salt: "test"))
        #expect(keys.derivedMasterKeys == "8809fd1f1e620cf1156353571199e227adeb766ab435c9fa0d0cb3097f5d8fdf")
        #expect(keys.derivedPassword == "61da3afe761a9bfe7cdc7db9783ed2fdb12157eed2be209db0fc3c17b8396bb3e0fc6844b01c5ca7a605861c6a792669d10e76a4b002d68d3e8cdedfeb167893")
    }

    @Test("foldername", arguments: [
        "TestFolder A",
        "Supports!@#$%^&*()_+{}|:<>?[];',.",
    ])
    func testDecryptFoldername(clientTestName: String) async throws {
        let encrypted = try FilenCrypto.shared.encryptFileName(name: "{\"name\": \"\(clientTestName)\"}", fileKey: client.config!.masterKeys.first!)
        let decrypted = try client.decryptFolderName(name: encrypted)
        #expect(decrypted == clientTestName)
    }

    // TODO: Write better tests
    @Test("upload") func testUpload() async throws {
        guard let url = Bundle.module.url(forResource: "config", withExtension: "json") else {
            throw FilenError.missingConfigFile
        }
        
        let serialized = try JSONDecoder().decode(SDKConfiguration.self, from: try Data(contentsOf: url))
        let client = FilenClient(tempPath: FileManager.default.temporaryDirectory, from: serialized)
        let fileURL = URL(fileURLWithPath: "")
        let upload = try await client.uploadFile(url: fileURL.path, parent: client.config?.baseFolderUUID ?? "")
        print(upload)
    }

}
