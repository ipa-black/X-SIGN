//
//  ExtendedTabbarView.swift
//  feather
//
//  Created by samara on 5/17/24.
//  Copyright (c) 2024 Samara M (khcrysalis)
//

import SwiftUI

@available(iOS 18, *)
struct ExtendedTabbarView: View {
	@AppStorage("Feather.tabCustomization") var customization = TabViewCustomization()
	
	var body: some View {
		TabView {
			Tab(TabEnum.today.title, systemImage: TabEnum.today.icon) {
				TabEnum.view(for: .today)
			}
			
			Tab(TabEnum.games.title, systemImage: TabEnum.games.icon) {
				TabEnum.view(for: .games)
			}
			
			Tab(TabEnum.sources.title, systemImage: TabEnum.sources.icon) {
				TabEnum.view(for: .sources)
			}
			
			Tab(TabEnum.library.title, systemImage: TabEnum.library.icon) {
				TabEnum.view(for: .library)
			}
			
			Tab(TabEnum.search.title, systemImage: TabEnum.search.icon, role: .search) {
				TabEnum.view(for: .search)
			}
		}
		.tabViewStyle(.sidebarAdaptable)
		.tabViewCustomization($customization)
		.environment(\.layoutDirection, .rightToLeft)
	}
}
