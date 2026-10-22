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
import Nuke
import UIKit

// MARK: - Precomputed App Item (Zero Scroll CPU Overhead)
struct AppStoreAppItem: Identifiable, Hashable {
	let id: String
	let sourceURL: URL?
	let repository: ASRepository
	let app: ASRepository.App
	let category: AppStore2026Category
	let isGame: Bool
	let screenshots: [URL]
	
	init(id: String, sourceURL: URL?, repository: ASRepository, app: ASRepository.App) {
		self.id = id
		self.sourceURL = sourceURL
		self.repository = repository
		self.app = app
		let classified = AppStore2026Category.classify(app: app)
		self.category = classified
		self.isGame = classified.isGameCategory
		if let urls = app.screenshotURLs, !urls.isEmpty {
			self.screenshots = urls
		} else if let iphone = app.screenshots?.iPhone, !iphone.isEmpty {
			self.screenshots = iphone
		} else {
			self.screenshots = []
		}
	}
	
	static func == (lhs: AppStoreAppItem, rhs: AppStoreAppItem) -> Bool {
		lhs.id == rhs.id
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

// MARK: - High-Performance Store Cache Manager
@MainActor
final class AppStoreCacheManager: ObservableObject {
	static let shared = AppStoreCacheManager()
	
	@Published private(set) var allApps: [AppStoreAppItem] = []
	@Published private(set) var gamesList: [AppStoreAppItem] = []
	@Published private(set) var appsByCategory: [AppStore2026Category: [AppStoreAppItem]] = [:]
	
	private var lastSourceCount: Int = -1
	private var hasPerformedInitialFetch = false
	
	func ensureFetched(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
		if !hasPerformedInitialFetch || viewModel.sources.isEmpty {
			hasPerformedInitialFetch = true
			await viewModel.fetchSources(sources)
		}
		rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
	}
	
	func forceRefresh(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
		await viewModel.fetchSources(sources, refresh: true)
		lastSourceCount = -1
		rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
	}
	
	func rebuildCacheIfNeeded(sources: FetchedResults<AltSource>, repositoriesMap: [AltSource: ASRepository]) {
		let currentTotalApps = repositoriesMap.values.reduce(0) { $0 + $1.apps.count }
		guard currentTotalApps != lastSourceCount else { return }
		lastSourceCount = currentTotalApps
		
		var builtItems: [AppStoreAppItem] = []
		builtItems.reserveCapacity(currentTotalApps)
		var seenIDs = Set<String>()
		
		for source in sources {
			guard let repo = repositoriesMap[source] else { continue }
			let sourceStr = source.sourceURL?.absoluteString ?? ""
			for app in repo.apps {
				let key = "\(app.id ?? app.currentName)_\(sourceStr)"
				if seenIDs.insert(key).inserted {
					builtItems.append(
						AppStoreAppItem(
							id: key,
							sourceURL: source.sourceURL,
							repository: repo,
							app: app
						)
					)
				}
			}
		}
		
		let games = builtItems.filter { $0.isGame }
		let nonGames = builtItems.filter { !$0.isGame }
		
		var catMap: [AppStore2026Category: [AppStoreAppItem]] = [:]
		for cat in AppStore2026Category.allCases {
			switch cat {
			case .topApps:
				catMap[cat] = nonGames.isEmpty ? builtItems : nonGames
			case .topGames:
				catMap[cat] = games.isEmpty ? builtItems : games
			case .bestSellingApps:
				catMap[cat] = Array((nonGames.isEmpty ? builtItems : nonGames).reversed())
			case .bestSellingGames:
				catMap[cat] = Array((games.isEmpty ? builtItems : games).reversed())
			default:
				let matched = builtItems.filter { $0.category == cat }
				catMap[cat] = matched.isEmpty ? Array(builtItems.prefix(10)) : matched
			}
		}
		
		self.allApps = builtItems
		self.gamesList = games.isEmpty ? builtItems : games
		self.appsByCategory = catMap
	}
}

// MARK: - App Icon Provider (Loads Our App's Own Icon for the Top Avatar)
enum AppStoreAppIconProvider {
	static let cachedIcon: UIImage? = {
		if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
		   let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
		   let files = primary["CFBundleIconFiles"] as? [String],
		   let lastIcon = files.last,
		   let image = UIImage(named: lastIcon) {
			return image
		}
		if let image = UIImage(named: "AppIcon") {
			return image
		}
		return nil
	}()
}

// MARK: - Categories Enum
enum AppStore2026Category: String, CaseIterable, Identifiable {
	case topApps = "التطبيقات الأكثر تنزيلاً"
	case topGames = "الألعاب الأكثر تنزيلاً"
	case bestSellingApps = "التطبيقات الأكثر مبيعاً"
	case bestSellingGames = "الألعاب الأكثر مبيعاً"
	case social = "التواصل الاجتماعي"
	case devTools = "تطبيقات أدوات التطوير"
	case photoVideo = "صور وفيديو"
	case visualArts = "فنون بصرية"
	case productivity = "إنتاجية"
	case strategyGames = "ألعاب إستراتيجية"
	case pvpGames = "لاعب ضد لاعب"
	case casualGames = "ألعاب تسالي"
	case timePass = "تمضية وقت"
	case mediaReaders = "قارئات الوسائط"
	
	var id: String { rawValue }
	
	var isGameCategory: Bool {
		switch self {
		case .topGames, .bestSellingGames, .strategyGames, .pvpGames, .casualGames, .timePass:
			return true
		default:
			return false
		}
	}
	
	var sfSymbol: String {
		switch self {
		case .topApps:          return "star.fill"
		case .topGames:         return "trophy.fill"
		case .bestSellingApps:  return "crown.fill"
		case .bestSellingGames: return "medal.fill"
		case .social:           return "bubble.left.and.bubble.right.fill"
		case .devTools:         return "wrench.and.screwdriver.fill"
		case .photoVideo:       return "camera.fill"
		case .visualArts:       return "paintpalette.fill"
		case .productivity:     return "paperplane.fill"
		case .strategyGames:    return "flag.2.crossed.fill"
		case .pvpGames:         return "gamecontroller.fill"
		case .casualGames:      return "airplane.departure"
		case .timePass:         return "sparkles"
		case .mediaReaders:     return "book.pages.fill"
		}
	}
	
	var gradientColors: [Color] {
		switch self {
		case .topApps:
			return [Color(red: 0.44, green: 0.69, blue: 0.98), Color(red: 0.32, green: 0.56, blue: 0.92)]
		case .topGames:
			return [Color(red: 0.96, green: 0.69, blue: 0.45), Color(red: 0.92, green: 0.53, blue: 0.31)]
		case .bestSellingApps:
			return [Color(red: 0.52, green: 0.85, blue: 0.49), Color(red: 0.35, green: 0.75, blue: 0.38)]
		case .bestSellingGames:
			return [Color(red: 0.69, green: 0.62, blue: 0.98), Color(red: 0.56, green: 0.47, blue: 0.94)]
		case .social:
			return [Color(red: 0.68, green: 0.62, blue: 0.97), Color(red: 0.53, green: 0.45, blue: 0.93)]
		case .devTools:
			return [Color(red: 0.52, green: 0.82, blue: 0.95), Color(red: 0.38, green: 0.72, blue: 0.89)]
		case .photoVideo:
			return [Color(red: 0.94, green: 0.79, blue: 0.48), Color(red: 0.88, green: 0.68, blue: 0.34)]
		case .visualArts:
			return [Color(red: 0.55, green: 0.85, blue: 0.96), Color(red: 0.42, green: 0.75, blue: 0.90)]
		case .productivity:
			return [Color(red: 0.62, green: 0.75, blue: 0.96), Color(red: 0.48, green: 0.64, blue: 0.90)]
		case .strategyGames:
			return [Color(red: 0.54, green: 0.82, blue: 0.48), Color(red: 0.42, green: 0.72, blue: 0.38)]
		case .pvpGames:
			return [Color(red: 0.79, green: 0.56, blue: 0.98), Color(red: 0.68, green: 0.40, blue: 0.93)]
		case .casualGames:
			return [Color(red: 0.55, green: 0.82, blue: 0.95), Color(red: 0.42, green: 0.72, blue: 0.89)]
		case .timePass:
			return [Color(red: 0.54, green: 0.84, blue: 0.96), Color(red: 0.42, green: 0.75, blue: 0.90)]
		case .mediaReaders:
			return [Color(red: 0.96, green: 0.71, blue: 0.42), Color(red: 0.91, green: 0.58, blue: 0.27)]
		}
	}
	
	static func classify(app: ASRepository.App) -> AppStore2026Category {
		let haystack = "\(app.name ?? "") \(app.id ?? "") \(app.category ?? "")".lowercased()
		
		if haystack.contains("instagram") || haystack.contains("whatsapp") || haystack.contains("tiktok") || haystack.contains("snapchat") || haystack.contains("twitter") || haystack.contains("telegram") || haystack.contains("facebook") || haystack.contains("discord") || haystack.contains("watusi") || haystack.contains("bh") {
			return .social
		}
		if haystack.contains("pubg") || haystack.contains("pool") || haystack.contains("8ball") || haystack.contains("cod") || haystack.contains("brawl") || haystack.contains("clash") || haystack.contains("fifa") {
			return .pvpGames
		}
		if haystack.contains("game") || haystack.contains("roblox") || haystack.contains("minecraft") || haystack.contains("gta") || haystack.contains("subway") || haystack.contains("minion") || haystack.contains("sonic") || haystack.contains("car") {
			return .casualGames
		}
		if haystack.contains("capcut") || haystack.contains("lightroom") || haystack.contains("picsart") || haystack.contains("inshot") || haystack.contains("video") || haystack.contains("photo") || haystack.contains("camera") {
			return .photoVideo
		}
		if haystack.contains("canva") || haystack.contains("art") || haystack.contains("design") || haystack.contains("draw") {
			return .visualArts
		}
		if haystack.contains("filza") || haystack.contains("esign") || haystack.contains("feather") || haystack.contains("troll") || haystack.contains("vpn") || haystack.contains("ipa") || haystack.contains("cert") || haystack.contains("sign") {
			return .devTools
		}
		if haystack.contains("youtube") || haystack.contains("movie") || haystack.contains("tv") || haystack.contains("anime") || haystack.contains("spotify") || haystack.contains("music") {
			return .mediaReaders
		}
		return .productivity
	}
}

// MARK: - 1. TODAY VIEW (صفحة اليوم - 120FPS Smooth)
struct AppStoreTodayView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var showSettingsSheet = false
	@State private var showAddSourceSheet = false
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 22) {
					AppStore2026TopHeader(
						title: "اليوم",
						onSettingsTap: { showSettingsSheet = true },
						onAddSourceTap: { showAddSourceSheet = true }
					)
					
					if cache.allApps.isEmpty {
						AppStore2026EmptyState(
							isLoading: !viewModel.isFinished,
							onAddSource: { showAddSourceSheet = true }
						)
						.padding(.horizontal, 18)
						.padding(.top, 30)
					} else {
						if let firstHero = cache.allApps.first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: firstHero.sourceURL,
									source: firstHero.repository,
									app: firstHero.app
								)
							} label: {
								Today2026HeroCard(
									item: firstHero,
									tagText: "رائج الآن",
									headlineText: "العب فعاليات \(firstHero.app.currentName)"
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						if let secondSpotlight = cache.allApps.dropFirst().first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: secondSpotlight.sourceURL,
									source: secondSpotlight.repository,
									app: secondSpotlight.app
								)
							} label: {
								Today2026CenterIconBanner(item: secondSpotlight)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						let listItems = Array(cache.allApps.dropFirst(2).prefix(5))
						if !listItems.isEmpty {
							Today2026ListSectionCard(
								outerTitle: "واصل الركض!",
								outerSubtitle: "إلى متى يمكنك الصمود في هذه الألعاب والتطبيقات؟",
								innerCaption: "أفضل الاختيارات",
								innerTitle: "ركض بلا نهاية",
								items: listItems
							)
							.padding(.horizontal, 18)
						}
						
						if let thirdHero = cache.allApps.dropFirst(7).first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: thirdHero.sourceURL,
									source: thirdHero.repository,
									app: thirdHero.app
								)
							} label: {
								Today2026HeroCard(
									item: thirdHero,
									tagText: "اختيار المحررين",
									headlineText: "اكتشف ميزات \(thirdHero.app.currentName)"
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
					}
				}
				.padding(.bottom, 100)
			}
			.background(Color.black.ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
			.refreshable {
				await cache.forceRefresh(sources: _sources, viewModel: viewModel)
			}
			.sheet(isPresented: $showAddSourceSheet) {
				SourcesAddView()
			}
			.sheet(isPresented: $showSettingsSheet) {
				AppStore2026SettingsPopup(sources: _sources, viewModel: viewModel)
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
		.preferredColorScheme(.dark)
		.task {
			await cache.ensureFetched(sources: _sources, viewModel: viewModel)
		}
		.onChange(of: viewModel.sources.count) { _ in
			cache.rebuildCacheIfNeeded(sources: _sources, repositoriesMap: viewModel.sources)
		}
	}
}

// MARK: - 2. APPS VIEW (قسم التطبيقات - يعرض كل التطبيقات بسرعة 120FPS)
struct SourcesView: View {
	@StateObject var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var _isAddingPresenting = false
	@State private var _isSettingsPresenting = false
	@State private var _selectedCategoryFilter: String = "الكل"
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	private let quickFilters = [
		"الكل",
		"التواصل الاجتماعي",
		"صور وفيديو",
		"تطبيقات أدوات التطوير",
		"قارئات الوسائط",
		"الألعاب"
	]
	
	private var displayedAllApps: [AppStoreAppItem] {
		switch _selectedCategoryFilter {
		case "الكل":
			return cache.allApps
		case "الألعاب":
			return cache.gamesList
		default:
			return cache.allApps.filter { $0.category.rawValue == _selectedCategoryFilter }
		}
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 22) {
					AppStore2026TopHeader(
						title: "التطبيقات",
						onSettingsTap: { _isSettingsPresenting = true },
						onAddSourceTap: { _isAddingPresenting = true }
					)
					
					if cache.allApps.isEmpty {
						AppStore2026EmptyState(
							isLoading: !viewModel.isFinished,
							onAddSource: { _isAddingPresenting = true }
						)
						.padding(.horizontal, 18)
						.padding(.top, 30)
					} else {
						// 1. Fast Category Filter Pills
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								ForEach(quickFilters, id: \.self) { filter in
									Button {
										_selectedCategoryFilter = filter
									} label: {
										Text(filter)
											.font(.subheadline.weight(.bold))
											.foregroundStyle(_selectedCategoryFilter == filter ? .black : .white)
											.padding(.horizontal, 16)
											.padding(.vertical, 9)
											.background(
												Capsule(style: .continuous)
													.fill(_selectedCategoryFilter == filter ? Color.white : Color(white: 0.14))
											)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 18)
						}
						
						if _selectedCategoryFilter == "الكل" {
							// 2. Top Featured Banner Carousel
							ScrollView(.horizontal, showsIndicators: false) {
								LazyHStack(spacing: 16) {
									ForEach(Array(cache.allApps.prefix(5))) { item in
										NavigationLink {
											SourceAppsDetailView(
												sourceURL: item.sourceURL,
												source: item.repository,
												app: item.app
											)
										} label: {
											AppStore2026FeaturedBanner(item: item)
										}
										.buttonStyle(.plain)
									}
								}
								.padding(.horizontal, 18)
							}
							
							// 3. Horizontal 3-Row Section
							AppStore2026ThreeRowSection(
								title: "التطبيقات الأكثر تنزيلاً",
								subtitle: "تطبيقات لا غنى عنها على جهازك",
								items: Array(cache.allApps.prefix(15))
							)
						}
						
						// 4. All Apps Section Header
						HStack {
							VStack(alignment: .leading, spacing: 3) {
								Text(_selectedCategoryFilter == "الكل" ? "جميع التطبيقات" : _selectedCategoryFilter)
									.font(.system(size: 22, weight: .bold))
									.foregroundStyle(.white)
								Text("\(displayedAllApps.count) تطبيق متاح للتنزيل المباشر")
									.font(.footnote)
									.foregroundStyle(.secondary)
							}
							Spacer()
						}
						.padding(.horizontal, 18)
						.padding(.top, 4)
						
						// 5. Lazy All-Apps List (Only renders visible rows on screen -> Zero Lag!)
						ForEach(Array(displayedAllApps.enumerated()), id: \.element.id) { index, item in
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: item.sourceURL,
									source: item.repository,
									app: item.app
								)
							} label: {
								VStack(spacing: 0) {
									AppStore2026AppRow(
										item: item,
										useCloudIcon: index % 3 == 0
									)
									.padding(.horizontal, 18)
									.padding(.vertical, 8)
									
									Divider()
										.background(Color.white.opacity(0.08))
										.padding(.leading, 82)
										.padding(.trailing, 18)
								}
							}
							.buttonStyle(.plain)
						}
					}
				}
				.padding(.bottom, 100)
			}
			.background(Color.black.ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
			.refreshable {
				await cache.forceRefresh(sources: _sources, viewModel: viewModel)
			}
			.sheet(isPresented: $_isAddingPresenting) {
				SourcesAddView()
			}
			.sheet(isPresented: $_isSettingsPresenting) {
				AppStore2026SettingsPopup(sources: _sources, viewModel: viewModel)
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
		.preferredColorScheme(.dark)
		.task {
			await cache.ensureFetched(sources: _sources, viewModel: viewModel)
		}
	}
}

// MARK: - 3. GAMES VIEW (قسم الألعاب - 120FPS Smooth)
struct AppStoreGamesView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var showSettingsSheet = false
	@State private var showAddSourceSheet = false
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 24) {
					AppStore2026TopHeader(
						title: "الألعاب",
						onSettingsTap: { showSettingsSheet = true },
						onAddSourceTap: { showAddSourceSheet = true }
					)
					
					if cache.gamesList.isEmpty {
						AppStore2026EmptyState(
							isLoading: !viewModel.isFinished,
							onAddSource: { showAddSourceSheet = true }
						)
						.padding(.horizontal, 18)
						.padding(.top, 30)
					} else {
						if let heroGame = cache.gamesList.first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: heroGame.sourceURL,
									source: heroGame.repository,
									app: heroGame.app
								)
							} label: {
								Today2026HeroCard(
									item: heroGame,
									tagText: "رائج الآن",
									headlineText: "العب فعاليات \(heroGame.app.currentName)"
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						Today2026ListSectionCard(
							outerTitle: "واصل الركض!",
							outerSubtitle: "إلى متى يمكنك الصمود في هذه الألعاب؟",
							innerCaption: "أفضل الألعاب",
							innerTitle: "ركض بلا نهاية",
							items: Array(cache.gamesList.prefix(5))
						)
						.padding(.horizontal, 18)
						
						AppStore2026ThreeRowSection(
							title: "الألعاب الأكثر تنزيلاً",
							subtitle: "أقوى الألعاب المختارة لك",
							items: Array(cache.gamesList.prefix(15))
						)
					}
				}
				.padding(.bottom, 100)
			}
			.background(Color.black.ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
			.refreshable {
				await cache.forceRefresh(sources: _sources, viewModel: viewModel)
			}
			.sheet(isPresented: $showAddSourceSheet) {
				SourcesAddView()
			}
			.sheet(isPresented: $showSettingsSheet) {
				AppStore2026SettingsPopup(sources: _sources, viewModel: viewModel)
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
		.preferredColorScheme(.dark)
		.task {
			await cache.ensureFetched(sources: _sources, viewModel: viewModel)
		}
	}
}

// MARK: - 4. SEARCH VIEW (قسم البحث وتصفح الفئات - 120FPS Smooth)
struct AppStoreSearchView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var searchText = ""
	@State private var showSettingsSheet = false
	@State private var showAddSourceSheet = false
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	private var suggestedApps: [AppStoreAppItem] {
		Array(cache.allApps.prefix(3))
	}
	
	private var searchResults: [AppStoreAppItem] {
		let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return [] }
		return cache.allApps.filter { item in
			item.app.currentName.localizedCaseInsensitiveContains(q) ||
			(item.app.id?.localizedCaseInsensitiveContains(q) ?? false) ||
			item.category.rawValue.localizedCaseInsensitiveContains(q)
		}
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 26) {
					AppStore2026TopHeader(
						title: "بحث",
						onSettingsTap: { showSettingsSheet = true },
						onAddSourceTap: { showAddSourceSheet = true }
					)
					
					if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
						if !suggestedApps.isEmpty {
							VStack(alignment: .leading, spacing: 14) {
								HStack(spacing: 6) {
									Text("مقترحات")
										.font(.system(size: 22, weight: .bold))
										.foregroundStyle(.white)
									Image(systemName: "chevron.left")
										.font(.system(size: 16, weight: .bold))
										.foregroundStyle(.secondary)
									Spacer()
								}
								.padding(.horizontal, 18)
								
								VStack(spacing: 10) {
									ForEach(Array(suggestedApps.enumerated()), id: \.element.id) { index, item in
										NavigationLink {
											SourceAppsDetailView(
												sourceURL: item.sourceURL,
												source: item.repository,
												app: item.app
											)
										} label: {
											if index == 0 {
												AppStore2026SuggestedHighlightRow(item: item)
											} else {
												AppStore2026AppRow(
													item: item,
													useCloudIcon: index == 2
												)
												.padding(.horizontal, 14)
												.padding(.vertical, 6)
											}
										}
										.buttonStyle(.plain)
										
										if index == 1 {
											Divider()
												.background(Color.white.opacity(0.1))
												.padding(.leading, 76)
										}
									}
								}
								.padding(.horizontal, 18)
							}
						}
						
						VStack(alignment: .leading, spacing: 14) {
							HStack(spacing: 6) {
								Text("تصفح")
									.font(.system(size: 22, weight: .bold))
									.foregroundStyle(.white)
								Image(systemName: "chevron.left")
									.font(.system(size: 16, weight: .bold))
									.foregroundStyle(.secondary)
								Spacer()
							}
							.padding(.horizontal, 18)
							
							LazyVGrid(
								columns: [
									GridItem(.flexible(), spacing: 12),
									GridItem(.flexible(), spacing: 12)
								],
								spacing: 12
							) {
								ForEach(AppStore2026Category.allCases) { category in
									let catApps = cache.appsByCategory[category] ?? []
									NavigationLink {
										AppStore2026CategoryListView(
											category: category,
											items: catApps
										)
									} label: {
										AppStore2026BrowseCategoryTile(
											category: category,
											previewApps: Array(catApps.prefix(2))
										)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 18)
						}
					} else {
						LazyVStack(spacing: 14) {
							if searchResults.isEmpty {
								VStack(spacing: 12) {
									Image(systemName: "magnifyingglass")
										.font(.system(size: 42))
										.foregroundStyle(.secondary)
									Text("لا توجد نتائج لـ \"\(searchText)\"")
										.font(.headline)
										.foregroundStyle(.white)
								}
								.frame(maxWidth: .infinity)
								.padding(.top, 60)
							} else {
								ForEach(searchResults) { item in
									NavigationLink {
										SourceAppsDetailView(
											sourceURL: item.sourceURL,
											source: item.repository,
											app: item.app
										)
									} label: {
										AppStore2026SearchResultCard(item: item)
									}
									.buttonStyle(.plain)
								}
							}
						}
						.padding(.horizontal, 18)
					}
				}
				.padding(.bottom, 110)
			}
			.background(Color.black.ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
			.searchable(
				text: $searchText,
				placement: .automatic,
				prompt: "الألعاب والتطبيقات والمزيد..."
			)
			.sheet(isPresented: $showAddSourceSheet) {
				SourcesAddView()
			}
			.sheet(isPresented: $showSettingsSheet) {
				AppStore2026SettingsPopup(sources: _sources, viewModel: viewModel)
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
		.preferredColorScheme(.dark)
		.task {
			await cache.ensureFetched(sources: _sources, viewModel: viewModel)
		}
	}
}

// MARK: - Top Header with App Icon as Account Avatar (Opens Settings!)
struct AppStore2026TopHeader: View {
	let title: String
	let onSettingsTap: () -> Void
	let onAddSourceTap: () -> Void
	
	var body: some View {
		HStack(alignment: .center) {
			Text(title)
				.font(.system(size: 34, weight: .heavy))
				.foregroundStyle(.white)
			
			Spacer()
			
			HStack(spacing: 12) {
				Button(action: onAddSourceTap) {
					Image(systemName: "plus")
						.font(.system(size: 16, weight: .bold))
						.foregroundStyle(.white)
						.frame(width: 36, height: 36)
						.background(Color(white: 0.16), in: Circle())
				}
				
				// App Icon Avatar Button (Replaces Apple ID Avatar & Opens Settings)
				AppStoreAccountAppIconButton(action: onSettingsTap)
			}
		}
		.padding(.horizontal, 18)
		.padding(.top, 10)
	}
}

struct AppStoreAccountAppIconButton: View {
	let action: () -> Void
	
	var body: some View {
		Button(action: action) {
			Group {
				if let icon = AppStoreAppIconProvider.cachedIcon {
					Image(uiImage: icon)
						.resizable()
						.scaledToFill()
				} else {
					ZStack {
						LinearGradient(
							colors: [.blue, .indigo],
							startPoint: .topLeading,
							endPoint: .bottomTrailing
						)
						Image(systemName: "checkmark.seal.fill")
							.font(.system(size: 18, weight: .bold))
							.foregroundStyle(.white)
					}
				}
			}
			.frame(width: 38, height: 38)
			.clipShape(Circle())
			.overlay(
				Circle()
					.stroke(Color.white.opacity(0.22), lineWidth: 1)
			)
		}
		.buttonStyle(.plain)
	}
}

// MARK: - Settings & Account Sheet (Opens when tapping Top App Icon)
struct AppStore2026SettingsPopup: View {
	@Environment(\.dismiss) private var dismiss
	let sources: FetchedResults<AltSource>
	@ObservedObject var viewModel: SourcesViewModel
	@State private var isAddingSource = false
	@State private var selectedSection = 0
	
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				// Top Account Banner with App Icon + Segmented Switcher
				VStack(spacing: 12) {
					HStack(spacing: 12) {
						if let icon = AppStoreAppIconProvider.cachedIcon {
							Image(uiImage: icon)
								.resizable()
								.scaledToFill()
								.frame(width: 48, height: 48)
								.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
						}
						
						VStack(alignment: .leading, spacing: 2) {
							Text(Bundle.main.name)
								.font(.headline.weight(.bold))
							Text("الإعدادات، الشهادات، والمصادر")
								.font(.caption)
								.foregroundStyle(.secondary)
						}
						
						Spacer()
						
						Button("تم") {
							dismiss()
						}
						.font(.body.weight(.bold))
					}
					
					Picker("", selection: $selectedSection) {
						Text("الإعدادات").tag(0)
						Text("المصادر (\(sources.count))").tag(1)
						Text("الشهادات").tag(2)
					}
					.pickerStyle(.segmented)
				}
				.padding(.horizontal, 18)
				.padding(.vertical, 12)
				.background(Color(uiColor: .secondarySystemGroupedBackground))
				
				if selectedSection == 0 {
					SettingsView()
				} else if selectedSection == 1 {
					List {
						Section {
							Button {
								isAddingSource = true
							} label: {
								Label("إضافة مصدر (سورس) جديد", systemImage: "plus.circle.fill")
									.font(.body.weight(.semibold))
							}
						}
						
						Section("المصادر المضافة") {
							ForEach(sources) { source in
								NavigationLink {
									SourceAppsView(object: [source], viewModel: viewModel)
								} label: {
									SourcesCellView(source: source)
								}
							}
						}
					}
				} else {
					CertificatesView()
				}
			}
			.toolbar(.hidden, for: .navigationBar)
			.sheet(isPresented: $isAddingSource) {
				SourcesAddView()
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
	}
}

// MARK: - GPU-Optimized App Store 2026 Cards (No Lag, No Heavy Blur)

struct Today2026HeroCard: View {
	let item: AppStoreAppItem
	let tagText: String
	let headlineText: String
	
	private var themeColor: Color {
		item.app.tintColor ?? item.repository.tintColor ?? Color(red: 0.12, green: 0.32, blue: 0.88)
	}
	
	var body: some View {
		VStack(spacing: 0) {
			ZStack(alignment: .bottomLeading) {
				LinearGradient(
					colors: [
						themeColor.opacity(0.95),
						themeColor.opacity(0.40),
						Color(red: 0.05, green: 0.06, blue: 0.10)
					],
					startPoint: .topTrailing,
					endPoint: .bottomLeading
				)
				
				AppStoreIconView(url: item.app.iconURL, size: 126)
					.shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 6)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.offset(y: -24)
				
				LinearGradient(
					colors: [.clear, .black.opacity(0.88)],
					startPoint: .center,
					endPoint: .bottom
				)
				
				VStack(alignment: .leading, spacing: 4) {
					Text(tagText)
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.white.opacity(0.85))
					Text(headlineText)
						.font(.system(size: 27, weight: .heavy))
						.foregroundStyle(.white)
						.lineLimit(2)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 18)
				.padding(.bottom, 16)
			}
			.frame(height: 320)
			
			HStack(spacing: 12) {
				AppStoreIconView(url: item.app.iconURL, size: 50)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(item.app.currentName)
						.font(.system(size: 16, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
					Text(item.app.currentDescription ?? item.category.rawValue)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				
				Spacer()
				
				AppStore2026DownloadButton(app: item.app, useCloudStyle: true)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			.background(Color(red: 0.10, green: 0.11, blue: 0.14))
		}
		.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 28, style: .continuous)
				.stroke(Color.white.opacity(0.08), lineWidth: 0.6)
		)
	}
}

struct Today2026CenterIconBanner: View {
	let item: AppStoreAppItem
	
	var body: some View {
		ZStack(alignment: .bottom) {
			LinearGradient(
				colors: [
					Color(red: 0.48, green: 0.50, blue: 0.55),
					Color(red: 0.22, green: 0.24, blue: 0.28)
				],
				startPoint: .top,
				endPoint: .bottom
			)
			
			AppStoreIconView(url: item.app.iconURL, size: 84)
				.frame(maxHeight: .infinity, alignment: .top)
				.padding(.top, 22)
			
			HStack(spacing: 10) {
				VStack(alignment: .leading, spacing: 4) {
					Text(item.app.currentName)
						.font(.system(size: 17, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
					
					HStack(spacing: 6) {
						Text("مميز")
							.font(.system(size: 10, weight: .bold))
							.foregroundStyle(.white)
							.padding(.horizontal, 6)
							.padding(.vertical, 2)
							.background(Color.blue, in: RoundedRectangle(cornerRadius: 5))
						
						Text(item.app.currentDescription ?? item.category.rawValue)
							.font(.caption)
							.foregroundStyle(.white.opacity(0.85))
							.lineLimit(1)
					}
				}
				
				Spacer()
				
				AppStore2026DownloadButton(app: item.app, useCloudStyle: false, isLightPill: true)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 14)
			.background(Color.black.opacity(0.45))
		}
		.frame(height: 195)
		.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
	}
}

struct Today2026ListSectionCard: View {
	let outerTitle: String
	let outerSubtitle: String
	let innerCaption: String
	let innerTitle: String
	let items: [AppStoreAppItem]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			VStack(alignment: .leading, spacing: 3) {
				Text(outerTitle)
					.font(.system(size: 22, weight: .heavy))
					.foregroundStyle(.white)
				Text(outerSubtitle)
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 4)
			
			VStack(alignment: .leading, spacing: 16) {
				VStack(alignment: .leading, spacing: 4) {
					Text(innerCaption)
						.font(.caption.weight(.semibold))
						.foregroundStyle(.secondary)
					Text(innerTitle)
						.font(.system(size: 26, weight: .heavy))
						.foregroundStyle(.white)
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
							AppStore2026AppRow(
								item: item,
								useCloudIcon: index == 0 || index == 4
							)
						}
						.buttonStyle(.plain)
					}
				}
			}
			.padding(20)
			.background(
				RoundedRectangle(cornerRadius: 26, style: .continuous)
					.fill(Color(red: 0.11, green: 0.11, blue: 0.12))
			)
		}
	}
}

struct AppStore2026AppRow: View {
	let item: AppStoreAppItem
	var useCloudIcon: Bool = false
	
	var body: some View {
		HStack(spacing: 12) {
			AppStoreIconView(url: item.app.iconURL, size: 58)
			
			VStack(alignment: .leading, spacing: 3) {
				Text(item.app.currentName)
					.font(.system(size: 16, weight: .bold))
					.foregroundStyle(.white)
					.lineLimit(1)
				Text(item.app.currentDescription ?? item.category.rawValue)
					.font(.system(size: 13))
					.foregroundStyle(.secondary)
					.lineLimit(2)
			}
			
			Spacer(minLength: 8)
			
			AppStore2026DownloadButton(app: item.app, useCloudStyle: useCloudIcon)
		}
	}
}

struct AppStore2026SuggestedHighlightRow: View {
	let item: AppStoreAppItem
	
	var body: some View {
		HStack(spacing: 12) {
			AppStoreIconView(url: item.app.iconURL, size: 60)
			
			VStack(alignment: .leading, spacing: 3) {
				Text(item.app.currentName)
					.font(.system(size: 16, weight: .bold))
					.foregroundStyle(.white)
					.lineLimit(1)
				Text(item.app.currentDescription ?? "سهل. موثوق. خاص.")
					.font(.system(size: 13))
					.foregroundStyle(.secondary)
					.lineLimit(1)
				Text("مقترح")
					.font(.system(size: 10, weight: .bold))
					.foregroundStyle(.white)
					.padding(.horizontal, 6)
					.padding(.vertical, 2)
					.background(Color.blue.opacity(0.8), in: RoundedRectangle(cornerRadius: 4))
			}
			
			Spacer()
			
			AppStore2026DownloadButton(app: item.app, useCloudStyle: false)
		}
		.padding(12)
		.background(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(Color(red: 0.12, green: 0.14, blue: 0.18))
		)
	}
}

struct AppStore2026BrowseCategoryTile: View {
	let category: AppStore2026Category
	let previewApps: [AppStoreAppItem]
	
	var body: some View {
		ZStack {
			LinearGradient(
				colors: category.gradientColors,
				startPoint: .topTrailing,
				endPoint: .bottomLeading
			)
			
			Group {
				if previewApps.count >= 2 {
					ZStack {
						AppStoreIconView(url: previewApps[1].app.iconURL, size: 40)
							.rotationEffect(.degrees(12))
							.offset(x: -14, y: 8)
						
						AppStoreIconView(url: previewApps[0].app.iconURL, size: 44)
							.rotationEffect(.degrees(-10))
							.offset(x: 10, y: -4)
					}
				} else {
					Image(systemName: category.sfSymbol)
						.font(.system(size: 38, weight: .bold))
						.foregroundStyle(.white.opacity(0.75))
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
			.padding(.top, 14)
			.padding(.trailing, 18)
			
			Text(category.rawValue)
				.font(.system(size: 16, weight: .bold))
				.foregroundStyle(.white)
				.multilineTextAlignment(.leading)
				.lineLimit(2)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
				.padding(14)
		}
		.frame(height: 102)
		.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	}
}

struct AppStore2026DownloadButton: View {
	let app: ASRepository.App
	var useCloudStyle: Bool = false
	var isLightPill: Bool = false
	@State private var isDownloading = false
	
	var body: some View {
		Button {
			guard let url = app.currentDownloadUrl else { return }
			UIImpactFeedbackGenerator(style: .medium).impactOccurred()
			isDownloading = true
			_ = DownloadManager.shared.startDownload(from: url)
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
				isDownloading = false
			}
		} label: {
			if isDownloading {
				ProgressView()
					.tint(.blue)
					.frame(width: 74, height: 34)
			} else if useCloudStyle {
				Image(systemName: "icloud.and.arrow.down")
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(Color(red: 0.08, green: 0.52, blue: 1.0))
					.frame(width: 44, height: 36)
			} else {
				VStack(spacing: 3) {
					Text("تنزيل")
						.font(.system(size: 15, weight: .bold))
						.foregroundStyle(isLightPill ? .white : Color(red: 0.10, green: 0.54, blue: 1.0))
						.frame(width: 78, height: 32)
						.background(
							Capsule(style: .continuous)
								.fill(isLightPill ? Color.white.opacity(0.28) : Color(white: 0.18))
						)
					
					if !isLightPill {
						Text("الشراء داخل التطبيق")
							.font(.system(size: 8, weight: .medium))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
			}
		}
		.buttonStyle(.plain)
	}
}

struct AppStore2026ThreeRowSection: View {
	let title: String
	let subtitle: String
	let items: [AppStoreAppItem]
	
	private let rows = [
		GridItem(.fixed(72), spacing: 12),
		GridItem(.fixed(72), spacing: 12),
		GridItem(.fixed(72), spacing: 12)
	]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(title)
						.font(.system(size: 21, weight: .bold))
						.foregroundStyle(.white)
					Text(subtitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "chevron.left")
					.font(.caption.weight(.bold))
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 18)
			
			ScrollView(.horizontal, showsIndicators: false) {
				LazyHGrid(rows: rows, spacing: 16) {
					ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
						NavigationLink {
							SourceAppsDetailView(
								sourceURL: item.sourceURL,
								source: item.repository,
								app: item.app
							)
						} label: {
							AppStore2026AppRow(
								item: item,
								useCloudIcon: idx % 3 == 1
							)
							.frame(width: min(UIScreen.main.bounds.width - 48, 320))
						}
						.buttonStyle(.plain)
					}
				}
				.padding(.horizontal, 18)
			}
		}
	}
}

struct AppStore2026FeaturedBanner: View {
	let item: AppStoreAppItem
	
	private var bannerColor: Color {
		item.app.tintColor ?? item.repository.tintColor ?? Color.blue
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("تحديث مميز")
				.font(.caption2.weight(.bold))
				.foregroundStyle(.blue)
			Text(item.app.currentName)
				.font(.title3.weight(.bold))
				.foregroundStyle(.white)
				.lineLimit(1)
			Text(item.app.currentDescription ?? item.category.rawValue)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.lineLimit(1)
			
			ZStack(alignment: .bottom) {
				LinearGradient(
					colors: [bannerColor.opacity(0.85), Color(white: 0.12)],
					startPoint: .topTrailing,
					endPoint: .bottomLeading
				)
				
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
					
					AppStore2026DownloadButton(app: item.app, useCloudStyle: true)
				}
				.padding(14)
				.background(Color.black.opacity(0.55))
			}
			.frame(height: 175)
			.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		}
		.frame(width: min(UIScreen.main.bounds.width - 44, 336))
	}
}

struct AppStore2026SearchResultCard: View {
	let item: AppStoreAppItem
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			AppStore2026AppRow(item: item, useCloudIcon: false)
			
			if !item.screenshots.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 10) {
						ForEach(Array(item.screenshots.prefix(3)), id: \.self) { url in
							LazyImage(url: url) { state in
								if let image = state.image {
									image
										.resizable()
										.scaledToFill()
								} else {
									RoundedRectangle(cornerRadius: 12, style: .continuous)
										.fill(Color(white: 0.16))
								}
							}
							.processors([.resize(size: CGSize(width: 220, height: 380))])
							.frame(width: 106, height: 188)
							.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
						}
					}
				}
			}
		}
		.padding(16)
		.background(
			RoundedRectangle(cornerRadius: 22, style: .continuous)
				.fill(Color(red: 0.11, green: 0.11, blue: 0.12))
		)
	}
}

struct AppStore2026CategoryListView: View {
	let category: AppStore2026Category
	let items: [AppStoreAppItem]
	
	var body: some View {
		ScrollView(.vertical, showsIndicators: false) {
			LazyVStack(spacing: 12) {
				ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
					NavigationLink {
						SourceAppsDetailView(
							sourceURL: item.sourceURL,
							source: item.repository,
							app: item.app
						)
					} label: {
						AppStore2026AppRow(item: item, useCloudIcon: index % 2 == 1)
							.padding(14)
							.background(
								RoundedRectangle(cornerRadius: 20, style: .continuous)
									.fill(Color(red: 0.11, green: 0.11, blue: 0.12))
							)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(18)
		}
		.background(Color.black.ignoresSafeArea())
		.navigationTitle(category.rawValue)
		.environment(\.layoutDirection, .rightToLeft)
	}
}

// MARK: - Downsampled Fast Icon View (Prevents Memory Spikes & Scroll Hitching)
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
				.processors([.resize(size: CGSize(width: size * 2, height: size * 2))])
			} else {
				placeholder
			}
		}
		.frame(width: size, height: size)
		.clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
				.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
		)
	}
	
	private var placeholder: some View {
		RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
			.fill(Color(white: 0.18))
	}
}

struct AppStore2026EmptyState: View {
	let isLoading: Bool
	let onAddSource: () -> Void
	
	var body: some View {
		VStack(spacing: 16) {
			if isLoading {
				ProgressView()
					.tint(.white)
					.scaleEffect(1.3)
				Text("جاري جلب التطبيقات والألعاب...")
					.font(.subheadline)
					.foregroundStyle(.secondary)
			} else {
				Image(systemName: "bag.badge.plus")
					.font(.system(size: 46))
					.foregroundStyle(.blue)
				Text("المتجر جاهز لإضافة مصادرك")
					.font(.title3.weight(.bold))
					.foregroundStyle(.white)
				Text("اضغط على + في الأعلى لإضافة سورس (Repo) وعرض جميع تطبيقاته.")
					.font(.subheadline)
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.center)
				Button(action: onAddSource) {
					Text("إضافة مصدر الآن")
						.font(.subheadline.weight(.bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 24)
						.padding(.vertical, 12)
						.background(Color.blue, in: Capsule())
				}
			}
		}
		.frame(maxWidth: .infinity)
		.padding(32)
		.background(
			RoundedRectangle(cornerRadius: 26, style: .continuous)
				.fill(Color(red: 0.11, green: 0.11, blue: 0.12))
		)
	}
}
