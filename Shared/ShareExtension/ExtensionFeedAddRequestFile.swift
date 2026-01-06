//
//  ExtensionFeedAddRequestFile.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 2/11/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import os.log
import Account
import RSCore

final class ExtensionFeedAddRequestFile: NSObject, NSFilePresenter, Sendable {
	static let shared = ExtensionFeedAddRequestFile()

	static private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExtensionFeedAddRequestFile")

	private static var fileURL: URL? {
		guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String,
			  !appGroup.isEmpty,
			  !appGroup.contains("$(") else {
			return nil
		}

		guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
			return nil
		}

		return containerURL.appendingPathComponent("extension_feed_add_request.plist")
	}

	private let operationQueue = {
		let queue = OperationQueue()
		queue.maxConcurrentOperationCount = 1
		return queue
	}()

	var presentedItemURL: URL? {
		ExtensionFeedAddRequestFile.fileURL
	}

	var presentedItemOperationQueue: OperationQueue {
		operationQueue
	}

	private let didStart = Mutex(false)

	func start() {
		guard ExtensionFeedAddRequestFile.fileURL != nil else {
			Self.logger.error("Start skipped: shared file unavailable (missing App Group entitlement or invalid AppGroup key).")
			return
		}

		var shouldBail = false
		didStart.withLock { didStart in
			if didStart {
				shouldBail = true
				assertionFailure("start called when already did start")
				return
			}

			didStart = true
		}

		if shouldBail {
			return
		}

		NSFileCoordinator.addFilePresenter(self)
		Task { @MainActor in
			process()
		}
	}

	func presentedItemDidChange() {
		Task { @MainActor in
			process()
		}
	}

	func resume() {
		guard ExtensionFeedAddRequestFile.fileURL != nil else {
			return
		}

		var started = false
		didStart.withLock { didStart in
			started = didStart
		}
		guard started else { return }

		NSFileCoordinator.addFilePresenter(self)
		Task { @MainActor in
			process()
		}
	}

	func suspend() {
		var started = false
		didStart.withLock { didStart in
			started = didStart
		}
		guard started else { return }

		NSFileCoordinator.removeFilePresenter(self)
	}

	static func save(_ feedAddRequest: ExtensionFeedAddRequest) {
		guard let fileURL = ExtensionFeedAddRequestFile.fileURL else {
			Self.logger.error("Save skipped: shared file unavailable (missing App Group entitlement or invalid AppGroup key).")
			return
		}

		let decoder = PropertyListDecoder()
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary

		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator()

		fileCoordinator.coordinate(writingItemAt: fileURL, options: [.forMerging], error: errorPointer, byAccessor: { url in
			do {

				var requests: [ExtensionFeedAddRequest]
				if let fileData = try? Data(contentsOf: url),
					let decodedRequests = try? decoder.decode([ExtensionFeedAddRequest].self, from: fileData) {
					requests = decodedRequests
				} else {
					requests = [ExtensionFeedAddRequest]()
				}

				requests.append(feedAddRequest)

				let data = try encoder.encode(requests)
				try data.write(to: url)

			} catch let error as NSError {
				Self.logger.error("Save to disk failed: \(error.localizedDescription)")
			}
		})

		if let error = errorPointer?.pointee {
			Self.logger.error("Save to disk coordination failed: \(error.localizedDescription)")
		}
	}
}

@MainActor private extension ExtensionFeedAddRequestFile {

	func process() {
		guard let fileURL = ExtensionFeedAddRequestFile.fileURL else {
			return
		}

		let decoder = PropertyListDecoder()
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary

		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator(filePresenter: self)

		var requests: [ExtensionFeedAddRequest]? = nil

		fileCoordinator.coordinate(writingItemAt: fileURL, options: [.forMerging], error: errorPointer, byAccessor: { url in
			do {

				if let fileData = try? Data(contentsOf: url),
					let decodedRequests = try? decoder.decode([ExtensionFeedAddRequest].self, from: fileData) {
					requests = decodedRequests
				}

				let data = try encoder.encode([ExtensionFeedAddRequest]())
				try data.write(to: url)

			} catch let error as NSError {
				Self.logger.error("Save to disk failed: \(error.localizedDescription)")
			}
		})

		if let error = errorPointer?.pointee {
			Self.logger.error("Save to disk coordination failed: \(error.localizedDescription)")
		}

		requests?.forEach { processRequest($0) }
	}

	func processRequest(_ request: ExtensionFeedAddRequest) {
		var destinationAccountID: String? = nil
		switch request.destinationContainerID {
		case .account(let accountID):
			destinationAccountID = accountID
		case .folder(let accountID, _):
			destinationAccountID = accountID
		default:
			break
		}

		guard let accountID = destinationAccountID, let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			return
		}

		var destinationContainer: Container? = nil
		if account.containerID == request.destinationContainerID {
			destinationContainer = account
		} else {
			destinationContainer = account.folders?.first(where: { $0.containerID == request.destinationContainerID })
		}

		guard let container = destinationContainer else { return }

		account.createFeed(url: request.feedURL.absoluteString, name: request.name, container: container, validateFeed: true) { _ in }
	}
}
