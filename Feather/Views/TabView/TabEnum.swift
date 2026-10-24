//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//

import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable {
	case today
	case games
	case sources
	case library
	case search
	case settings
	case certificates
	
	var title: String {
		switch self {
		case .today:        return "اليوم"
		case .games:        return "الألعاب"
		case .sources:     	return "التطبيقات"
		case .library: 		return "Arcade"
		case .search:       return "بحث"
		case .settings: 	return "الإعدادات"
		case .certificates:	return "الشهادات"
		}
	}
	
	var icon: String {
		switch self {
		case .today:        return "doc.text.image"
		case .games:        return "flame.fill"
		case .sources: 		return "square.stack.3d.up.fill"
		case .library: 		return "arcade.stick.console"
		case .search:       return "magnifyingglass"
		case .settings: 	return "gearshape.fill"
		case .certificates: return "person.text.rectangle"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .today:        AppStoreTodayView()
		case .games:        AppStoreGamesView()
		case .sources:      SourcesView()
		case .library:      LibraryView()
		case .search:       AppStoreSearchView()
		case .settings:     SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		}
	}
	
	static var defaultTabs: [TabEnum] {
		return [
			.today,
			.games,
			.sources,
			.library,
			.search
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return []
	}
}
