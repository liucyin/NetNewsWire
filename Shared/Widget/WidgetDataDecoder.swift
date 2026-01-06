//
//  WidgetDataDecoder.swift
//  NetNewsWire
//
//  Created by Stuart Breckenridge on 18/11/20.
//  Copyright © 2020 Ranchero Software. All rights reserved.
//

import Foundation

struct WidgetDataDecoder {

	static func decodeWidgetData() throws -> WidgetData {
		guard let appGroup = Bundle.main.object(forInfoDictionaryKey: "AppGroup") as? String,
			  !appGroup.isEmpty,
			  !appGroup.contains("$("),
			  let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
			return WidgetData(currentUnreadCount: 0, currentTodayCount: 0, currentStarredCount: 0, unreadArticles: [], starredArticles: [], todayArticles: [], lastUpdateTime: Date())
		}

		let dataURL = containerURL.appendingPathComponent("widget-data.json")
		guard FileManager.default.fileExists(atPath: dataURL.path) else {
			return WidgetData(currentUnreadCount: 0, currentTodayCount: 0, currentStarredCount: 0, unreadArticles: [], starredArticles: [], todayArticles: [], lastUpdateTime: Date())
		}

		let decodedWidgetData = try JSONDecoder().decode(WidgetData.self, from: Data(contentsOf: dataURL))
		return decodedWidgetData
	}

	static func sampleData() -> WidgetData {
		let pathToSample = Bundle.main.url(forResource: "widget-sample", withExtension: "json")
		do {
			let data = try Data(contentsOf: pathToSample!)
			let decoded = try JSONDecoder().decode(WidgetData.self, from: data)
			return decoded
		} catch {
			return WidgetData(currentUnreadCount: 0, currentTodayCount: 0, currentStarredCount: 0, unreadArticles: [], starredArticles: [], todayArticles: [], lastUpdateTime: Date())
		}
	}

}
