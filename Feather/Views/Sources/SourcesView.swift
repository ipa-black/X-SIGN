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

// MARK: - Dynamic Visual Identity (White, Black, Ocean Blue + Settings Tint)
enum AppStoreTheme {
	static let oceanBlue = Color(red: 0.00, green: 0.36, blue: 0.73) // #005BBB
	static let deepOcean = Color(red: 0.02, green: 0.16, blue: 0.36) // #05295C
	static let pureBlack = Color.black
	static let cardSurface = Color(red: 0.10, green: 0.11, blue: 0.13)
	
	static var dynamicAccent: Color {
		let hex = UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#005BBB"
		return Color(hex: hex)
	}
}

// MARK: - Protected Sources Vault (IPABLACK + store-api)
enum ProtectedSourcesVault {
	static let coreURLs: [String] = [
		"https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json",
		"https://raw.githubusercontent.com/ipa-black/store-api/main/public/repo.json"
	]
	
	// يحدد سورس IPABLACK المخصص لصفحة اليوم حصرياً
	static func isIPABlackSource(_ sourceURL: URL?, identifier: String? = nil) -> Bool {
		let urlStr = sourceURL?.absoluteString.lowercased() ?? ""
		let idStr = identifier?.lowercased() ?? ""
		return urlStr.contains("/ipablack/") || idStr == "xsign.core.ipablack"
	}
	
	// يخفي السورسين الأساسيين (IPABLACK و store-api) من قائمة المصادر ويمنع تصديرهما
	static func isHiddenCoreSource(_ source: AltSource) -> Bool {
		let urlStr = source.sourceURL?.absoluteString.lowercased() ?? ""
		let idStr = source.identifier?.lowercased() ?? ""
		return urlStr.contains("/ipablack/") ||
			urlStr.contains("store-api") ||
			idStr.contains("xsign.core")
	}
}

// MARK: - Bilingual Search & Localization Engine
enum AppStoreBilingualEngine {
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
		
		if let original = app.currentDescription,
		   original.range(of: "\\p{Arabic}", options: .regularExpression) != nil {
			return original
		}
		return category.defaultArabicSubtitle
	}
}

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

// MARK: - Editorial Instruction Model (Parsed Exclusively from IPA BLACK Source)
struct TodayEditorialInstruction: Identifiable {
	let id: String
	let badge: String
	let title: String
	let caption: String
	let imageURL: URL?
	let tintColor: Color
	let associatedApp: AppStoreAppItem?
}

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
			return [Color(red: 0.04, green: 0.45, blue: 0.85), Color(red: 0.02, green: 0.25, blue: 0.58)]
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
			return [Color(red: 0.08, green: 0.52, blue: 0.92), Color(red: 0.04, green: 0.32, blue: 0.68)]
		case .casualGames:
			return [Color(red: 0.55, green: 0.82, blue: 0.95), Color(red: 0.42, green: 0.72, blue: 0.89)]
		case .timePass:
			return [Color(red: 0.54, green: 0.84, blue: 0.96), Color(red: 0.42, green: 0.75, blue: 0.90)]
		case .mediaReaders:
			return [Color(red: 0.96, green: 0.71, blue: 0.42), Color(red: 0.91, green: 0.58, blue: 0.27)]
		case .productivity:
			return [Color(red: 0.12, green: 0.48, blue: 0.84), Color(red: 0.05, green: 0.28, blue: 0.56)]
		case .strategyGames:
			return [Color(red: 0.54, green: 0.82, blue: 0.48), Color(red: 0.42, green: 0.72, blue: 0.38)]
		case .pvpGames:
			return [Color(red: 0.79, green: 0.56, blue: 0.98), Color(red: 0.68, green: 0.40, blue: 0.93)]
		case .devTools:
			return [Color(red: 0.06, green: 0.42, blue: 0.78), Color(red: 0.02, green: 0.22, blue: 0.48)]
		case .visualArts:
			return [Color(red: 0.55, green: 0.85, blue: 0.96), Color(red: 0.42, green: 0.75, blue: 0.90)]
		case .photoVideo:
			return [Color(red: 0.94, green: 0.79, blue: 0.48), Color(red: 0.88, green: 0.68, blue: 0.34)]
		}
	}
	
	static func strictlyClassify(app: ASRepository.App) -> AppStore2026Category {
		let nameAndBundle = "\(app.name ?? "") \(app.id ?? "") \(app.category ?? "")".lowercased()
		let desc = (app.localizedDescription ?? app.subtitle ?? "").lowercased()
		let combined = "\(nameAndBundle) \(desc)"
		
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

// MARK: - Store Cache Manager (Separates IPA BLACK Exclusively for Today View)
@MainActor
final class AppStoreCacheManager: ObservableObject {
	static let shared = AppStoreCacheManager()
	
	@Published private(set) var ipablackItems: [AppStoreAppItem] = []
	@Published private(set) var ipablackEditorialNews: [TodayEditorialInstruction] = []
	
	@Published private(set) var allCombinedItems: [AppStoreAppItem] = []
	@Published private(set) var pureAppsOnly: [AppStoreAppItem] = []
	@Published private(set) var pureGamesOnly: [AppStoreAppItem] = []
	@Published private(set) var itemsByCategory: [AppStore2026Category: [AppStoreAppItem]] = [:]
	
	private var lastSourceSignature: String = ""
	private var isFetching = false
	private var isBuildingCache = false
	
	func ensureFetched(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
		if !isFetching && viewModel.sources.isEmpty {
			isFetching = true
			await viewModel.fetchSources(sources)
			isFetching = false
		}
		rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
	}
	
	func forceRefresh(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
		guard !isFetching else { return }
		isFetching = true
		await viewModel.fetchSources(sources, refresh: true)
		isFetching = false
		lastSourceSignature = ""
		rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
	}
	
	func rebuildCacheIfNeeded(sources: FetchedResults<AltSource>, repositoriesMap: [AltSource: ASRepository]) {
		guard !isBuildingCache else { return }
		let totalCount = repositoriesMap.values.reduce(0) { $0 + $1.apps.count }
		let signature = "\(sources.count)_\(totalCount)"
		guard signature != lastSourceSignature, totalCount > 0 else { return }
		
		lastSourceSignature = signature
		isBuildingCache = true
		
		let snapshot: [(URL?, String?, ASRepository)] = sources.compactMap { source in
			guard let repo = repositoriesMap[source] else { return nil }
			return (source.sourceURL, source.identifier, repo)
		}
		
		Task.detached(priority: .userInitiated) {
			var allItems: [AppStoreAppItem] = []
			var ipaBlackOnly: [AppStoreAppItem] = []
			var ipaBlackNews: [TodayEditorialInstruction] = []
			
			allItems.reserveCapacity(totalCount)
			var seenKeys = Set<String>()
			
			for (sourceURL, sourceID, repo) in snapshot {
				let isIPABlack = ProtectedSourcesVault.isIPABlackSource(sourceURL, identifier: sourceID)
				let sourceURLString = sourceURL?.absoluteString ?? ""
				
				var currentRepoItems: [AppStoreAppItem] = []
				for app in repo.apps {
					let uniqueKey = "\(app.id ?? app.currentName)_\(sourceURLString)"
					let item = AppStoreAppItem(
						id: uniqueKey,
						sourceURL: sourceURL,
						repository: repo,
						app: app
					)
					if isIPABlack {
						currentRepoItems.append(item)
					}
					if seenKeys.insert(uniqueKey).inserted {
						allItems.append(item)
					}
				}
				
				if isIPABlack {
					ipaBlackOnly.append(contentsOf: currentRepoItems)
					
					if let newsList = repo.news {
						for newsItem in newsList {
							let matchedApp = currentRepoItems.first {
								$0.app.id == newsItem.appID
							} ?? currentRepoItems.first
							
							ipaBlackNews.append(
								TodayEditorialInstruction(
									id: newsItem.id,
									badge: "يحدث الآن",
									title: newsItem.title,
									caption: newsItem.caption,
									imageURL: newsItem.imageURL,
									tintColor: newsItem.tintColor ?? AppStoreTheme.oceanBlue,
									associatedApp: matchedApp
								)
							)
						}
					}
				}
			}
			
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
			
			let finalIPABlack = ipaBlackOnly.isEmpty ? allItems : ipaBlackOnly
			let finalIPABlackNews = ipaBlackNews
			let finalAll = allItems
			let finalApps = onlyApps
			let finalGames = onlyGames
			let finalCats = categoryDict
			
			await MainActor.run {
				let manager = AppStoreCacheManager.shared
				manager.ipablackItems = finalIPABlack
				manager.ipablackEditorialNews = finalIPABlackNews
				manager.allCombinedItems = finalAll
				manager.pureAppsOnly = finalApps
				manager.pureGamesOnly = finalGames
				manager.itemsByCategory = finalCats
				manager.isBuildingCache = false
			}
		}
	}
}

// MARK: - Instant CoreData-Driven Auto-Sign Engine (Zero Delay, Pre-cached Cert)
@MainActor
final class AutoSignPipelineManager: ObservableObject {
	static let shared = AutoSignPipelineManager()
	
	@Published var activeStates: [String: Stage] = [:]
	@Published var readyToInstallApp: AnyApp? = nil
	
	enum Stage: Equatable {
		case downloading
		case signing
		case ready
	}
	
	private var watchTasks: [String: Task<Void, Never>] = [:]
	private var cachedCertificate: CertificatePair? = nil
	
	init() {
		refreshCertificateCache()
	}
	
	func refreshCertificateCache() {
		cachedCertificate = Self.fetchActiveCertificate()
	}
	
	func downloadAndAutoSign(app: ASRepository.App) {
		guard let url = app.currentDownloadUrl else { return }
		let appKey = app.id ?? app.currentName
		
		guard activeStates[appKey] == nil else { return }
		UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
		activeStates[appKey] = .downloading
		
		refreshCertificateCache()
		let existingUUIDs = Set(Self.fetchImportedApps().compactMap { $0.uuid })
		let downloadID = "AutoSign_\(UUID().uuidString)"
		_ = DownloadManager.shared.startDownload(from: url, id: downloadID)
		
		watchTasks[appKey]?.cancel()
		watchTasks[appKey] = Task {
			// فحص فائق السرعة كل 0.12 ثانية لبدء التوقيع في نفس اللحظة التي يكتمل فيها التنزيل
			for _ in 0..<1500 {
				if Task.isCancelled { return }
				try? await Task.sleep(nanoseconds: 120_000_000)
				
				let currentImported = Self.fetchImportedApps()
				if let newlyImported = currentImported.first(where: { item in
					guard let uuid = item.uuid else { return false }
					return !existingUUIDs.contains(uuid)
				}) {
					await triggerInstantSign(for: newlyImported, appKey: appKey)
					return
				}
			}
			activeStates[appKey] = nil
		}
	}
	
	private func triggerInstantSign(for importedApp: Imported, appKey: String) async {
		guard let cert = cachedCertificate ?? Self.fetchActiveCertificate() else {
			activeStates[appKey] = nil
			UIAlertController.showAlertWithOk(
				title: "تم التنزيل",
				message: "تم تنزيل التطبيق، يرجى إضافة شهادة من أيقونة الحساب في الأعلى لتوقيعه تلقائياً."
			)
			return
		}
		
		activeStates[appKey] = .signing
		let options = OptionsManager.shared.options
		
		FR.signPackageFile(
			importedApp,
			using: options,
			icon: nil,
			certificate: cert
		) { [weak self] error in
			DispatchQueue.main.async {
				guard let self else { return }
				if let error {
					self.activeStates[appKey] = nil
					UINotificationFeedbackGenerator().notificationOccurred(.error)
					UIAlertController.showAlertWithOk(
						title: "فشل التوقيع التلقائي",
						message: error.localizedDescription
					)
				} else {
					self.activeStates[appKey] = .ready
					UINotificationFeedbackGenerator().notificationOccurred(.success)
					
					if let latestSigned = Self.fetchSignedApps().first {
						self.readyToInstallApp = AnyApp(base: latestSigned)
					}
					
					DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
						self.activeStates[appKey] = nil
					}
				}
			}
		}
	}
	
	private static func fetchImportedApps() -> [Imported] {
		let request = NSFetchRequest<Imported>(entityName: "Imported")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
		request.fetchLimit = 5
		return (try? Storage.shared.context.fetch(request)) ?? []
	}
	
	private static func fetchSignedApps() -> [Signed] {
		let request = NSFetchRequest<Signed>(entityName: "Signed")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
		request.fetchLimit = 2
		return (try? Storage.shared.context.fetch(request)) ?? []
	}
	
	private static func fetchActiveCertificate() -> CertificatePair? {
		let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
		guard let certs = try? Storage.shared.context.fetch(request), !certs.isEmpty else {
			return nil
		}
		let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		return certs.indices.contains(index) ? certs[index] : certs.first
	}
}

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

// MARK: - 1. TODAY VIEW (Exclusively from IPA BLACK Source)
struct AppStoreTodayView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	@State private var showSettingsSheet = false
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	private var todayApps: [AppStoreAppItem] {
		cache.ipablackItems
	}
	
	private var accentColor: Color {
		Color(hex: userTintHex)
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 26) {
					AppStore2026TopHeader(
						title: "اليوم",
						onSettingsTap: { showSettingsSheet = true }
					)
					
					if todayApps.isEmpty {
						AppStore2026EmptyState(isLoading: !viewModel.isFinished)
							.padding(.horizontal, 18)
							.padding(.top, 30)
					} else {
						ForEach(cache.ipablackEditorialNews) { instruction in
							if let appItem = instruction.associatedApp {
								NavigationLink {
									SourceAppsDetailView(
										sourceURL: appItem.sourceURL,
										source: appItem.repository,
										app: appItem.app
									)
								} label: {
									TodayLiveEventHeroCard(
										outerTitle: nil,
										outerSubtitle: nil,
										cornerBadge: instruction.badge,
										eventTag: "حدث مميز",
										headline: instruction.title,
										descriptionText: instruction.caption,
										bannerImageURL: instruction.imageURL,
										cardColor: instruction.tintColor,
										item: appItem
									)
								}
								.buttonStyle(.plain)
								.padding(.horizontal, 18)
							}
						}
						
						let trendingFour = Array(todayApps.prefix(4))
						if !trendingFour.isEmpty {
							TodayFourAppsListCard(
								outerTitle: nil,
								outerSubtitle: nil,
								innerCaption: "رائج الآن",
								innerTitle: "جرّب هذه التطبيقات الرائجة",
								items: trendingFour
							)
							.padding(.horizontal, 18)
						}
						
						if let hotHero = todayApps.first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: hotHero.sourceURL,
									source: hotHero.repository,
									app: hotHero.app
								)
							} label: {
								TodayLiveEventHeroCard(
									outerTitle: "Hot This Week",
									outerSubtitle: "Catch what's trending on the App Store",
									cornerBadge: "يحدث الآن",
									eventTag: "حدث مميز",
									headline: "اكتشف تجربة \(hotHero.app.currentName) الملحمية",
									descriptionText: hotHero.app.currentDescription ?? hotHero.arabicSubtitle,
									bannerImageURL: hotHero.screenshots.first,
									cardColor: Color(red: 0.78, green: 0.18, blue: 0.12),
									item: hotHero
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						if let secondLive = todayApps.dropFirst().first ?? todayApps.first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: secondLive.sourceURL,
									source: secondLive.repository,
									app: secondLive.app
								)
							} label: {
								TodayLiveEventHeroCard(
									outerTitle: nil,
									outerSubtitle: nil,
									cornerBadge: "متوفر الآن",
									eventTag: "تحديث جديد",
									headline: "انطلق مع \(secondLive.app.currentName)",
									descriptionText: secondLive.arabicSubtitle,
									bannerImageURL: secondLive.screenshots.first,
									cardColor: accentColor,
									item: secondLive
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						let expressGridApps = Array(todayApps.prefix(8))
						if !expressGridApps.isEmpty, let firstTarget = expressGridApps.first {
							NavigationLink {
								AppStore2026CategoryListView(
									category: .topApps,
									items: expressGridApps
								)
							} label: {
								TodayTwoRowIconGridCard(
									outerTitle: "Express Yourself",
									outerSubtitle: nil,
									outerPuzzleIcon: false,
									caption: "من المحرّرين",
									headline: "أقوى إضافات\nالتصميم والتعديل",
									descriptionText: "ارتقِ بصورك وفيديوهاتك وتطبيقاتك مع هذه المجموعة المختارة.",
									gradientColors: [
										Color(red: 0.34, green: 0.38, blue: 0.38),
										accentColor.opacity(0.88),
										Color(red: 0.25, green: 0.56, blue: 0.78)
									],
									items: expressGridApps,
									fallbackItem: firstTarget
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						let arcadeStyleFour = Array(todayApps.dropFirst(2).prefix(4))
						if !arcadeStyleFour.isEmpty {
							TodayFourAppsListCard(
								outerTitle: "اكتشف IPA BLACK",
								outerSubtitle: "تصفح أقوى التطبيقات المعدلة والحصرية بضغطة واحدة.",
								innerCaption: "هيا نبدأ",
								innerTitle: "تطبيقات حصرية جاهزة للتثبيت الفوري",
								items: arcadeStyleFour
							)
							.padding(.horizontal, 18)
						}
						
						if let fullArtworkItem = todayApps.dropFirst(3).first ?? todayApps.last {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: fullArtworkItem.sourceURL,
									source: fullArtworkItem.repository,
									app: fullArtworkItem.app
								)
							} label: {
								TodayFullArtworkDockCard(
									categoryTag: "تطبيقات نُحبها",
									headline: fullArtworkItem.app.currentName,
									subtitle: fullArtworkItem.arabicSubtitle,
									showPlayBadge: true,
									item: fullArtworkItem
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						let classicGridApps = Array(todayApps.reversed().prefix(8))
						if !classicGridApps.isEmpty, let fallback = classicGridApps.first {
							NavigationLink {
								AppStore2026CategoryListView(
									category: .bestSellingApps,
									items: classicGridApps
								)
							} label: {
								TodayTwoRowIconGridCard(
									outerTitle: "إصدارات كلاسيكية شهيرة",
									outerSubtitle: "عش أجواء التميز مع هذه التطبيقات المختارة",
									outerPuzzleIcon: false,
									caption: "هيا نبدأ",
									headline: "تطبيقات تأخذك إلى القمة",
									descriptionText: nil,
									gradientColors: [
										Color(red: 0.42, green: 0.48, blue: 0.36),
										Color(red: 0.30, green: 0.62, blue: 0.30),
										Color(red: 0.22, green: 0.54, blue: 0.24)
									],
									items: classicGridApps,
									fallbackItem: fallback
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						if let tipsItem = todayApps.dropFirst(4).first ?? todayApps.first {
							NavigationLink {
								SourceAppsDetailView(
									sourceURL: tipsItem.sourceURL,
									source: tipsItem.repository,
									app: tipsItem.app
								)
							} label: {
								TodayEditorialTipsCard(item: tipsItem)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
						
						let worldGridApps = Array(todayApps.shuffled().prefix(8))
						if !worldGridApps.isEmpty, let worldFallback = worldGridApps.first {
							NavigationLink {
								AppStore2026CategoryListView(
									category: .topApps,
									items: worldGridApps
								)
							} label: {
								TodayTwoRowIconGridCard(
									outerTitle: "شيّد عوالم مذهلة",
									outerSubtitle: "اصنع وابتكر في هذه التطبيقات الرائعة",
									outerPuzzleIcon: true,
									caption: "المفضلة لدينا",
									headline: "شيّد الأمجاد الرائعة",
									descriptionText: nil,
									gradientColors: [
										Color(red: 0.48, green: 0.46, blue: 0.62),
										Color(red: 0.56, green: 0.66, blue: 0.78),
										Color(red: 0.46, green: 0.60, blue: 0.72)
									],
									items: worldGridApps,
									fallbackItem: worldFallback
								)
							}
							.buttonStyle(.plain)
							.padding(.horizontal, 18)
						}
					}
				}
				.padding(.bottom, 105)
			}
			.background(Color.black.ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
			.refreshable {
				await cache.forceRefresh(sources: _sources, viewModel: viewModel)
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

// MARK: - 2. APPS VIEW
struct SourcesView: View {
	@StateObject var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	@State private var _isSettingsPresenting = false
	@State private var _selectedAppCategory: AppStore2026Category? = nil
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
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
	
	private var accentColor: Color {
		Color(hex: userTintHex)
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 24) {
					AppStore2026TopHeader(
						title: "التطبيقات",
						onSettingsTap: { _isSettingsPresenting = true }
					)
					
					if cache.pureAppsOnly.isEmpty {
						AppStore2026EmptyState(isLoading: !viewModel.isFinished)
							.padding(.horizontal, 18)
							.padding(.top, 30)
					} else {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								Button {
									_selectedAppCategory = nil
								} label: {
									Text("الكل")
										.font(.subheadline.weight(.bold))
										.foregroundStyle(_selectedAppCategory == nil ? .white : .white.opacity(0.85))
										.padding(.horizontal, 18)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(_selectedAppCategory == nil ? accentColor : Color(white: 0.14))
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
										.foregroundStyle(.white)
										.padding(.horizontal, 16)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(_selectedAppCategory == cat ? accentColor : Color(white: 0.14))
										)
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.horizontal, 18)
						}
						
						if _selectedAppCategory == nil {
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
							
							AppStore2026ThreeRowSection(
								title: "التطبيقات الأكثر تنزيلاً",
								subtitle: "أفضل التطبيقات المختارة لك",
								items: Array(cache.pureAppsOnly.prefix(18))
							)
							
							let socialApps = cache.pureAppsOnly.filter { $0.category == .social }
							if !socialApps.isEmpty {
								TodayFourAppsListCard(
									outerTitle: "تواصل بلا حدود",
									outerSubtitle: "أحدث نسخ تطبيقات التواصل الاجتماعي",
									innerCaption: "التواصل الاجتماعي",
									innerTitle: "تطبيقات المحادثة والمشاركة",
									items: Array(socialApps.prefix(4))
								)
								.padding(.horizontal, 18)
							}
						}
						
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
									AppStore2026AppRow(item: item)
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

// MARK: - 3. GAMES VIEW
struct AppStoreGamesView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	@State private var showSettingsSheet = false
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
	
	private var accentColor: Color {
		Color(hex: userTintHex)
	}
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 24) {
					AppStore2026TopHeader(
						title: "الألعاب",
						onSettingsTap: { showSettingsSheet = true }
					)
					
					if cache.pureGamesOnly.isEmpty {
						AppStore2026EmptyState(isLoading: !viewModel.isFinished)
							.padding(.horizontal, 18)
							.padding(.top, 20)
					} else {
						ScrollView(.horizontal, showsIndicators: false) {
							HStack(spacing: 10) {
								Button {
									selectedGameCategory = nil
								} label: {
									Text("كل الألعاب")
										.font(.subheadline.weight(.bold))
										.foregroundStyle(.white)
										.padding(.horizontal, 18)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(selectedGameCategory == nil ? accentColor : Color(white: 0.14))
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
										.foregroundStyle(.white)
										.padding(.horizontal, 16)
										.padding(.vertical, 9)
										.background(
											Capsule(style: .continuous)
												.fill(selectedGameCategory == cat ? accentColor : Color(white: 0.14))
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
									TodayLiveEventHeroCard(
										outerTitle: nil,
										outerSubtitle: nil,
										cornerBadge: "يحدث الآن",
										eventTag: "رائج الآن",
										headline: "العب مواجهة \(heroGame.app.currentName)",
										descriptionText: heroGame.arabicSubtitle,
										bannerImageURL: heroGame.screenshots.first,
										cardColor: accentColor,
										item: heroGame
									)
								}
								.buttonStyle(.plain)
								.padding(.horizontal, 18)
							}
							
							TodayFourAppsListCard(
								outerTitle: "واصل الركض!",
								outerSubtitle: "إلى متى يمكنك الصمود في هذه الألعاب؟",
								innerCaption: "أفضل الألعاب",
								innerTitle: "جرّب هذه الألعاب الرائجة",
								items: Array(cache.pureGamesOnly.prefix(4))
							)
							.padding(.horizontal, 18)
							
							AppStore2026ThreeRowSection(
								title: "الألعاب الأكثر تنزيلاً",
								subtitle: "أقوى الألعاب المختارة لك",
								items: Array(cache.pureGamesOnly.prefix(15))
							)
						}
						
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
									AppStore2026AppRow(item: item)
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

// MARK: - 4. SEARCH VIEW
struct AppStoreSearchView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var searchText = ""
	@State private var showSettingsSheet = false
	
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
						onSettingsTap: { showSettingsSheet = true }
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
												AppStore2026AppRow(item: item)
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
						LazyVStack(spacing: 14) {
							if searchResults.isEmpty {
								VStack(spacing: 12) {
									Image(systemName: "magnifyingglass")
										.font(.system(size: 42))
										.foregroundStyle(.secondary)
									Text("لا توجد نتائج لـ \"\(searchText)\"")
										.font(.headline)
										.foregroundStyle(.white)
									Text("جرب البحث بالعربية أو الإنجليزية (مثل: انستقرام أو Instagram)")
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

// MARK: - Top Header (Only Account Avatar Remains - No "+" Button)
struct AppStore2026TopHeader: View {
	let title: String
	let onSettingsTap: () -> Void
	@ObservedObject private var autoSign = AutoSignPipelineManager.shared
	
	var body: some View {
		HStack(alignment: .center) {
			Text(title)
				.font(.system(size: 34, weight: .heavy))
				.foregroundStyle(.white)
			
			Spacer()
			
			AppStoreAccountAppIconButton(action: onSettingsTap)
		}
		.padding(.horizontal, 18)
		.padding(.top, 10)
		.sheet(item: $autoSign.readyToInstallApp) { signedApp in
			InstallPreviewView(app: signedApp.base, isSharing: signedApp.archive)
				.presentationDetents([.height(200)])
				.presentationDragIndicator(.visible)
		}
	}
}

struct AppStoreAccountAppIconButton: View {
	let action: () -> Void
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
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
							colors: [Color(hex: userTintHex), AppStoreTheme.deepOcean],
							startPoint: .topLeading,
							endPoint: .bottomTrailing
						)
						Image(systemName: "person.fill")
							.font(.system(size: 17, weight: .bold))
							.foregroundStyle(.white)
					}
				}
			}
			.frame(width: 38, height: 38)
			.clipShape(Circle())
			.overlay(
				Circle()
					.stroke(Color(hex: userTintHex).opacity(0.65), lineWidth: 1.2)
			)
		}
		.buttonStyle(.plain)
	}
}

// MARK: - Authentic Apple App Store Today Cards

struct TodayLiveEventHeroCard: View {
	let outerTitle: String?
	let outerSubtitle: String?
	let cornerBadge: String
	let eventTag: String
	let headline: String
	let descriptionText: String
	let bannerImageURL: URL?
	let cardColor: Color
	let item: AppStoreAppItem
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let outerTitle {
				VStack(alignment: .leading, spacing: 2) {
					Text(outerTitle)
						.font(.system(size: 22, weight: .heavy))
						.foregroundStyle(.white)
					if let outerSubtitle {
						Text(outerSubtitle)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.horizontal, 2)
			}
			
			VStack(spacing: 0) {
				ZStack(alignment: .topLeading) {
					ZStack(alignment: .bottomLeading) {
						LinearGradient(
							colors: [
								cardColor,
								cardColor.opacity(0.82),
								Color(red: 0.08, green: 0.08, blue: 0.10)
							],
							startPoint: .top,
							endPoint: .bottom
						)
						
						if let bannerURL = bannerImageURL {
							LazyImage(url: bannerURL) { state in
								if let image = state.image {
									image
										.resizable()
										.scaledToFill()
										.frame(height: 350)
										.clipped()
										.opacity(0.55)
								}
							}
							.processors([.resize(size: CGSize(width: 500, height: 500))])
						} else {
							AppStoreIconView(url: item.app.iconURL, size: 138)
								.shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
								.frame(maxWidth: .infinity, maxHeight: .infinity)
								.offset(y: -38)
						}
						
						LinearGradient(
							colors: [.clear, cardColor.opacity(0.88), cardColor],
							startPoint: .center,
							endPoint: .bottom
						)
						
						VStack(alignment: .leading, spacing: 6) {
							Text(eventTag)
								.font(.system(size: 13, weight: .bold))
								.foregroundStyle(.white.opacity(0.9))
							
							Text(headline)
								.font(.system(size: 28, weight: .heavy))
								.foregroundStyle(.white)
								.lineLimit(2)
								.multilineTextAlignment(.leading)
							
							Text(descriptionText)
								.font(.system(size: 14, weight: .medium))
								.foregroundStyle(.white.opacity(0.88))
								.lineLimit(2)
								.multilineTextAlignment(.leading)
						}
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 20)
						.padding(.bottom, 18)
					}
					.frame(height: 350)
					
					Text(cornerBadge)
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.white)
						.padding(.horizontal, 16)
						.padding(.vertical, 8)
						.background(
							UnevenRoundedRectangle(
								topLeadingRadius: 26,
								bottomLeadingRadius: 0,
								bottomTrailingRadius: 16,
								topTrailingRadius: 0,
								style: .continuous
							)
							.fill(Color.black.opacity(0.38))
						)
				}
				
				Divider()
					.background(Color.white.opacity(0.14))
				
				HStack(spacing: 12) {
					AppStoreIconView(url: item.app.iconURL, size: 52)
					
					VStack(alignment: .leading, spacing: 2) {
						Text(item.app.currentName)
							.font(.system(size: 16, weight: .bold))
							.foregroundStyle(.white)
							.lineLimit(1)
						Text(item.arabicSubtitle)
							.font(.system(size: 13))
							.foregroundStyle(.white.opacity(0.8))
							.lineLimit(1)
					}
					
					Spacer()
					
					AppStore2026DownloadButton(app: item.app, isLightPill: true)
				}
				.padding(.horizontal, 18)
				.padding(.vertical, 14)
				.background(cardColor.opacity(0.92))
			}
			.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.stroke(Color.white.opacity(0.10), lineWidth: 0.7)
			)
		}
	}
}

struct TodayTwoRowIconGridCard: View {
	let outerTitle: String?
	let outerSubtitle: String?
	let outerPuzzleIcon: Bool
	let caption: String
	let headline: String
	let descriptionText: String?
	let gradientColors: [Color]
	let items: [AppStoreAppItem]
	let fallbackItem: AppStoreAppItem
	
	private var topRowItems: [AppStoreAppItem] {
		Array(items.prefix(4))
	}
	
	private var bottomRowItems: [AppStoreAppItem] {
		let rest = Array(items.dropFirst(4).prefix(4))
		return rest.isEmpty ? Array(items.reversed().prefix(4)) : rest
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			if let outerTitle {
				VStack(alignment: .leading, spacing: 3) {
					HStack(spacing: 6) {
						if outerPuzzleIcon {
							Image(systemName: "puzzlepiece.extension.fill")
								.font(.system(size: 20))
								.foregroundStyle(Color(red: 0.35, green: 0.72, blue: 0.98))
						}
						Text(outerTitle)
							.font(.system(size: 22, weight: .heavy))
							.foregroundStyle(.white)
					}
					if let outerSubtitle {
						Text(outerSubtitle)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.horizontal, 2)
			}
			
			ZStack(alignment: .bottomLeading) {
				LinearGradient(
					colors: gradientColors,
					startPoint: .top,
					endPoint: .bottom
				)
				
				VStack(spacing: 16) {
					HStack(spacing: 14) {
						ForEach(topRowItems) { appItem in
							AppStoreIconView(url: appItem.app.iconURL, size: 84)
								.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
						}
					}
					.offset(x: 16)
					
					HStack(spacing: 14) {
						ForEach(bottomRowItems) { appItem in
							AppStoreIconView(url: appItem.app.iconURL, size: 84)
								.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
						}
					}
					.offset(x: -16)
					
					Spacer()
				}
				.padding(.top, 28)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
				
				LinearGradient(
					colors: [.clear, gradientColors.last?.opacity(0.95) ?? .black],
					startPoint: .center,
					endPoint: .bottom
				)
				
				VStack(alignment: .leading, spacing: 6) {
					Text(caption)
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.white.opacity(0.88))
					
					Text(headline)
						.font(.system(size: 28, weight: .heavy))
						.foregroundStyle(.white)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
					
					if let descriptionText {
						Text(descriptionText)
							.font(.system(size: 14, weight: .medium))
							.foregroundStyle(.white.opacity(0.90))
							.lineLimit(2)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(22)
			}
			.frame(height: 365)
			.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.stroke(Color.white.opacity(0.10), lineWidth: 0.7)
			)
		}
	}
}

struct TodayFourAppsListCard: View {
	let outerTitle: String?
	let outerSubtitle: String?
	let innerCaption: String
	let innerTitle: String
	let items: [AppStoreAppItem]
	
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if let outerTitle {
				VStack(alignment: .leading, spacing: 3) {
					Text(outerTitle)
						.font(.system(size: 22, weight: .heavy))
						.foregroundStyle(.white)
					if let outerSubtitle {
						Text(outerSubtitle)
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
				}
				.padding(.horizontal, 4)
			}
			
			VStack(alignment: .leading, spacing: 18) {
				VStack(alignment: .leading, spacing: 4) {
					Text(innerCaption)
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.secondary)
					Text(innerTitle)
						.font(.system(size: 27, weight: .heavy))
						.foregroundStyle(.white)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
				}
				
				VStack(spacing: 14) {
					ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
						NavigationLink {
							SourceAppsDetailView(
								sourceURL: item.sourceURL,
								source: item.repository,
								app: item.app
							)
						} label: {
							AppStore2026AppRow(item: item)
						}
						.buttonStyle(.plain)
						
						if index < min(items.count, 4) - 1 {
							Divider()
								.background(Color.white.opacity(0.08))
								.padding(.leading, 70)
						}
					}
				}
			}
			.padding(20)
			.background(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.fill(AppStoreTheme.cardSurface)
			)
			.overlay(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.stroke(Color.white.opacity(0.07), lineWidth: 0.6)
			)
		}
	}
}

struct TodayFullArtworkDockCard: View {
	let categoryTag: String
	let headline: String
	let subtitle: String
	let showPlayBadge: Bool
	let item: AppStoreAppItem
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	private var baseColor: Color {
		item.app.tintColor ?? Color(hex: userTintHex)
	}
	
	var body: some View {
		VStack(spacing: 0) {
			ZStack(alignment: .bottomLeading) {
				LinearGradient(
					colors: [
						baseColor.opacity(0.75),
						Color(red: 0.16, green: 0.28, blue: 0.42),
						Color(red: 0.12, green: 0.20, blue: 0.30)
					],
					startPoint: .topTrailing,
					endPoint: .bottomLeading
				)
				
				if let firstScreen = item.screenshots.first {
					LazyImage(url: firstScreen) { state in
						if let image = state.image {
							image
								.resizable()
								.scaledToFill()
								.frame(height: 330)
								.clipped()
						}
					}
					.processors([.resize(size: CGSize(width: 500, height: 500))])
				} else {
					AppStoreIconView(url: item.app.iconURL, size: 128)
						.shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.offset(y: -35)
				}
				
				if showPlayBadge {
					Circle()
						.fill(.ultraThinMaterial)
						.frame(width: 58, height: 58)
						.overlay {
							Image(systemName: "play.fill")
								.font(.system(size: 22))
								.foregroundStyle(.white)
								.offset(x: 2)
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.offset(y: -30)
				}
				
				LinearGradient(
					colors: [.clear, Color.black.opacity(0.78)],
					startPoint: .center,
					endPoint: .bottom
				)
				
				VStack(alignment: .leading, spacing: 5) {
					Text(categoryTag)
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.white.opacity(0.88))
					Text(headline)
						.font(.system(size: 28, weight: .heavy))
						.foregroundStyle(.white)
						.lineLimit(2)
					Text(subtitle)
						.font(.system(size: 14, weight: .medium))
						.foregroundStyle(.white.opacity(0.88))
						.lineLimit(2)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.bottom, 16)
			}
			.frame(height: 330)
			
			HStack(spacing: 12) {
				AppStoreIconView(url: item.app.iconURL, size: 50)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(item.app.currentName)
						.font(.system(size: 16, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
					Text(item.category.rawValue)
						.font(.caption)
						.foregroundStyle(.white.opacity(0.75))
						.lineLimit(1)
				}
				
				Spacer()
				
				AppStore2026DownloadButton(app: item.app, isLightPill: true)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 14)
			.background(Color(red: 0.16, green: 0.22, blue: 0.28))
		}
		.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 28, style: .continuous)
				.stroke(Color.white.opacity(0.10), lineWidth: 0.6)
		)
	}
}

struct TodayEditorialTipsCard: View {
	let item: AppStoreAppItem
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	var body: some View {
		VStack(spacing: 0) {
			ZStack(alignment: .bottomLeading) {
				LinearGradient(
					colors: [
						Color(hex: userTintHex).opacity(0.35),
						Color(red: 0.05, green: 0.18, blue: 0.36),
						Color(red: 0.03, green: 0.12, blue: 0.24)
					],
					startPoint: .topLeading,
					endPoint: .bottomTrailing
				)
				
				AppStoreIconView(url: item.app.iconURL, size: 132)
					.shadow(color: .black.opacity(0.45), radius: 16, x: 0, y: 8)
					.frame(maxWidth: .infinity, maxHeight: .infinity)
					.offset(y: -36)
				
				VStack(alignment: .leading, spacing: 4) {
					Text("البدء")
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.white.opacity(0.80))
					Text("٥ نصائح لاحتراف\n\(item.app.currentName)")
						.font(.system(size: 27, weight: .heavy))
						.foregroundStyle(.white)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.horizontal, 20)
				.padding(.bottom, 18)
			}
			.frame(height: 315)
			
			Divider()
				.background(Color.white.opacity(0.12))
			
			HStack(spacing: 12) {
				AppStoreIconView(url: item.app.iconURL, size: 50)
				
				VStack(alignment: .leading, spacing: 2) {
					Text(item.app.currentName)
						.font(.system(size: 16, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
					Text(item.arabicSubtitle)
						.font(.caption)
						.foregroundStyle(.white.opacity(0.75))
						.lineLimit(1)
				}
				
				Spacer()
				
				AppStore2026DownloadButton(app: item.app, isLightPill: true)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 14)
			.background(Color(red: 0.04, green: 0.14, blue: 0.28))
		}
		.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 28, style: .continuous)
				.stroke(Color.white.opacity(0.10), lineWidth: 0.6)
		)
	}
}

// MARK: - Settings Popup (Core Sources Hidden & Protected)
struct AppStore2026SettingsPopup: View {
	@Environment(\.dismiss) private var dismiss
	let sources: FetchedResults<AltSource>
	@ObservedObject var viewModel: SourcesViewModel
	@State private var isAddingSource = false
	@State private var selectedSection = 0
	
	private var userAddedSourcesOnly: [AltSource] {
		sources.filter { !ProtectedSourcesVault.isHiddenCoreSource($0) }
	}
	
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
						Text("الشهادات").tag(1)
						Text("مصادري (\(userAddedSourcesOnly.count))").tag(2)
					}
					.pickerStyle(.segmented)
				}
				.padding(.horizontal, 18)
				.padding(.vertical, 12)
				.background(Color(uiColor: .secondarySystemGroupedBackground))
				
				if selectedSection == 0 {
					SettingsView()
				} else if selectedSection == 1 {
					CertificatesView()
				} else {
					List {
						Section {
							Button {
								isAddingSource = true
							} label: {
								Label("إضافة مصدر (سورس) خاص بك", systemImage: "plus.circle.fill")
									.font(.body.weight(.semibold))
							}
						} footer: {
							Text("جميع المصادر المضافة هنا محمية ولا يمكن تصدير أو نسخ روابطها.")
								.font(.caption2)
						}
						
						if !userAddedSourcesOnly.isEmpty {
							Section("المصادر الإضافية") {
								ForEach(userAddedSourcesOnly) { source in
									HStack(spacing: 12) {
										Image(systemName: "shippingbox.fill")
											.font(.system(size: 20))
											.foregroundStyle(AppStoreTheme.dynamicAccent)
											.frame(width: 38, height: 38)
											.background(AppStoreTheme.dynamicAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
										
										VStack(alignment: .leading, spacing: 2) {
											Text(source.name ?? "مصدر مضاف")
												.font(.body.weight(.bold))
												.foregroundStyle(.white)
											Text("مصدر مفعل • الرابط مخفي للحماية")
												.font(.caption2)
												.foregroundStyle(.secondary)
										}
										Spacer()
									}
									.padding(.vertical, 4)
									.swipeActions(edge: .trailing, allowsFullSwipe: true) {
										Button(role: .destructive) {
											Storage.shared.deleteSource(for: source)
										} label: {
											Label("حذف", systemImage: "trash")
										}
									}
								}
							}
						}
					}
				}
			}
			.toolbar(.hidden, for: .navigationBar)
			.sheet(isPresented: $isAddingSource) {
				CustomSafeAddSourceSheet()
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
	}
}

struct CustomSafeAddSourceSheet: View {
	@Environment(\.dismiss) private var dismiss
	@State private var sourceURLText = ""
	@State private var isSaving = false
	
	var body: some View {
		NavigationStack {
			Form {
				Section("رابط المصدر (JSON URL)") {
					TextField("https://example.com/repo.json", text: $sourceURLText)
						.keyboardType(.URL)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
				}
				
				Section {
					Button {
						addSource()
					} label: {
						HStack {
							Spacer()
							if isSaving {
								ProgressView()
							} else {
								Text("إضافة المصدر")
									.font(.body.weight(.bold))
							}
							Spacer()
						}
					}
					.disabled(sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
				}
			}
			.navigationTitle("إضافة مصدر")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button("إلغاء") {
						dismiss()
					}
				}
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
	}
	
	private func addSource() {
		let trimmed = sourceURLText.trimmingCharacters(in: .whitespacesAndNewlines)
		guard URL(string: trimmed) != nil else { return }
		isSaving = true
		FR.handleSource(trimmed) {
			isSaving = false
			dismiss()
		}
	}
}

// MARK: - Unified Download & Auto-Sign Button (Always Shows "تنزيل" Capsule - No Cloud Icon)
struct AppStore2026DownloadButton: View {
	let app: ASRepository.App
	var useCloudStyle: Bool = false
	var isLightPill: Bool = false
	@ObservedObject private var pipeline = AutoSignPipelineManager.shared
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	private var accentColor: Color {
		Color(hex: userTintHex)
	}
	
	private var appKey: String {
		app.id ?? app.currentName
	}
	
	private var currentStage: AutoSignPipelineManager.Stage? {
		pipeline.activeStates[appKey]
	}
	
	var body: some View {
		Button {
			pipeline.downloadAndAutoSign(app: app)
		} label: {
			switch currentStage {
			case .downloading:
				HStack(spacing: 5) {
					ProgressView()
						.tint(.white)
						.scaleEffect(0.75)
					Text("تنزيل...")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.white)
				}
				.frame(width: 82, height: 32)
				.background(Capsule().fill(accentColor.opacity(0.65)))
				
			case .signing:
				HStack(spacing: 5) {
					ProgressView()
						.tint(.white)
						.scaleEffect(0.75)
					Text("توقيع...")
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(.white)
				}
				.frame(width: 82, height: 32)
				.background(Capsule().fill(accentColor))
				
			case .ready:
				HStack(spacing: 4) {
					Image(systemName: "checkmark")
						.font(.system(size: 11, weight: .bold))
					Text("تثبيت")
						.font(.system(size: 13, weight: .bold))
				}
				.foregroundStyle(.white)
				.frame(width: 78, height: 32)
				.background(Capsule().fill(Color.green))
				
			case nil:
				VStack(spacing: 3) {
					Text("تنزيل")
						.font(.system(size: 15, weight: .bold))
						.foregroundStyle(isLightPill ? .white : accentColor)
						.frame(width: 78, height: 32)
						.background(
							Capsule(style: .continuous)
								.fill(isLightPill ? Color.white.opacity(0.24) : Color(white: 0.18))
						)
					
					Text("الشراء داخل التطبيق")
						.font(.system(size: 7.5, weight: .medium))
						.foregroundStyle(isLightPill ? .white.opacity(0.75) : .secondary)
						.lineLimit(1)
				}
			}
		}
		.buttonStyle(.plain)
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
			
			AppStore2026DownloadButton(app: item.app)
		}
	}
}

struct AppStore2026SuggestedHighlightRow: View {
	let item: AppStoreAppItem
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
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
					.background(Color(hex: userTintHex), in: RoundedRectangle(cornerRadius: 4))
			}
			
			Spacer()
			
			AppStore2026DownloadButton(app: item.app)
		}
		.padding(12)
		.background(
			RoundedRectangle(cornerRadius: 20, style: .continuous)
				.fill(Color(red: 0.08, green: 0.13, blue: 0.22))
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
					ForEach(items) { item in
						NavigationLink {
							SourceAppsDetailView(
								sourceURL: item.sourceURL,
								source: item.repository,
								app: item.app
							)
						} label: {
							AppStore2026AppRow(item: item)
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
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	private var bannerColor: Color {
		item.app.tintColor ?? Color(hex: userTintHex)
	}
	
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text(item.category.rawValue)
				.font(.caption2.weight(.bold))
				.foregroundStyle(Color(hex: userTintHex))
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
					colors: [bannerColor.opacity(0.88), AppStoreTheme.deepOcean],
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
					
					AppStore2026DownloadButton(app: item.app, isLightPill: true)
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
			AppStore2026AppRow(item: item)
			
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
				.fill(AppStoreTheme.cardSurface)
		)
	}
}

struct AppStore2026CategoryListView: View {
	let category: AppStore2026Category
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
						AppStore2026AppRow(item: item)
							.padding(14)
							.background(
								RoundedRectangle(cornerRadius: 20, style: .continuous)
									.fill(AppStoreTheme.cardSurface)
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
				.stroke(Color.white.opacity(0.14), lineWidth: 0.6)
		)
	}
	
	private var placeholder: some View {
		RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
			.fill(Color(white: 0.18))
	}
}

struct AppStore2026EmptyState: View {
	let isLoading: Bool
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	var body: some View {
		VStack(spacing: 16) {
			ProgressView()
				.tint(Color(hex: userTintHex))
				.scaleEffect(1.3)
			Text("جاري مزامنة المتجر...")
				.font(.subheadline.weight(.semibold))
				.foregroundStyle(.white)
		}
		.frame(maxWidth: .infinity)
		.padding(36)
		.background(
			RoundedRectangle(cornerRadius: 26, style: .continuous)
				.fill(AppStoreTheme.cardSurface)
		)
	}
}
