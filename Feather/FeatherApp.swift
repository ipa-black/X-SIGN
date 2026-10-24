//
//  FeatherApp.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Nuke
import IDeviceSwift
import OSLog

@main
struct FeatherApp: App {
	@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
	
	let heartbeat = HeartbeatManager.shared
	
	@StateObject var downloadManager = DownloadManager.shared
	let storage = Storage.shared
	
	@State private var _showSplash = true
	
	var body: some Scene {
		WindowGroup {
			ZStack {
				VStack {
					DownloadHeaderView(downloadManager: downloadManager)
						.transition(.move(edge: .top).combined(with: .opacity))
					VariedTabbarView()
						.environment(\.managedObjectContext, storage.context)
						.onOpenURL(perform: _handleURL)
						.transition(.move(edge: .top).combined(with: .opacity))
				}
				.animation(.smooth, value: downloadManager.manualDownloads.description)
				
				if _showSplash {
					XSignLaunchSplashView {
						withAnimation(.easeInOut(duration: 0.55)) {
							_showSplash = false
						}
					}
					.transition(.opacity)
					.zIndex(999)
				}
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
				if let style = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "Feather.userInterfaceStyle")) {
					UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
				}
				
				UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#848ef9"))
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

// MARK: - Animated Slow-Drawing "X" Splash Screen
struct XLetterShape: Shape {
	func path(in rect: CGRect) -> Path {
		var path = Path()
		let inset: CGFloat = rect.width * 0.14
		// الضلع الأول من اليسار العلوي إلى اليمين السفلي
		path.move(to: CGPoint(x: inset, y: inset))
		path.addLine(to: CGPoint(x: rect.width - inset, y: rect.height - inset))
		// الضلع الثاني من اليمين العلوي إلى اليسار السفلي
		path.move(to: CGPoint(x: rect.width - inset, y: inset))
		path.addLine(to: CGPoint(x: inset, y: rect.height - inset))
		return path
	}
}

struct XSignLaunchSplashView: View {
	var onFinished: () -> Void
	
	@State private var drawProgress: CGFloat = 0.0
	@State private var glowOpacity: Double = 0.0
	@State private var subtitleOpacity: Double = 0.0
	@State private var scaleEffectValue: CGFloat = 0.92
	
	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()
			
			// إضاءة خلفية ناعمة خلف حرف X
			Circle()
				.fill(
					RadialGradient(
						colors: [Color.blue.opacity(0.28), Color.indigo.opacity(0.10), .clear],
						center: .center,
						startRadius: 10,
						endRadius: 180
					)
				)
				.frame(width: 340, height: 340)
				.opacity(glowOpacity)
			
			VStack(spacing: 28) {
				ZStack {
					// مسار خلفي خافت لحرف X
					XLetterShape()
						.stroke(
							Color.white.opacity(0.08),
							style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
						)
						.frame(width: 130, height: 130)
					
					// رسم حرف X تدريجياً ببطء وأناقة
					XLetterShape()
						.trim(from: 0.0, to: drawProgress)
						.stroke(
							LinearGradient(
								colors: [
									Color.white,
									Color(red: 0.35, green: 0.68, blue: 1.0),
									Color(red: 0.20, green: 0.45, blue: 0.98)
								],
								startPoint: .topLeading,
								endPoint: .bottomTrailing
							),
							style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
						)
						.frame(width: 130, height: 130)
						.shadow(color: Color.blue.opacity(0.65), radius: 16, x: 0, y: 0)
				}
				.scaleEffect(scaleEffectValue)
				
				VStack(spacing: 8) {
					Text("X-SIGN")
						.font(.system(size: 22, weight: .heavy, design: .rounded))
						.tracking(4)
						.foregroundStyle(.white)
					
					Text("جاري تجهيز المتجر والتطبيقات...")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
				}
				.opacity(subtitleOpacity)
			}
		}
		.onAppear {
			// رسم بطيء وسلس لحرف X يستغرق 2.3 ثانية حتى تتحمل التطبيقات في الخلفية
			withAnimation(.easeInOut(duration: 2.3)) {
				drawProgress = 1.0
				scaleEffectValue = 1.0
			}
			withAnimation(.easeIn(duration: 1.2).delay(0.3)) {
				glowOpacity = 1.0
				subtitleOpacity = 1.0
			}
			DispatchQueue.main.asyncAfter(deadline: .now() + 2.85) {
				onFinished()
			}
		}
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
