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
						withAnimation(.easeInOut(duration: 0.5)) {
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
				Task.detached(priority: .userInitiated) {
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

// MARK: - Exact Geometric Double-Slash Hollow "X" Shape
struct ExactGeometricXShape: Shape {
	func path(in rect: CGRect) -> Path {
		let w = rect.width
		let h = rect.height
		
		func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
			CGPoint(x: x * w, y: y * h)
		}
		
		var path = Path()
		
		// الشفرة اليسرى والعلوية
		path.move(to: pt(0.645, 0.040))
		path.addLine(to: pt(0.455, 0.355))
		path.addLine(to: pt(0.395, 0.235))
		path.addLine(to: pt(0.285, 0.235))
		path.addLine(to: pt(0.422, 0.482))
		path.addLine(to: pt(0.165, 0.945))
		path.addLine(to: pt(0.388, 0.482))
		path.addLine(to: pt(0.228, 0.195))
		path.addLine(to: pt(0.418, 0.195))
		path.addLine(to: pt(0.458, 0.282))
		path.closeSubpath()
		
		// الشفرة اليمنى والسفلية
		path.move(to: pt(0.765, 0.048))
		path.addLine(to: pt(0.578, 0.495))
		path.addLine(to: pt(0.715, 0.755))
		path.addLine(to: pt(0.525, 0.755))
		path.addLine(to: pt(0.482, 0.665))
		path.addLine(to: pt(0.315, 0.952))
		path.addLine(to: pt(0.485, 0.592))
		path.addLine(to: pt(0.548, 0.715))
		path.addLine(to: pt(0.655, 0.715))
		path.addLine(to: pt(0.538, 0.495))
		path.closeSubpath()
		
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
	
	@State private var strokeProgress: CGFloat = 0.0
	@State private var fillOpacity: Double = 0.0
	@State private var depthAngle: Double = 12.0
	@State private var scaleValue: CGFloat = 0.88
	@State private var glowIntensity: Double = 0.25
	@State private var didFinishMinimumAnimation = false
	@State private var didDismiss = false
	
	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()
			
			Circle()
				.fill(
					RadialGradient(
						colors: [
							Color.white.opacity(0.14 * glowIntensity),
							Color(red: 0.0, green: 0.36, blue: 0.73).opacity(0.22 * glowIntensity),
							.clear
						],
						center: .center,
						startRadius: 5,
						endRadius: 210
					)
				)
				.frame(width: 380, height: 380)
			
			ZStack {
				ExactGeometricXShape()
					.trim(from: 0, to: strokeProgress)
					.stroke(
						Color(red: 0.05, green: 0.25, blue: 0.55).opacity(0.65),
						style: StrokeStyle(lineWidth: 6, lineCap: .square, lineJoin: .miter)
					)
					.frame(width: 220, height: 220)
					.offset(x: 4, y: 6)
					.blur(radius: 3)
				
				ExactGeometricXShape()
					.fill(
						LinearGradient(
							colors: [
								Color.white,
								Color(white: 0.90),
								Color.white
							],
							startPoint: .topLeading,
							endPoint: .bottomTrailing
						)
					)
					.frame(width: 220, height: 220)
					.opacity(fillOpacity)
					.shadow(color: Color.white.opacity(0.55 * glowIntensity), radius: 16, x: 0, y: 0)
				
				ExactGeometricXShape()
					.trim(from: 0, to: strokeProgress)
					.stroke(
						LinearGradient(
							colors: [
								Color.white,
								Color(white: 0.92),
								Color.white
							],
							startPoint: .topTrailing,
							endPoint: .bottomLeading
						),
						style: StrokeStyle(lineWidth: 3.2, lineCap: .butt, lineJoin: .miter, miterLimit: 20)
					)
					.frame(width: 220, height: 220)
					.shadow(color: Color.white.opacity(0.75 * glowIntensity), radius: 10, x: 0, y: 0)
			}
			.rotation3DEffect(
				.degrees(depthAngle),
				axis: (x: 0.2, y: -0.3, z: 0.0),
				perspective: 0.4
			)
			.scaleEffect(scaleValue)
		}
		.task {
			await cache.ensureFetched(sources: _sources, viewModel: sourcesViewModel)
			checkIfReadyToDismiss()
		}
		.onChange(of: cache.allCombinedItems.count) { _ in
			checkIfReadyToDismiss()
		}
		.onAppear {
			startGeometricXAnimation()
		}
	}
	
	private func startGeometricXAnimation() {
		withAnimation(.easeInOut(duration: 2.1)) {
			strokeProgress = 1.0
			scaleValue = 1.0
			depthAngle = 0.0
		}
		withAnimation(.easeInOut(duration: 1.1).delay(1.25)) {
			fillOpacity = 1.0
			glowIntensity = 1.0
		}
		
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.65) {
			didFinishMinimumAnimation = true
			checkIfReadyToDismiss()
			
			withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
				glowIntensity = 0.45
				scaleValue = 0.97
			}
		}
		
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
				config.httpMaximumConnectionsPerHost = 8
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache")
			let imageCache = Nuke.ImageCache()
			dataCache?.sizeLimit = 350 * 1024 * 1024
			imageCache.costLimit = 45 * 1024 * 1024
			imageCache.countLimit = 120
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
			
			let purgedOnceKey = "xsign.didPurgeLegacyDefaultRepos_v4"
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
