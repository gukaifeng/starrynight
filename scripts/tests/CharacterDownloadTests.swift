import XCTest
import Foundation
import CryptoKit
import ZIPFoundation
@testable import DownloadCore

final class CharacterDownloadTests:XCTestCase {
    private func fixture(extra:[(String,Entry.EntryType,Data)] = [],badHash:Bool=false,platform:String="ios") throws -> (URL,URL,CharacterDownloadStore.Manifest) {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        addTeardownBlock{try? FileManager.default.removeItem(at:root)}
        let data=Data("non-executable asset-bundle fixture".utf8)
        let hash=SHA256.hash(data:data).map {String(format:"%02x",$0)}.joined()
        let header:[String:Any]=["schemaVersion":1,"characterID":"role","version":1,"platform":platform,"runtimeVersion":"starry-runtime/1","bundle":"runtime/character.bundle","bundleCRC":0,"files":[["path":"runtime/character.bundle","size":data.count,"sha256":badHash ? String(repeating:"0",count:64):hash]]]
        let zip=root.appendingPathComponent("character.zip")
        let archive=try Archive(url:zip,accessMode:.create)
        for (path,type,payload) in [("package.json",Entry.EntryType.file,try JSONSerialization.data(withJSONObject:header)),("runtime/character.bundle",.file,data)]+extra {
            try archive.addEntry(with:path,type:type,uncompressedSize:Int64(payload.count),provider:{position,size in payload.subdata(in:Int(position)..<Int(position)+size)})
        }
        let m=CharacterDownloadStore.Manifest(schemaVersion:1,characterId:"role",releaseId:"fixture",version:1,platform:"ios",runtimeVersion:"starry-runtime/1",files:[])
        return (zip,root.appendingPathComponent("expanded"),m)
    }
    func testVerifiedArchiveExtractsTheExpectedMembers()throws {
        let (zip,out,m)=try fixture();try CharacterDownloadStore.expand(zip,to:out,manifest:m)
        XCTAssertTrue(FileManager.default.fileExists(atPath:out.appendingPathComponent("runtime/character.bundle").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath:out.appendingPathComponent("package.json").path))
    }
    func testCorruptedMemberCannotBeActivated()throws {
        let (zip,out,m)=try fixture(badHash:true)
        XCTAssertThrowsError(try CharacterDownloadStore.expand(zip,to:out,manifest:m))
    }
    func testOtherPlatformIsRejected()throws {
        let (zip,out,m)=try fixture(platform:"ios-simulator")
        XCTAssertThrowsError(try CharacterDownloadStore.expand(zip,to:out,manifest:m))
    }
    func testParentTraversalIsRejectedBeforeAnyExtraction()throws {
        let (zip,out,m)=try fixture(extra:[("../escaped",.file,Data("escape".utf8))])
        XCTAssertThrowsError(try CharacterDownloadStore.expand(zip,to:out,manifest:m))
        XCTAssertFalse(FileManager.default.fileExists(atPath:out.deletingLastPathComponent().appendingPathComponent("escaped").path))
    }
    func testSymlinksAreRejected()throws {
        let (zip,out,m)=try fixture(extra:[("media/link",.symlink,Data("../../outside".utf8))])
        XCTAssertThrowsError(try CharacterDownloadStore.expand(zip,to:out,manifest:m))
    }
    func testUnexpectedArchiveMembersAreRejected()throws {
        let (zip,out,m)=try fixture(extra:[("media/unlisted",.file,Data("unlisted".utf8))])
        XCTAssertThrowsError(try CharacterDownloadStore.expand(zip,to:out,manifest:m))
    }
}
