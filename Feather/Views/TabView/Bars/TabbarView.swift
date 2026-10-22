//
//  TabbarView.swift
//  feather
//
//  Created by samara on 5/17/24.
//

import SwiftUI

struct TabbarView: View {
	@Binding var selectedTab: TabEnum
	
	// تهيئة افتراضية لمنع أي خطأ في الملفات الأخرى التي تستدعي TabbarView() بدون وسائط
	init(selectedTab: Binding<TabEnum> = .constant(.today)) {
		self._selectedTab = selectedTab
	}
	
	var body: some View {
		HStack {
			ForEach(TabEnum.defaultTabs, id: \.self) { tab in
				Spacer()
				Button {
					selectedTab = tab
					UIImpactFeedbackGenerator(style: .light).impactOccurred()
				} label: {
					VStack(spacing: 4) {
						Image(systemName: tab.icon)
							.font(.system(size: 20, weight: selectedTab == tab ? .bold : .regular))
						Text(tab.title)
							.font(.system(size: 10, weight: selectedTab == tab ? .bold : .medium))
					}
					.foregroundStyle(selectedTab == tab ? Color.accentColor : Color.secondary)
				}
				.buttonStyle(.plain)
				Spacer()
			}
		}
		.padding(.vertical, 8)
		.background(.ultraThinMaterial)
	}
}
