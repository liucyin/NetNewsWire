//
//  ArticleUtilities.swift
//  NetNewsWire
//
//  Created by Brent Simmons on 7/25/15.
//  Copyright © 2015 Ranchero Software, LLC. All rights reserved.
//

import Foundation
import RSCore
import Articles
import Account

// These handle multiple accounts.

@MainActor func markArticles(_ articles: Set<Article>, statusKey: ArticleStatus.Key, flag: Bool, completion: (() -> Void)? = nil) {

	let d: [String: Set<Article>] = accountAndArticlesDictionary(articles)

	let group = DispatchGroup()

	for (accountID, accountArticles) in d {
		guard let account = AccountManager.shared.existingAccount(accountID: accountID) else {
			continue
		}
		group.enter()
		account.markArticles(accountArticles, statusKey: statusKey, flag: flag) { _ in
			group.leave()
		}
	}

	group.notify(queue: .main) {
		completion?()
	}
}

private func accountAndArticlesDictionary(_ articles: Set<Article>) -> [String: Set<Article>] {

	let d = Dictionary(grouping: articles, by: { $0.accountID })
	return d.mapValues{ Set($0) }
}

@MainActor extension Article {

	var feed: Feed? {
		return account?.existingFeed(withFeedID: feedID)
	}

	var url: URL? {
		return URL.encodeSpacesIfNeeded(rawLink)
	}

	var externalURL: URL? {
		return URL.encodeSpacesIfNeeded(rawExternalLink)
	}

	var imageURL: URL? {
		return URL.encodeSpacesIfNeeded(rawImageLink)
	}

	var link: String? {
		// Prefer link from URL, if one can be created, as these are repaired if required.
		// Provide the raw link if URL creation fails.
		return url?.absoluteString ?? rawLink
	}

	var externalLink: String? {
		// Prefer link from externalURL, if one can be created, as these are repaired if required.
		// Provide the raw link if URL creation fails.
		return externalURL?.absoluteString ?? rawExternalLink
	}

	var imageLink: String? {
		// Prefer link from imageURL, if one can be created, as these are repaired if required.
		// If imageURL is invalid/empty, fall back to extracting the first usable image URL from the HTML.
		if let imageURL,
		   let scheme = imageURL.scheme?.lowercased(),
		   scheme == "http" || scheme == "https" {
			return imageURL.absoluteString
		}

		return extractImageURL(from: contentHTML) ?? extractImageURL(from: summary)
	}

	private static let imageTagRegex = try! NSRegularExpression(pattern: "<img\\b[^>]*>", options: [.caseInsensitive])
	private static let imageAttributeRegex = try! NSRegularExpression(pattern: "\\b(data-original|data-src|srcset|src|width|height)\\s*=\\s*(?:\"([^\"]+)\"|'([^']+)'|([^\\s>]+))", options: [.caseInsensitive])

	private func extractImageURL(from html: String?) -> String? {
		guard let html, !html.isEmpty else {
			return nil
		}

		let range = NSRange(location: 0, length: html.utf16.count)
		var firstValidURL: String?

		Self.imageTagRegex.enumerateMatches(in: html, options: [], range: range) { match, _, stop in
			guard let match, let tagRange = Range(match.range, in: html) else {
				return
			}

			let tagString = String(html[tagRange])
			if let urlString = extractFirstImageURL(fromImageTag: tagString) {
				firstValidURL = urlString
				stop.pointee = true
			}
		}

		return firstValidURL
	}

	private func extractFirstImageURL(fromImageTag tagString: String) -> String? {
		let range = NSRange(location: 0, length: tagString.utf16.count)
		var attributes = [String: String]()

		Self.imageAttributeRegex.enumerateMatches(in: tagString, options: [], range: range) { match, _, _ in
			guard let match else { return }
			guard let nameRange = Range(match.range(at: 1), in: tagString) else { return }

			let name = tagString[nameRange].lowercased()

			let value: String?
			if let valueRange = Range(match.range(at: 2), in: tagString) {
				value = String(tagString[valueRange])
			} else if let valueRange = Range(match.range(at: 3), in: tagString) {
				value = String(tagString[valueRange])
			} else if let valueRange = Range(match.range(at: 4), in: tagString) {
				value = String(tagString[valueRange])
			} else {
				value = nil
			}

			if let value, !value.isEmpty {
				attributes[name] = value
			}
		}

		let width = parsePixelDimension(attributes["width"])
		let height = parsePixelDimension(attributes["height"])

		let candidates = [
			attributes["data-original"],
			attributes["data-src"],
			firstURL(fromSrcset: attributes["srcset"]),
			attributes["src"]
		]

		for candidate in candidates {
			guard let candidate, let url = sanitizedHTTPImageURLString(candidate) else { continue }
			if isLikelyTrackingPixel(urlString: url, width: width, height: height) {
				continue
			}
			return url
		}

		return nil
	}

	private func firstURL(fromSrcset srcset: String?) -> String? {
		guard let srcset else { return nil }
		let firstEntry = srcset.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: true).first
		guard let firstEntry else { return nil }
		let firstURL = firstEntry.split(maxSplits: 1, omittingEmptySubsequences: true) { $0.isWhitespace }.first
		return firstURL.map(String.init)
	}

	private func sanitizedHTTPImageURLString(_ urlString: String) -> String? {
		let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }

		let decoded = trimmed.replacingOccurrences(of: "&amp;", with: "&")
		if decoded.lowercased().hasPrefix("data:") {
			return nil
		}

		let normalized: String
		if decoded.hasPrefix("//") {
			normalized = "https:" + decoded
		} else {
			normalized = decoded
		}

		guard let url = URL.encodeSpacesIfNeeded(normalized),
			  let scheme = url.scheme?.lowercased(),
			  scheme == "http" || scheme == "https" else {
			return nil
		}

		return url.absoluteString
	}

	private func parsePixelDimension(_ rawValue: String?) -> Int? {
		guard let rawValue else { return nil }
		let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
		if let value = Int(trimmed) {
			return value
		}
		if let range = trimmed.range(of: #"^\d+"#, options: .regularExpression) {
			return Int(trimmed[range])
		}
		return nil
	}

	private func isLikelyTrackingPixel(urlString: String, width: Int?, height: Int?) -> Bool {
		if let width, let height, width <= 2, height <= 2 {
			return true
		}
		guard let url = URL(string: urlString) else { return false }
		let filename = url.lastPathComponent.lowercased()
		if filename == "pixel.gif" || filename == "pixel.png" {
			return true
		}
		return false
	}

	var preferredLink: String? {
		if let link = link, !link.isEmpty {
			return link
		}
		if let externalLink = externalLink, !externalLink.isEmpty {
			return externalLink
		}
		return nil
	}

	var preferredURL: URL? {
		return url ?? externalURL
	}

	var body: String? {
		return contentHTML ?? contentText ?? summary
	}

	var logicalDatePublished: Date {
		return datePublished ?? dateModified ?? status.dateArrived
	}

	var isAvailableToMarkUnread: Bool {
		guard let markUnreadWindow = account?.behaviors.compactMap( { behavior -> Int? in
			switch behavior {
			case .disallowMarkAsUnreadAfterPeriod(let days):
				return days
			default:
				return nil
			}
		}).first else {
			return true
		}

		if logicalDatePublished.byAdding(days: markUnreadWindow) > Date() {
			return true
		} else {
			return false
		}
	}

	func iconImage() -> IconImage? {
		return IconImageCache.shared.imageForArticle(self)
	}

	func iconImageUrl(feed: Feed) -> URL? {
		if let image = iconImage() {
			let fm = FileManager.default
			var path = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			let feedID = feed.feedID.replacingOccurrences(of: "/", with: "_")
			path.appendPathComponent(feedID + "_smallIcon.png")
			fm.createFile(atPath: path.path, contents: image.image.dataRepresentation()!, attributes: nil)
			return path
		} else {
			return nil
		}
	}

	func byline() -> String {
		guard let authors = authors ?? feed?.authors, !authors.isEmpty else {
			return ""
		}

		// If the author's name is the same as the feed, then we don't want to display it.
		// This code assumes that multiple authors would never match the feed name so that
		// if there feed owner has an article co-author all authors are given the byline.
		if authors.count == 1, let author = authors.first {
			if author.name == feed?.nameForDisplay {
				return ""
			}
		}

		var byline = ""
		var isFirstAuthor = true

		for author in authors {
			if !isFirstAuthor {
				byline += ", "
			}
			isFirstAuthor = false

			var authorEmailAddress: String? = nil
			if let emailAddress = author.emailAddress, !(emailAddress.contains("noreply@") || emailAddress.contains("no-reply@")) {
				authorEmailAddress = emailAddress
			}

			if let emailAddress = authorEmailAddress, emailAddress.contains(" ") {
				byline += emailAddress // probably name plus email address
			}
			else if let name = author.name, let emailAddress = authorEmailAddress {
				byline += "\(name) <\(emailAddress)>"
			}
			else if let name = author.name {
				byline += name
			}
			else if let emailAddress = authorEmailAddress {
				byline += "<\(emailAddress)>"
			}
			else if let url = author.url {
				byline += url
			}
		}

		return byline
	}

}

// MARK: Path

struct ArticlePathKey {
	static let accountID = "accountID"
	static let accountName = "accountName"
	static let feedID = "feedID"
	static let articleID = "articleID"
}

@MainActor extension Article {

	public var pathUserInfo: [AnyHashable : Any] {
		return [
			ArticlePathKey.accountID: accountID,
			ArticlePathKey.accountName: account?.nameForDisplay ?? "",
			ArticlePathKey.feedID: feedID,
			ArticlePathKey.articleID: articleID
		]
	}

}

// MARK: SortableArticle

@MainActor extension Article: SortableArticle {

	var sortableName: String {
		return feed?.name ?? ""
	}

	var sortableDate: Date {
		return logicalDatePublished
	}

	var sortableArticleID: String {
		return articleID
	}

	var sortableFeedID: String {
		return feedID
	}

}
