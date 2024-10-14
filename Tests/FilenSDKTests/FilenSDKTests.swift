import Testing
import Foundation
@testable import FilenSDK

//@Test func example() async throws {
//    // Write your test here and use APIs like `#expect(...)` to check expected conditions.
//    let client = FilenClient()
//    let resp = try await client.getAuthInfo(email: "nonslip-diploma.02@icloud.com")
//    #expect(resp.email == "nonslip-diploma.02@icloud.com")
//}

@Test func testGenerateMasterKey() throws {
    let keys = (try FilenCrypto.shared.generatePasswordAndMasterKeysBasedOnAuthVersion(authVersion: 2, rawPassword: "test", salt: "test"))
    #expect(keys.derivedMasterKeys == "8809fd1f1e620cf1156353571199e227adeb766ab435c9fa0d0cb3097f5d8fdf")
    #expect(keys.derivedPassword == "61da3afe761a9bfe7cdc7db9783ed2fdb12157eed2be209db0fc3c17b8396bb3e0fc6844b01c5ca7a605861c6a792669d10e76a4b002d68d3e8cdedfeb167893")
}

@Test("login test")
func login() async throws {
    let client = FilenClient(tempPath: FileManager.default.temporaryDirectory)
    try await client.login(email: "", password: "", twoFactorCode: "XXXXXX")
    print(client.config)
}

@Test("config") func initFromConfig() async throws {
    guard let url = Bundle.module.url(forResource: "config", withExtension: "json") else {
        throw FilenError("Missing file: config.json")
    }
    
    let serialized = try JSONDecoder().decode(SDKConfiguration.self, from: try Data(contentsOf: url))
    let client = FilenClient(tempPath: FileManager.default.temporaryDirectory, from: serialized)
    print(FileManager.default.temporaryDirectory)
    print(client.config)
    
    let folderContents = try await client.dirContent(uuid: client.config!.baseFolderUUID)
    print(folderContents)
    let res = try await client.downloadFile(fileInfo: folderContents.uploads[1], url: URL(filePath: "~/Downloads/test.txt", directoryHint: .notDirectory)!.path)
    print(res)
//    print(folderContents.folders.count)
//    print(folderContents.files.count)
//    try folderContents.files.debugDescription.write(toFile: FileManager.default.temporaryDirectory.appending(path: "test.txt").absoluteString, atomically: true, encoding: .utf8)
//    print(FileManager.default.temporaryDirectory.appending(path: "test.txt").absoluteString)
}
