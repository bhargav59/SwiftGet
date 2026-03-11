import XCTest
@testable import SwiftGet

final class DownloadManagerTests: XCTestCase {
    
    func testAddDownload() {
        let manager = DownloadManager.shared
        let url = URL(string: "https://example.com/test.zip")!
        manager.addDownload(url: url)
        
        let expectation = XCTestExpectation(description: "Download added")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(manager.downloads.contains { $0.url == url })
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testFileCategory() {
        XCTAssertEqual(FileCategory.from(url: URL(string: "https://x.com/video.mp4")!), .video)
        XCTAssertEqual(FileCategory.from(url: URL(string: "https://x.com/doc.pdf")!), .document)
        XCTAssertEqual(FileCategory.from(url: URL(string: "https://x.com/song.mp3")!), .music)
        XCTAssertEqual(FileCategory.from(url: URL(string: "https://x.com/archive.zip")!), .archive)
        XCTAssertEqual(FileCategory.from(url: URL(string: "https://x.com/other.xyz")!), .other)
    }
    
    func testDownloadItemInitialization() {
        let url = URL(string: "https://example.com/file.zip")!
        let item = DownloadItem(url: url)
        XCTAssertEqual(item.filename, "file.zip")
        XCTAssertEqual(item.status, .queued)
        XCTAssertEqual(item.progress, 0.0)
        XCTAssertEqual(item.category, .archive)
    }
    
    func testPriorityOrdering() {
        let manager = DownloadManager.shared
        let high = DownloadItem(url: URL(string: "https://example.com/high.zip")!)
        let low = DownloadItem(url: URL(string: "https://example.com/low.zip")!)
        high.priority = .high
        low.priority = .low
        
        let sorted = [low, high].sorted { a, b in
            let order: [DownloadPriority] = [.high, .normal, .low]
            return (order.firstIndex(of: a.priority) ?? 1) < (order.firstIndex(of: b.priority) ?? 1)
        }
        XCTAssertEqual(sorted.first?.priority, .high)
    }
}
