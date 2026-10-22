//
//  TabbarView.swift
//  feather
//
//  Created by samara on 5/17/24.
//

import SwiftUI

struct TabbarView: View {
	@State private var selectedTab: TabEnum = .today
	
	var body: some View {
		TabView(selection: $selectedTab) {
			ForEach(TabEnum.defaultTabs, id: \.hashValue) { tab in
				TabEnum.view(for: tab)
					.tabItem {
						Label(tab.title, systemImage: tab.icon)
					}
					.tag(tab)
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
	}
}
