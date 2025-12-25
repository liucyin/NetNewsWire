//
//  ImageDownloaderTests.swift
//  NetNewsWireTests
//
//  Created by OpenAI Codex on 12/25/25.
//

import Foundation
import XCTest

@testable import NetNewsWire

@MainActor final class ImageDownloaderTests: XCTestCase {

	func testImageDataCoalescesConcurrentRequestsForSameURL() async {
		let urlString = "https://example.com/image.png"
		let url = URL(string: urlString)!
		let expectedData = Data([0x00, 0x01, 0x02, 0x03])

		var downloadCallCount = 0
		let download: ImageDownloader.DownloadFunction = { requestedURL in
			downloadCallCount += 1
			XCTAssertEqual(requestedURL, url)
			try await Task.sleep(nanoseconds: 50_000_000)
			let response = HTTPURLResponse(url: requestedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
			return (expectedData, response)
		}

		let cacheFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)

		let imageDownloader = ImageDownloader(cacheFolder: cacheFolder, maxConcurrentDownloads: 2, download: download)

		async let d1 = imageDownloader.imageData(for: urlString)
		async let d2 = imageDownloader.imageData(for: urlString)
		async let d3 = imageDownloader.imageData(for: urlString)

		let results = await [d1, d2, d3]
		XCTAssertEqual(results.compactMap { $0 }.count, 3)
		XCTAssertEqual(results[0], expectedData)
		XCTAssertEqual(results[1], expectedData)
		XCTAssertEqual(results[2], expectedData)
		XCTAssertEqual(downloadCallCount, 1)
	}

	func testImageDataReadsFromDiskCacheWithoutReDownloading() async throws {
		let urlString = "https://example.com/image.png"
		let url = URL(string: urlString)!
		let expectedData = Data([0x10, 0x11, 0x12, 0x13, 0x14])

		let cacheFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
		try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)

		do {
			var downloadCallCount = 0
			let download: ImageDownloader.DownloadFunction = { requestedURL in
				downloadCallCount += 1
				XCTAssertEqual(requestedURL, url)
				let response = HTTPURLResponse(url: requestedURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
				return (expectedData, response)
			}

			let imageDownloader = ImageDownloader(cacheFolder: cacheFolder, maxConcurrentDownloads: 1, download: download)
			let data = await imageDownloader.imageData(for: urlString)
			XCTAssertEqual(data, expectedData)
			XCTAssertEqual(downloadCallCount, 1)
		}

		do {
			var downloadCallCount = 0
			let download: ImageDownloader.DownloadFunction = { _ in
				downloadCallCount += 1
				throw URLError(.badServerResponse)
			}

			let imageDownloader = ImageDownloader(cacheFolder: cacheFolder, maxConcurrentDownloads: 1, download: download)
			let data = await imageDownloader.imageData(for: urlString)
			XCTAssertEqual(data, expectedData)
			XCTAssertEqual(downloadCallCount, 0)
		}
	}
}

