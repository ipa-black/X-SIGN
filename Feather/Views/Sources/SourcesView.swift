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

// MARK: - Bilingual Search & Localization Engine (Arabic <-> English)
enum AppStoreBilingualEngine {
	// قاموس شامل يربط أسماء التطبيقات والكلمات المفتاحية بين العربية والإنجليزية
	static let synonymGroups: [[String]] = [
		["instagram", "insta", "ig", "rocket", "plus", "bhinsta", "انستقرام", "انستا", "انستجرام", "إنستجرام", "انستغرام", "إنستغرام"],
		["whatsapp", "watusi", "wa", "واتساب", "واتس", "واتس اب", "وتساب"],
		["tiktok", "tik tok", "lrd", "bh", "dl", "تيك توك", "تيكتوك", "تك توك"],
		["snapchat", "snap", "wicked", "shadow", "سناب", "سناب شات", "سنابشات"],
		["youtube", "uplus", "uyou", "cercube", "yt", "يوتيوب", "يتوب", "فيديو"],
		["telegram", "swiftgram", "nicegram", "tele", "تليجرام", "تلغرام", "تلكرام", "تيليجرام"],
		["twitter", "x", "bhx", "twt", "تويتر", "اكس", "إكس"],
		["facebook", "fb", "wolf", "فيسبوك", "فيس بوك", "فيس"],
		["messenger", "مسنجر", "ماسنجر"],
		["discord", "enmity", "vendetta", "ديسكورد", "دسكورد"],
		["reddit", "ريديت"],
		["threads", "ثريدز"],
		["spotify", "eevee", "spotilife", "سبوتيفاي", "سبوتفاي", "موسيقى", "اغاني", "أغاني"],
		["soundcloud", "ساوند كلاود", "ساوندكلاود"],
		["shahid", "شاهد", "مسلسلات"],
		["netflix", "نتفلكس", "نتفليكس", "افلام", "أفلام"],
		["osn", "ostora", "اسطورة", "الأسطورة", "مباريات", "بث", "تلفزيون", "iptv", "tv", "movie", "anime", "انمي", "أنمي"],
		["capcut", "كاب كات", "كابكات", "مونتاج", "تعديل فيديو"],
		["picsart", "بيكس ارت", "بيكس آرت", "تعديل صور"],
		["lightroom", "لايت روم", "لايتروم", "فلاتر"],
		["inshot", "انشوت", "إنشوت"],
		["videostar", "video star", "فيديو ستار", "فيديوستار"],
		["alight", "alight motion", "الايت موشن", "ألايت موشن"],
		["canva", "كانفا", "تصميم"],
		["photoshop", "فوتوشوب"],
		["remini", "ريميني", "توضيح الصور"],
		["pubg", "ببجي", "بوبجي", "شدات"],
		["8ball", "pool", "8 ball", "بلياردو", "بول", "بليارد"],
		["roblox", "روبلوكس", "روبلكس"],
		["minecraft", "ماين كرافت", "ماينكرافت"],
		["subway", "صب واي", "سابوي", "ركض"],
		["gta", "san andreas", "قراند", "جاتا", "حرامي السيارات"],
		["cod", "call of duty", "كود", "كول اوف ديوتي"],
		["freefire", "free fire", "فري فاير"],
		["clash", "brawl", "كلاش", "براول ستارز"],
		["fifa", "fc", "pes", "efootball", "فيفا", "بيس", "كرة قدم"],
		["ludo", "yalla", "لودو", "يلا لودو"],
		["chess", "شطرنج"],
		["car", "racing", "drift", "سيارات", "سباق", "هجولة", "تفحيط"],
		["filza", "فيلزا", "مدير ملفات", "ملفات"],
		["esign", "feather", "scarlet", "gbox", "ksign", "x-sign", "vsign", "توقيع", "شهادات", "متجر", "اي ساين", "فيذر"],
		["troll", "trollstore", "ترول ستور", "ترول"],
		["vpn", "adblock", "dns", "في بي ان", "كاسر بروكسي", "حجب اعلانات", "مانع اعلانات"],
		["ai", "chatgpt", "gemini", "claude", "ذكاء اصطناعي", "شات جي بي تي", "جيميناي"]
	]
	
	static func normalize(_ text: String) -> String {
		text.lowercased()
			.replacingOccurrences(of: "أ", with: "ا")
			.replacingOccurrences(of: "إ", with: "ا")
			.replacingOccurrences(of: "آ", with: "ا")
			.replacingOccurrences(of: "ة", with: "ه")
			.replacingOccurrences(of: "ى", with: "ي")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
	
	static func buildSearchTokens(for app: ASRepository.App, category: AppStore2026Category) -> String {
		let base = normalize("\(app.name ?? "") \(app.id ?? "") \(app.subtitle ?? "") \(app.localizedDescription ?? "") \(category.rawValue)")
		var expanded = base
		for group in synonymGroups {
			let normalizedGroup = group.map { normalize($0) }
			if normalizedGroup.contains(where: { base.contains($0) }) {
				expanded += " " + normalizedGroup.joined(separator: " ")
			}
		}
		return expanded
	}
	
	static func localizedSubtitle(for app: ASRepository.App, category: AppStore2026Category) -> String {
		let nameAndID = normalize("\(app.name ?? "") \(app.id ?? "")")
		
		if nameAndID.contains("instagram") || nameAndID.contains("insta") || nameAndID.contains("rocket") {
			return "تواصل، شارك الصور والريلز بميزات إضافية"
		}
		if nameAndID.contains("whatsapp") || nameAndID.contains("watusi") {
			return "مراسلة فورية مع مزايا الخصوصية والتحميل"
		}
		if nameAndID.contains("tiktok") || nameAndID.contains("lrd") {
			return "فيديوهات قصيرة وحفظ بدون علامة مائية"
		}
		if nameAndID.contains("snapchat") || nameAndID.contains("wicked") || nameAndID.contains("shadow") {
			return "شارك اللحظات مع أدوات الحفظ المتقدمة"
		}
		if nameAndID.contains("youtube") || nameAndID.contains("uyou") || nameAndID.contains("uplus") {
			return "مشاهدة بدون إعلانات وتشغيل في الخلفية"
		}
		if nameAndID.contains("telegram") || nameAndID.contains("swiftgram") || nameAndID.contains("nicegram") {
			return "مراسلة سحابية سريعة وآمنة بلا حدود"
		}
		if nameAndID.contains("twitter") || nameAndID.contains("bhx") {
			return "أحدث الأخبار والتغريدات مع تحميل الوسائط"
		}
		if nameAndID.contains("spotify") || nameAndID.contains("eevee") {
			return "استمع للموسيقى والبودكاست بجودة عالية"
		}
		if nameAndID.contains("capcut") || nameAndID.contains("videostar") || nameAndID.contains("alight") || nameAndID.contains("inshot") {
			return "تحرير ومونتاج الفيديو باحترافية عالية"
		}
		if nameAndID.contains("picsart") || nameAndID.contains("lightroom") || nameAndID.contains("photoshop") || nameAndID.contains("remini") {
			return "تعديل الصور والفلاتر الاحترافية"
		}
		if nameAndID.contains("canva") {
			return "تصميم الجرافيك والشعارات بسهولة"
		}
		if nameAndID.contains("pubg") {
			return "معارك باتل رويال جماعية مشوقة"
		}
		if nameAndID.contains("pool") || nameAndID.contains("8ball") {
			return "لعبة البلياردو العالمية رقم 1"
		}
		if nameAndID.contains("roblox") {
			return "استمتع بلعب ملايين الألعاب والعوالم"
		}
		if nameAndID.contains("minecraft") {
			return "ابنِ عالمك واستكشف بلا حدود"
		}
		if nameAndID.contains("subway") || nameAndID.contains("minion") || nameAndID.contains("temple") || nameAndID.contains("sonic") {
			return "انضم إلى مرح دائم من الركض والقفز!"
		}
		if nameAndID.contains("filza") {
			return "مدير ملفات متكامل لنظام iOS"
		}
		if nameAndID.contains("esign") || nameAndID.contains("feather") || nameAndID.contains("scarlet") || nameAndID.contains("sign") {
			return "توقيع وتثبيت تطبيقات IPA بسهولة"
		}
		
		// إذا كان الوصف الأصلي يحتوي على حروف عربية نعرضه، وإلا نعرض وصف الفئة بالعربية
		if let original = app.currentDescription,
		   original.range(of: "\\p{Arabic}", options: .regularExpression) != nil {
			return original
		}
		return category.defaultArabicSubtitle
	}
}

// MARK: - Precomputed App Store Item (Strict App vs Game Separation)
struct AppStoreAppItem: Identifiable, Hashable {
	let id: String
	let sourceURL: URL?
	let repository: ASRepository
	let app: ASRepository.App
	let category: AppStore2026Category
	let isGame: Bool
	let arabicSubtitle: String
	let searchIndexTokens: String
	let screenshots: [URL]
	
	init(id: String, sourceURL: URL?, repository: ASRepository, app: ASRepository.App) {
		self.id = id
		self.sourceURL = sourceURL
		self.repository = repository
		self.app = app
		
		let classified = AppStore2026Category.strictlyClassify(app: app)
		self.category = classified
		self.isGame = classified.isGameCategory
		self.arabicSubtitle = AppStoreBilingualEngine.localizedSubtitle(for: app, category: classified)
		self.searchIndexTokens = AppStoreBilingualEngine.buildSearchTokens(for: app, category: classified)
		
		if let urls = app.screenshotURLs, !urls.isEmpty {
			self.screenshots = urls
		} else if let iphone = app.screenshots?.iPhone, !iphone.isEmpty {
			self.screenshots = iphone
		} else {
			self.screenshots = []
		}
	}
	
	func matchesSearch(_ query: String) -> Bool {
		let normalizedQuery = AppStoreBilingualEngine.normalize(query)
		guard !normalizedQuery.isEmpty else { return true }
		let words = normalizedQuery.split(separator: " ")
		return words.allSatisfy { word in
			searchIndexTokens.contains(word)
		}
	}
	
	static func == (lhs: AppStoreAppItem, rhs: AppStoreAppItem) -> Bool {
		lhs.id == rhs.id
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

// MARK: - Exact App Store 2026 Categories (Matching Screenshots 3, 4, 5)
enum AppStore2026Category: String, CaseIterable, Identifiable {
	case topApps = "التطبيقات الأكثر تنزيلاً"
	case topGames = "الألعاب الأكثر تنزيلاً"
	case bestSellingApps = "التطبيقات الأكثر مبيعاً"
	case bestSellingGames = "الألعاب الأكثر مبيعاً"
	case puzzleGames = "ألعاب ألغاز"
	case simulationGames = "ألعاب محاكاة"
	case social = "التواصل الاجتماعي"
	case casualGames = "ألعاب تسالي"
	case timePass = "تمضية وقت"
	case mediaReaders = "قارئات الوسائط"
	case productivity = "إنتاجية"
	case strategyGames = "ألعاب إستراتيجية"
	case pvpGames = "لاعب ضد لاعب"
	case devTools = "تطبيقات أدوات التطوير"
	case visualArts = "فنون بصرية"
	case photoVideo = "صور وفيديو"
	
	var id: String { rawValue }
	
	var isGameCategory: Bool {
		switch self {
		case .topGames, .bestSellingGames, .puzzleGames, .simulationGames, .casualGames, .timePass, .strategyGames, .pvpGames:
			return true
		case .topApps, .bestSellingApps, .social, .mediaReaders, .productivity, .devTools, .visualArts, .photoVideo:
			return false
		}
	}
	
	var defaultArabicSubtitle: String {
		switch self {
		case .topApps, .bestSellingApps: return "تطبيق مميز للآيفون"
		case .topGames, .bestSellingGames: return "لعبة رائجة ومختارة"
		case .puzzleGames: return "ألغاز وتحديات ذكاء ممتعة"
		case .simulationGames: return "محاكاة واقعية وبناء عوالم"
		case .social: return "تواصل اجتماعي ومراسلة فورية"
		case .casualGames: return "ألعاب تسالي سريعة وممتعة"
		case .timePass: return "ترفيه وتسلية في كل وقت"
		case .mediaReaders: return "مشاهدة الفيديو والموسيقى"
		case .productivity: return "إنتاجية وأدوات ذكية يومية"
		case .strategyGames: return "تخطيط، معارك، وإستراتيجية"
		case .pvpGames: return "منافسات جماعية لاعب ضد لاعب"
		case .devTools: return "أدوات النظام والتوقيع والمطورين"
		case .visualArts: return "تصميم جرافيك وفنون رقمية"
		case .photoVideo: return "تصوير ومونتاج وتحرير احترافي"
		}
	}
	
	var sfSymbol: String {
		switch self {
		case .topApps:          return "star.fill"
		case .topGames:         return "trophy.fill"
		case .bestSellingApps:  return "crown.fill"
		case .bestSellingGames: return "medal.fill"
		case .puzzleGames:      return "puzzlepiece.fill"
		case .simulationGames:  return "house.and.flag.fill"
		case .social:           return "bubble.left.and.bubble.right.fill"
		case .casualGames:      return "airplane.departure"
		case .timePass:         return "sparkles"
		case .mediaReaders:     return "book.pages.fill"
		case .productivity:     return "paperplane.fill"
		case .strategyGames:    return "flag.2.crossed.fill"
		case .pvpGames:         return "gamecontroller.fill"
		case .devTools:         return "wrench.and.screwdriver.fill"
		case .visualArts:       return "paintpalette.fill"
		case .photoVideo:       return "camera.fill"
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
		case .puzzleGames:
			return [Color(red: 0.53, green: 0.84, blue: 0.96), Color(red: 0.38, green: 0.72, blue: 0.88)]
		case .simulationGames:
			return [Color(red: 0.55, green: 0.84, blue: 0.68), Color(red: 0.40, green: 0.72, blue: 0.54)]
		case .social:
			return [Color(red: 0.68, green: 0.62, blue: 0.97), Color(red: 0.53, green: 0.45, blue: 0.93)]
		case .casualGames:
			return [Color(red: 0.55, green: 0.82, blue: 0.95), Color(red: 0.42, green: 0.72, blue: 0.89)]
		case .timePass:
			return [Color(red: 0.54, green: 0.84, blue: 0.96), Color(red: 0.42, green: 0.75, blue: 0.90)]
		case .mediaReaders:
			return [Color(red: 0.96, green: 0.71, blue: 0.42), Color(red: 0.91, green: 0.58, blue: 0.27)]
		case .productivity:
			return [Color(red: 0.62, green: 0.75, blue: 0.96), Color(red: 0.48, green: 0.64, blue: 0.90)]
		case .strategyGames:
			return [Color(red: 0.54, green: 0.82, blue: 0.48), Color(red: 0.42, green: 0.72, blue: 0.38)]
		case .pvpGames:
			return [Color(red: 0.79, green: 0.56, blue: 0.98), Color(red: 0.68, green: 0.40, blue: 0.93)]
		case .devTools:
			return [Color(red: 0.52, green: 0.82, blue: 0.95), Color(red: 0.38, green: 0.72, blue: 0.89)]
		case .visualArts:
			return [Color(red: 0.55, green: 0.85, blue: 0.96), Color(red: 0.42, green: 0.75, blue: 0.90)]
		case .photoVideo:
			return [Color(red: 0.94, green: 0.79, blue: 0.48), Color(red: 0.88, green: 0.68, blue: 0.34)]
		}
	}
	
	// تصنيف صارم جداً: يفصل الألعاب 100% عن التطبيقات
	static func strictlyClassify(app: ASRepository.App) -> AppStore2026Category {
		let nameAndBundle = "\(app.name ?? "") \(app.id ?? "") \(app.category ?? "")".lowercased()
		let desc = (app.localizedDescription ?? app.subtitle ?? "").lowercased()
		let combined = "\(nameAndBundle) \(desc)"
		
		// أولاً: فحص التطبيقات المعروفة لضمان عدم تصنيفها كألعاب بالخطأ
		let socialApps = ["instagram", "whatsapp", "tiktok", "snapchat", "twitter", "telegram", "facebook", "discord", "messenger", "reddit", "threads", "watusi", "bhinsta", "uplus", "rocket", "swiftgram", "nicegram", "wicked", "انستقرام", "واتس", "تيك توك", "سناب", "تليجرام", "تويتر", "فيسبوك", "ديسكورد"]
		if socialApps.contains(where: { nameAndBundle.contains($0) }) { return .social }
		
		let mediaApps = ["youtube", "uyou", "cercube", "spotify", "eevee", "soundcloud", "shahid", "netflix", "ostora", "iptv", "movie", "anime", "music", "podcast", "player", "infuse", "vlc", "يوتيوب", "سبوتيفاي", "شاهد", "نتفلكس", "افلام", "مسلسلات", "انمي", "موسيقى", "اسطورة"]
		if mediaApps.contains(where: { nameAndBundle.contains($0) }) { return .mediaReaders }
		
		let photoVideoApps = ["capcut", "lightroom", "picsart", "inshot", "videostar", "alight", "photoshop", "remini", "vn", "camera", "dazz", "lensa", "b612", "snow", "vsco", "snapseed", "كاب كات", "بيكس ارت", "لايت روم", "فيديو ستار", "مونتاج", "فوتوشوب"]
		if photoVideoApps.contains(where: { nameAndBundle.contains($0) }) { return .photoVideo }
		
		let visualArtApps = ["canva", "procreate", "ibis", "sketch", "pixelmator", "vector", "font", "logo", "كانفا", "رسم", "خطوط"]
		if visualArtApps.contains(where: { nameAndBundle.contains($0) }) { return .visualArts }
		
		let devToolApps = ["filza", "esign", "feather", "scarlet", "troll", "gbox", "ksign", "x-sign", "vsign", "vpn", "adblock", "adguard", "dns", "flex", "igamegod", "dl", "terminal", "ssh", "cert", "ipa", "sideload", "altstore", "فيلزا", "توقيع", "شهادات", "ترول"]
		if devToolApps.contains(where: { nameAndBundle.contains($0) }) { return .devTools }
		
		// ثانياً: فحص دقيق وشامل للألعاب (تذهب حصرياً لقسم الألعاب)
		let pvpKeywords = ["pubg", "8ball", "pool", "cod", "callofduty", "freefire", "brawl", "fortnite", "fifa", "efootball", "pes", "mobilelegends", "wildrift", "standoff", "bullet", "pvp", "multiplayer", "ببجي", "بلياردو", "فري فاير", "كود", "فيفا", "بيس"]
		if pvpKeywords.contains(where: { combined.contains($0) }) { return .pvpGames }
		
		let strategyKeywords = ["clash", "royale", "clans", "strategy", "chess", "tower", "defense", "war", "empire", "civilization", "boombeach", "plantsvs", "كلاش", "شطرنج", "حرب", "استراتيجيه"]
		if strategyKeywords.contains(where: { combined.contains($0) }) { return .strategyGames }
		
		let simulationKeywords = ["roblox", "minecraft", "sims", "simcity", "gta", "rockstar", "sanandreas", "parking", "simulator", "bus", "truck", "flight", "farm", "hayday", "township", "روبلوكس", "ماين كرافت", "قراند", "محاكاة", "مزرعه"]
		if simulationKeywords.contains(where: { combined.contains($0) }) { return .simulationGames }
		
		let puzzleKeywords = ["puzzle", "candy", "crush", "match", "brain", "sudoku", "word", "gardenscapes", "homescapes", "royalmatch", "angrybirds", "cuttherope", "2048", "trivia", "الغاز", "ألغاز", "ذكاء", "كلمات"]
		if puzzleKeywords.contains(where: { combined.contains($0) }) { return .puzzleGames }
		
		let casualGameKeywords = [
			"game", "games", "gaming", "arcade", "subway", "surfers", "minion", "temple", "run", "sonic",
			"talking", "tom", "flappy", "jump", "racing", "race", "asphalt", "carx", "drift", "hillclimb",
			"ludo", "yalla", "uno", "monopoly", "fruitninja", "jetpack", "pacman", "mario", "pokemon",
			"zelda", "ppsspp", "delta", "retroarch", "emulator", "hack", "mod menu", "infinite coins",
			"unlimited money", "god mode", "unlocked all", "playdead", "gameloft", "supercell", "zynga",
			"rovio", "ketchapp", "voodoo", "miniclip", "ea.", "ubisoft", "activision", "konami", "sega",
			"bandai", "capcom", "squareenix", "لعبة", "لعبه", "العاب", "ألعاب", "تهكير لعبة", "اموال غير محدودة"
		]
		if casualGameKeywords.contains(where: { combined.contains($0) }) { return .casualGames }
		
		return .productivity
	}
}

// MARK: - High-Performance Store Cache Manager (Strict Separation)
@MainActor
final class AppStoreCacheManager: ObservableObject {
	static let shared = AppStoreCacheManager()
	
	// جميع العناصر للبحث واليوم
	@Published private(set) var allCombinedItems: [AppStoreAppItem] = []
	// التطبيقات فقط (بدون أي لعبة نهائياً)
	@Published private(set) var pureAppsOnly: [AppStoreAppItem] = []
	// الألعاب فقط (بدون أي تطبيق نهائياً)
	@Published private(set) var pureGamesOnly: [AppStoreAppItem] = []
	// القوائم المصنفة لكل فئة بدقة
	@Published private(set) var itemsByCategory: [AppStore2026Category: [AppStoreAppItem]] = [:]
	
	private var lastSourceSignature: String = ""
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
		lastSourceSignature = ""
		rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
	}
	
	func rebuildCacheIfNeeded(sources: FetchedResults<AltSource>, repositoriesMap: [AltSource: ASRepository]) {
		let totalCount = repositoriesMap.values.reduce(0) { $0 + $1.apps.count }
		let signature = "\(sources.count)_\(totalCount)"
		guard signature != lastSourceSignature else { return }
		lastSourceSignature = signature
		
		var allItems: [AppStoreAppItem] = []
		allItems.reserveCapacity(totalCount)
		var seenKeys = Set<String>()
		
		for source in sources {
			guard let repo = repositoriesMap[source] else { continue }
			let sourceURLString = source.sourceURL?.absoluteString ?? ""
			for app in repo.apps {
				let uniqueKey = "\(app.id ?? app.currentName)_\(sourceURLString)"
				if seenKeys.insert(uniqueKey).inserted {
					allItems.append(
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
		
		// فصل حازم 100%: التطبيقات في قائمة، والألعاب في قائمة منفصلة
		let onlyApps = allItems.filter { !$0.isGame }
		let onlyGames = allItems.filter { $0.isGame }
		
		var categoryDict: [AppStore2026Category: [AppStoreAppItem]] = [:]
		for category in AppStore2026Category.allCases {
			switch category {
			case .topApps:
				categoryDict[category] = onlyApps
			case .bestSellingApps:
				categoryDict[category] = Array(onlyApps.reversed())
			case .topGames:
				categoryDict[category] = onlyGames
			case .bestSellingGames:
				categoryDict[category] = Array(onlyGames.reversed())
			case .timePass:
				let casual = onlyGames.filter { $0.category == .casualGames || $0.category == .puzzleGames }
				categoryDict[category] = casual.isEmpty ? onlyGames : casual
			default:
				let exactMatches = allItems.filter { $0.category == category }
				if !exactMatches.isEmpty {
					categoryDict[category] = exactMatches
				} else {
					categoryDict[category] = category.isGameCategory ? onlyGames : onlyApps
				}
			}
		}
		
		self.allCombinedItems = allItems
		self.pureAppsOnly = onlyApps
		self.pureGamesOnly = onlyGames
		self.itemsByCategory = categoryDict
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

// MARK: - 1. TODAY VIEW (صفحة اليوم - App Store 2026)
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
					
					if cache.allCombinedItems.isEmpty {
						AppStore2026EmptyState(
							isLoading: !viewModel.isFinished,
							onAddSource: { showAddSourceSheet = true }
						)
						.padding(.horizontal, 18)
						.padding(.top, 30)
					} else {
						// 1. Hero Card
						if let firstHero = cache.pureGamesOnly.first ?? cache.allCombinedItems.first {
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
						
						// 2. Center Icon Spotlight Banner
						if let secondSpotlight = cache.pureAppsOnly.first ?? cache.allCombinedItems.dropFirst().first {
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
						
						// 3. Games List Card (Exact 5 items like Apple Store)
						let gameListItems = Array((cache.pureGamesOnly.isEmpty ? cache.allCombinedItems : cache.pureGamesOnly).prefix(5))
						if !gameListItems.isEmpty {
							Today2026ListSectionCard(
								outerTitle: "واصل الركض!",
								outerSubtitle: "إلى متى يمكنك الصمود في هذه الألعاب؟",
								innerCaption: "أفضل الألعاب",
								innerTitle: "ركض بلا نهاية",
								items: gameListItems
							)
							.padding(.horizontal, 18)
						}
						
						// 4. Apps List Card (Exact 5 items from pureAppsOnly)
						let appListItems = Array(cache.pureAppsOnly.prefix(5))
						if !appListItems.isEmpty {
							Today2026ListSectionCard(
								outerTitle: "تطبيقات لا غنى عنها",
								outerSubtitle: "أقوى التطبيقات المعدلة والأدوات اليومية",
								innerCaption: "اختيارات المحررين",
								innerTitle: "تطبيقات أساسية",
								items: appListItems
							)
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

// MARK: - 2. APPS VIEW (قسم التطبيقات فقط - لا يعرض الألعاب إطلاقاً!)
struct SourcesView: View {
	@StateObject var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var _isAddingPresenting = false
	@State private var _isSettingsPresenting = false
	@State private var _selectedAppCategory: AppStore2026Category? = nil
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	// فئات التطبيقات فقط (بدون أي فئة ألعاب)
	private let appOnlyCategories: [AppStore2026Category] = [
		.social,
		.photoVideo,
		.mediaReaders,
		.devTools,
		.visualArts,
		.productivity
	]
	
	private var filteredPureApps: [AppStoreAppItem] {
		guard let selected = _selectedAppCategory else {
			return cache.pureAppsOnly
		}
		return cache.pureAppsOnly.filter { $0.category == selected }
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 24) {
					AppStore2026TopHeader(
						title: "التطبيقات",
						onSettingsTap: { _isSettingsPresenting = true },
						onAddSourceTap: { _isAddingPresenting = true }
					)
					
					if cache.pureAppsOnly.isEmpty {
						AppStore2026EmptyState(
							isLoading: !viewModel.isFinished,
							onAddSource: { _isAddingPresenting = true }
						)
						.padding(.horizontal, 18)
						.padding(.top, 30)
					} else {
						// 1. فلاتر فئات التطبيقات فقط
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								Button {
									_selectedAppCategory = nil
								} label: {
									Text("الكل")
										.font(.subheadline.weight(.bold))
										.foregroundStyle(_selectedAppCategory == nil ? .black : .white)
										.padding(.horizontal, 18)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(_selectedAppCategory == nil ? Color.white : Color(white: 0.14))
										)
								}
								.buttonStyle(.plain)
								
								ForEach(appOnlyCategories) { cat in
									Button {
										_selectedAppCategory = cat
									} label: {
										HStack(spacing: 6) {
											Image(systemName: cat.sfSymbol)
												.font(.caption)
											Text(cat.rawValue)
												.font(.subheadline.weight(.bold))
										}
										.foregroundStyle(_selectedAppCategory == cat ? .black : .white)
										.padding(.horizontal, 16)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(_selectedAppCategory == cat ? Color.white : Color(white: 0.14))
										)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 18)
						}
						
						if _selectedAppCategory == nil {
							// 2. البطاقات الترويجية العلوية للتطبيقات
							ScrollView(.horizontal, showsIndicators: false) {
								LazyHStack(spacing: 16) {
									ForEach(Array(cache.pureAppsOnly.prefix(6))) { item in
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
							
							// 3. قسم الثلاثة صفوف: التطبيقات الأكثر تنزيلاً
							AppStore2026ThreeRowSection(
								title: "التطبيقات الأكثر تنزيلاً",
								subtitle: "أفضل التطبيقات المختارة لك",
								items: Array(cache.pureAppsOnly.prefix(18))
							)
							
							// 4. بطاقة تطبيقات التواصل الاجتماعي
							let socialApps = cache.pureAppsOnly.filter { $0.category == .social }
							if !socialApps.isEmpty {
								Today2026ListSectionCard(
									outerTitle: "تواصل بلا حدود",
									outerSubtitle: "أحدث نسخ تطبيقات التواصل الاجتماعي",
									innerCaption: "التواصل الاجتماعي",
									innerTitle: "تطبيقات المحادثة والمشاركة",
									items: Array(socialApps.prefix(5))
								)
								.padding(.horizontal, 18)
							}
							
							// 5. قسم الثلاثة صفوف: صور وفيديو + أدوات التطوير
							let mediaAndPhotoApps = cache.pureAppsOnly.filter { $0.category == .photoVideo || $0.category == .mediaReaders }
							if !mediaAndPhotoApps.isEmpty {
								AppStore2026ThreeRowSection(
									title: "صور وفيديو وترفيه",
									subtitle: "مونتاج، تصميم، ومشاهدة بلا حدود",
									items: Array(mediaAndPhotoApps.prefix(15))
								)
							}
						}
						
						// 6. قائمة جميع التطبيقات (تطبيقات فقط 100% بتصميم آبل ستور النظيف)
						HStack {
							Text(_selectedAppCategory?.rawValue ?? "جميع التطبيقات")
								.font(.system(size: 22, weight: .bold))
								.foregroundStyle(.white)
							Spacer()
						}
						.padding(.horizontal, 18)
						.padding(.top, 4)
						
						ForEach(Array(filteredPureApps.enumerated()), id: \.element.id) { index, item in
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
		.onChange(of: viewModel.sources.count) { _ in
			cache.rebuildCacheIfNeeded(sources: _sources, repositoriesMap: viewModel.sources)
		}
	}
}

// MARK: - 3. GAMES VIEW (قسم الألعاب فقط - يعرض الألعاب حصرياً!)
struct AppStoreGamesView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var showSettingsSheet = false
	@State private var showAddSourceSheet = false
	@State private var selectedGameCategory: AppStore2026Category? = nil
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	private let gameOnlyCategories: [AppStore2026Category] = [
		.pvpGames,
		.simulationGames,
		.strategyGames,
		.puzzleGames,
		.casualGames
	]
	
	private var displayedGames: [AppStoreAppItem] {
		guard let selected = selectedGameCategory else {
			return cache.pureGamesOnly
		}
		return cache.pureGamesOnly.filter { $0.category == selected }
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 24) {
					AppStore2026TopHeader(
						title: "الألعاب",
						onSettingsTap: { showSettingsSheet = true },
						onAddSourceTap: { showAddSourceSheet = true }
					)
					
					if cache.pureGamesOnly.isEmpty {
						VStack(spacing: 14) {
							Image(systemName: "gamecontroller.fill")
								.font(.system(size: 44))
								.foregroundStyle(.blue)
							Text("لا توجد ألعاب في المصادر الحالية")
								.font(.title3.weight(.bold))
								.foregroundStyle(.white)
							Text("أضف سورس يحتوي على ألعاب لتظهر هنا تلقائياً.")
								.font(.subheadline)
								.foregroundStyle(.secondary)
						}
						.frame(maxWidth: .infinity)
						.padding(32)
						.background(
							RoundedRectangle(cornerRadius: 26, style: .continuous)
								.fill(Color(red: 0.11, green: 0.11, blue: 0.12))
						)
						.padding(.horizontal, 18)
						.padding(.top, 20)
					} else {
						// فلاتر فئات الألعاب فقط
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								Button {
									selectedGameCategory = nil
								} label: {
									Text("كل الألعاب")
										.font(.subheadline.weight(.bold))
										.foregroundStyle(selectedGameCategory == nil ? .black : .white)
										.padding(.horizontal, 18)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(selectedGameCategory == nil ? Color.white : Color(white: 0.14))
										)
								}
								.buttonStyle(.plain)
								
								ForEach(gameOnlyCategories) { cat in
									Button {
										selectedGameCategory = cat
									} label: {
										HStack(spacing: 6) {
											Image(systemName: cat.sfSymbol)
												.font(.caption)
											Text(cat.rawValue)
												.font(.subheadline.weight(.bold))
										}
										.foregroundStyle(selectedGameCategory == cat ? .black : .white)
										.padding(.horizontal, 16)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(selectedGameCategory == cat ? Color.white : Color(white: 0.14))
										)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 18)
						}
						
						if selectedGameCategory == nil {
							if let heroGame = cache.pureGamesOnly.first {
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
								items: Array(cache.pureGamesOnly.prefix(5))
							)
							.padding(.horizontal, 18)
							
							AppStore2026ThreeRowSection(
								title: "الألعاب الأكثر تنزيلاً",
								subtitle: "أقوى الألعاب المختارة لك",
								items: Array(cache.pureGamesOnly.prefix(15))
							)
						}
						
						// قائمة جميع الألعاب
						HStack {
							Text(selectedGameCategory?.rawValue ?? "جميع الألعاب")
								.font(.system(size: 22, weight: .bold))
								.foregroundStyle(.white)
							Spacer()
						}
						.padding(.horizontal, 18)
						
						ForEach(Array(displayedGames.enumerated()), id: \.element.id) { index, item in
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

// MARK: - 4. SEARCH VIEW (بحث ثنائي اللغة عربي + إنجليزي وتصفح الفئات مطابق لـ App Store)
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
		Array(cache.allCombinedItems.prefix(3))
	}
	
	private var searchResults: [AppStoreAppItem] {
		let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !q.isEmpty else { return [] }
		return cache.allCombinedItems.filter { $0.matchesSearch(q) }
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
						// 1. قسم "مقترحات >" (مطابق لصورة App Store)
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
						
						// 2. قسم "تصفح >" (نفس فئات وألوان وترتيب App Store 2026)
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
									let catApps = cache.itemsByCategory[category] ?? []
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
						// نتائج البحث الفوري (عربي أو إنجليزي)
						LazyVStack(spacing: 14) {
							if searchResults.isEmpty {
								VStack(spacing: 12) {
									Image(systemName: "magnifyingglass")
										.font(.system(size: 42))
										.foregroundStyle(.secondary)
									Text("لا توجد نتائج لـ \"\(searchText)\"")
										.font(.headline)
										.foregroundStyle(.white)
									Text("جرب البحث باسم التطبيق بالعربية أو الإنجليزية (مثل: انستقرام أو Instagram)")
										.font(.caption)
										.foregroundStyle(.secondary)
										.multilineTextAlignment(.center)
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
		.onChange(of: viewModel.sources.count) { _ in
			cache.rebuildCacheIfNeeded(sources: _sources, repositoriesMap: viewModel.sources)
		}
	}
}

// MARK: - Top Header with App Icon as Account Avatar
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

// MARK: - Settings & Account Sheet
struct AppStore2026SettingsPopup: View {
	@Environment(\.dismiss) private var dismiss
	let sources: FetchedResults<AltSource>
	@ObservedObject var viewModel: SourcesViewModel
	@State private var isAddingSource = false
	@State private var selectedSection = 0
	
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
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

// MARK: - App Store 2026 UI Components (Translated Subtitles & Authentic Layout)

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
					Text(item.arabicSubtitle)
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
						
						Text(item.arabicSubtitle)
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
				Text(item.arabicSubtitle)
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
				Text(item.arabicSubtitle)
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
			Text(item.category.rawValue)
				.font(.caption2.weight(.bold))
				.foregroundStyle(.blue)
			Text(item.app.currentName)
				.font(.title3.weight(.bold))
				.foregroundStyle(.white)
				.lineLimit(1)
			Text(item.arabicSubtitle)
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
						Text(item.arabicSubtitle)
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
