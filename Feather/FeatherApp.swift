//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import Nuke
import IDeviceSwift
import OSLog
import WebKit
import Combine

// MARK: - نماذج إعدادات التحكم عن بُعد (X-Sign Remote Config)
struct XSignRemoteRoot: Codable {
	let tintColor: String?
	let xsign_config: XSignRemoteConfig?
}

struct XSignRemoteConfig: Codable {
	let splash_screen: XSignSplashConfig?
	let theme: XSignThemeColors?
	let maintenance: XSignMaintenance?
	let force_update: XSignForceUpdate?
	let app_control: XSignAppControl?
}

struct XSignSplashConfig: Codable {
	let engine: String?          // "native_vector" أو "custom_css"
	let animation_style: String? // "laser_draw", "twin_slash", "neon_pulse", "liquid_shine", "cyber_glitch", "apple_minimal"
	let show_sign_feather: Bool?
	let duration_seconds: Double?
	let custom_code: String?
}

struct XSignThemeColors: Codable {
	let app_tint_hex: String?
	let splash_bg_top_hex: String?
	let splash_bg_bottom_hex: String?
	let splash_logo_hex: String?
}

struct XSignMaintenance: Codable {
	let enabled: Bool
	let title: String
	let message: String
	let button_url: String
}

struct XSignForceUpdate: Codable {
	let enabled: Bool
	let min_version: String
	let update_url: String
	let message: String
}

struct XSignCoreSourceItem: Codable {
	let name: String
	let id: String
	let url: String
}

struct XSignAppControl: Codable {
	let top_banner_enabled: Bool?
	let top_banner_text: String?
	let top_banner_url: String?
	let cache_flush_id: Int?
	let purge_sources_id: Int?
	let core_sources: [XSignCoreSourceItem]?
}

// MARK: - مدير الاتصال بلوحة التحكم
@MainActor
final class XSignRemoteManager: ObservableObject {
	static let shared = XSignRemoteManager()
	
	private let remoteJSONURL = "https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json"
	private let cacheKey = "xsign.cachedRemoteConfig_v2"
	
	@Published var config: XSignRemoteConfig?
	
	init() {
		if let savedData = UserDefaults.standard.data(forKey: cacheKey),
		   let cached = try? JSONDecoder().decode(XSignRemoteConfig.self, from: savedData) {
			self.config = cached
		}
	}
	
	var currentVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
	}
	
	var isMaintenanceActive: Bool {
		config?.maintenance?.enabled == true
	}
	
	var isForceUpdateRequired: Bool {
		guard let upd = config?.force_update, upd.enabled else { return false }
		return currentVersion.compare(upd.min_version, options: .numeric) == .orderedAscending
	}
	
	func fetchRemoteConfig() async {
		guard let url = URL(string: "\(remoteJSONURL)?t=\(Int(Date().timeIntervalSince1970))") else { return }
		do {
			let (data, _) = try await URLSession.shared.data(from: url)
			let decoded = try JSONDecoder().decode(XSignRemoteRoot.self, from: data)
			if let remoteCfg = decoded.xsign_config {
				self.config = remoteCfg
				if let encoded = try? JSONEncoder().encode(remoteCfg) {
					UserDefaults.standard.set(encoded, forKey: cacheKey)
				}
				if let newTint = remoteCfg.theme?.app_tint_hex, !newTint.isEmpty {
					UserDefaults.standard.set(newTint, forKey: "Feather.userTintColor")
					UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: newTint))
				}
				applyAppControlCommands(remoteCfg.app_control)
			}
		} catch {
			Logger.misc.error("XSignRemoteManager sync error: \(error.localizedDescription)")
		}
	}
	
	private func applyAppControlCommands(_ ctrl: XSignAppControl?) {
		guard let ctrl = ctrl else { return }
		if let flushID = ctrl.cache_flush_id {
			let lastFlush = UserDefaults.standard.integer(forKey: "xsign.lastCacheFlushID")
			if flushID > lastFlush {
				ImagePipeline.shared.cache.removeAll()
				URLCache.shared.removeAllCachedResponses()
				ResetView.clearWorkCache()
				UserDefaults.standard.set(flushID, forKey: "xsign.lastCacheFlushID")
			}
		}
	}
}

// MARK: - مشغل كود CSS / SVG المخصص لشاشة الإقلاع
struct XSignCustomCSSSplashWebView: UIViewRepresentable {
	let htmlCode: String
	
	func makeUIView(context: Context) -> WKWebView {
		let webView = WKWebView()
		webView.isOpaque = false
		webView.backgroundColor = .clear
		webView.scrollView.backgroundColor = .clear
		webView.scrollView.isScrollEnabled = false
		webView.isUserInteractionEnabled = false
		return webView
	}
	
	func updateUIView(_ webView: WKWebView, context: Context) {
		let doc = "<!DOCTYPE html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no'></head><body>\(htmlCode)</body></html>"
		webView.loadHTMLString(doc, baseURL: nil)
	}
}

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	let heartbeat = HeartbeatManager.shared
	
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject private var storeCache = AppStoreCacheManager.shared
	@StateObject private var sourcesViewModel = SourcesViewModel.shared
	@StateObject private var remoteManager = XSignRemoteManager.shared
	let storage = Storage.shared
	
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	@State private var _showSplash = true
	
	private var activeTintColor: Color {
		Color(hex: userTintHex)
	}
	
	var body: some Scene {
		WindowGroup {
			ZStack {
				VStack(spacing: 0) {
					// شريط التنبيه العلوي المدار من لوحة التحكم
					if remoteManager.config?.app_control?.top_banner_enabled == true,
					   let text = remoteManager.config?.app_control?.top_banner_text, !text.isEmpty {
						Button {
							if let uStr = remoteManager.config?.app_control?.top_banner_url,
							   let u = URL(string: uStr) {
								UIApplication.shared.open(u)
							}
						} label: {
							HStack(spacing: 8) {
								Image(systemName: "bell.badge.fill")
									.font(.caption.bold())
								Text(text)
									.font(.caption.bold())
									.lineLimit(1)
								Spacer()
								Image(systemName: "chevron.left")
									.font(.caption2)
							}
							.foregroundColor(.white)
							.padding(.horizontal, 14)
							.padding(.vertical, 8)
							.background(activeTintColor)
						}
					}
					
					DownloadHeaderView(downloadManager: downloadManager)
						.transition(.move(edge: .top).combined(with: .opacity))
					VariedTabbarView()
						.environment(\.managedObjectContext, storage.context)
						.onOpenURL(perform: _handleURL)
						.transition(.move(edge: .top).combined(with: .opacity))
				}
				.tint(activeTintColor)
				.accentColor(activeTintColor)
				.animation(.smooth, value: downloadManager.manualDownloads.description)
				
				if _showSplash {
					XSignPhotoIdenticalSplashView(
						cache: storeCache,
						sourcesViewModel: sourcesViewModel,
						remoteManager: remoteManager
					) {
						withAnimation(.easeInOut(duration: 0.45)) {
							_showSplash = false
						}
					}
					.transition(.opacity)
					.zIndex(999)
				}
				
				if !_showSplash && (remoteManager.isMaintenanceActive || remoteManager.isForceUpdateRequired) {
					XSignRemoteGateOverlayView(remoteManager: remoteManager, tintColor: activeTintColor)
						.transition(.opacity)
						.zIndex(1000)
				}
			}
			.preferredColorScheme(.dark)
			.task {
				await remoteManager.fetchRemoteConfig()
			}
			.onChange(of: userTintHex) { newHex in
				UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: newHex))
			}
			.onReceive(NotificationCenter.default.publisher(for: .heartbeatInvalidHost)) { _ in
				DispatchQueue.main.async {
					UIAlertController.showAlertWithOk(
						title: "InvalidHostID",
						message: .localized("Your pairing file is invalid and is incompatible with your device, please import a valid pairing file.")
					)
				}
			}
			.onAppear {
				if UserDefaults.standard.string(forKey: "Feather.userTintColor") == nil {
					UserDefaults.standard.set("#005BBB", forKey: "Feather.userTintColor")
				}
				if let style = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "Feather.userInterfaceStyle")) {
					UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
				}
				UIApplication.topViewController()?.view.window?.tintColor = UIColor(activeTintColor)
			}
		}
	}
	
	private func _handleURL(_ url: URL) {
		if url.scheme == "feather" {
			if url.host == "import-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
					let queryItems = components.queryItems
				else {
					return
				}
				
				func queryValue(_ name: String) -> String? {
					queryItems.first(where: { $0.name == name })?.value?.removingPercentEncoding
				}
				
				guard
					let p12Base64 = queryValue("p12"),
					let provisionBase64 = queryValue("mobileprovision"),
					let passwordBase64 = queryValue("password"),
					let passwordData = Data(base64Encoded: passwordBase64),
					let password = String(data: passwordData, encoding: .utf8)
				else {
					return
				}
				
				let generator = UINotificationFeedbackGenerator()
				generator.prepare()
				
				guard
					let p12URL = FileManager.default.decodeAndWrite(base64: p12Base64, pathComponent: ".p12"),
					let provisionURL = FileManager.default.decodeAndWrite(base64: provisionBase64, pathComponent: ".mobileprovision"),
					FR.checkPasswordForCertificate(for: p12URL, with: password, using: provisionURL)
				else {
					generator.notificationOccurred(.error)
					return
				}
				
				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
					p12Password: password
				) { error in
					if let error = error {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
					} else {
						generator.notificationOccurred(.success)
					}
				}
				
				return
			}
			if url.host == "export-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
				else {
					return
				}
				
				let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
				guard let callbackTemplate = queryItems["callback_template"]?.removingPercentEncoding else { return }
				
				FR.exportCertificateAndOpenUrl(using: callbackTemplate)
			}
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { }
			}
			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				UIAlertController.showAlertWithCancel(
					title: .localized("Install"),
					message: .localized("Do you want to download and install this file?") + "\n\n\(downloadURL)",
					actions: [
						UIAlertAction(title: .localized("Install"), style: .default) { _ in
							_ = DownloadManager.shared.startDownload(from: downloadURL)
						}
					]
				)
			}
		} else {
			if url.pathExtension == "ipa" || url.pathExtension == "tipa" {
				Task.detached(priority: .userInteractive) {
					autoreleasepool {
						if FileManager.default.isFileFromFileProvider(at: url) {
							guard url.startAccessingSecurityScopedResource() else { return }
							defer { url.stopAccessingSecurityScopedResource() }
							FR.handlePackageFile(url) { _ in }
						} else {
							FR.handlePackageFile(url) { _ in }
						}
					}
				}
				return
			}
		}
	}
}

// MARK: - شاشة الصيانة والتحديث الإجباري
struct XSignRemoteGateOverlayView: View {
	@ObservedObject var remoteManager: XSignRemoteManager
	let tintColor: Color
	
	var body: some View {
		ZStack {
			Color(red: 0.0, green: 0.17, blue: 0.40).ignoresSafeArea()
			
			VStack(spacing: 20) {
				Image(systemName: remoteManager.isMaintenanceActive ? "wrench.and.screwdriver.fill" : "arrow.down.circle.fill")
					.font(.system(size: 56))
					.foregroundColor(.white)
				
				Text(remoteManager.isMaintenanceActive
					 ? (remoteManager.config?.maintenance?.title ?? "التطبيق قيد الصيانة")
					 : "تحديث إجباري مطلوب")
					.font(.title2.bold())
					.foregroundColor(.white)
					.multilineTextAlignment(.center)
				
				Text(remoteManager.isMaintenanceActive
					 ? (remoteManager.config?.maintenance?.message ?? "يرجى المحاولة لاحقاً.")
					 : (remoteManager.config?.force_update?.message ?? "يرجى تحديث التطبيق لأحدث إصدار."))
					.font(.subheadline)
					.foregroundColor(.white.opacity(0.8))
					.multilineTextAlignment(.center)
					.padding(.horizontal, 24)
				
				Button {
					let target = remoteManager.isMaintenanceActive
						? (remoteManager.config?.maintenance?.button_url ?? "")
						: (remoteManager.config?.force_update?.update_url ?? "")
					if let url = URL(string: target) {
						UIApplication.shared.open(url)
					}
				} label: {
					Text(remoteManager.isMaintenanceActive ? "متابعة قناة التيليجرام" : "تحديث التطبيق الآن")
						.font(.headline.bold())
						.foregroundColor(Color(red: 0.0, green: 0.17, blue: 0.40))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
						.background(Color.white)
						.cornerRadius(14)
				}
				.padding(.horizontal, 36)
			}
			.padding(24)
		}
	}
}

// MARK: - المسارات الهندسية المطابقة 100% لصورة X Sign (الشريطان المفرغان + الريشة)

// الشريط الهندسي الأيسر العلوي لحرف X (مع الشفرة الحادة الصاعدة والهابطة)
struct ExactImageXLeftRibbon: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height
		func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
		
		var path = Path()
		path.move(to: pt(0.3157, 0.1961))
		path.addLine(to: pt(0.4431, 0.1961))
		path.addLine(to: pt(0.4863, 0.2725))
		path.addLine(to: pt(0.6373, 0.0569))
		path.addLine(to: pt(0.4863, 0.3176))
		path.addLine(to: pt(0.4275, 0.2196))
		path.addLine(to: pt(0.3529, 0.2196))
		path.addLine(to: pt(0.4373, 0.3824))
		path.addLine(to: pt(0.2549, 0.6941))
		path.addLine(to: pt(0.4157, 0.3824))
		path.closeSubpath()
		return path
	}
}

// الشريط الهندسي الأيمن السفلي لحرف X (الموازي للشريط الأول مع القاعدة اليمنى)
struct ExactImageXRightRibbon: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height
		func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
		
		var path = Path()
		path.move(to: pt(0.7451, 0.0569))
		path.addLine(to: pt(0.5765, 0.3961))
		path.addLine(to: pt(0.6745, 0.5745))
		path.addLine(to: pt(0.5353, 0.5745))
		path.addLine(to: pt(0.5000, 0.5020))
		path.addLine(to: pt(0.3588, 0.6980))
		path.addLine(to: pt(0.5020, 0.4549))
		path.addLine(to: pt(0.5529, 0.5471))
		path.addLine(to: pt(0.6353, 0.5471))
		path.addLine(to: pt(0.5471, 0.3961))
		path.closeSubpath()
		return path
	}
}

// مسار الريشة الانسيابية المتصلة بنهاية كلمة Sign
struct ExactImageSignFeatherWing: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height
		func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
		
		var path = Path()
		path.move(to: pt(0.604, 0.812))
		path.addCurve(to: pt(0.725, 0.760), control1: pt(0.625, 0.782), control2: pt(0.665, 0.785))
		path.addCurve(to: pt(0.668, 0.770), control1: pt(0.702, 0.770), control2: pt(0.686, 0.772))
		path.addCurve(to: pt(0.746, 0.672), control1: pt(0.708, 0.752), control2: pt(0.738, 0.725))
		path.addCurve(to: pt(0.646, 0.745), control1: pt(0.722, 0.715), control2: pt(0.688, 0.732))
		path.addCurve(to: pt(0.704, 0.692), control1: pt(0.672, 0.728), control2: pt(0.695, 0.712))
		path.addCurve(to: pt(0.622, 0.752), control1: pt(0.674, 0.718), control2: pt(0.642, 0.726))
		path.addCurve(to: pt(0.594, 0.816), control1: pt(0.612, 0.765), control2: pt(0.602, 0.795))
		path.closeSubpath()
		return path
	}
}

// العرض المتكامل للشعار المطابق للصورة مع أنماط الحركة الستة
struct PhotoIdenticalXVectorView: View {
	let progress: CGFloat
	let fillAlpha: Double
	let glow: Double
	var logoColor: Color = .white
	var showSignAndFeather: Bool = true
	var leftOffset: CGSize = .zero
	var rightOffset: CGSize = .zero
	
	var body: some View {
		ZStack {
			// الشريط الأيسر العلوي لحرف X
			ZStack {
				ExactImageXLeftRibbon()
					.fill(logoColor.opacity(fillAlpha))
				ExactImageXLeftRibbon()
					.trim(from: 0, to: progress)
					.stroke(logoColor, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .miter, miterLimit: 18))
			}
			.offset(leftOffset)
			
			// الشريط الأيمن السفلي لحرف X
			ZStack {
				ExactImageXRightRibbon()
					.fill(logoColor.opacity(fillAlpha))
				ExactImageXRightRibbon()
					.trim(from: 0, to: progress)
					.stroke(logoColor, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .miter, miterLimit: 18))
			}
			.offset(rightOffset)
			
			// كلمة Sign المائلة + الريشة البيضاء المطابقة للصورة
			if showSignAndFeather {
				ZStack {
					Text("Sign")
						.font(.custom("Georgia-Italic", size: 52))
						.foregroundColor(logoColor)
						.position(x: 146, y: 262)
					
					ExactImageSignFeatherWing()
						.fill(logoColor)
				}
				.opacity(fillAlpha)
			}
		}
		.frame(width: 320, height: 320)
		.shadow(color: logoColor.opacity(0.65 * glow), radius: 14, x: 0, y: 0)
	}
}

struct XSignPhotoIdenticalSplashView: View {
	@ObservedObject var cache: AppStoreCacheManager
	@ObservedObject var sourcesViewModel: SourcesViewModel
	@ObservedObject var remoteManager: XSignRemoteManager
	var onFinished: () -> Void
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	@State private var drawProgress: CGFloat = 0.0
	@State private var fillAlpha: Double = 0.0
	@State private var glowOpacity: Double = 0.0
	@State private var scaleValue: CGFloat = 0.92
	@State private var leftSlide: CGSize = .zero
	@State private var rightSlide: CGSize = .zero
	@State private var didFinishMinimumAnimation = false
	@State private var didDismiss = false
	
	private var useCustomCSS: Bool {
		guard let sp = remoteManager.config?.splash_screen else { return false }
		return sp.engine == "custom_css" && !(sp.custom_code ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	}
	
	var body: some View {
		ZStack {
			if useCustomCSS, let code = remoteManager.config?.splash_screen?.custom_code {
				XSignCustomCSSSplashWebView(htmlCode: code)
					.ignoresSafeArea()
			} else {
				let topHex = remoteManager.config?.theme?.splash_bg_top_hex ?? "#002B66"
				let botHex = remoteManager.config?.theme?.splash_bg_bottom_hex ?? "#00183B"
				let logoHex = remoteManager.config?.theme?.splash_logo_hex ?? "#FFFFFF"
				let showSign = remoteManager.config?.splash_screen?.show_sign_feather ?? true
				
				LinearGradient(
					colors: [Color(hex: topHex), Color(hex: botHex)],
					startPoint: .top,
					endPoint: .bottom
				)
				.ignoresSafeArea()
				
				PhotoIdenticalXVectorView(
					progress: drawProgress,
					fillAlpha: fillAlpha,
					glow: glowOpacity,
					logoColor: Color(hex: logoHex),
					showSignAndFeather: showSign,
					leftOffset: leftSlide,
					rightOffset: rightSlide
				)
				.scaleEffect(scaleValue)
			}
		}
		.task {
			await cache.ensureFetched(sources: _sources, viewModel: sourcesViewModel)
			checkIfReadyToDismiss()
		}
		.onChange(of: cache.allCombinedItems.count) { _ in
			checkIfReadyToDismiss()
		}
		.onAppear {
			runSelectedAnimationStyle()
		}
	}
	
	private func runSelectedAnimationStyle() {
		let style = remoteManager.config?.splash_screen?.animation_style ?? "laser_draw"
		let duration = remoteManager.config?.splash_screen?.duration_seconds ?? 3.8
		
		switch style {
		case "twin_slash":
			drawProgress = 1.0
			fillAlpha = 1.0
			leftSlide = CGSize(width: -120, height: 120)
			rightSlide = CGSize(width: 120, height: -120)
			withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) {
				leftSlide = .zero
				rightSlide = .zero
				scaleValue = 1.0
				glowOpacity = 0.85
			}
		case "neon_pulse":
			drawProgress = 1.0
			fillAlpha = 1.0
			scaleValue = 1.0
			withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
				glowOpacity = 1.0
				scaleValue = 0.96
			}
		case "apple_minimal":
			drawProgress = 1.0
			scaleValue = 0.85
			withAnimation(.easeOut(duration: 1.1)) {
				fillAlpha = 1.0
				scaleValue = 1.0
				glowOpacity = 0.35
			}
		default: // "laser_draw" والأنماط الأخرى
			drawProgress = 0.0
			fillAlpha = 0.0
			withAnimation(.easeInOut(duration: 1.35)) {
				drawProgress = 1.0
				scaleValue = 1.0
			}
			withAnimation(.easeIn(duration: 0.55).delay(1.05)) {
				fillAlpha = 1.0
				glowOpacity = 0.6
			}
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
			didFinishMinimumAnimation = true
			checkIfReadyToDismiss()
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
			dismissSplash()
		}
	}
	
	private func checkIfReadyToDismiss() {
		guard didFinishMinimumAnimation else { return }
		if !cache.ipablackItems.isEmpty || !cache.allCombinedItems.isEmpty {
			dismissSplash()
		}
	}
	
	private func dismissSplash() {
		guard !didDismiss else { return }
		didDismiss = true
		onFinished()
	}
}

class AppDelegate: NSObject, UIApplicationDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		_createLowMemoryPipeline()
		_createDocumentsDirectories()
		ResetView.clearWorkCache()
		_addDefaultCertificates()
		_configureProtectedCoreSources()
		return true
	}
	
	func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
		ImagePipeline.shared.cache.removeAll()
		URLCache.shared.removeAllCachedResponses()
	}
	
	private func _createLowMemoryPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		DataLoader.sharedUrlCache.memoryCapacity = 0
		
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				config.requestCachePolicy = .returnCacheDataElseLoad
				config.httpMaximumConnectionsPerHost = 12
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache")
			let imageCache = Nuke.ImageCache()
			dataCache?.sizeLimit = 300 * 1024 * 1024
			imageCache.costLimit = 40 * 1024 * 1024
			imageCache.countLimit = 100
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .storeEncodedImages
			$0.isStoringPreviewsInMemoryCache = false
			$0.isDecompressionEnabled = true
		}
		
		ImagePipeline.shared = pipeline
	}
	
	private func _createDocumentsDirectories() {
		let fileManager = FileManager.default

		let directories: [URL] = [
			fileManager.archives,
			fileManager.certificates,
			fileManager.signed,
			fileManager.unsigned
		]
		
		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}
	
	private func _configureProtectedCoreSources() {
		let context = Storage.shared.context
		context.perform {
			let request = NSFetchRequest<AltSource>(entityName: "AltSource")
			let existingSources = (try? context.fetch(request)) ?? []
			
			let purgedOnceKey = "xsign.didPurgeLegacyDefaultRepos_v5"
			for source in existingSources {
				let urlStr = source.sourceURL?.absoluteString.lowercased() ?? ""
				let idStr = source.identifier?.lowercased() ?? ""
				if urlStr.contains("apptesters") || idStr.contains("apptesters") {
					context.delete(source)
				} else if !UserDefaults.standard.bool(forKey: purgedOnceKey) {
					if !urlStr.contains("/ipablack/") && !urlStr.contains("store-api") {
						context.delete(source)
					}
				}
			}
			UserDefaults.standard.set(true, forKey: purgedOnceKey)
			
			let coreRepos: [(name: String, id: String, url: String)] = [
				("IPA BLACK", "xsign.core.ipablack", "https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json"),
				("IPA BLACK Store", "xsign.core.storeapi", "https://raw.githubusercontent.com/ipa-black/store-api/main/public/repo.json")
			]
			
			let updatedExisting = (try? context.fetch(request)) ?? []
			for repo in coreRepos {
				guard let repoURL = URL(string: repo.url) else { continue }
				let alreadyExists = updatedExisting.contains {
					$0.sourceURL?.absoluteString.lowercased() == repo.url.lowercased() ||
					$0.identifier == repo.id
				}
				if !alreadyExists {
					let newSource = AltSource(context: context)
					newSource.name = repo.name
					newSource.identifier = repo.id
					newSource.sourceURL = repoURL
					newSource.date = Date()
				}
			}
			
			try? context.save()
		}
	}
	
	private func _addDefaultCertificates() {
		guard
			UserDefaults.standard.bool(forKey: "feather.didImportDefaultCertificates") == false,
			let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
		else {
			return
		}
		
		do {
			let folderContents = try FileManager.default.contentsOfDirectory(
				at: signingAssetsURL,
				includingPropertiesForKeys: nil,
				options: .skipsHiddenFiles
			)
			
			for folderURL in folderContents {
				guard folderURL.hasDirectoryPath else { continue }
				
				let certName = folderURL.lastPathComponent
				
				let p12Url = folderURL.appendingPathComponent("cert.p12")
				let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
				let passwordUrl = folderURL.appendingPathComponent("cert.txt")
				
				guard
					FileManager.default.fileExists(atPath: p12Url.path),
					FileManager.default.fileExists(atPath: provisionUrl.path),
					FileManager.default.fileExists(atPath: passwordUrl.path)
				else {
					Logger.misc.warning("Skipping \(certName): missing required files")
					continue
				}
				
				let password = try String(contentsOf: passwordUrl, encoding: .utf8)
				
				FR.handleCertificateFiles(
					p12URL: p12Url,
					provisionURL: provisionUrl,
					p12Password: password,
					certificateName: certName,
					isDefault: true
				) { _ in
					
				}
			}
			UserDefaults.standard.set(true, forKey: "feather.didImportDefaultCertificates")
		} catch {
			Logger.misc.error("Failed to list signing-assets: \(error)")
		}
	}
}
