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
	case sources
	case library
	case search
	case settings
	case certificates
	
	var title: String {
		switch self {
		case .today:        return "اليوم"
		case .sources:     	return "التطبيقات"
		case .library: 		return "التوقيع"
		case .search:       return "البحث"
		case .settings: 	return "الإعدادات"
		case .certificates:	return "الشهادات"
		}
	}
	
	var icon: String {
		switch self {
		case .today:        return "doc.text.image.fill"
		case .sources: 		return "square.stack.3d.up.fill"
		case .library: 		return "checkmark.seal.fill"
		case .search:       return "magnifyingglass"
		case .settings: 	return "gearshape.2.fill"
		case .certificates: return "person.text.rectangle"
		}
	}
	
	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .today:        AppStoreTodayView()
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
			.sources,
			.library,
			.search,
			.settings
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return [
			.certificates
		]
	}
}
