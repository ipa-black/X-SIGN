//
//  SourcesView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import AltSourceKit
import SwiftUI
import NaturalLanguage
import Translation
import NimbleViews
import NukeUI
import Nuke
import UIKit

// MARK: - Dynamic Visual Identity (White, Black, Ocean Blue + Settings Tint)
enum AppStoreTheme {
	nonisolated static let oceanBlue = Color(red: 0.00, green: 0.36, blue: 0.73) // #005BBB
	nonisolated static let deepOcean = Color(red: 0.02, green: 0.16, blue: 0.36) // #05295C
	nonisolated static let pureBlack = Color.black
	nonisolated static let cardSurface = Color(red: 0.10, green: 0.11, blue: 0.13)
	
	static var dynamicAccent: Color {
		let hex = UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#005BBB"
		return Color(hex: hex)
	}
}

// MARK: - Protected Sources Vault (IPABLACK + store-api)
enum ProtectedSourcesVault {
	nonisolated static let ipaBlackURLString = "https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json"
	nonisolated static let storeAPIURLString = "https://raw.githubusercontent.com/ipa-black/store-api/main/public/repo.json"
	
	nonisolated static let coreURLs: [String] = [
		ipaBlackURLString,
		storeAPIURLString
	]
	
	nonisolated static func isIPABlackSource(_ sourceURL: URL?, identifier: String? = nil) -> Bool {
		let urlStr = sourceURL?.absoluteString.lowercased() ?? ""
		let idStr = identifier?.lowercased() ?? ""
		return urlStr.contains("/ipablack/") || idStr == "xsign.core.ipablack"
	}
	
	nonisolated static func isHiddenCoreSource(_ source: AltSource) -> Bool {
		let urlStr = source.sourceURL?.absoluteString.lowercased() ?? ""
		let idStr = source.identifier?.lowercased() ?? ""
		return urlStr.contains("/ipablack/") ||
			urlStr.contains("store-api") ||
			idStr.contains("xsign.core")
	}
}

// MARK: - Rich Apple App Store Metadata Model (Skips Deleted Apps Automatically)
struct AppleStoreRichMetadata: Codable, Sendable {
	let screenshots: [URL]
	let artworkURL: URL?
	let description: String?
	let releaseNotes: String?
	let sellerName: String?
	let genre: String?
	let contentRating: String?
	let rating: Double?
	let fileSizeBytes: Int64?
}

actor AppStoreLiveMetadataBridge {
	static let shared = AppStoreLiveMetadataBridge()
	
	private var memoryCache: [String: AppleStoreRichMetadata] = [:]
	private var negativeCache: Set<String> = []
	private var inFlightTasks: [String: Task<AppleStoreRichMetadata?, Never>] = [:]
	
	private nonisolated static var diskCacheDir: URL {
		let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("XSignAppleMetadataCache_SA_v5", isDirectory: true)
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}
	
	// إذا كانت الأيقونة مستخرجة من ملفات التطبيق ومرفوعة على GitHub، فالتطبيق محذوف من متجر أبل ولا نطلب أي صور من أبل
	nonisolated static func hasExtractedGitHubIcon(_ iconURL: URL?) -> Bool {
		guard let str = iconURL?.absoluteString.lowercased() else { return false }
		return str.contains("/assets/icons/")
	}
	
	func fetchMetadata(bundleID: String?, appName: String, iconURL: URL? = nil) async -> AppleStoreRichMetadata? {
		// تخطي متجر أبل نهائياً إذا كان التطبيق يستخدم أيقونة مستخرجة من ملفاته على GitHub
		if Self.hasExtractedGitHubIcon(iconURL) {
			return nil
		}
		
		let cacheKey = "\(bundleID ?? "")_\(appName)".lowercased()
			.replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
		
		if negativeCache.contains(cacheKey) {
			return nil
		}
		
		if let cached = memoryCache[cacheKey] {
			return cached
		}
		
		let diskFile = Self.diskCacheDir.appendingPathComponent("\(cacheKey).json")
		if let data = try? Data(contentsOf: diskFile),
		   let decoded = try? JSONDecoder().decode(AppleStoreRichMetadata.self, from: data) {
			memoryCache[cacheKey] = decoded
			return decoded
		}
		
		if let existingTask = inFlightTasks[cacheKey] {
			return await existingTask.value
		}
		
		let task = Task<AppleStoreRichMetadata?, Never> {
			// الفحص يتم حصرياً عبر الـ Bundle ID؛ إذا كان التطبيق محذوفاً من المتجر نتوقف فوراً ولا نجلب صوراً عشوائية بالاسم
			guard let bID = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
				  bID.contains("."),
				  !bID.hasPrefix("games."),
				  bID != "com.ipablack.app",
				  let encodedID = bID.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
			else {
				return nil
			}
			
			if let found = await Self.queryiTunes(
				urlString: "https://itunes.apple.com/lookup?bundleId=\(encodedID)&country=SA"
			) {
				return found
			}
			
			if let foundUS = await Self.queryiTunes(
				urlString: "https://itunes.apple.com/lookup?bundleId=\(encodedID)&country=US"
			) {
				return foundUS
			}
			
			// التطبيق محذوف من متجر أبل -> لا نجلب أي صور من أبل
			return nil
		}
		
		inFlightTasks[cacheKey] = task
		let result = await task.value
		inFlightTasks.removeValue(forKey: cacheKey)
		
		if let result {
			memoryCache[cacheKey] = result
			if let encodedData = try? JSONEncoder().encode(result) {
				try? encodedData.write(to: diskFile, options: .atomic)
			}
		} else {
			negativeCache.insert(cacheKey)
		}
		return result
	}
	
	private nonisolated static func queryiTunes(urlString: String) async -> AppleStoreRichMetadata? {
		guard let url = URL(string: urlString) else { return nil }
		do {
			var request = URLRequest(url: url)
			request.timeoutInterval = 6
			request.setValue("ar-SA,ar;q=0.9", forHTTPHeaderField: "Accept-Language")
			let (data, response) = try await URLSession.shared.data(for: request)
			guard let http = response as? HTTPURLResponse,
			      (200..<300).contains(http.statusCode) else { return nil }
			guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let results = json["results"] as? [[String: Any]],
				  let first = results.first else {
				return nil
			}
			
			var screenshots = (first["screenshotUrls"] as? [String])?.compactMap { URL(string: $0) } ?? []
			if screenshots.isEmpty {
				screenshots = (first["ipadScreenshotUrls"] as? [String])?.compactMap { URL(string: $0) } ?? []
			}
			
			let artString = (first["artworkUrl512"] as? String) ?? (first["artworkUrl100"] as? String)
			let artworkURL = artString.flatMap { URL(string: $0) }
			let description = first["description"] as? String
			let releaseNotes = first["releaseNotes"] as? String
			let sellerName = first["sellerName"] as? String
			let genre = first["primaryGenreName"] as? String
			let contentRating = first["trackContentRating"] as? String
			let rating = first["averageUserRating"] as? Double
			
			var parsedBytes: Int64? = nil
			if let sizeStr = first["fileSizeBytes"] as? String, let b = Int64(sizeStr) {
				parsedBytes = b
			} else if let sizeNum = first["fileSizeBytes"] as? NSNumber {
				parsedBytes = sizeNum.int64Value
			}
			
			return AppleStoreRichMetadata(
				screenshots: screenshots,
				artworkURL: artworkURL,
				description: description,
				releaseNotes: releaseNotes,
				sellerName: sellerName,
				genre: genre,
				contentRating: contentRating,
				rating: rating,
				fileSizeBytes: parsedBytes
			)
		} catch {
			return nil
		}
	}
}

// MARK: - Zero-Lag Bilingual Search & Clean Localization Engine
enum AppStoreBilingualEngine {
	nonisolated static let rawSynonymGroups: [[String]] = [
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
	
	// تجهيز المرادفات مسبقاً لمرة واحدة في الذاكرة لمنع أي لاك أثناء الكتابة في البحث
	nonisolated static let preNormalizedSynonymGroups: [[String]] = {
		rawSynonymGroups.map { group in
			group.map { normalize($0) }
		}
	}()
	
	nonisolated static func normalize(_ text: String) -> String {
		text.lowercased()
			.replacingOccurrences(of: "أ", with: "ا")
			.replacingOccurrences(of: "إ", with: "ا")
			.replacingOccurrences(of: "آ", with: "ا")
			.replacingOccurrences(of: "ة", with: "ه")
			.replacingOccurrences(of: "ى", with: "ي")
			.trimmingCharacters(in: .whitespacesAndNewlines)
	}
	
	nonisolated static func buildFastSearchTokens(for app: ASRepository.App, category: AppStore2026Category) -> String {
		var base = normalize("\(app.name ?? "") \(app.id ?? "") \(category.rawValue)")
		for group in preNormalizedSynonymGroups {
			if group.contains(where: { base.contains($0) }) {
				base.append(" ")
				base.append(group.joined(separator: " "))
			}
		}
		return base
	}
	
	nonisolated static func matchesQuery(tokens: String, normalizedQuery: String) -> Bool {
		guard !normalizedQuery.isEmpty else { return true }
		return tokens.contains(normalizedQuery)
	}
	
	nonisolated static func isInternalSourceNote(_ text: String?) -> Bool {
		guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
			return true
		}
		let lower = text.lowercased()
		return lower.hasPrefix("sources:") ||
			lower.contains("flekstore") ||
			lower.contains("unkeyapp") ||
			lower.contains("khoipa") ||
			lower.contains(" | ")
	}
	
	nonisolated static func localizedSubtitle(for app: ASRepository.App, category: AppStore2026Category) -> String {
		if let customDesc = app.localizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !customDesc.isEmpty,
		   !isInternalSourceNote(customDesc),
		   customDesc.count <= 65 {
			return customDesc
		}
		
		let nameAndID = "\(app.name ?? "") \(app.id ?? "")".lowercased()
		
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
		
		return category.defaultArabicSubtitle
	}
}

struct AppStoreAppItem: Identifiable, Hashable, Sendable {
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
		self.searchIndexTokens = AppStoreBilingualEngine.buildFastSearchTokens(for: app, category: classified)
		
		if let urls = app.screenshotURLs, !urls.isEmpty {
			self.screenshots = urls
		} else if let iphone = app.screenshots?.iPhone, !iphone.isEmpty {
			self.screenshots = iphone
		} else {
			self.screenshots = []
		}
	}
	
	nonisolated func matchesNormalizedQuery(_ normalizedQuery: String) -> Bool {
		AppStoreBilingualEngine.matchesQuery(tokens: searchIndexTokens, normalizedQuery: normalizedQuery)
	}
	
	static func == (lhs: AppStoreAppItem, rhs: AppStoreAppItem) -> Bool {
		lhs.id == rhs.id
	}
	
	func hash(into hasher: inout Hasher) {
		hasher.combine(id)
	}
}

// MARK: - Editorial Instruction Model
struct TodayEditorialInstruction: Identifiable {
	let id: String
	let badge: String
	let title: String
	let caption: String
	let imageURL: URL?
	let tintColor: Color
	let associatedApp: AppStoreAppItem?
}

enum AppStore2026Category: String, CaseIterable, Identifiable, Sendable {
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
	
	nonisolated var isGameCategory: Bool {
		switch self {
		case .topGames, .bestSellingGames, .puzzleGames, .simulationGames, .casualGames, .timePass, .strategyGames, .pvpGames:
			return true
		case .topApps, .bestSellingApps, .social, .mediaReaders, .productivity, .devTools, .visualArts, .photoVideo:
			return false
		}
	}
	
	nonisolated var defaultArabicSubtitle: String {
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
	
	nonisolated static func strictlyClassify(app: ASRepository.App) -> AppStore2026Category {
		let catRaw = (app.category ?? "").lowercased()
		if catRaw == "games" { return .casualGames }
		if catRaw == "social" { return .social }
		if catRaw == "media" { return .photoVideo }
		if catRaw == "tools" { return .devTools }
		
		let nameAndBundle = "\(app.name ?? "") \(app.id ?? "") \(catRaw)".lowercased()
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
		
		let pvpKeywords = ["pubg", "8ball", "pool", "cod", "callofduty", "freefire", "brawl", "fortnite", "fifa", "efootball", "pes", "mobilelegends", "wildrift", "standoff", "bullet", "pvp", "multiplayer", "ark", "ببجي", "بلياردو", "فري فاير", "كود", "فيفا", "بيس"]
		if pvpKeywords.contains(where: { combined.contains($0) }) { return .pvpGames }
		
		let strategyKeywords = ["clash", "royale", "clans", "strategy", "chess", "tower", "defense", "war", "stick war", "empire", "civilization", "boombeach", "plantsvs", "كلاش", "شطرنج", "حرب", "استراتيجيه"]
		if strategyKeywords.contains(where: { combined.contains($0) }) { return .strategyGames }
		
		let simulationKeywords = ["roblox", "minecraft", "sims", "simcity", "gta", "rockstar", "sanandreas", "parking", "simulator", "bus", "truck", "flight", "farm", "hayday", "township", "روبلوكس", "ماين كرافت", "قراند", "محاكاة", "مزرعه"]
		if simulationKeywords.contains(where: { combined.contains($0) }) { return .simulationGames }
		
		let puzzleKeywords = ["puzzle", "candy", "crush", "match", "brain", "sudoku", "word", "gardenscapes", "homescapes", "royalmatch", "angrybirds", "cuttherope", "2048", "trivia", "الغاز", "ألغاز", "ذكاء", "كلمات"]
		if puzzleKeywords.contains(where: { combined.contains($0) }) { return .puzzleGames }
		
		let casualGameKeywords = [
			"game", "games", "gaming", "arcade", "subway", "surfers", "minion", "temple", "run", "sonic",
			"talking", "tom", "flappy", "jump", "racing", "race", "asphalt", "carx", "drift", "hillclimb",
			"ludo", "yalla", "uno", "monopoly", "fruitninja", "jetpack", "pacman", "mario", "pokemon",
			"zelda", "ppsspp", "delta", "retroarch", "emulator", "hack", "playdead", "gameloft", "supercell",
			"zynga", "rovio", "ketchapp", "voodoo", "miniclip", "ubisoft", "activision", "konami", "sega",
			"لعبة", "لعبه", "العاب", "ألعاب"
		]
		if casualGameKeywords.contains(where: { combined.contains($0) }) { return .casualGames }
		
		return .productivity
	}
}

// MARK: - Instant Store Cache Manager (Strictly Separates IPABLACK for Today View)
@MainActor
final class AppStoreCacheManager: ObservableObject {
	static let shared = AppStoreCacheManager()
	
	@Published private(set) var ipablackItems: [AppStoreAppItem] = []
	@Published private(set) var ipablackEditorialNews: [TodayEditorialInstruction] = []
	
	@Published private(set) var allCombinedItems: [AppStoreAppItem] = []
	@Published private(set) var pureAppsOnly: [AppStoreAppItem] = []
	@Published private(set) var pureGamesOnly: [AppStoreAppItem] = []
	@Published private(set) var itemsByCategory: [AppStore2026Category: [AppStoreAppItem]] = [:]
	
	private var isFetching = false
	private var isBuildingCache = false
	private var directLoadedRepos: [String: ASRepository] = [:]
	
	private nonisolated static var diskCacheDirectory: URL {
		let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("XSignInstantStoreCache_v2", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}
	
	private nonisolated static let fastRepoSession: URLSession = {
		let config = URLSessionConfiguration.default
		config.networkServiceType = .responsiveData
		config.httpMaximumConnectionsPerHost = 12
		config.timeoutIntervalForRequest = 15
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		return URLSession(configuration: config)
	}()
	
	// تنظيف JSON من أي روابط فارغة "" قد تمنع AltSourceKit من قراءة سورس IPABLACK
	nonisolated static func sanitizeRepoJSONData(_ rawData: Data) -> Data {
		guard var dict = (try? JSONSerialization.jsonObject(with: rawData)) as? [String: Any] else {
			return rawData
		}
		
		let urlKeys = ["iconURL", "website", "headerURL", "imageURL", "url"]
		for key in urlKeys {
			if let val = dict[key] as? String, val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
				dict.removeValue(forKey: key)
			}
		}
		
		if var newsList = dict["news"] as? [[String: Any]] {
			for i in newsList.indices {
				for key in urlKeys {
					if let val = newsList[i][key] as? String, val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
						newsList[i].removeValue(forKey: key)
					}
				}
			}
			dict["news"] = newsList
		}
		
		if var appsList = dict["apps"] as? [[String: Any]] {
			for i in appsList.indices {
				if let iconVal = appsList[i]["iconURL"] as? String, iconVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					appsList[i].removeValue(forKey: "iconURL")
				}
			}
			dict["apps"] = appsList
		}
		
		return (try? JSONSerialization.data(withJSONObject: dict)) ?? rawData
	}
	
	init() {
		loadInstantDiskSnapshot()
	}
	
	private func loadInstantDiskSnapshot() {
		Task.detached(priority: .userInitiated) {
			var snapshotRepos: [(URL?, String?, ASRepository)] = []
			let decoder = JSONDecoder()
			
			let cachedFiles: [(urlStr: String, id: String, file: String)] = [
				(ProtectedSourcesVault.ipaBlackURLString, "xsign.core.ipablack", "ipablack_cache.json"),
				(ProtectedSourcesVault.storeAPIURLString, "xsign.core.storeapi", "storeapi_cache.json")
			]
			
			for entry in cachedFiles {
				let fileURL = Self.diskCacheDirectory.appendingPathComponent(entry.file)
				if let rawData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
					let cleanData = Self.sanitizeRepoJSONData(rawData)
					if let repo = try? decoder.decode(ASRepository.self, from: cleanData) {
						snapshotRepos.append((URL(string: entry.urlStr), entry.id, repo))
					}
				}
			}
			
			guard !snapshotRepos.isEmpty else { return }
			await Self.processAndPublish(snapshot: snapshotRepos)
		}
	}
	
	func ensureFetched(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
		guard !isFetching else { return }
		isFetching = true
		
		await fetchCoreReposDirectlyInParallel()
		
		let customSources = sources.filter { !ProtectedSourcesVault.isHiddenCoreSource($0) }
		if !customSources.isEmpty {
			await viewModel.fetchSources(sources)
			rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
		}
		
		isFetching = false
	}
	
	func forceRefresh(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
		guard !isFetching else { return }
		isFetching = true
		await fetchCoreReposDirectlyInParallel()
		await viewModel.fetchSources(sources, refresh: true)
		rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
		isFetching = false
	}
	
	private func fetchCoreReposDirectlyInParallel() async {
		let targets: [(urlStr: String, id: String, cacheFile: String)] = [
			(ProtectedSourcesVault.ipaBlackURLString, "xsign.core.ipablack", "ipablack_cache.json"),
			(ProtectedSourcesVault.storeAPIURLString, "xsign.core.storeapi", "storeapi_cache.json")
		]
		
		await withTaskGroup(of: (String, String, URL, ASRepository)?.self) { group in
			for target in targets {
				group.addTask(priority: .userInitiated) {
					let bustURLString = "\(target.urlStr)?t=\(Int(Date().timeIntervalSince1970))"
					guard let url = URL(string: bustURLString),
						  let baseTargetURL = URL(string: target.urlStr) else { return nil }
					var request = URLRequest(url: url)
					request.setValue("X-SIGN/2.0 (FastRepoFetch)", forHTTPHeaderField: "User-Agent")
					
					do {
						let (rawData, _) = try await Self.fastRepoSession.data(for: request)
						let cleanData = Self.sanitizeRepoJSONData(rawData)
						let cachePath = Self.diskCacheDirectory.appendingPathComponent(target.cacheFile)
						try? cleanData.write(to: cachePath, options: .atomic)
						let repo = try JSONDecoder().decode(ASRepository.self, from: cleanData)
						return (target.urlStr, target.id, baseTargetURL, repo)
					} catch {
						return nil
					}
				}
			}
			
			for await result in group {
				if let (urlStr, _, _, repo) = result {
					directLoadedRepos[urlStr] = repo
				}
			}
		}
		
		var finalSnapshot: [(URL?, String?, ASRepository)] = []
		if let ipaRepo = directLoadedRepos[ProtectedSourcesVault.ipaBlackURLString] {
			finalSnapshot.append((URL(string: ProtectedSourcesVault.ipaBlackURLString), "xsign.core.ipablack", ipaRepo))
		}
		if let storeRepo = directLoadedRepos[ProtectedSourcesVault.storeAPIURLString] {
			finalSnapshot.append((URL(string: ProtectedSourcesVault.storeAPIURLString), "xsign.core.storeapi", storeRepo))
		}
		if !finalSnapshot.isEmpty {
			await Self.processAndPublish(snapshot: finalSnapshot)
		}
	}
	
	func rebuildCacheIfNeeded(sources: FetchedResults<AltSource>, repositoriesMap: [AltSource: ASRepository]) {
		guard !isBuildingCache else { return }
		isBuildingCache = true
		
		var combinedSnapshot: [(URL?, String?, ASRepository)] = []
		
		if let ipaRepo = directLoadedRepos[ProtectedSourcesVault.ipaBlackURLString] {
			combinedSnapshot.append((URL(string: ProtectedSourcesVault.ipaBlackURLString), "xsign.core.ipablack", ipaRepo))
		}
		if let storeRepo = directLoadedRepos[ProtectedSourcesVault.storeAPIURLString] {
			combinedSnapshot.append((URL(string: ProtectedSourcesVault.storeAPIURLString), "xsign.core.storeapi", storeRepo))
		}
		
		for source in sources {
			if let repo = repositoriesMap[source] {
				let urlStr = source.sourceURL?.absoluteString ?? ""
				if directLoadedRepos[urlStr] == nil {
					combinedSnapshot.append((source.sourceURL, source.identifier, repo))
				}
			}
		}
		
		guard !combinedSnapshot.isEmpty else {
			isBuildingCache = false
			return
		}
		
		Task.detached(priority: .userInitiated) {
			await Self.processAndPublish(snapshot: combinedSnapshot)
			await MainActor.run {
				AppStoreCacheManager.shared.isBuildingCache = false
			}
		}
	}
	
	private nonisolated static func processAndPublish(snapshot: [(URL?, String?, ASRepository)]) async {
		let totalCount = snapshot.reduce(0) { $0 + $1.2.apps.count }
		var allItems: [AppStoreAppItem] = []
		var ipaBlackOnly: [AppStoreAppItem] = []
		var ipaBlackNews: [TodayEditorialInstruction] = []
		var didIncludeIPABlackRepo = false
		
		allItems.reserveCapacity(totalCount)
		var seenKeys = Set<String>()
		
		for (sourceURL, sourceID, repo) in snapshot {
			let isIPABlack = ProtectedSourcesVault.isIPABlackSource(sourceURL, identifier: sourceID)
			if isIPABlack {
				didIncludeIPABlackRepo = true
			}
			let sourceURLString = sourceURL?.absoluteString ?? ""
			
			var currentRepoItems: [AppStoreAppItem] = []
			currentRepoItems.reserveCapacity(repo.apps.count)
			
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
		
		// حصر صفحة اليوم بسورس IPABLACK فقط وعدم خلطها مع السورسات الأخرى
		let finalIPABlack = ipaBlackOnly
		let finalIPABlackNews = ipaBlackNews
		let finalAll = allItems
		let finalApps = onlyApps
		let finalGames = onlyGames
		let finalCats = categoryDict
		let shouldUpdateIPABlack = didIncludeIPABlackRepo
		
		await MainActor.run {
			let manager = AppStoreCacheManager.shared
			if shouldUpdateIPABlack {
				manager.ipablackItems = finalIPABlack
				manager.ipablackEditorialNews = finalIPABlackNews
			}
			if !finalAll.isEmpty {
				manager.allCombinedItems = finalAll
				manager.pureAppsOnly = finalApps
				manager.pureGamesOnly = finalGames
				manager.itemsByCategory = finalCats
			}
		}
	}
}

// MARK: - Universal IPABlack & KhoIPA Payload Extractor + Instant ZSign
@MainActor
final class AutoSignPipelineManager: ObservableObject {
	static let shared = AutoSignPipelineManager()
	
	@Published var activeStates: [String: Stage] = [:]
	@Published var downloadProgress: [String: Int] = [:]
	@Published var readyToInstallApp: AnyApp? = nil
	
	enum Stage: Equatable {
		case downloading
		case signing
		case ready
	}
	
	private var cachedCertificate: CertificatePair? = nil
	private var progressObservations: [String: NSKeyValueObservation] = [:]
	
	private lazy var turboSession: URLSession = {
		let config = URLSessionConfiguration.default
		config.networkServiceType = .responsiveData
		config.multipathServiceType = .handover
		config.httpMaximumConnectionsPerHost = 16
		config.waitsForConnectivity = false
		config.requestCachePolicy = .reloadIgnoringLocalCacheData
		config.urlCache = nil
		return URLSession(configuration: config)
	}()
	
	init() {
		refreshCertificateCache()
	}
	
	func refreshCertificateCache() {
		cachedCertificate = Self.fetchActiveCertificate()
	}
	
	nonisolated static func prewarmInfoPlist(for app: Imported) {
		prewarmAndNormalizePayload(for: app)
	}
	
	nonisolated static func prewarmAndNormalizePayload(for app: Imported) {
		guard let uuid = app.uuid else { return }
		let unsignedDir = FileManager.default.unsigned.appendingPathComponent(uuid)
		
		guard let enumerator = FileManager.default.enumerator(
			at: unsignedDir,
			includingPropertiesForKeys: [.isDirectoryKey],
			options: [.skipsHiddenFiles]
		) else { return }
		
		for case let fileURL as URL in enumerator {
			if fileURL.pathExtension == "app" {
				let infoPlistURL = fileURL.appendingPathComponent("Info.plist")
				if let plist = NSDictionary(contentsOf: infoPlistURL) {
					_ = plist["CFBundleExecutable"]
					_ = plist["CFBundleIdentifier"]
				}
				break
			}
		}
	}
	
	func downloadAndAutoSign(app: ASRepository.App) {
		// فحص حظر الـ VPN ومراقب الشبكة قبل السماح بتحميل أي تطبيق من السورس
		XSignSecurityEnforcer.shared.evaluateNetworkSecurity()
		if XSignSecurityEnforcer.shared.isVPNOrProxyDetected {
			UIAlertController.showAlertWithOk(
				title: "تنبيه أمني",
				message: XSignSecurityEnforcer.shared.locks.vpn_warning_message ?? "لا يمكن تحميل التطبيقات أثناء تشغيل VPN أو مراقب شبكة."
			)
			return
		}
		
		guard let url = app.currentDownloadUrl ?? app.versions?.first?.downloadURL else { return }
		let appKey = app.id ?? app.currentName
		
		guard activeStates[appKey] == nil else { return }
		UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
		activeStates[appKey] = .downloading
		downloadProgress[appKey] = 1
		refreshCertificateCache()
		
		let existingUUIDs = Set(Self.fetchImportedApps().compactMap { $0.uuid })
		
		var request = URLRequest(url: url)
		request.setValue("X-SIGN/2.0 (TurboDirect; iOS)", forHTTPHeaderField: "User-Agent")
		
		let task = turboSession.downloadTask(with: request) { [weak self] tempURL, _, error in
			guard let self else { return }
			
			if error != nil || tempURL == nil {
				Task { @MainActor in
					self.progressObservations.removeValue(forKey: appKey)
					self.activeStates[appKey] = nil
					self.downloadProgress.removeValue(forKey: appKey)
				}
				return
			}
			
			let fastFileURL = FileManager.default.temporaryDirectory
				.appendingPathComponent("TurboZSign_\(UUID().uuidString).ipa")
			
			do {
				if FileManager.default.fileExists(atPath: fastFileURL.path) {
					try? FileManager.default.removeItem(at: fastFileURL)
				}
				try FileManager.default.moveItem(at: tempURL!, to: fastFileURL)
			} catch {
				Task { @MainActor in
					self.progressObservations.removeValue(forKey: appKey)
					self.activeStates[appKey] = nil
					self.downloadProgress.removeValue(forKey: appKey)
				}
				return
			}
			
			Task { @MainActor in
				self.progressObservations.removeValue(forKey: appKey)
				self.activeStates[appKey] = .signing
				self.downloadProgress.removeValue(forKey: appKey)
			}
			
			FR.handlePackageFile(fastFileURL) { [weak self] extractError in
				try? FileManager.default.removeItem(at: fastFileURL)
				Task { @MainActor in
					guard let self else { return }
					if extractError != nil {
						self.activeStates[appKey] = nil
						return
					}
					let updatedImported = Self.fetchImportedApps()
					if let newlyImported = updatedImported.first(where: { item in
						guard let uuid = item.uuid else { return false }
						return !existingUUIDs.contains(uuid)
					}) ?? updatedImported.first {
						Self.prewarmAndNormalizePayload(for: newlyImported)
						self.triggerInstantZSign(for: newlyImported, appKey: appKey)
					} else {
						self.activeStates[appKey] = nil
					}
				}
			}
		}
		
		let observation = task.progress.observe(\Progress.fractionCompleted, options: [.new]) { [weak self] progress, _ in
			let percent = max(1, min(99, Int(progress.fractionCompleted * 100)))
			Task { @MainActor in
				guard let self else { return }
				if self.downloadProgress[appKey] != percent {
					self.downloadProgress[appKey] = percent
				}
			}
		}
		progressObservations[appKey] = observation
		task.priority = URLSessionTask.highPriority
		task.resume()
	}
	
	func triggerInstantZSign(for importedApp: Imported, appKey: String) {
		guard let cert = cachedCertificate ?? Self.fetchActiveCertificate() else {
			activeStates[appKey] = nil
			UIAlertController.showAlertWithOk(
				title: "تم استخراج التطبيق",
				message: "أضف شهادة من أيقونة الحساب في الأعلى ليتم التوقيع والتثبيت اللحظي."
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
						title: "فشل التوقيع",
						message: error.localizedDescription
					)
				} else {
					self.activeStates[appKey] = .ready
					UINotificationFeedbackGenerator().notificationOccurred(.success)
					
					if let latestSigned = Self.fetchSignedApps().first {
						self.readyToInstallApp = AnyApp(base: latestSigned)
					}
					
					DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
						self.activeStates[appKey] = nil
					}
				}
			}
		}
	}
	
	nonisolated static func fetchImportedApps() -> [Imported] {
		let request = NSFetchRequest<Imported>(entityName: "Imported")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
		request.fetchLimit = 5
		return (try? Storage.shared.context.fetch(request)) ?? []
	}
	
	nonisolated static func fetchSignedApps() -> [Signed] {
		let request = NSFetchRequest<Signed>(entityName: "Signed")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
		request.fetchLimit = 2
		return (try? Storage.shared.context.fetch(request)) ?? []
	}
	
	nonisolated static func fetchActiveCertificate() -> CertificatePair? {
		let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
		request.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
		guard let certs = try? Storage.shared.context.fetch(request), !certs.isEmpty else {
			return nil
		}
		let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		return certs.indices.contains(index) ? certs[index] : certs.first
	}
}

// MARK: - Authentic App Store 2026 Detail View (Hides Screenshots if App is Removed from App Store)
struct AppStore2026DetailView: View {
	let item: AppStoreAppItem
	@State private var appleMetadata: AppleStoreRichMetadata? = nil
	@State private var isLoadingMetadata = true
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	private var accentColor: Color {
		Color(hex: userTintHex)
	}
	
	private var displayScreenshots: [URL] {
		if let screenshots = appleMetadata?.screenshots, !screenshots.isEmpty {
			return screenshots
		}
		return item.screenshots
	}
	
	private var displayDescription: String {
		if let original = item.app.currentDescription,
		   !AppStoreBilingualEngine.isInternalSourceNote(original) {
			return original
		}
		if let appleDesc = appleMetadata?.description, !appleDesc.isEmpty {
			return appleDesc
		}
		return "نسخة معدلة ومحدثة جاهزة للتثبيت الفوري عبر X-SIGN."
	}
	
	private var displayReleaseNotes: String {
		if let versionDesc = item.app.versions?.first?.localizedDescription,
		   !AppStoreBilingualEngine.isInternalSourceNote(versionDesc) {
			return versionDesc
		}
		if let appleNotes = appleMetadata?.releaseNotes, !appleNotes.isEmpty {
			return appleNotes
		}
		return "نسخة معدلة ومحدثة."
	}
	
	private var displayDeveloper: String {
		if let seller = appleMetadata?.sellerName, !seller.isEmpty {
			return seller
		}
		if let dev = item.app.developerName, !dev.isEmpty {
			return dev
		}
		return "IPA BLACK"
	}
	
	private var formattedSize: String {
		let repoSize = item.app.size ?? item.app.versions?.first?.size ?? 0
		let bytes = Int64(repoSize > 0 ? repoSize : (appleMetadata?.fileSizeBytes ?? 0))
		guard bytes > 0 else { return "IPA" }
		let formatter = ByteCountFormatter()
		formatter.allowedUnits = [.useMB, .useGB]
		formatter.countStyle = .file
		return formatter.string(fromByteCount: bytes)
	}
	
	var body: some View {
		ScrollView(.vertical, showsIndicators: false) {
			VStack(alignment: .leading, spacing: 24) {
				HStack(alignment: .top, spacing: 16) {
					AppStoreIconView(
						url: item.app.iconURL,
						bundleID: item.app.id,
						appName: item.app.currentName,
						size: 112
					)
					.shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
					
					VStack(alignment: .leading, spacing: 6) {
						Text(item.app.currentName)
							.font(.title2.bold())
							.foregroundStyle(.white)
							.lineLimit(2)
						
						Text(item.arabicSubtitle)
							.font(.system(size: 14, weight: .medium))
							.foregroundStyle(.secondary)
							.lineLimit(1)
						
						Spacer(minLength: 8)
						
						HStack {
							AppStore2026DownloadButton(app: item.app)
							Spacer()
						}
					}
				}
				.padding(.horizontal, 18)
				.padding(.top, 10)
				
				Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 18)
				
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 0) {
						AppStoreStatBadge(
							topTitle: "التقييمات",
							mainValue: appleMetadata?.rating.map { String(format: "%.1f", $0) } ?? "5.0",
							bottomText: "★★★★★"
						)
						
						Divider().frame(height: 36).background(Color.white.opacity(0.12))
						
						AppStoreStatBadge(
							topTitle: "العمر",
							mainValue: appleMetadata?.contentRating ?? "+4",
							bottomText: "سنة"
						)
						
						Divider().frame(height: 36).background(Color.white.opacity(0.12))
						
						AppStoreStatBadge(
							topTitle: "الفئة",
							mainValue: item.category.rawValue,
							bottomText: "التصنيف"
						)
						
						Divider().frame(height: 36).background(Color.white.opacity(0.12))
						
						AppStoreStatBadge(
							topTitle: "الحجم",
							mainValue: formattedSize,
							bottomText: "iOS"
						)
					}
					.padding(.horizontal, 18)
				}
				
				// لا يظهر قسم لقطات الشاشة إذا كان التطبيق محذوفاً من متجر أبل ولا يملك لقطات شاشة
				if !displayScreenshots.isEmpty || isLoadingMetadata {
					Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 18)
					
					VStack(alignment: .leading, spacing: 14) {
						Text("معاينة")
							.font(.title2.bold())
							.foregroundStyle(.white)
							.padding(.horizontal, 18)
						
						if !displayScreenshots.isEmpty {
							ScrollView(.horizontal, showsIndicators: false) {
								HStack(spacing: 12) {
									ForEach(displayScreenshots, id: \.self) { screenURL in
										LazyImage(url: screenURL) { state in
											if let image = state.image {
												image
													.resizable()
													.scaledToFit()
											} else {
												RoundedRectangle(cornerRadius: 20, style: .continuous)
													.fill(Color(white: 0.14))
													.overlay { ProgressView().tint(.white) }
											}
										}
										.processors([.resize(size: CGSize(width: 460, height: 920))])
										.frame(width: min(UIScreen.main.bounds.width * 0.62, 280), height: 440)
										.background(Color(white: 0.08))
										.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
										.overlay(
											RoundedRectangle(cornerRadius: 20, style: .continuous)
												.stroke(Color.white.opacity(0.12), lineWidth: 0.6)
										)
									}
								}
								.padding(.horizontal, 18)
							}
						} else if isLoadingMetadata {
							ScrollView(.horizontal, showsIndicators: false) {
								HStack(spacing: 12) {
									ForEach(0..<2, id: \.self) { _ in
										RoundedRectangle(cornerRadius: 20, style: .continuous)
											.fill(Color(white: 0.12))
											.frame(width: min(UIScreen.main.bounds.width * 0.62, 280), height: 440)
											.overlay {
												ProgressView().tint(accentColor)
											}
									}
								}
								.padding(.horizontal, 18)
							}
						}
					}
				}
				
				Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 18)
				
				VStack(alignment: .leading, spacing: 10) {
					HStack {
						Text("ما الجديد")
							.font(.title2.bold())
							.foregroundStyle(.white)
						Spacer()
						Text("الإصدار \(item.app.currentVersion ?? "—")")
							.font(.subheadline)
							.foregroundStyle(.secondary)
					}
					
					Text(displayReleaseNotes)
						.font(.system(size: 15))
						.foregroundStyle(.white.opacity(0.9))
						.lineSpacing(4)
						.lineLimit(4)
				}
				.padding(.horizontal, 18)
				
				Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 18)
				
				XSignTranslatableDescription(text: displayDescription, accentColor: accentColor)
				.padding(.horizontal, 18)
				
				Divider().background(Color.white.opacity(0.1)).padding(.horizontal, 18)
				
				VStack(alignment: .leading, spacing: 14) {
					Text("المعلومات")
						.font(.title2.bold())
						.foregroundStyle(.white)
					
					AppStoreInfoRow(label: "المصدر", value: "IPA BLACK")
					AppStoreInfoRow(label: "المطور", value: displayDeveloper)
					AppStoreInfoRow(label: "الحجم", value: formattedSize)
					AppStoreInfoRow(label: "الفئة", value: item.category.rawValue)
					AppStoreInfoRow(label: "الإصدار", value: item.app.currentVersion ?? "—")
				}
				.padding(.horizontal, 18)
				.padding(.bottom, 36)
			}
		}
		.background(Color.black.ignoresSafeArea())
		.navigationBarTitleDisplayMode(.inline)
		.environment(\.layoutDirection, .rightToLeft)
		.task {
			if AppStoreLiveMetadataBridge.hasExtractedGitHubIcon(item.app.iconURL) {
				isLoadingMetadata = false
				return
			}
			appleMetadata = await AppStoreLiveMetadataBridge.shared.fetchMetadata(
				bundleID: item.app.id,
				appName: item.app.currentName,
				iconURL: item.app.iconURL
			)
			isLoadingMetadata = false
		}
	}
}

struct AppStoreStatBadge: View {
	let topTitle: String
	let mainValue: String
	let bottomText: String
	
	var body: some View {
		VStack(spacing: 4) {
			Text(topTitle)
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(.secondary)
			Text(mainValue)
				.font(.system(size: 20, weight: .heavy, design: .rounded))
				.foregroundStyle(.white.opacity(0.9))
			Text(bottomText)
				.font(.system(size: 11, weight: .medium))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
		.frame(width: 92)
	}
}

struct AppStoreInfoRow: View {
	let label: String
	let value: String
	
	var body: some View {
		VStack(spacing: 10) {
			HStack {
				Text(label)
					.font(.system(size: 14))
					.foregroundStyle(.secondary)
				Spacer()
				Text(value)
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white)
					.lineLimit(1)
			}
			Divider().background(Color.white.opacity(0.08))
		}
	}
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
						AppStore2026EmptyState(isLoading: true)
							.padding(.horizontal, 18)
							.padding(.top, 30)
					} else {
						ForEach(cache.ipablackEditorialNews) { instruction in
							if let appItem = instruction.associatedApp {
								NavigationLink {
									AppStore2026DetailView(item: appItem)
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
								AppStore2026DetailView(item: hotHero)
							} label: {
								TodayLiveEventHeroCard(
									outerTitle: "Hot This Week",
									outerSubtitle: "Catch what's trending on the App Store",
									cornerBadge: "يحدث الآن",
									eventTag: "حدث مميز",
									headline: "اكتشف تجربة \(hotHero.app.currentName) الملحمية",
									descriptionText: hotHero.arabicSubtitle,
									bannerImageURL: hotHero.screenshots.first,
									cardColor: Color(red: 0.78, green: 0.18, blue: 0.12),
									item: hotHero
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
								AppStore2026DetailView(item: fullArtworkItem)
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
						AppStore2026EmptyState(isLoading: true)
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
											AppStore2026DetailView(item: item)
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
								AppStore2026DetailView(item: item)
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
						AppStore2026EmptyState(isLoading: true)
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
									AppStore2026DetailView(item: heroGame)
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
								AppStore2026DetailView(item: item)
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
	}
}

// MARK: - 4. SEARCH VIEW (Background Debounced 120fps Zero-Lag Search)
struct AppStoreSearchView: View {
	@StateObject private var viewModel = SourcesViewModel.shared
	@StateObject private var cache = AppStoreCacheManager.shared
	@State private var searchText = ""
	@State private var debouncedResults: [AppStoreAppItem] = []
	@State private var searchTask: Task<Void, Never>? = nil
	@State private var showSettingsSheet = false
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	var body: some View {
		NavigationStack {
			ScrollView(.vertical, showsIndicators: false) {
				LazyVStack(alignment: .leading, spacing: 26) {
					AppStore2026TopHeader(
						title: "بحث",
						onSettingsTap: { showSettingsSheet = true }
					)
					
					if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
							if debouncedResults.isEmpty {
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
								ForEach(debouncedResults) { item in
									NavigationLink {
										AppStore2026DetailView(item: item)
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
			.onChange(of: searchText) { newQuery in
				triggerBackgroundSearch(query: newQuery)
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
	
	private func triggerBackgroundSearch(query: String) {
		searchTask?.cancel()
		let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else {
			debouncedResults = []
			return
		}
		
		let snapshot = cache.allCombinedItems
		searchTask = Task.detached(priority: .userInitiated) {
			try? await Task.sleep(nanoseconds: 160_000_000)
			guard !Task.isCancelled else { return }
			
			let normQuery = AppStoreBilingualEngine.normalize(trimmed)
			var matches: [AppStoreAppItem] = []
			matches.reserveCapacity(60)
			
			for item in snapshot {
				if Task.isCancelled { return }
				if item.matchesNormalizedQuery(normQuery) {
					matches.append(item)
					if matches.count >= 60 { break }
				}
			}
			
			let finalMatches = matches
			await MainActor.run {
				if !Task.isCancelled {
					self.debouncedResults = finalMatches
				}
			}
		}
	}
}

// MARK: - Top Header
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

    var body: some View {
        Button(action: action) {
            FRAppIconView(size: 38)
                .frame(width: 38, height: 38)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 1.1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("الإعدادات")
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
	
	@State private var liveScreenshots: [URL] = []
	
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
					Color.clear
						.frame(maxWidth: .infinity)
						.frame(height: 350)
						.background(
							LinearGradient(
								colors: [
									cardColor,
									cardColor.opacity(0.82),
									Color(red: 0.08, green: 0.08, blue: 0.10)
								],
								startPoint: .top,
								endPoint: .bottom
							)
						)
						.overlay {
							let displayBanner = bannerImageURL ?? liveScreenshots.first
							if let bannerURL = displayBanner {
								LazyImage(url: bannerURL) { state in
									if let image = state.image {
										image
											.resizable()
											.scaledToFill()
											.opacity(0.55)
									}
								}
								.processors([.resize(size: CGSize(width: 500, height: 500))])
							} else {
								AppStoreIconView(
									url: item.app.iconURL,
									bundleID: item.app.id,
									appName: item.app.currentName,
									size: 138
								)
								.shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 10)
								.offset(y: -38)
							}
						}
						.clipped()
						.overlay(alignment: .bottomLeading) {
							ZStack(alignment: .bottomLeading) {
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
										.font(.system(size: 26, weight: .heavy))
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
						}
					
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
							.fill(Color.black.opacity(0.42))
						)
				}
				
				Divider()
					.background(Color.white.opacity(0.14))
				
				HStack(spacing: 12) {
					AppStoreIconView(
						url: item.app.iconURL,
						bundleID: item.app.id,
						appName: item.app.currentName,
						size: 50
					)
					
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
					
					Spacer(minLength: 8)
					
					AppStore2026DownloadButton(app: item.app, isLightPill: true)
				}
				.padding(.horizontal, 18)
				.padding(.vertical, 14)
				.frame(maxWidth: .infinity)
				.background(cardColor.opacity(0.95))
			}
			.frame(maxWidth: .infinity)
			.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
			.overlay(
				RoundedRectangle(cornerRadius: 28, style: .continuous)
					.stroke(Color.white.opacity(0.10), lineWidth: 0.7)
			)
			.task {
				if bannerImageURL == nil && liveScreenshots.isEmpty && !AppStoreLiveMetadataBridge.hasExtractedGitHubIcon(item.app.iconURL) {
					if let meta = await AppStoreLiveMetadataBridge.shared.fetchMetadata(
						bundleID: item.app.id,
						appName: item.app.currentName,
						iconURL: item.app.iconURL
					) {
						liveScreenshots = meta.screenshots
					}
				}
			}
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
			
			Color.clear
				.frame(maxWidth: .infinity)
				.frame(height: 365)
				.background(
					LinearGradient(
						colors: gradientColors,
						startPoint: .top,
						endPoint: .bottom
					)
				)
				.overlay(alignment: .top) {
					VStack(spacing: 16) {
						HStack(spacing: 14) {
							ForEach(topRowItems) { appItem in
								AppStoreIconView(
									url: appItem.app.iconURL,
									bundleID: appItem.app.id,
									appName: appItem.app.currentName,
									size: 80
								)
								.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
							}
						}
						.offset(x: 12)
						
						HStack(spacing: 14) {
							ForEach(bottomRowItems) { appItem in
								AppStoreIconView(
									url: appItem.app.iconURL,
									bundleID: appItem.app.id,
									appName: appItem.app.currentName,
									size: 80
								)
								.shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 5)
							}
						}
						.offset(x: -12)
					}
					.padding(.top, 26)
				}
				.overlay(alignment: .bottomLeading) {
					ZStack(alignment: .bottomLeading) {
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
								.font(.system(size: 27, weight: .heavy))
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
				}
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
						.font(.system(size: 26, weight: .heavy))
						.foregroundStyle(.white)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
				}
				
				VStack(spacing: 14) {
					ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
						NavigationLink {
							AppStore2026DetailView(item: item)
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
			.frame(maxWidth: .infinity)
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
	
	@State private var liveScreenshots: [URL] = []
	
	private var baseColor: Color {
		item.app.tintColor ?? Color(hex: userTintHex)
	}
	
	var body: some View {
		VStack(spacing: 0) {
			Color.clear
				.frame(maxWidth: .infinity)
				.frame(height: 330)
				.background(
					LinearGradient(
						colors: [
							baseColor.opacity(0.75),
							Color(red: 0.16, green: 0.28, blue: 0.42),
							Color(red: 0.12, green: 0.20, blue: 0.30)
						],
						startPoint: .topTrailing,
						endPoint: .bottomLeading
					)
				)
				.overlay {
					let displayImg = item.screenshots.first ?? liveScreenshots.first
					if let firstScreen = displayImg {
						LazyImage(url: firstScreen) { state in
							if let image = state.image {
								image
									.resizable()
									.scaledToFill()
							}
						}
						.processors([.resize(size: CGSize(width: 500, height: 500))])
					} else {
						AppStoreIconView(
							url: item.app.iconURL,
							bundleID: item.app.id,
							appName: item.app.currentName,
							size: 128
						)
						.shadow(color: .black.opacity(0.4), radius: 16, x: 0, y: 8)
						.offset(y: -35)
					}
				}
				.clipped()
				.overlay {
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
							.offset(y: -30)
					}
				}
				.overlay(alignment: .bottomLeading) {
					ZStack(alignment: .bottomLeading) {
						LinearGradient(
							colors: [.clear, Color.black.opacity(0.82)],
							startPoint: .center,
							endPoint: .bottom
						)
						
						VStack(alignment: .leading, spacing: 5) {
							Text(categoryTag)
								.font(.system(size: 13, weight: .bold))
								.foregroundStyle(.white.opacity(0.88))
							Text(headline)
								.font(.system(size: 26, weight: .heavy))
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
				}
			
			HStack(spacing: 12) {
				AppStoreIconView(
					url: item.app.iconURL,
					bundleID: item.app.id,
					appName: item.app.currentName,
					size: 50
				)
				
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
				
				Spacer(minLength: 8)
				
				AppStore2026DownloadButton(app: item.app, isLightPill: true)
			}
			.padding(.horizontal, 18)
			.padding(.vertical, 14)
			.frame(maxWidth: .infinity)
			.background(Color(red: 0.16, green: 0.22, blue: 0.28))
		}
		.frame(maxWidth: .infinity)
		.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 28, style: .continuous)
				.stroke(Color.white.opacity(0.10), lineWidth: 0.6)
		)
		.task {
			if item.screenshots.isEmpty && liveScreenshots.isEmpty && !AppStoreLiveMetadataBridge.hasExtractedGitHubIcon(item.app.iconURL) {
				if let meta = await AppStoreLiveMetadataBridge.shared.fetchMetadata(
					bundleID: item.app.id,
					appName: item.app.currentName,
					iconURL: item.app.iconURL
				) {
					liveScreenshots = meta.screenshots
				}
			}
		}
	}
}

// MARK: - Settings Popup
struct AppStore2026SettingsPopup: View {
	@Environment(\.dismiss) private var dismiss
	let sources: FetchedResults<AltSource>
	@ObservedObject var viewModel: SourcesViewModel
	@State private var isAddingSource = false
	@State private var selectedSection = 0
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	private var userAddedSourcesOnly: [AltSource] {
		sources.filter { !ProtectedSourcesVault.isHiddenCoreSource($0) }
	}
	
	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				VStack(spacing: 12) {
					HStack(spacing: 12) {
						ZStack {
							RoundedRectangle(cornerRadius: 12, style: .continuous)
								.fill(
									LinearGradient(
										colors: [Color(hex: userTintHex), AppStoreTheme.deepOcean],
										startPoint: .topLeading,
										endPoint: .bottomTrailing
									)
								)
							FRAppIconView(size: 48)
						}
						.frame(width: 48, height: 48)
						
						VStack(alignment: .leading, spacing: 2) {
							Text("X-SIGN")
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

// MARK: - Unified Download & Auto-Sign Button
struct AppStore2026DownloadButton: View {
	let app: ASRepository.App
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
	
	private var progressPercent: Int {
		pipeline.downloadProgress[appKey] ?? 0
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
						.scaleEffect(0.72)
					Text("\(progressPercent)%")
						.font(.system(size: 12, weight: .heavy, design: .rounded))
						.monospacedDigit()
						.foregroundStyle(.white)
				}
				.frame(width: 82, height: 32)
				.background(Capsule().fill(accentColor.opacity(0.85)))
				
			case .signing:
				HStack(spacing: 4) {
					Image(systemName: "bolt.fill")
						.font(.system(size: 11, weight: .bold))
					Text("توقيع...")
						.font(.system(size: 11, weight: .bold))
				}
				.foregroundStyle(.white)
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
	
	var body: some View {
		HStack(spacing: 12) {
			AppStoreIconView(
				url: item.app.iconURL,
				bundleID: item.app.id,
				appName: item.app.currentName,
				size: 58
			)
			
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
						AppStoreIconView(
							url: previewApps[1].app.iconURL,
							bundleID: previewApps[1].app.id,
							appName: previewApps[1].app.currentName,
							size: 40
						)
						.rotationEffect(.degrees(12))
						.offset(x: -14, y: 8)
						
						AppStoreIconView(
							url: previewApps[0].app.iconURL,
							bundleID: previewApps[0].app.id,
							appName: previewApps[0].app.currentName,
							size: 44
						)
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
							AppStore2026DetailView(item: item)
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
					AppStoreIconView(
						url: item.app.iconURL,
						bundleID: item.app.id,
						appName: item.app.currentName,
						size: 50
					)
					
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
	@State private var liveScreenshots: [URL] = []
	
	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			AppStore2026AppRow(item: item)
			
			let displayScreenshots = liveScreenshots.isEmpty ? item.screenshots : liveScreenshots
			if !displayScreenshots.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 10) {
						ForEach(Array(displayScreenshots.prefix(3)), id: \.self) { url in
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
		.task {
			guard item.screenshots.isEmpty,
				  liveScreenshots.isEmpty,
				  !AppStoreLiveMetadataBridge.hasExtractedGitHubIcon(item.app.iconURL) else { return }
			
			try? await Task.sleep(nanoseconds: 250_000_000)
			guard !Task.isCancelled else { return }
			
			if let meta = await AppStoreLiveMetadataBridge.shared.fetchMetadata(
				bundleID: item.app.id,
				appName: item.app.currentName,
				iconURL: item.app.iconURL
			) {
				liveScreenshots = meta.screenshots
			}
		}
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
						AppStore2026DetailView(item: item)
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
	var bundleID: String? = nil
	var appName: String = ""
	let size: CGFloat
	@State private var appleIconURL: URL? = nil
	
	private var isFallbackGitHubIcon: Bool {
		guard let u = url?.absoluteString.lowercased() else { return true }
		return u.contains("github.com/ipa-black.png") || u.hasSuffix("/assets/icon.png")
	}
	
	var body: some View {
		Group {
			let effectiveURL = url ?? appleIconURL
			if let effectiveURL {
				LazyImage(url: effectiveURL) { state in
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
		.task {
			if (url == nil || isFallbackGitHubIcon) && !appName.isEmpty && !AppStoreLiveMetadataBridge.hasExtractedGitHubIcon(url) {
				if let meta = await AppStoreLiveMetadataBridge.shared.fetchMetadata(
					bundleID: bundleID,
					appName: appName,
					iconURL: url
				) {
					appleIconURL = meta.artworkURL
				}
			}
		}
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
			Text("جاري مزامنة المتجر بسرعة فائقة...")
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

// MARK: - XSign Inline Description Translation
struct XSignTranslatableDescription: View {
    let text: String
    let accentColor: Color

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                XSignInlineTranslation(text: text, accentColor: accentColor)
                    .id(text)
            } else {
                XSignLegacyTranslation(text: text, accentColor: accentColor)
                    .id(text)
            }
        }
    }
}

private struct XSignDescriptionContent: View {
    let text: String
    let translated: String?
    let accentColor: Color
    let isBusy: Bool
    let canTranslate: Bool
    let translate: () -> Void
    let restore: () -> Void
    @State private var expanded = false

    private var visibleText: String { translated ?? text }

    private var isArabic: Bool {
        NLLanguageRecognizer.dominantLanguage(for: visibleText) == .arabic
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("الوصف").font(.title2.bold())
                    Spacer(minLength: 12)
                    translationButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("الوصف").font(.title2.bold())
                    translationButton
                }
            }

            Text(verbatim: visibleText)
                .font(.body)
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(5)
                .lineLimit(expanded ? nil : 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
                .textSelection(.enabled)

            Button(expanded ? "عرض أقل" : "المزيد") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            }
            .font(.subheadline.bold())
            .foregroundStyle(accentColor)
        }
        .buttonStyle(.plain)
        .onChange(of: translated) { _ in
            expanded = true
        }
    }

    @ViewBuilder private var translationButton: some View {
        if translated != nil {
            Button("عرض الأصل", action: restore)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
        } else if canTranslate && NLLanguageRecognizer.dominantLanguage(for: text) != .arabic {
            Button(action: translate) {
                HStack(spacing: 6) {
                    if isBusy {
                        ProgressView().tint(accentColor)
                    }
                    Label(
                        isBusy ? "جارٍ الترجمة…" : "ترجمة للعربية",
                        systemImage: "translate"
                    )
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accentColor.opacity(0.12), in: Capsule())
            }
            .disabled(
                isBusy ||
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        }
    }
}

@available(iOS 18.0, *)
private struct XSignInlineTranslation: View {
    let text: String
    let accentColor: Color

    @State private var configuration: TranslationSession.Configuration?
    @State private var translated: String?
    @State private var isBusy = false
    @State private var showError = false

    var body: some View {
        XSignDescriptionContent(
            text: text,
            translated: translated,
            accentColor: accentColor,
            isBusy: isBusy,
            canTranslate: true,
            translate: {
                isBusy = true
                if configuration == nil {
                    configuration = TranslationSession.Configuration(
                        source: nil,
                        target: Locale.Language(identifier: "ar")
                    )
                } else {
                    configuration?.invalidate()
                }
            },
            restore: {
                translated = nil
            }
        )
        .translationTask(configuration) { session in
            do {
                let response = try await session.translate(text)
                try Task.checkCancellation()

                await MainActor.run {
                    translated = response.targetText
                    isBusy = false
                }
            } catch {
                let cancelled = Task.isCancelled || error is CancellationError
                await MainActor.run {
                    isBusy = false
                    if !cancelled {
                        showError = true
                    }
                }
            }
        }
        .alert("تعذّرت الترجمة", isPresented: $showError) {
            Button("حسنًا", role: .cancel) {}
        } message: {
            Text("تأكد من توفر لغات الترجمة واتصال الإنترنت عند تنزيلها، ثم أعد المحاولة.")
        }
    }
}

private struct XSignLegacyTranslation: View {
    let text: String
    let accentColor: Color

    @State private var presented = false
    @State private var translated: String?

    private var content: some View {
        XSignDescriptionContent(
            text: text,
            translated: translated,
            accentColor: accentColor,
            isBusy: false,
            canTranslate: supportsTranslation,
            translate: {
                presented = true
            },
            restore: {
                translated = nil
            }
        )
    }

    private var supportsTranslation: Bool {
        if #available(iOS 17.4, *) {
            return true
        }
        return false
    }

    var body: some View {
        Group {
            if #available(iOS 17.4, *) {
                content.translationPresentation(
                    isPresented: $presented,
                    text: text
                ) { result in
                    translated = result
                    presented = false
                }
            } else {
                content
            }
        }
    }
}
// MARK: - End XSign Inline Description Translation
