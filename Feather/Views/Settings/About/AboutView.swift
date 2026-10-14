//
//  AboutView.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import SwiftUI
import NimbleViews
import NimbleJSON

// MARK: - Extension: Model
extension AboutView {
	struct CreditsModel: Codable, Hashable {
		let name: String
		let desc: String
		let icon: String
		let url: String
	}
}

// MARK: - View
struct AboutView: View {
	@State private var _credits: [CreditsModel] = [
		.init(
			name: "IPA BLACK",
			desc: "مطور ios",
			icon: "https://up6.cc/2026/10/179193779451191.jpeg",
			url: "https://t.me/hl00ss"
		)
	]
	
	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack {
					// سيتم استبدال الأيقونة هنا عند إرسال الصورة
					FRAppIconView(size: 72)
					
					Text("X-SIGN")
						.font(.largeTitle)
						.bold()
						.foregroundStyle(Color.accentColor)
					
					HStack(spacing: 4) {
						Text(.localized("Version"))
						Text("0.1")
					}
					.font(.footnote)
					.foregroundStyle(.secondary)
				}
			}
			.frame(maxWidth: .infinity)
			.listRowBackground(EmptyView())
			
			NBSection(.localized("Credits")) {
				ForEach(_credits, id: \.url) { credit in
					_credit(
						name: credit.name,
						desc: credit.desc,
						icon: credit.icon,
						url: credit.url
					)
				}
				.transition(.slide)
			}
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	@ViewBuilder
	private func _credit(
		name: String,
		desc: String,
		icon: String,
		url: String
	) -> some View {
		Button {
			UIApplication.open(url)
		} label: {
			HStack {
				FRIconCellView(
					title: name,
					subtitle: desc,
					iconUrl: URL(string: icon)!,
					size: 45,
					isCircle: true
				)
				
				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
