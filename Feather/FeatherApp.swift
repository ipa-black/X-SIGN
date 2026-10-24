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

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	let heartbeat = HeartbeatManager.shared
	
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject private var storeCache = AppStoreCacheManager.shared
	@StateObject private var sourcesViewModel = SourcesViewModel.shared
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
					XSignExactLaunchSplashView(
						cache: storeCache,
						sourcesViewModel: sourcesViewModel
					) {
						withAnimation(.easeInOut(duration: 0.45)) {
							_showSplash = false
						}
					}
					.transition(.opacity)
					.zIndex(999)
				}
			}
			.preferredColorScheme(.dark)
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

// MARK: - Exact Authentic X-Sign Logo Vector Shape (100% Identical to User Image)
struct ExactXSignOutlineLogoShape: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height
		
		func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: x * w, y: y * h)
		}
		
		var path = Path()
		
		// 1. الشفرة القطرية الرئيسية الأولى (من أقصى أعلى اليمين الحاد إلى أقصى أسفل اليسار المستدق الحاد)
		path.move(to: p(0.638, 0.062))
		path.addLine(to: p(0.485, 0.282))
		path.addLine(to: p(0.395, 0.198))
		path.addLine(to: p(0.315, 0.198))
		path.addLine(to: p(0.435, 0.448))
		path.addLine(to: p(0.258, 0.692))
		path.addLine(to: p(0.535, 0.692))
		path.addLine(to: p(0.675, 0.575))
		path.addLine(to: p(0.515, 0.448))
		path.addLine(to: p(0.638, 0.062))
		path.closeSubpath()
		
		// 2. الشفرة المتوازية السفلية الحادة الحارقة (تخرج كشفرة سيف مستدقة كما في صورتك)
		path.move(to: p(0.742, 0.065))
		path.addLine(to: p(0.565, 0.485))
		path.addLine(to: p(0.365, 0.692))
		path.addLine(to: p(0.485, 0.575))
		path.addLine(to: p(0.742, 0.065))
		path.closeSubpath()
		
		// 3. الذراع الموازي الممتد بحدة نحو أسفل اليسار
		path.move(to: p(0.258, 0.692))
		path.addLine(to: p(0.365, 0.935))
		path.addLine(to: p(0.445, 0.745))
		path.addLine(to: p(0.258, 0.692))
		path.closeSubpath()
		
		return path
	}
}

// رسم شعار X الهندسي الأصلي المفرّغ المحاط بالأبيض الناصع
struct ExactXSignRenderView: View {
	let progress: CGFloat
	let glow: Double
	
	var body: some View {
		ZStack {
			// الظل العميق الأزرق المحيطي 3D
			ExactXSignOutlineLogoShape()
				.trim(from: 0, to: progress)
				.stroke(
					Color(red: 0.0, green: 0.36, blue: 0.73).opacity(0.85),
					style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)
				)
				.frame(width: 210, height: 210)
				.offset(x: 4, y: 7)
				.blur(radius: 6)
			
			// المسار الخارجي الأبيض الصافي الحاد
			ExactXSignOutlineLogoShape()
				.trim(from: 0, to: progress)
				.stroke(
					Color.white,
					style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .miter, miterLimit: 16)
				)
				.frame(width: 210, height: 210)
				.shadow(color: Color.white.opacity(0.85 * glow), radius: 14, x: 0, y: 0)
			
			// اللمسة الداخلية الفاخرة للون الكحلي المحيطي مثل صورة الأيقونة
			ExactXSignOutlineLogoShape()
				.fill(
					LinearGradient(
						colors: [
							Color(red: 0.00, green: 0.28, blue: 0.60),
							Color(red: 0.01, green: 0.18, blue: 0.42)
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					)
				)
				.frame(width: 210, height: 210)
				.opacity(min(1.0, Double(progress) * 1.2))
		}
	}
}

struct XSignExactLaunchSplashView: View {
	@ObservedObject var cache: AppStoreCacheManager
	@ObservedObject var sourcesViewModel: SourcesViewModel
	var onFinished: () -> Void
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	@State private var drawProgress: CGFloat = 0.0
	@State private var glowOpacity: Double = 0.2
	@State private var scaleValue: CGFloat = 0.86
	@State private var depthAngle: Double = 14.0
	@State private var didFinishMinimumAnimation = false
	@State private var didDismiss = false
	
	var body: some View {
		ZStack {
			// الخلفية البحرية الكحلية الداكنة المستوحاة من صورتك
			LinearGradient(
				colors: [
					Color(red: 0.00, green: 0.15, blue: 0.38),
					Color.black
				],
				startPoint: .top,
				endPoint: .bottom
			)
			.ignoresSafeArea()
			
			// هالة زرقاء متوهجة ناعمة
			Circle()
				.fill(
					RadialGradient(
						colors: [
							Color.white.opacity(0.18 * glowOpacity),
							Color(red: 0.0, green: 0.42, blue: 0.88).opacity(0.25 * glowOpacity),
							.clear
						],
						center: .center,
						startRadius: 10,
						endRadius: 230
					)
				)
				.frame(width: 400, height: 400)
			
			ExactXSignRenderView(progress: drawProgress, glow: glowOpacity)
				.rotation3DEffect(
					.degrees(depthAngle),
					axis: (x: 0.2, y: -0.25, z: 0.0),
					perspective: 0.4
				)
				.scaleEffect(scaleValue)
		}
		.task {
			// تسريع تحميل وقراءة السورسات بأقصى أولوية معالجة في الخلفية
			await cache.ensureFetched(sources: _sources, viewModel: sourcesViewModel)
			checkIfReadyToDismiss()
		}
		.onChange(of: cache.allCombinedItems.count) { _ in
			checkIfReadyToDismiss()
		}
		.onAppear {
			startDrawing()
		}
	}
	
	private func startDrawing() {
		withAnimation(.easeInOut(duration: 1.85)) {
			drawProgress = 1.0
			scaleValue = 1.0
			depthAngle = 0.0
			glowOpacity = 1.0
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
			didFinishMinimumAnimation = true
			checkIfReadyToDismiss()
			
			withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
				glowOpacity = 0.55
				scaleValue = 0.98
			}
		}
		
		// حد أمان 4 ثوانٍ
		DispatchQueue.main.asyncAfter(deadline: .now() + 4.2) {
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
