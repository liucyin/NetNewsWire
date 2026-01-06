//
//  ExtensionContainersFile.swift
//  NetNewsWire-iOS
//
//  Created by Maurice Parker on 2/10/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation
import os.log
import RSCore
import RSParser
import Account

@MainActor final class ExtensionContainersFile {
	static let shared = ExtensionContainersFile()

	static private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ExtensionContainersFile")

	private static var fileURL: URL? {
		guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String,
			  !appGroup.isEmpty,
			  !appGroup.contains("$(") else {
			return nil
		}

		guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
			return nil
		}

		return containerURL.appendingPathComponent("extension_containers.plist")
	}

	private static var filePath: String? {
		fileURL?.path
	}

	private var isActive = false
	private var isDirty = false {
		didSet {
			queueSaveToDiskIfNeeded()
		}
	}
	private let saveQueue = CoalescingQueue(name: "Save Queue", interval: 0.5)

	func start() {
		guard !isActive else {
			assertionFailure("start() called when already active")
			return
		}

		guard let filePath = ExtensionContainersFile.filePath else {
			Self.logger.error("Extension containers shared file unavailable (missing App Group entitlement or invalid AppGroup key).")
			return
		}

		isActive = true

		if !FileManager.default.fileExists(atPath: filePath) {
			save()
		}

		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .UserDidAddAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .UserDidDeleteAccount, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .AccountStateDidChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(markAsDirty), name: .ChildrenDidChange, object: nil)
	}

	/// Reads and decodes the shared plist file.
	static func read() -> ExtensionContainers? {
		guard let fileURL = ExtensionContainersFile.fileURL else {
			Self.logger.error("Read failed: shared file unavailable (missing App Group entitlement or invalid AppGroup key).")
			return nil
		}

		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator()
		var extensionContainers: ExtensionContainers? = nil

		fileCoordinator.coordinate(readingItemAt: fileURL, options: [], error: errorPointer, byAccessor: { readURL in
			if let fileData = try? Data(contentsOf: readURL) {
				let decoder = PropertyListDecoder()
				extensionContainers = try? decoder.decode(ExtensionContainers.self, from: fileData)
			}
		})

		if let error = errorPointer?.pointee {
			Self.logger.error("Read from disk coordination failed: \(error.localizedDescription)")
		}

		return extensionContainers
	}

}

@MainActor private extension ExtensionContainersFile {

	@objc func markAsDirty() {
		isDirty = true
	}

	func queueSaveToDiskIfNeeded() {
		saveQueue.add(self, #selector(saveToDiskIfNeeded))
	}

	@objc func saveToDiskIfNeeded() {
		if isDirty {
			isDirty = false
			save()
		}
	}

	func save() {
		guard let fileURL = ExtensionContainersFile.fileURL else {
			Self.logger.error("Save failed: shared file unavailable (missing App Group entitlement or invalid AppGroup key).")
			return
		}

		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary

		let errorPointer: NSErrorPointer = nil
		let fileCoordinator = NSFileCoordinator()

		fileCoordinator.coordinate(writingItemAt: fileURL, options: [], error: errorPointer, byAccessor: { writeURL in
			do {
				let extensionAccounts = AccountManager.shared.sortedActiveAccounts.map { ExtensionAccount(account: $0) }
				let extensionContainers = ExtensionContainers(accounts: extensionAccounts)
				let data = try encoder.encode(extensionContainers)
				try data.write(to: writeURL)
			} catch let error as NSError {
				Self.logger.error("Save to disk failed: \(error.localizedDescription)")
			}
		})

		if let error = errorPointer?.pointee {
			Self.logger.error("Save to disk coordination failed: \(error.localizedDescription)")
		}
	}
}
