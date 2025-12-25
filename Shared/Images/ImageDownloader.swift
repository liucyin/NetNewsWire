//
//  ImageDownloader.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 11/25/17.
//  Copyright © 2017 Ranchero Software. All rights reserved.
//

import Foundation
import os.log
import RSCore
import RSWeb

extension Notification.Name {
	static let imageDidBecomeAvailable = Notification.Name("ImageDidBecomeAvailableNotification") // UserInfoKey.url
}

@MainActor final class ImageDownloader {
	public static let shared = ImageDownloader()

	typealias DownloadFunction = @MainActor (URL) async throws -> (Data?, URLResponse?)

	nonisolated static private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ImageDownloader")

	nonisolated private let diskCache: BinaryDiskCache
	private let queue: DispatchQueue
	private var imageCache = [String: Data]() // url: image
	private var badURLs = Set<String>() // That return a 404 or whatever. Just skip them in the future.

	private let download: DownloadFunction

	private var fetchTasks = [String: Task<Void, Never>]()
	private var waiters = [String: [CheckedContinuation<Data?, Never>]]()

	private let maxConcurrentDownloads: Int
	private var activeDownloadCount = 0
	private var downloadSlotWaiters = [CheckedContinuation<Void, Never>]()

	convenience init() {
		let folder = AppConfig.cacheSubfolder(named: "Images")
		self.init(cacheFolder: folder)
	}

	init(cacheFolder: URL, maxConcurrentDownloads: Int = 4, download: @escaping DownloadFunction = { url in
		try await Downloader.shared.download(url)
	}) {
		try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
		self.diskCache = BinaryDiskCache(folder: cacheFolder.path)
		self.queue = DispatchQueue(label: "ImageDownloader serial queue - \(cacheFolder.path)")
		self.maxConcurrentDownloads = max(1, maxConcurrentDownloads)
		self.download = download
	}

	@discardableResult
	func image(for url: String) -> Data? {
		assert(Thread.isMainThread)
		if let data = imageCache[url] {
			return data
		}

		startFetchIfNeeded(url)

		return nil
	}

	func imageData(for url: String) async -> Data? {
		assert(Thread.isMainThread)

		if let data = imageCache[url] {
			return data
		}
		guard !badURLs.contains(url) else {
			return nil
		}

		return await withCheckedContinuation { continuation in
			waiters[url, default: []].append(continuation)
			startFetchIfNeeded(url)
		}
	}

	func cancelFetch(for url: String) {
		fetchTasks[url]?.cancel()
	}
}

private extension ImageDownloader {

		func cacheImage(_ url: String, _ image: Data) {
			assert(Thread.isMainThread)
			imageCache[url] = image
			postImageDidBecomeAvailableNotification(url)
		}

		func startFetchIfNeeded(_ url: String) {
			assert(Thread.isMainThread)
			guard !url.isEmpty, !badURLs.contains(url), fetchTasks[url] == nil else {
				return
			}

			let task = Task { @MainActor in
				defer {
					fetchTasks[url] = nil
					resumeWaiters(for: url, data: nil)
				}

				let data = await fetchImage(url)
				guard !Task.isCancelled else {
					return
				}

				guard let data, !data.isEmpty else {
					return
				}

				cacheImage(url, data)
				resumeWaiters(for: url, data: data)
			}

			fetchTasks[url] = task
		}

		func resumeWaiters(for url: String, data: Data?) {
			guard let continuations = waiters[url] else {
				return
			}
			waiters[url] = nil
			for continuation in continuations {
				continuation.resume(returning: data)
			}
		}

		func fetchImage(_ url: String) async -> Data? {
			guard !Task.isCancelled else { return nil }

			if let image = await readFromDisk(url: url) {
				return image
			}

			guard !Task.isCancelled else { return nil }
			return await downloadImageWithLimit(url)
		}

		func readFromDisk(url: String) async -> Data? {
			await withCheckedContinuation { continuation in
			readFromDisk(url) { data in
				continuation.resume(returning: data)
			}
		}
	}

	func readFromDisk(_ url: String, _ completion: @escaping @MainActor (Data?) -> Void) {
		queue.async {
			if let data = self.diskCache[self.diskKey(url)], !data.isEmpty {
				DispatchQueue.main.async {
					completion(data)
				}
				return
			}

			DispatchQueue.main.async {
				completion(nil)
			}
			}
		}

		func downloadImageWithLimit(_ url: String) async -> Data? {
			await acquireDownloadSlot()
			defer { releaseDownloadSlot() }
			guard !Task.isCancelled else { return nil }
			return await downloadImage(url)
		}

		func acquireDownloadSlot() async {
			if activeDownloadCount < maxConcurrentDownloads {
				activeDownloadCount += 1
				return
			}

			await withCheckedContinuation { continuation in
				downloadSlotWaiters.append(continuation)
			}
			activeDownloadCount += 1
		}

		func releaseDownloadSlot() {
			activeDownloadCount = max(0, activeDownloadCount - 1)
			guard !downloadSlotWaiters.isEmpty else { return }
			let continuation = downloadSlotWaiters.removeFirst()
			continuation.resume()
		}

		func downloadImage(_ url: String) async -> Data? {
			guard let imageURL = URL(string: url) else {
				return nil
			}

			do {
				let (data, response) = try await download(imageURL)

				if let data, !data.isEmpty, let response, response.statusIsOK {
					saveToDisk(url, data)
					return data
				}

			if let response = response as? HTTPURLResponse, response.statusCode >= HTTPResponseCode.badRequest && response.statusCode <= HTTPResponseCode.notAcceptable {
				badURLs.insert(url)
			}

			return nil
		} catch {
			Self.logger.error("Error downloading image at \(url) \(error.localizedDescription)")
			return nil
		}
	}

	func saveToDisk(_ url: String, _ data: Data) {
		queue.async {
			self.diskCache[self.diskKey(url)] = data
		}
	}

	nonisolated func diskKey(_ url: String) -> String {
		url.md5String
	}

	func postImageDidBecomeAvailableNotification(_ url: String) {
		assert(Thread.isMainThread)
		NotificationCenter.default.post(name: .imageDidBecomeAvailable, object: self, userInfo: [UserInfoKey.url: url])
	}
}
