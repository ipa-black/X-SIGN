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
					XSignLaunchSplashView(
						cache: storeCache,
						sourcesViewModel: sourcesViewModel
					) {
						withAnimation(.easeInOut(duration: 0.55)) {
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
				if FileManager.default.isFileFromFileProvider(at: url) {
					guard url.startAccessingSecurityScopedResource() else { return }
					FR.handlePackageFile(url) { _ in }
				} else {
					FR.handlePackageFile(url) { _ in }
				}
				
				return
			}
		}
	}
}

// MARK: - Pure 3D White "X" Splash Screen (Stays Until Apps Are Loaded)
struct X3DRibbonShape: Shape {
	let firstStroke: Bool
	
	func path(in rect: CGRect) -> Path {
		var path = Path()
		let inset: CGFloat = rect.width * 0.14
		if firstStroke {
			path.move(to: CGPoint(x: inset, y: inset))
			path.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset))
		} else {
			path.move(to: CGPoint(x: rect.width - inset, y: inset))
			path.addLine(to: CGPoint(x: inset, y: rect.height - inset))
		}
		return path
	}
}

struct XSignLaunchSplashView: View {
	@ObservedObject var cache: AppStoreCacheManager
	@ObservedObject var sourcesViewModel: SourcesViewModel
	var onFinished: () -> Void
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	@State private var strokeOneProgress: CGFloat = 0.0
	@State private var strokeTwoProgress: CGFloat = 0.0
	@State private var depthTilt: Double = 14.0
	@State private var scaleValue: CGFloat = 0.86
	@State private var glowIntensity: Double = 0.2
	@State private var didFinishMinimumAnimation = false
	@State private var didDismiss = false
	
	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()
			
			// هالة محيطية ناعمة جداً خلف المجسم ثلاثي الأبعاد
			Circle()
				.fill(
					RadialGradient(
						colors: [
							Color.white.opacity(0.14 * glowIntensity),
							Color(red: 0.0, green: 0.36, blue: 0.73).opacity(0.18 * glowIntensity),
							.clear
						],
						center: .center,
						startRadius: 4,
						endRadius: 200
					)
				)
				.frame(width: 360, height: 360)
			
			ZStack {
				// 1. طبقة العمق الخلفي 3D Extrusion
				ZStack {
					X3DRibbonShape(firstStroke: true)
						.trim(from: 0, to: strokeOneProgress)
						.stroke(
							Color(white: 0.22),
							style: StrokeStyle(lineWidth: 24, lineCap: .round)
						)
					X3DRibbonShape(firstStroke: false)
						.trim(from: 0, to: strokeTwoProgress)
						.stroke(
							Color(white: 0.22),
							style: StrokeStyle(lineWidth: 24, lineCap: .round)
						)
				}
				.frame(width: 148, height: 148)
				.offset(x: 5, y: 7)
				.blur(radius: 3)
				
				// 2. الضلع الأول من حرف X بتدرج ثلاثي الأبعاد أبيض ناصع
				X3DRibbonShape(firstStroke: true)
					.trim(from: 0, to: strokeOneProgress)
					.stroke(
						LinearGradient(
							colors: [
								Color.white,
								Color(white: 0.88),
								Color.white
							],
							startPoint: .topLeading,
							endPoint: .bottomTrailing
						),
						style: StrokeStyle(lineWidth: 20, lineCap: .round)
					)
					.frame(width: 148, height: 148)
					.shadow(color: .black.opacity(0.65), radius: 8, x: 3, y: 5)
				
				// 3. الضلع الثاني المتقاطع فوقه بلمعة 3D وظل واقعي عند نقطة التقاطع
				X3DRibbonShape(firstStroke: false)
					.trim(from: 0, to: strokeTwoProgress)
					.stroke(
						LinearGradient(
							colors: [
								Color.white,
								Color(white: 0.94),
								Color(white: 0.82),
								Color.white
							],
							startPoint: .topTrailing,
							endPoint: .bottomLeading
						),
						style: StrokeStyle(lineWidth: 20, lineCap: .round)
					)
					.frame(width: 148, height: 148)
					.shadow(color: .black.opacity(0.75), radius: 10, x: -2, y: 4)
					.shadow(color: .white.opacity(0.55 * glowIntensity), radius: 16, x: 0, y: 0)
			}
			.rotation3DEffect(
				.degrees(depthTilt),
				axis: (x: 0.25, y: -0.35, z: 0.0),
				perspective: 0.45
			)
			.scaleEffect(scaleValue)
		}
		.task {
			// بدء تحميل السورسات والتطبيقات فوراً أثناء رسم حرف X
			await cache.ensureFetched(sources: _sources, viewModel: sourcesViewModel)
			checkIfReadyToDismiss()
		}
		.onChange(of: cache.allCombinedItems.count) { _ in
			checkIfReadyToDismiss()
		}
		.onAppear {
			startSlow3DDrawing()
		}
	}
	
	private func startSlow3DDrawing() {
		// رسم الضلع الأول ببطء
		withAnimation(.easeInOut(duration: 1.35)) {
			strokeOneProgress = 1.0
			scaleValue = 0.95
		}
		// رسم الضلع الثاني فوقه ببطء مع اعتدال زاوية الـ 3D
		withAnimation(.easeInOut(duration: 1.45).delay(1.15)) {
			strokeTwoProgress = 1.0
			depthTilt = 0.0
			scaleValue = 1.0
			glowIntensity = 1.0
		}
		
		// نبض 3D هادئ في حال استغرق الإنترنت ثواني إضافية لتحميل التطبيقات
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
			didFinishMinimumAnimation = true
			checkIfReadyToDismiss()
			
			withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
				glowIntensity = 0.45
				scaleValue = 0.97
			}
		}
		
		// حد أقصى للأمان (6.5 ثانية) حتى يفتح التطبيق لو كان الجهاز بدون إنترنت
		DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
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
		_createPipeline()
		_createDocumentsDirectories()
		ResetView.clearWorkCache()
		_addDefaultCertificates()
		_configureProtectedCoreSources()
		return true
	}
	
	private func _createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache")
			let imageCache = Nuke.ImageCache()
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .automatic
			$0.isStoringPreviewsInMemoryCache = false
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
			
			let purgedOnceKey = "xsign.didPurgeLegacyDefaultRepos_v3"
			if !UserDefaults.standard.bool(forKey: purgedOnceKey) {
				for source in existingSources {
					let urlStr = source.sourceURL?.absoluteString.lowercased() ?? ""
					if !urlStr.contains("apptesters") && !urlStr.contains("ipablack") {
						context.delete(source)
					}
				}
				UserDefaults.standard.set(true, forKey: purgedOnceKey)
			}
			
			let coreRepos: [(name: String, id: String, url: String)] = [
				("IPA BLACK", "xsign.core.ipablack", "https://raw.githubusercontent.com/ipa-black/IPABLACK/refs/heads/main/repo.json"),
				("AppTesters", "xsign.core.apptesters", "https://repository.apptesters.org/")
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
