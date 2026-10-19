//
//  SourcesView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews
import NukeUI
import UIKit

// MARK: - Unified App Store Item & Smart Category Classifier
struct AppStoreAppItem: Identifiable, Hashable {
	let id: String
	let sourceURL: URL?
	let repository: ASRepository
	let app: ASRepository.App
	
	var category: AppStoreCategory {
		AppStoreCategory.classify(app: app)
	}
	
	var allScreenshots: [URL] {
		if let urls = app.screenshotURLs, !urls.isEmpty {
			return urls
		}
		if let iphone = app.screenshots?.iPhone, !iphone.isEmpty {
			return iphone
		}
		return []
	}
}

enum AppStoreCategory: String, CaseIterable, Identifiable {
	case all = "الكل"
	case social = "التواصل الاجتماعي"
	case games = "الألعاب"
	case photoVideo = "التصميم والمونتاج"
	case utilities = "الأدوات والنظام"
	case entertainment = "الترفيه والمشاهدة"
	case other = "تطبيقات متنوعة"
	
	var id: String { rawValue }
	
	var icon: String {
		switch self {
		case .all:           return "square.grid.2x2.fill"
		case .social:        return "bubble.left.and.bubble.right.fill"
		case .games:         return "gamecontroller.fill"
		case .photoVideo:    return "wand.and.stars"
		case .utilities:     return "wrench.and.screwdriver.fill"
		case .entertainment: return "play.tv.fill"
		case .other:         return "app.badge.fill"
		}
	}
	
	var gradientColors: [Color] {
		switch self {
		case .all:           return [Color.blue, Color.indigo]
		case .social:        return [Color(red: 0.05, green: 0.45, blue: 0.95), Color.cyan]
		case .games:         return [Color.purple, Color.indigo]
		case .photoVideo:    return [Color.pink, Color.orange]
		case .utilities:     return [Color.teal, Color.green]
		case .entertainment: return [Color.red, Color.orange]
		case .other:         return [Color.indigo, Color.blue]
		}
	}
	
	static var browsableCategories: [AppStoreCategory] {
		[.social, .games, .photoVideo, .utilities, .entertainment, .other]
	}
	
	static func classify(app: ASRepository.App) -> AppStoreCategory {
		let haystack = [
			app.name ?? "",
			app.id ?? "",
			app.category ?? "",
			app.subtitle ?? "",
			app.localizedDescription ?? ""
		].joined(separator: " ").lowercased()
		
		let socialKeys = ["instagram", "whatsapp", "tiktok", "youtube", "snapchat", "twitter", "telegram", "facebook", "discord", "messenger", "reddit", "threads", "watusi", "uplus", "bh", "rocket", "انستقرام", "واتس", "تيك توك", "يوتيوب", "سناب", "تليجرام", "تويتر", "تواصل"]
		if socialKeys.contains(where: { haystack.contains($0) }) { return .social }
		
		let gameKeys = ["game", "pubg", "pool", "8ball", "clash", "roblox", "minecraft", "gta", "fifa", "pes", "cod", "freefire", "brawl", "fortnite", "car", "racing", "chess", "ludo", "ببجي", "لعبة", "العاب", "كلاش", "بلياردو"]
		if gameKeys.contains(where: { haystack.contains($0) }) { return .games }
		
		let photoKeys = ["capcut", "lightroom", "picsart", "inshot", "vn", "videostar", "alight", "photoshop", "canva", "remini", "editor", "photo", "video", "camera", "تصميم", "مونتاج", "صور", "فيديو"]
		if photoKeys.contains(where: { haystack.contains($0) }) { return .photoVideo }
		
		let utilKeys = ["filza", "esign", "feather", "scarlet", "troll", "vpn", "adblock", "cleaner", "files", "ipa", "cert", "sign", "terminal", "flex", "dl", "أدوات", "ملفات", "توقيع"]
		if utilKeys.contains(where: { haystack.contains($0) }) { return .utilities }
		
		let mediaKeys = ["movie", "tv", "anime", "shahid", "netflix", "spotify", "music", "stream", "drama", "iqtv", "cinema", "ostora", "افلام", "مسلسلات", "انمي", "تلفزيون", "موسيقى", "مشاهدة"]
		if mediaKeys.contains(where: { haystack.contains($0) }) { return .entertainment }
		
		return .other
	}
}

// MARK: - Helper Extraction from SourcesViewModel
extension SourcesViewModel {
	func allAppItems(from fetchedSources: FetchedResults<AltSource>) -> [AppStoreAppItem] {
		var items: [AppStoreAppItem] = []
		var seenIDs = Set<String>()
		
		for source in fetchedSources {
			guard let repo = sources[source] else { continue }
			for app in repo.apps {
				let uniqueKey = "\(app.id ?? app.currentName)_\(source.sourceURL?.absoluteString ?? "")"
				if !seenIDs.contains(uniqueKey) {
					seenIDs.insert(uniqueKey)
					items.append(
						AppStoreAppItem(
							id: uniqueKey,
							sourceURL: source.sourceURL,
							repository: repo,
							app: app
						)
					)
				}
			}
		}
		return items
	}
}

// MARK: - 1. TODAY VIEW (صفحة اليوم - App Store Today)
struct AppStoreTodayView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@State private var isAddingSource = false
	@State private var isManagingSources = false
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	private var allApps: [AppStoreAppItem] {
		viewModel.allAppItems(from: _sources)
	}
	
	private var featuredHeroApps: [AppStoreAppItem] {
		Array(allApps.prefix(4))
	}
	
	private var dailyListApps: [AppStoreAppItem] {
		Array(allApps.dropFirst(4).prefix(5))
	}
	
	private var recentApps: [AppStoreAppItem] {
		let sorted = allApps.sorted {
			($0.app.currentDate?.date ?? .distantPast) > ($1.app.currentDate?.date ?? .distantPast)
		}
		return Array(sorted.prefix(6))
	}
	
	private var arabicDateString: String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "ar")
		formatter.dateFormat = "EEEE، d MMMM"
		return formatter.string(from: Date())
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				VStack(alignment: .leading, spacing: 24) {
					// Top App Store Today Header
					HStack(alignment: .bottom) {
						VStack(alignment: .leading, spacing: 4) {
							Text(arabicDateString.uppercased())
								.font(.caption.weight(.bold))
								.foregroundStyle(.secondary)
							Text("اليوم")
								.font(.system(size: 34, weight: .bold))
						}
						Spacer()
						HStack(spacing: 12) {
							Button {
								isManagingSources = true
							} label: {
								Image(systemName: "globe.desk.fill")
									.font(.system(size: 18, weight: .semibold))
									.foregroundStyle(.primary)
									.frame(width: 38, height: 38)
									.background(Color(.secondarySystemGroupedBackground), in: Circle())
							}
							
							Button {
								isAddingSource = true
							} label: {
								Image(systemName: "plus")
									.font(.system(size: 18, weight: .bold))
									.foregroundStyle(.white)
									.frame(width: 38, height: 38)
									.background(Color.accentColor, in: Circle())
							}
						}
					}
					.padding(.horizontal, 20)
					.padding(.top, 10)
					
					if allApps.isEmpty {
						AppStoreEmptyStateView(
							isLoading: !viewModel.isFinished,
							onAddSource: { isAddingSource = true }
						)
						.padding(.horizontal, 20)
						.padding(.top, 40)
					} else {
						// Hero Featured Cards
						ForEach(Array(featuredHeroApps.enumerated()), id: \.element.id) { index, item in
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: item.sourceURL,
									source: item.repository,
									app: item.app
								)
							} label: {
								TodayHeroCardView(
									item: item,
									badgeText: index == 0 ? "تطبيق اليوم المميز" : (index == 1 ? "اختيار المحررين" : "موصى به لك")
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 20)
						}
						
						// The Daily List Card (قائمة اليوم)
						if !dailyListApps.isEmpty {
							TodayListCardView(
								subtitle: "قائمة اليوم المختارة",
								title: "تطبيقات أساسية لا غنى عنها",
								items: dailyListApps
							)
							.padding(.horizontal, 20)
						}
						
						// Latest Releases Card
						if !recentApps.isEmpty {
							TodayListCardView(
								subtitle: "تحديثات المتجر",
								title: "أحدث الإصدارات المضافة",
								items: recentApps
							)
							.padding(.horizontal, 20)
						}
					}
				}
				.padding(.bottom, 32)
			}
			.background(Color(.systemGroupedBackground).ignoresSafeArea())
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
			.sheet(isPresented: $isAddingSource) {
				SourcesAddView()
			}
			.sheet(isPresented: $isManagingSources) {
				SourcesManageSheetView(sources: _sources, viewModel: viewModel)
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}

// MARK: - 2. APPS & CATEGORIES VIEW (تبويب التطبيقات - SourcesView)
struct SourcesView: View {
	@StateObject var viewModel = SourcesViewModel.shared
	@State private var _isAddingPresenting = false
	@State private var _isManagingSources = false
	@State private var _selectedCategory: AppStoreCategory = .all
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	private var allApps: [AppStoreAppItem] {
		viewModel.allAppItems(from: _sources)
	}
	
	private var filteredApps: [AppStoreAppItem] {
		if _selectedCategory == .all {
			return allApps
		}
		return allApps.filter { $0.category == _selectedCategory }
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				VStack(alignment: .leading, spacing: 22) {
					// Category Filter Pills
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 10) {
							ForEach(AppStoreCategory.allCases) { category in
								Button {
									withAnimation(.snappy) {
										_selectedCategory = category
									}
								} label: {
									HStack(spacing: 6) {
										Image(systemName: category.icon)
											.font(.system(size: 13, weight: .semibold))
										Text(category.rawValue)
											.font(.subheadline.weight(.semibold))
									}
									.padding(.horizontal, 14)
									.padding(.vertical, 8)
									.foregroundStyle(_selectedCategory == category ? .white : .primary)
									.background(
										Capsule(style: .continuous)
											.fill(_selectedCategory == category ? Color.accentColor : Color(.secondarySystemGroupedBackground))
									)
								}
								.buttonStyle(.plain)
							}
						}
						.padding(.horizontal, 20)
					}
					.padding(.top, 6)
					
					if allApps.isEmpty {
						AppStoreEmptyStateView(
							isLoading: !viewModel.isFinished,
							onAddSource: { _isAddingPresenting = true }
						)
						.padding(.horizontal, 20)
						.padding(.top, 30)
					} else if _selectedCategory == .all {
						// Top Featured Banner Carousel
						ScrollView(.horizontal, showsIndicators: false) {
							LazyHStack(spacing: 16) {
								ForEach(Array(allApps.prefix(6))) { item in
									NavigationLink {
										SourceAppsDetailView(
											sourceURL: item.sourceURL,
											source: item.repository,
											app: item.app
										)
									} label: {
										AppStoreFeaturedBannerCard(item: item)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 20)
						}
						
						Divider().padding(.horizontal, 20)
						
						// Top Popular 3-Row Grid
						AppStoreHorizontalThreeRowSection(
							title: "الأكثر شعبية",
							subtitle: "أفضل التطبيقات المختارة من مصادرك",
							items: Array(allApps.prefix(15))
						)
						
						// Category Sections
						ForEach(AppStoreCategory.browsableCategories) { category in
							let catApps = allApps.filter { $0.category == category }
							if !catApps.isEmpty {
								Divider().padding(.horizontal, 20)
								AppStoreHorizontalThreeRowSection(
									title: category.rawValue,
									subtitle: "تصفح أحدث تطبيقات \(category.rawValue)",
									items: Array(catApps.prefix(12)),
									categoryLink: category,
									allCategoryApps: catApps
								)
							}
						}
						
						Divider().padding(.horizontal, 20)
						
						// Active Repositories Section
						VStack(alignment: .leading, spacing: 12) {
							HStack {
								Text("المصادر المضافة (\(_sources.count))")
									.font(.title3.weight(.bold))
								Spacer()
								Button("إدارة المصادر") {
									_isManagingSources = true
								}
								.font(.subheadline.weight(.semibold))
							}
							.padding(.horizontal, 20)
							
							VStack(spacing: 10) {
								ForEach(_sources) { source in
									NavigationLink {
										SourceAppsView(object: [source], viewModel: viewModel)
									} label: {
										HStack {
											SourcesCellView(source: source)
											Spacer()
											Image(systemName: "chevron.left")
												.font(.caption.weight(.bold))
												.foregroundStyle(.tertiary)
										}
										.padding(14)
										.background(
											RoundedRectangle(cornerRadius: 16, style: .continuous)
												.fill(Color(.secondarySystemGroupedBackground))
										)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 20)
						}
					} else {
						// Filtered Single Category List
						VStack(alignment: .leading, spacing: 12) {
							HStack {
								Label(_selectedCategory.rawValue, systemImage: _selectedCategory.icon)
									.font(.title3.weight(.bold))
								Spacer()
								Text("\(filteredApps.count) تطبيق")
									.font(.subheadline)
									.foregroundStyle(.secondary)
							}
							.padding(.horizontal, 20)
							
							LazyVStack(spacing: 12) {
								ForEach(filteredApps) { item in
									NavigationLink {
										SourceAppsDetailView(
											sourceURL: item.sourceURL,
											source: item.repository,
											app: item.app
										)
									} label: {
										AppStoreRowCardView(item: item)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 20)
						}
					}
				}
				.padding(.bottom, 30)
			}
			.background(Color(.systemGroupedBackground).ignoresSafeArea())
			.navigationTitle("التطبيقات")
			.toolbar {
				ToolbarItemGroup(placement: .topBarTrailing) {
					Button {
						_isManagingSources = true
					} label: {
						Image(systemName: "globe.desk")
					}
					
					Button {
						_isAddingPresenting = true
					} label: {
						Image(systemName: "plus.circle.fill")
					}
				}
			}
			.refreshable {
				await viewModel.fetchSources(_sources, refresh: true)
			}
			.sheet(isPresented: $_isAddingPresenting) {
				SourcesAddView()
			}
			.sheet(isPresented: $_isManagingSources) {
				SourcesManageSheetView(sources: _sources, viewModel: viewModel)
			}
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}

// MARK: - 3. SEARCH VIEW (تبويب البحث والفئات - App Store Search)
struct AppStoreSearchView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@State private var searchText = ""
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>
	
	private let discoverTags = [
		"YouTube", "Instagram", "TikTok", "WhatsApp",
		"Snapchat", "PUBG", "CapCut", "Filza", "Twitter"
	]
	
	private var allApps: [AppStoreAppItem] {
		viewModel.allAppItems(from: _sources)
	}
	
	private var searchResults: [AppStoreAppItem] {
		let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return [] }
		return allApps.filter { item in
			item.app.currentName.localizedCaseInsensitiveContains(q) ||
			(item.app.id?.localizedCaseInsensitiveContains(q) ?? false) ||
			(item.app.developer?.localizedCaseInsensitiveContains(q) ?? false) ||
			(item.app.currentDescription?.localizedCaseInsensitiveContains(q) ?? false) ||
			item.category.rawValue.localizedCaseInsensitiveContains(q)
		}
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					VStack(alignment: .leading, spacing: 28) {
						// Discover Section (اكتشف)
						VStack(alignment: .leading, spacing: 14) {
							Text("اكتشف")
								.font(.title2.weight(.bold))
								.padding(.horizontal, 20)
							
							LazyVGrid(
								columns: [GridItem(.flexible()), GridItem(.flexible())],
								alignment: .leading,
								spacing: 10
							) {
								ForEach(discoverTags, id: \.self) { tag in
									Button {
										searchText = tag
									} label: {
										HStack(spacing: 8) {
											Image(systemName: "magnifyingglass")
												.font(.subheadline.weight(.semibold))
												.foregroundStyle(Color.accentColor)
											Text(tag)
												.font(.body.weight(.medium))
												.foregroundStyle(Color.accentColor)
												.lineLimit(1)
											Spacer()
										}
										.padding(.vertical, 10)
										.padding(.horizontal, 12)
										.background(
											RoundedRectangle(cornerRadius: 12, style: .continuous)
												.fill(Color(.secondarySystemGroupedBackground))
										)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 20)
						}
						
						// Browse Categories Grid (تصفح الفئات)
						VStack(alignment: .leading, spacing: 14) {
							Text("تصفح الفئات")
								.font(.title2.weight(.bold))
								.padding(.horizontal, 20)
							
							LazyVGrid(
								columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
								spacing: 14
							) {
								ForEach(AppStoreCategory.browsableCategories) { category in
									let categoryApps = allApps.filter { $0.category == category }
									NavigationLink {
										AppStoreCategoryDetailView(
											category: category,
											items: categoryApps
										)
									} label: {
										ZStack(alignment: .bottomLeading) {
											LinearGradient(
												colors: category.gradientColors,
												startPoint: .topLeading,
												endPoint: .bottomTrailing
											)
											
											Image(systemName: category.icon)
												.font(.system(size: 46, weight: .bold))
												.foregroundStyle(.white.opacity(0.22))
												.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
												.padding(12)
											
											VStack(alignment: .leading, spacing: 2) {
												Text(category.rawValue)
													.font(.headline.weight(.bold))
													.foregroundStyle(.white)
													.lineLimit(1)
												Text("\(categoryApps.count) تطبيق")
													.font(.caption2.weight(.medium))
													.foregroundStyle(.white.opacity(0.85))
											}
											.padding(14)
										}
										.frame(height: 96)
										.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 20)
						}
					}
					.padding(.top, 10)
					.padding(.bottom, 30)
				} else {
					// Search Results with Screenshots
					LazyVStack(spacing: 16) {
						if searchResults.isEmpty {
							VStack(spacing: 12) {
								Image(systemName: "magnifyingglass")
									.font(.system(size: 44))
									.foregroundStyle(.secondary)
								Text("لا توجد نتائج لـ \"\(searchText)\"")
									.font(.headline)
								Text("جرب البحث باسم التطبيق باللغة الإنجليزية أو اسم الحزمة.")
									.font(.subheadline)
									.foregroundStyle(.secondary)
									.multilineTextAlignment(.center)
							}
							.padding(.top, 60)
							.padding(.horizontal, 30)
						} else {
							ForEach(searchResults) { item in
								NavigationLink {
									SourceAppsDetailView(
										sourceURL: item.sourceURL,
										source: item.repository,
										app: item.app
									)
								} label: {
									AppStoreSearchResultCard(item: item)
								}
								.buttonStyle(.plain)
							}
						}
					}
					.padding(.horizontal, 20)
					.padding(.vertical, 12)
				}
			}
			.background(Color(.systemGroupedBackground).ignoresSafeArea())
			.navigationTitle("البحث")
			.searchable(
				text: $searchText,
				placement: .navigationBarDrawer(displayMode: .always),
				prompt: "الألعاب، التطبيقات، والمزيد"
			)
		}
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
		}
	}
}

// MARK: - Reusable App Store Components

// 1. Hero Card for Today View
struct TodayHeroCardView: View {
	let item: AppStoreAppItem
	let badgeText: String
	
	private var cardColor: Color {
		item.app.tintColor ?? item.repository.tintColor ?? Color.accentColor
	}
	
	var body: some View {
		ZStack(alignment: .bottom) {
			// Background Gradient + Decorative Icon
			LinearGradient(
				colors: [cardColor.opacity(0.9), cardColor.opacity(0.55), Color.black.opacity(0.85)],
				startPoint: .topLeading,
				endPoint: .bottomTrailing
			)
			.overlay {
				if let iconURL = item.app.iconURL {
					LazyImage(url: iconURL) { state in
						if let image = state.image {
							image
								.resizable()
								.scaledToFill()
								.frame(width: 220, height: 220)
								.blur(radius: 28)
								.opacity(0.35)
						}
					}
				}
			}
			
			// Top Headlines & Center App Icon
			VStack(alignment: .leading, spacing: 12) {
				Text(badgeText.uppercased())
					.font(.caption.weight(.heavy))
					.foregroundStyle(.white.opacity(0.85))
					.padding(.horizontal, 10)
					.padding(.vertical, 5)
					.background(.ultraThinMaterial, in: Capsule())
				
				Text(item.app.currentName)
					.font(.system(size: 28, weight: .bold))
					.foregroundStyle(.white)
					.lineLimit(2)
				
				Text(item.app.currentDescription ?? item.repository.name ?? "متاح للتحميل والتوقيع المباشر")
					.font(.subheadline)
					.foregroundStyle(.white.opacity(0.85))
					.lineLimit(2)
				
				Spacer()
				
				// Bottom Frosted App Bar
				HStack(spacing: 12) {
					AppStoreIconView(url: item.app.iconURL, size: 50)
					
					VStack(alignment: .leading, spacing: 2) {
						Text(item.app.currentName)
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.white)
							.lineLimit(1)
						Text(item.category.rawValue)
							.font(.caption)
							.foregroundStyle(.white.opacity(0.75))
							.lineLimit(1)
					}
					
					Spacer()
					
					AppStoreGetButton(app: item.app, isLightStyle: true)
				}
				.padding(14)
				.background(.ultraThinMaterial)
			}
			.padding(.top, 20)
			.padding(.horizontal, 20)
		}
		.frame(height: 350)
		.clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
		.shadow(color: .black.opacity(0.15), radius: 14, x: 0, y: 8)
	}
}

// 2. Daily List Card for Today View
struct TodayListCardView: View {
	let subtitle: String
	let title: String
	let items: [AppStoreAppItem]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 16) {
			VStack(alignment: .leading, spacing: 4) {
				Text(subtitle.uppercased())
					.font(.caption.weight(.bold))
					.foregroundStyle(.secondary)
				Text(title)
					.font(.title2.weight(.bold))
					.foregroundStyle(.primary)
			}
			
			VStack(spacing: 14) {
				ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
					NavigationLink {
						SourceAppsDetailView(
							sourceURL: item.sourceURL,
							source: item.repository,
							app: item.app
						)
					} label: {
						HStack(spacing: 12) {
							AppStoreIconView(url: item.app.iconURL, size: 54)
							
							VStack(alignment: .leading, spacing: 3) {
								Text(item.app.currentName)
									.font(.body.weight(.semibold))
									.foregroundStyle(.primary)
									.lineLimit(1)
								Text(item.app.currentDescription ?? item.category.rawValue)
									.font(.caption)
									.foregroundStyle(.secondary)
									.lineLimit(1)
							}
							
							Spacer()
							
							AppStoreGetButton(app: item.app)
						}
					}
					.buttonStyle(.plain)
					
					if index < items.count - 1 {
						Divider().padding(.leading, 66)
					}
				}
			}
		}
		.padding(20)
		.background(
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.fill(Color(.secondarySystemGroupedBackground))
		)
		.shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)
	}
}

// 3. Featured Banner Card for Apps Tab
struct AppStoreFeaturedBannerCard: View {
	let item: AppStoreAppItem
	
	private var bannerColor: Color {
		item.app.tintColor ?? item.repository.tintColor ?? Color.accentColor
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("تطبيق مميز")
				.font(.caption2.weight(.bold))
				.foregroundStyle(Color.accentColor)
			
			Text(item.app.currentName)
				.font(.title3.weight(.bold))
				.foregroundStyle(.primary)
				.lineLimit(1)
			
			Text(item.app.currentDescription ?? item.category.rawValue)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.lineLimit(1)
			
			ZStack(alignment: .bottom) {
				LinearGradient(
					colors: [bannerColor.opacity(0.85), bannerColor.opacity(0.45)],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
				
				HStack(spacing: 12) {
					AppStoreIconView(url: item.app.iconURL, size: 56)
					
					VStack(alignment: .leading, spacing: 2) {
						Text(item.app.currentName)
							.font(.subheadline.weight(.bold))
							.foregroundStyle(.white)
							.lineLimit(1)
						Text(item.repository.name ?? item.category.rawValue)
							.font(.caption)
							.foregroundStyle(.white.opacity(0.8))
							.lineLimit(1)
					}
					
					Spacer()
					
					AppStoreGetButton(app: item.app, isLightStyle: true)
				}
				.padding(14)
				.background(.ultraThinMaterial)
			}
			.frame(height: 175)
			.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
		}
		.frame(width: min(UIScreen.main.bounds.width - 48, 340))
	}
}

// 4. 3-Row Horizontal Grid Section
struct AppStoreHorizontalThreeRowSection: View {
	let title: String
	let subtitle: String
	let items: [AppStoreAppItem]
	var categoryLink: AppStoreCategory? = nil
	var allCategoryApps: [AppStoreAppItem] = []
	
	private let rows = [
		GridItem(.fixed(72), spacing: 10),
		GridItem(.fixed(72), spacing: 10),
		GridItem(.fixed(72), spacing: 10)
	]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.title3.weight(.bold))
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				if let categoryLink {
					NavigationLink("عرض الكل") {
						AppStoreCategoryDetailView(category: categoryLink, items: allCategoryApps)
					}
					.font(.subheadline.weight(.semibold))
				}
			}
			.padding(.horizontal, 20)
			
			ScrollView(.horizontal, showsIndicators: false) {
				LazyHGrid(rows: rows, spacing: 16) {
					ForEach(items) { item in
						NavigationLink {
							SourceAppsDetailView(
								sourceURL: item.sourceURL,
								source: item.repository,
								app: item.app
							)
						} label: {
							HStack(spacing: 12) {
								AppStoreIconView(url: item.app.iconURL, size: 58)
								
								VStack(alignment: .leading, spacing: 3) {
									Text(item.app.currentName)
										.font(.subheadline.weight(.semibold))
										.foregroundStyle(.primary)
										.lineLimit(1)
									Text(item.app.currentDescription ?? item.category.rawValue)
										.font(.caption)
										.foregroundStyle(.secondary)
										.lineLimit(1)
									if let version = item.app.currentVersion {
										Text("v\(version)")
											.font(.caption2)
											.foregroundStyle(.tertiary)
									}
								}
								
								Spacer()
								
								AppStoreGetButton(app: item.app)
							}
							.frame(width: min(UIScreen.main.bounds.width - 56, 310))
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal, 20)
			}
		}
	}
}

// 5. Search Result Card with Screenshots
struct AppStoreSearchResultCard: View {
	let item: AppStoreAppItem
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 12) {
				AppStoreIconView(url: item.app.iconURL, size: 60)
				
				VStack(alignment: .leading, spacing: 3) {
					Text(item.app.currentName)
						.font(.body.weight(.semibold))
						.foregroundStyle(.primary)
						.lineLimit(1)
					Text(item.app.currentDescription ?? item.category.rawValue)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
					HStack(spacing: 8) {
						if let version = item.app.currentVersion {
							Text("الإصدار \(version)")
								.font(.caption2.weight(.medium))
								.foregroundStyle(.secondary)
						}
						if let repoName = item.repository.name {
							Text("• \(repoName)")
								.font(.caption2)
								.foregroundStyle(.tertiary)
								.lineLimit(1)
						}
					}
				}
				
				Spacer()
				
				AppStoreGetButton(app: item.app)
			}
			
			// Screenshots Preview (up to 3 screenshots like real App Store)
			if !item.allScreenshots.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 10) {
						ForEach(Array(item.allScreenshots.prefix(3)), id: \.self) { screenshotURL in
							LazyImage(url: screenshotURL) { state in
								if let image = state.image {
									image
										.resizable()
										.scaledToFill()
								} else {
									RoundedRectangle(cornerRadius: 12, style: .continuous)
										.fill(Color(.tertiarySystemFill))
								}
							}
							.frame(width: 108, height: 192)
							.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
							.overlay(
								RoundedRectangle(cornerRadius: 12, style: .continuous)
									.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
							)
						}
					}
				}
			}
		}
		.padding(16)
		.background(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(Color(.secondarySystemGroupedBackground))
		)
	}
}

// 6. Standard App Row Card
struct AppStoreRowCardView: View {
	let item: AppStoreAppItem
	
	var body: some View {
		HStack(spacing: 12) {
			AppStoreIconView(url: item.app.iconURL, size: 58)
			
			VStack(alignment: .leading, spacing: 3) {
				Text(item.app.currentName)
					.font(.body.weight(.semibold))
					.foregroundStyle(.primary)
					.lineLimit(1)
				Text(item.app.currentDescription ?? item.repository.name ?? item.category.rawValue)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
				if let version = item.app.currentVersion {
					Text("v\(version)")
						.font(.caption2)
						.foregroundStyle(.tertiary)
				}
			}
			
			Spacer()
			
			AppStoreGetButton(app: item.app)
		}
		.padding(14)
		.background(
			RoundedRectangle(cornerRadius: 18, style: .continuous)
				.fill(Color(.secondarySystemGroupedBackground))
		)
	}
}

// 7. Category Detail View
struct AppStoreCategoryDetailView: View {
	let category: AppStoreCategory
	let items: [AppStoreAppItem]
	
	var body: some View {
		ScrollView(.vertical, showsIndicators: false) {
			LazyVStack(spacing: 12) {
				ForEach(items) { item in
					NavigationLink {
						SourceAppsDetailView(
							sourceURL: item.sourceURL,
							source: item.repository,
							app: item.app
						)
					} label: {
						AppStoreRowCardView(item: item)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(20)
		}
		.background(Color(.systemGroupedBackground).ignoresSafeArea())
		.navigationTitle(category.rawValue)
	}
}

// 8. Interactive App Store "حصول / GET" Button
struct AppStoreGetButton: View {
	let app: ASRepository.App
	var isLightStyle: Bool = false
	@State private var didStartDownload = false
	
	var body: some View {
		Button {
			guard let url = app.currentDownloadUrl else { return }
			UIImpactFeedbackGenerator(style: .medium).impactOccurred()
			withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
				didStartDownload = true
			}
			_ = DownloadManager.shared.startDownload(from: url)
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
				withAnimation {
					didStartDownload = false
				}
			}
		} label: {
			Group {
				if didStartDownload {
					Image(systemName: "arrow.down.circle.fill")
						.font(.system(size: 16, weight: .bold))
				} else {
					Text("حصول")
						.font(.subheadline.weight(.bold))
				}
			}
			.foregroundStyle(isLightStyle ? .white : Color.accentColor)
			.padding(.horizontal, 18)
			.padding(.vertical, 7)
			.background(
				Capsule(style: .continuous)
					.fill(isLightStyle ? Color.white.opacity(0.24) : Color.accentColor.opacity(0.14))
			)
		}
		.buttonStyle(.plain)
	}
}

// 9. App Icon View with App Store Squircle Border
struct AppStoreIconView: View {
	let url: URL?
	let size: CGFloat
	
	var body: some View {
		Group {
			if let url {
				LazyImage(url: url) { state in
					if let image = state.image {
						image
							.resizable()
							.scaledToFill()
					} else {
						placeholder
					}
				}
			} else {
				placeholder
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
				.stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
		)
	}
	
	private var placeholder: some View {
		RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
			.fill(Color(.tertiarySystemFill))
			.overlay {
				Image(systemName: "app.fill")
					.foregroundStyle(.secondary)
			}
	}
}

// 10. Empty State View
struct AppStoreEmptyStateView: View {
	let isLoading: Bool
	let onAddSource: () -> Void
	
	var body: some View {
		VStack(spacing: 16) {
			if isLoading {
				ProgressView()
					.scaleEffect(1.3)
				Text("جاري تحميل المتجر والتطبيقات...")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				Image(systemName: "bag.badge.plus")
					.font(.system(size: 48))
					.foregroundStyle(Color.accentColor)
				Text("لا توجد مصادر مضافة بعد")
					.font(.title3.weight(.bold))
				Text("أضف مصدر (Repo) لعرض التطبيقات والألعاب بتصميم متجر التطبيقات.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
				Button(action: onAddSource) {
					Text("إضافة مصدر الآن")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 24)
						.padding(.vertical, 12)
						.background(Color.accentColor, in: Capsule())
				}
			}
		}
		.frame(maxWidth: .infinity)
		.padding(32)
		.background(
			RoundedRectangle(cornerRadius: 24, style: .continuous)
				.fill(Color(.secondarySystemGroupedBackground))
		)
	}
}

// 11. Sources Management Sheet
struct SourcesManageSheetView: View {
	@Environment(\.dismiss) private var dismiss
	let sources: FetchedResults<AltSource>
	@ObservedObject var viewModel: SourcesViewModel
	@State private var isAddingSource = false
	
	var body: some View {
		NavigationStack {
			List {
				Section {
					NavigationLink {
						SourceAppsView(object: Array(sources), viewModel: viewModel)
					} label: {
						HStack(spacing: 14) {
							Image("Repositories").appIconStyle()
							NBTitleWithSubtitleView(
								title: .localized("All Repositories"),
								subtitle: .localized("See all apps from your sources")
							)
						}
					}
				}
				
				Section("المصادر النشطة (\(sources.count))") {
					ForEach(sources) { source in
						NavigationLink {
							SourceAppsView(object: [source], viewModel: viewModel)
						} label: {
							SourcesCellView(source: source)
						}
					}
				}
			}
			.navigationTitle("إدارة المصادر")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button("تم") { dismiss() }
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						isAddingSource = true
					} label: {
						Image(systemName: "plus")
					}
				}
			}
			.sheet(isPresented: $isAddingSource) {
				SourcesAddView()
			}
		}
	}
}
