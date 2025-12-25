//
//  ArticleImageLinkTests.swift
//  NetNewsWire
//
//  Created by Codex on 12/25/25.
//

import Articles
import Foundation
import XCTest

@testable import NetNewsWire

@MainActor final class ArticleImageLinkTests: XCTestCase {

	func testImageLinkFallsBackWhenRawImageLinkEmpty() {
		let article = makeArticle(rawImageLink: "", contentHTML: #"<p><img src="https://example.com/a.png"></p>"#)
		XCTAssertEqual(article.imageLink, "https://example.com/a.png")
	}

	func testImageLinkFallsBackWhenRawImageLinkInvalid() {
		let article = makeArticle(rawImageLink: "not a url", contentHTML: #"<p><img src="https://example.com/a.png"></p>"#)
		XCTAssertEqual(article.imageLink, "https://example.com/a.png")
	}

	func testImageLinkFallsBackWhenRawImageLinkIsDataURL() {
		let article = makeArticle(rawImageLink: "data:image/gif;base64,R0lGODlhAQABAIAAAAUEBA==", contentHTML: #"<p><img src="https://example.com/a.png"></p>"#)
		XCTAssertEqual(article.imageLink, "https://example.com/a.png")
	}

	func testExtractsDataSrcOverDataPlaceholder() {
		let article = makeArticle(contentHTML: #"<p><img src="data:image/gif;base64,R0lGODlhAQABAIAAAAUEBA==" data-src="https://example.com/real.jpg"></p>"#)
		XCTAssertEqual(article.imageLink, "https://example.com/real.jpg")
	}

	func testExtractsDataOriginal() {
		let article = makeArticle(contentHTML: #"<p><img data-original="https://example.com/original.jpg" src="data:image/gif;base64,R0lGODlhAQABAIAAAAUEBA=="></p>"#)
		XCTAssertEqual(article.imageLink, "https://example.com/original.jpg")
	}

	func testExtractsFirstURLFromSrcset() {
		let article = makeArticle(contentHTML: #"<p><img srcset="https://example.com/one.jpg 1x, https://example.com/two.jpg 2x"></p>"#)
		XCTAssertEqual(article.imageLink, "https://example.com/one.jpg")
	}

	func testExtractsSingleQuotedAttributes() {
		let article = makeArticle(contentHTML: "<p><img src='https://example.com/single.png'></p>")
		XCTAssertEqual(article.imageLink, "https://example.com/single.png")
	}

	func testSkipsLikelyTrackingPixels() {
		let html = #"""
			<p>
				<img src="https://example.com/pixel.gif" width="1" height="1">
				<img src="https://example.com/real.png">
			</p>
			"""#
		let article = makeArticle(contentHTML: html)
		XCTAssertEqual(article.imageLink, "https://example.com/real.png")
	}

	private func makeArticle(rawImageLink: String? = nil, contentHTML: String? = nil, summary: String? = nil) -> Article {
		let articleID = "article-1"
		let status = ArticleStatus(articleID: articleID, read: false, dateArrived: Date())
		return Article(accountID: "account-1",
					   articleID: articleID,
					   feedID: "feed-1",
					   uniqueID: "unique-1",
					   title: nil,
					   contentHTML: contentHTML,
					   contentText: nil,
					   markdown: nil,
					   url: nil,
					   externalURL: nil,
					   summary: summary,
					   imageURL: rawImageLink,
					   datePublished: nil,
					   dateModified: nil,
					   authors: nil,
					   status: status)
	}
}
