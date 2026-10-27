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
import SystemConfiguration
import Network

// MARK: - نماذج إعدادات اللوحة (متوافقة مع Sendable في Xcode 26.3)
struct XSignRemoteRoot: Codable, Sendable {
	let tintColor: String?
	let repo_revision_id: Int?
	let xsign_config: XSignRemoteConfig?
}

struct XSignRemoteConfig: Codable, Equatable, Sendable {
	let splash_screen: XSignSplashConfig?
	let theme: XSignThemeColors?
	let maintenance: XSignMaintenance?
	let force_update: XSignForceUpdate?
	let security_locks: XSignSecurityLocks?
	let app_control: XSignAppControl?
}

struct XSignSplashConfig: Codable, Equatable, Sendable {
	let engine: String?
	let animation_style: String?
	let show_sign_feather: Bool?
	let duration_seconds: Double?
	let custom_code: String?
}

struct XSignThemeColors: Codable, Equatable, Sendable {
	let app_tint_hex: String?
	let splash_bg_top_hex: String?
	let splash_bg_bottom_hex: String?
	let splash_logo_hex: String?
}

struct XSignMaintenance: Codable, Equatable, Sendable {
	let enabled: Bool?
	let title: String?
	let message: String?
	let button_url: String?
}

struct XSignForceUpdate: Codable, Equatable, Sendable {
	let enabled: Bool?
	let min_version: String?
	let update_url: String?
	let message: String?
}

struct XSignSecurityLocks: Codable, Equatable, Sendable {
	let lock_bundle_rename: Bool?
	let lock_icon_change: Bool?
	let lock_dylib_injection: Bool?
	let anti_vpn_proxy: Bool?
	let require_online_handshake: Bool?
	let vpn_warning_message: String?
}

struct XSignCoreSourceItem: Codable, Equatable, Sendable {
	let name: String
	let id: String
	let url: String
}

struct XSignAppControl: Codable, Equatable, Sendable {
	let top_banner_enabled: Bool?
	let top_banner_text: String?
	let top_banner_url: String?
	let cache_flush_id: Int?
	let purge_sources_id: Int?
	let core_sources: [XSignCoreSourceItem]?
}

// MARK: - مدقق الحماية والأمان (بدون أي مؤقتات تسبب لاك أثناء البحث)
@MainActor
final class XSignSecurityEnforcer: ObservableObject {
	static let shared = XSignSecurityEnforcer()
	
	private let locksStorageKey = "xsign.persistedSecurityLocks_v4"
	private let pathMonitor = NWPathMonitor()
	private let monitorQueue = DispatchQueue(label: "com.ipablack.xsign.netguard", qos: .utility)
	
	@Published var locks: XSignSecurityLocks = XSignSecurityLocks(
		lock_bundle_rename: true,
		lock_icon_change: true,
		lock_dylib_injection: true,
		anti_vpn_proxy: true,
		require_online_handshake: true,
		vpn_warning_message: "عذراً، لا يمكن استخدام تطبيق X-Sign أو تحميل التطبيقات أثناء تشغيل VPN أو برامج مراقبة الشبكة (Proxy)."
	)
	@Published var isVPNOrProxyDetected: Bool = false
	@Published var didCompleteOnlineHandshake: Bool = false
	
	init() {
		if let data = UserDefaults.standard.data(forKey: locksStorageKey),
		   let saved = try? JSONDecoder().decode(XSignSecurityLocks.self, from: data) {
			self.locks = saved
		}
		evaluateNetworkSecurity()
		startEventDrivenNetworkMonitor()
	}
	
	func updateLocks(_ newLocks: XSignSecurityLocks?) {
		guard let newLocks = newLocks else { return }
		if self.locks != newLocks {
			self.locks = newLocks
		}
		self.didCompleteOnlineHandshake = true
		if let encoded = try? JSONEncoder().encode(newLocks) {
			UserDefaults.standard.set(encoded, forKey: locksStorageKey)
		}
		evaluateNetworkSecurity()
	}
	
	private func startEventDrivenNetworkMonitor() {
		pathMonitor.pathUpdateHandler = { [weak self] _ in
			let detected = Self.isVPNOrProxyActiveOnDevice()
			Task { @MainActor [weak self] in
				guard let self = self else { return }
				let shouldBlock = (self.locks.anti_vpn_proxy ?? true) && detected
				if self.isVPNOrProxyDetected != shouldBlock {
					self.isVPNOrProxyDetected = shouldBlock
				}
			}
		}
		pathMonitor.start(queue: monitorQueue)
	}
	
	func evaluateNetworkSecurity() {
		let antiVPNEnabled = locks.anti_vpn_proxy ?? true
		DispatchQueue.global(qos: .utility).async { [weak self] in
			let detected = antiVPNEnabled ? Self.isVPNOrProxyActiveOnDevice() : false
			DispatchQueue.main.async {
				guard let self = self else { return }
				if self.isVPNOrProxyDetected != detected {
					self.isVPNOrProxyDetected = detected
				}
			}
		}
	}
	
	nonisolated static func isVPNOrProxyActiveOnDevice() -> Bool {
		guard let cfSettings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() else {
			return false
		}
		guard let cfDict = cfSettings as NSDictionary as? [String: Any] else {
			return false
		}
		
		let proxyKeys = [
			"HTTPEnable", "HTTPSEnable", "SOCKSEnable", "ProxyAutoConfigEnable",
			"HTTPProxy", "HTTPSProxy", "SOCKSProxy"
		]
		for key in proxyKeys {
			if let val = cfDict[key] as? Int, val == 1 { return true }
			if let str = cfDict[key] as? String, !str.isEmpty { return true }
		}
		
		if let scoped = cfDict["__SCOPED__"] as? [String: Any] {
			let vpnPrefixes = ["tap", "tun", "utun", "ppp", "ipsec", "wg", "pptp", "l2tp"]
			for iface in scoped.keys {
				let lower = iface.lowercased()
				if vpnPrefixes.contains(where: { lower.contains($0) }) {
					return true
				}
			}
		}
		return false
	}
	
	func validateSigningPermissions(
		originalName: String,
		newName: String,
		originalBundleID: String,
		newBundleID: String,
		didModifyIcon: Bool,
		injectedDylibCount: Int
	) -> (allowed: Bool, errorMessage: String?) {
		if (locks.require_online_handshake ?? true) && !didCompleteOnlineHandshake {
			return (false, "يجب الاتصال بالإنترنت للتحقق من صلاحيات التوقيع والأمان.")
		}
		if isVPNOrProxyDetected {
			return (false, locks.vpn_warning_message ?? "يرجى إيقاف الـ VPN أو مراقب الشبكة أولاً.")
		}
		if (locks.lock_bundle_rename ?? true) && (originalName != newName || originalBundleID != newBundleID) {
			return (false, "غير مسموح بتعديل اسم التطبيق أو معرف الحزمة (Bundle ID).")
		}
		if (locks.lock_icon_change ?? true) && didModifyIcon {
			return (false, "غير مسموح بتغيير أو استبدال أيقونة التطبيق الأصلية.")
		}
		if (locks.lock_dylib_injection ?? true) && injectedDylibCount > 0 {
			return (false, "غير مسموح بحقن أدوات خارجية (.dylib / .deb) داخل التطبيق.")
		}
		return (true, nil)
	}
}

// MARK: - مدير المزامنة مع لوحة التحكم (يحدث التطبيقات المحذوفة والأيقونات الجديدة تلقائياً)
@MainActor
final class XSignRemoteManager: ObservableObject {
	static let shared = XSignRemoteManager()
	
	private let apiRawEndpoint = "https://api.github.com/repos/ipa-black/IPABLACK/contents/repo.json?ref=main"
	private let fallbackRawURL = "https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json"
	private let cacheKey = "xsign.cachedRemoteConfig_v6"
	private let revKey = "xsign.lastSeenRevisionID_v6"
	
	@Published var config: XSignRemoteConfig?
	@Published var currentRevisionID: Int = UserDefaults.standard.integer(forKey: "xsign.lastSeenRevisionID_v6")
	private var isFetching = false
	
	init() {
		if let savedData = UserDefaults.standard.data(forKey: cacheKey),
		   let cached = try? JSONDecoder().decode(XSignRemoteConfig.self, from: savedData) {
			self.config = cached
			XSignSecurityEnforcer.shared.updateLocks(cached.security_locks)
		}
	}
	
	var currentVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
	}
	
	var isMaintenanceActive: Bool {
		config?.maintenance?.enabled == true
	}
	
	var isForceUpdateRequired: Bool {
		guard let upd = config?.force_update, upd.enabled == true,
			  let minVer = upd.min_version else { return false }
		return currentVersion.compare(minVer, options: .numeric) == .orderedAscending
	}
	
	func fetchRemoteConfig(
		storeCache: AppStoreCacheManager? = nil,
		sourcesViewModel: SourcesViewModel? = nil
	) async {
		guard !isFetching else { return }
		isFetching = true
		defer { isFetching = false }
		
		XSignSecurityEnforcer.shared.evaluateNetworkSecurity()
		
		let apiEndpoint = self.apiRawEndpoint
		let fallbackEndpoint = self.fallbackRawURL
		
		let decodedRoot: XSignRemoteRoot? = await Task.detached(priority: .utility) {
			let sessionConfig = URLSessionConfiguration.ephemeral
			sessionConfig.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
			sessionConfig.timeoutIntervalForRequest = 6.0
			sessionConfig.urlCache = nil
			let session = URLSession(configuration: sessionConfig)
			
			var fetchedData: Data? = nil
			
			if let apiURL = URL(string: "\(apiEndpoint)&_=\(Int(Date().timeIntervalSince1970))") {
				var req = URLRequest(url: apiURL)
				req.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept")
				if let (data, res) = try? await session.data(for: req),
				   let http = res as? HTTPURLResponse, http.statusCode == 200 {
					fetchedData = data
				}
			}
			
			if fetchedData == nil, let rawURL = URL(string: "\(fallbackEndpoint)?t=\(Int(Date().timeIntervalSince1970))") {
				if let (data, _) = try? await session.data(from: rawURL) {
					fetchedData = data
				}
			}
			
			guard let data = fetchedData else { return nil }
			return try? JSONDecoder().decode(XSignRemoteRoot.self, from: data)
		}.value
		
		guard let decoded = decodedRoot else { return }
		
		if let remoteCfg = decoded.xsign_config {
			if self.config != remoteCfg {
				self.config = remoteCfg
				if let encoded = try? JSONEncoder().encode(remoteCfg) {
					UserDefaults.standard.set(encoded, forKey: cacheKey)
				}
				if !UserDefaults.standard.bool(forKey: "Feather.hasCustomTintColor"),
				   let newTint = remoteCfg.theme?.app_tint_hex, !newTint.isEmpty {
					let currentTint = UserDefaults.standard.string(forKey: "Feather.userTintColor")
					if currentTint != newTint {
						UserDefaults.standard.set(newTint, forKey: "Feather.userTintColor")
						UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: newTint))
					}
				}
				applyAppControlCommands(remoteCfg.app_control)
			}
			XSignSecurityEnforcer.shared.updateLocks(remoteCfg.security_locks)
		}
		
		// إذا تم حذف تطبيق أو رفع تطبيق جديد بصورة مستخرجة في اللوحة، يتغير repo_revision_id فنحدث السورس فوراً
		if let newRev = decoded.repo_revision_id, newRev != self.currentRevisionID {
			self.currentRevisionID = newRev
			UserDefaults.standard.set(newRev, forKey: revKey)
			URLCache.shared.removeAllCachedResponses()
			
			if let storeCache = storeCache, let sourcesViewModel = sourcesViewModel {
				let request = NSFetchRequest<AltSource>(entityName: "AltSource")
				if let sources = try? Storage.shared.context.fetch(request) {
					await storeCache.forceRefresh(sources: sources, viewModel: sourcesViewModel)
				}
			}
		}
	}
	
	private func applyAppControlCommands(_ ctrl: XSignAppControl?) {
		guard let ctrl = ctrl, let flushID = ctrl.cache_flush_id else { return }
		let lastFlush = UserDefaults.standard.integer(forKey: "xsign.lastCacheFlushID")
		if flushID > lastFlush {
			ImagePipeline.shared.cache.removeAll()
			URLCache.shared.removeAllCachedResponses()
			ResetView.clearWorkCache()
			UserDefaults.standard.set(flushID, forKey: "xsign.lastCacheFlushID")
		}
	}
}

// MARK: - جسر WKScriptMessageHandler لشاشة الإقلاع المخصصة
final class XSignSplashScriptCoordinator: NSObject, WKScriptMessageHandler {
	var onAnimationCompleted: (() -> Void)?
	
	func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
		if message.name == "xsignSplash" {
			DispatchQueue.main.async { [weak self] in
				self?.onAnimationCompleted?()
			}
		}
	}
}

struct XSignCustomCSSSplashWebView: UIViewRepresentable {
	let htmlCode: String
	var onFinishedFromJS: (() -> Void)? = nil
	
	func makeCoordinator() -> XSignSplashScriptCoordinator {
		let coord = XSignSplashScriptCoordinator()
		coord.onAnimationCompleted = onFinishedFromJS
		return coord
	}
	
	func makeUIView(context: Context) -> WKWebView {
		let contentController = WKUserContentController()
		contentController.add(context.coordinator, name: "xsignSplash")
		
		let webConfig = WKWebViewConfiguration()
		webConfig.userContentController = contentController
		
		let webView = WKWebView(frame: .zero, configuration: webConfig)
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
	@Environment(\.scenePhase) private var scenePhase
	
	let heartbeat = HeartbeatManager.shared
	
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject private var storeCache = AppStoreCacheManager.shared
	@StateObject private var sourcesViewModel = SourcesViewModel.shared
	@StateObject private var remoteManager = XSignRemoteManager.shared
	@StateObject private var securityEnforcer = XSignSecurityEnforcer.shared
	let storage = Storage.shared
	
	@AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
    @AppStorage("Feather.userInterfaceStyle")
    private var userInterfaceStyle: Int = UIUserInterfaceStyle.unspecified.rawValue
	
	private var activeTintColor: Color {
		Color(hex: userTintHex)
	}

    private var preferredAppColorScheme: ColorScheme? {
        switch UIUserInterfaceStyle(rawValue: userInterfaceStyle) ?? .unspecified {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }

    private func applyAppearanceToWindows() {
        let style = UIUserInterfaceStyle(rawValue: userInterfaceStyle) ?? .unspecified
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
                window.tintColor = UIColor(activeTintColor)
            }
        }
    }
	
	var body: some Scene {
		WindowGroup {
			ZStack {
				VStack(spacing: 0) {
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
							.foregroundColor(AppStoreTheme.contrastingText(forHex: userTintHex))
							.padding(.horizontal, 14)
							.padding(.vertical, 9)
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
				

				if remoteManager.isMaintenanceActive || remoteManager.isForceUpdateRequired {
					XSignRemoteGateOverlayView(remoteManager: remoteManager, tintColor: activeTintColor)
						.transition(.opacity)
						.zIndex(1000)
				}
				
				if securityEnforcer.isVPNOrProxyDetected {
					XSignVPNBlockedOverlayView(
						message: securityEnforcer.locks.vpn_warning_message ?? "عذراً، لا يمكن استخدام التطبيق أو التحميل أثناء تشغيل VPN أو مراقب شبكة."
					) {
						securityEnforcer.evaluateNetworkSecurity()
					}
					.transition(.opacity)
					.zIndex(2000)
				}
			}
            .tint(activeTintColor)
            .accentColor(activeTintColor)
			.preferredColorScheme(preferredAppColorScheme)
			.task {
                let launchSources = storage.getSources()
                Task { @MainActor in
                    await storeCache.ensureFetched(sources: launchSources, viewModel: sourcesViewModel)
                }
				await remoteManager.fetchRemoteConfig(storeCache: storeCache, sourcesViewModel: sourcesViewModel)
			}
			.onChange(of: scenePhase) { newPhase in
				if newPhase == .active {
					securityEnforcer.evaluateNetworkSecurity()
                    let activeSources = storage.getSources()
                    Task { @MainActor in
                        await storeCache.ensureFetched(sources: activeSources, viewModel: sourcesViewModel)
                    }
					Task {
						await remoteManager.fetchRemoteConfig(storeCache: storeCache, sourcesViewModel: sourcesViewModel)
					}
				}
			}
            .onChange(of: userTintHex) { _ in
                applyAppearanceToWindows()
            }
            .onChange(of: userInterfaceStyle) { _ in
                applyAppearanceToWindows()
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
                applyAppearanceToWindows()
			}
		}
	}
	
	private func _handleURL(_ url: URL) {
		XSignSecurityEnforcer.shared.evaluateNetworkSecurity()
		if XSignSecurityEnforcer.shared.isVPNOrProxyDetected {
			UIAlertController.showAlertWithOk(
				title: "تنبيه أمني",
				message: XSignSecurityEnforcer.shared.locks.vpn_warning_message ?? "يرجى إيقاف الـ VPN أو مراقب الشبكة أولاً."
			)
			return
		}
		
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
							guard !XSignSecurityEnforcer.shared.isVPNOrProxyDetected else { return }
							_ = DownloadManager.shared.startDownload(from: downloadURL)
						}
					]
				)
			}
		} else {
			if url.pathExtension == "ipa" || url.pathExtension == "tipa" {
				Task.detached(priority: .high) {
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

// MARK: - شاشة الحظر عند اكتشاف VPN أو مراقب شبكة
struct XSignVPNBlockedOverlayView: View {
	let message: String
	var onRetry: () -> Void
	
	var body: some View {
		ZStack {
			AppStoreTheme.background.ignoresSafeArea()
			
			VStack(spacing: 18) {
				Image(systemName: "network.badge.shield.half.filled")
					.font(.system(size: 58))
					.foregroundColor(.red)
				
				Text("تم إيقاف الاتصال لحماية التطبيق")
					.font(.title3.bold())
					.foregroundColor(.primary)
				
				Text(message)
					.font(.subheadline)
					.foregroundColor(.secondary)
					.multilineTextAlignment(.center)
					.padding(.horizontal, 28)
				
				Button(action: onRetry) {
					Text("إعادة الفحص بعد إيقاف الـ VPN")
						.font(.headline.bold())
						.foregroundColor(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
						.background(Color.red)
						.cornerRadius(14)
				}
				.padding(.horizontal, 40)
				.padding(.top, 8)
			}
			.padding(24)
		}
	}
}

// MARK: - شاشة الصيانة والتحديث الإجباري
struct XSignRemoteGateOverlayView: View {
	@ObservedObject var remoteManager: XSignRemoteManager
	let tintColor: Color
    @AppStorage("Feather.userTintColor") private var userTintHex: String = "#005BBB"
	
	var body: some View {
		ZStack {
			AppStoreTheme.background.ignoresSafeArea()
			
			VStack(spacing: 20) {
				Image(systemName: remoteManager.isMaintenanceActive ? "wrench.and.screwdriver.fill" : "arrow.down.circle.fill")
					.font(.system(size: 56))
					.foregroundColor(tintColor)
				
				Text(remoteManager.isMaintenanceActive
					 ? (remoteManager.config?.maintenance?.title ?? "التطبيق قيد الصيانة")
					 : "تحديث إجباري مطلوب")
					.font(.title2.bold())
					.foregroundColor(.primary)
					.multilineTextAlignment(.center)
				
				Text(remoteManager.isMaintenanceActive
					 ? (remoteManager.config?.maintenance?.message ?? "يرجى المحاولة لاحقاً.")
					 : (remoteManager.config?.force_update?.message ?? "يرجى تحديث التطبيق لأحدث إصدار."))
					.font(.subheadline)
					.foregroundColor(.secondary)
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
						.foregroundColor(AppStoreTheme.contrastingText(forHex: userTintHex))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
						.background(tintColor)
						.cornerRadius(14)
				}
				.padding(.horizontal, 36)
			}
			.padding(24)
		}
	}
}

// MARK: - المسارات الهندسية المطابقة 100% لصورة X Sign
struct ExactImageXLeftRibbon: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width, h = rect.height
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

struct ExactImageXRightRibbon: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width, h = rect.height
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

struct ExactImageSignFeatherWing: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width, h = rect.height
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
			ZStack {
				ExactImageXLeftRibbon()
					.fill(logoColor.opacity(fillAlpha))
				ExactImageXLeftRibbon()
					.trim(from: 0, to: progress)
					.stroke(logoColor, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .miter, miterLimit: 18))
			}
			.offset(leftOffset)
			
			ZStack {
				ExactImageXRightRibbon()
					.fill(logoColor.opacity(fillAlpha))
				ExactImageXRightRibbon()
					.trim(from: 0, to: progress)
					.stroke(logoColor, style: StrokeStyle(lineWidth: 2.8, lineCap: .round, lineJoin: .miter, miterLimit: 18))
			}
			.offset(rightOffset)
			
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
				XSignCustomCSSSplashWebView(htmlCode: code) {
					didFinishMinimumAnimation = true
					dismissSplash()
				}
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
		.onChange(of: cache.ipablackItems.count) { _ in
			checkIfReadyToDismiss()
		}
		.onAppear {
			runSelectedAnimationStyle()
		}
	}
	
	private func runSelectedAnimationStyle() {
		let style = remoteManager.config?.splash_screen?.animation_style ?? "laser_draw"
		let duration = remoteManager.config?.splash_screen?.duration_seconds ?? 3.2
		
		switch style {
		case "twin_slash":
			drawProgress = 1.0
			fillAlpha = 1.0
			leftSlide = CGSize(width: -120, height: 120)
			rightSlide = CGSize(width: 120, height: -120)
			withAnimation(.spring(response: 0.72, dampingFraction: 0.72)) {
				leftSlide = .zero
				rightSlide = .zero
				scaleValue = 1.0
				glowOpacity = 0.85
			}
		case "neon_pulse":
			drawProgress = 1.0
			fillAlpha = 1.0
			scaleValue = 1.0
			withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
				glowOpacity = 1.0
				scaleValue = 0.96
			}
		case "apple_minimal":
			drawProgress = 1.0
			scaleValue = 0.85
			withAnimation(.easeOut(duration: 1.0)) {
				fillAlpha = 1.0
				scaleValue = 1.0
				glowOpacity = 0.35
			}
		default:
			drawProgress = 0.0
			fillAlpha = 0.0
			withAnimation(.easeInOut(duration: 1.25)) {
				drawProgress = 1.0
				scaleValue = 1.0
			}
			withAnimation(.easeIn(duration: 0.5).delay(0.95)) {
				fillAlpha = 1.0
				glowOpacity = 0.6
			}
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
			didFinishMinimumAnimation = true
			checkIfReadyToDismiss()
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
			dismissSplash()
		}
	}
	
	private func checkIfReadyToDismiss() {
		guard didFinishMinimumAnimation else { return }
		if !cache.ipablackItems.isEmpty {
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
	
	// إعداد كاش صور ذكي يحمل أيقونات GitHub المستخرجة فوراً ولا يخزن أخطاء 404
	private func _createLowMemoryPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		DataLoader.sharedUrlCache.memoryCapacity = 0
		
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				config.requestCachePolicy = .useProtocolCachePolicy
				config.httpMaximumConnectionsPerHost = 4
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache")
			let imageCache = Nuke.ImageCache()
			dataCache?.sizeLimit = 300 * 1024 * 1024
			imageCache.costLimit = 32 * 1024 * 1024
			imageCache.countLimit = 120
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .storeAll
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
					if !urlStr.contains("/ipablack/") {
						context.delete(source)
					}
				}
			}
			UserDefaults.standard.set(true, forKey: purgedOnceKey)
			
			let coreRepos: [(name: String, id: String, url: String)] = [
				("IPA BLACK", "xsign.core.ipablack", "https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json")
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
				
				let p12URL = folderURL.appendingPathComponent("cert.p12")
				let provisionURL = folderURL.appendingPathComponent("cert.mobileprovision")
				let passwordURL = folderURL.appendingPathComponent("cert.txt")
				
				guard
					FileManager.default.fileExists(atPath: p12URL.path),
					FileManager.default.fileExists(atPath: provisionURL.path),
					FileManager.default.fileExists(atPath: passwordURL.path)
				else {
					Logger.misc.warning("Skipping \(certName): missing required files")
					continue
				}
				
				let password = try String(contentsOf: passwordURL, encoding: .utf8)
				
				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
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
