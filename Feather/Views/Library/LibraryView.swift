//
//  ContentView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - Minimalist Signing View with 1-Click Instant Sign
struct LibraryView: View {
	@StateObject var downloadManager = DownloadManager.shared
	@StateObject var sourcesViewModel = SourcesViewModel.shared
	
	@State private var _selectedInfoAppPresenting: AnyApp?
	@State private var _selectedSigningAppPresenting: AnyApp?
	@State private var _selectedInstallAppPresenting: AnyApp?
	@State private var _isImportingPresenting = false
	@State private var _isDownloadingPresenting = false
	@State private var _isSettingsPresenting = false
	@State private var _alertDownloadString: String = ""
	
	@State private var _signingInProgressUUIDs: Set<String> = []
	@State private var _oneClickStatusMessage: String? = nil
	
	@State private var _selectedAppUUIDs: Set<String> = []
	@State private var _editMode: EditMode = .inactive
	
	@State private var _searchText = ""
	@State private var _selectedScope: Scope = .all
	
	@Namespace private var _namespace
	
	private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		let query = AppStoreBilingualEngine.normalize(_searchText)
		guard !query.isEmpty else { return Array(apps) }
		
		return apps.filter { item in
			let name = (item.value(forKey: "name") as? String) ?? ""
			let identifier = (item.value(forKey: "identifier") as? String) ?? ""
			let combined = AppStoreBilingualEngine.normalize("\(name) \(identifier)")
			
			if combined.contains(query) { return true }
			
			for group in AppStoreBilingualEngine.synonymGroups {
				let normalizedGroup = group.map { AppStoreBilingualEngine.normalize($0) }
				if normalizedGroup.contains(where: { combined.contains($0) }) &&
				   normalizedGroup.contains(where: { $0.contains(query) || query.contains($0) }) {
					return true
				}
			}
			return false
		}
	}
	
	private var _filteredSignedApps: [Signed] {
		filteredAndSortedApps(from: _signedApps)
	}
	
	private var _filteredImportedApps: [Imported] {
		filteredAndSortedApps(from: _importedApps)
	}
	
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)]
	) private var _signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)]
	) private var _importedApps: FetchedResults<Imported>
	
	@FetchRequest(
		entity: CertificatePair.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
	) private var _certificates: FetchedResults<CertificatePair>
	
	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)]
	) private var _sources: FetchedResults<AltSource>
	
	var body: some View {
		NBNavigationView("التوقيع") {
			NBListAdaptable {
				Section {
					Picker("العرض", selection: $_selectedScope) {
						ForEach(Scope.allCases, id: \.displayName) { scope in
							Text(scope.displayName).tag(scope)
						}
					}
					.pickerStyle(.segmented)
					.listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
					.listRowBackground(Color.clear)
				}
				
				if let status = _oneClickStatusMessage {
					Section {
						HStack(spacing: 10) {
							ProgressView()
								.tint(.blue)
							Text(status)
								.font(.subheadline.weight(.semibold))
								.foregroundStyle(.white)
							Spacer()
						}
						.padding(.vertical, 4)
					}
				}
				
				if !_filteredImportedApps.isEmpty && (_selectedScope == .all || _selectedScope == .imported) {
					NBSection("جاهزة للتوقيع الفوري", secondary: _filteredImportedApps.count.description) {
						ForEach(_filteredImportedApps, id: \.uuid) { app in
							VStack(spacing: 8) {
								LibraryCellView(
									app: app,
									selectedInfoAppPresenting: $_selectedInfoAppPresenting,
									selectedSigningAppPresenting: $_selectedSigningAppPresenting,
									selectedInstallAppPresenting: $_selectedInstallAppPresenting,
									selectedAppUUIDs: $_selectedAppUUIDs
								)
								.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
								
								HStack(spacing: 10) {
									Button {
										_oneClickSign(app: app)
									} label: {
										HStack(spacing: 6) {
											if _signingInProgressUUIDs.contains(app.uuid ?? "") {
												ProgressView()
													.tint(.white)
													.scaleEffect(0.8)
												Text("جاري التوقيع...")
													.font(.footnote.weight(.bold))
											} else {
												Image(systemName: "bolt.fill")
													.font(.footnote.weight(.bold))
												Text("توقيع وتثبيت بضغطة واحدة")
													.font(.footnote.weight(.bold))
											}
										}
										.foregroundStyle(.white)
										.frame(maxWidth: .infinity)
										.padding(.vertical, 8)
										.background(
											Capsule(style: .continuous)
												.fill(
													LinearGradient(
														colors: [Color.blue, Color.indigo],
														startPoint: .leading,
														endPoint: .trailing
													)
												)
										)
									}
									.buttonStyle(.plain)
									.disabled(_signingInProgressUUIDs.contains(app.uuid ?? ""))
									
									Button {
										_selectedSigningAppPresenting = AnyApp(base: app)
									} label: {
										Image(systemName: "slider.horizontal.3")
											.font(.footnote.weight(.bold))
											.foregroundStyle(.secondary)
											.frame(width: 36, height: 32)
											.background(Color(white: 0.16), in: Capsule())
									}
									.buttonStyle(.plain)
								}
							}
							.padding(.vertical, 2)
						}
					}
				}
				
				if !_filteredSignedApps.isEmpty && (_selectedScope == .all || _selectedScope == .signed) {
					NBSection("الموقعة والجاهزة للتثبيت", secondary: _filteredSignedApps.count.description) {
						ForEach(_filteredSignedApps, id: \.uuid) { app in
							LibraryCellView(
								app: app,
								selectedInfoAppPresenting: $_selectedInfoAppPresenting,
								selectedSigningAppPresenting: $_selectedSigningAppPresenting,
								selectedInstallAppPresenting: $_selectedInstallAppPresenting,
								selectedAppUUIDs: $_selectedAppUUIDs
							)
							.compatMatchedTransitionSource(id: app.uuid ?? "", ns: _namespace)
						}
					}
				}
			}
			.searchable(text: $_searchText, placement: .platform(), prompt: "بحث في التوقيع (عربي / إنجليزي)...")
			.scrollDismissesKeyboard(.interactively)
			.overlay {
				if _filteredSignedApps.isEmpty && _filteredImportedApps.isEmpty {
					if #available(iOS 17, *) {
						ContentUnavailableView {
							Label("لا توجد تطبيقات", systemImage: "checkmark.seal")
						} description: {
							Text("اضغط على + لاستيراد ملف IPA وتوقيعه بضغطة واحدة.")
						} actions: {
							Button("استيراد ملف IPA") {
								_isImportingPresenting = true
							}
							.buttonStyle(.borderedProminent)
							.clipShape(Capsule())
						}
					}
				}
			}
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					EditButton()
				}
				
				ToolbarItemGroup(placement: .topBarTrailing) {
					if _editMode.isEditing {
						Button(role: .destructive) {
							_bulkDeleteSelectedApps()
						} label: {
							Image(systemName: "trash")
						}
						.disabled(_selectedAppUUIDs.isEmpty)
					} else {
						Menu {
							Button("استيراد من الملفات", systemImage: "folder") {
								_isImportingPresenting = true
							}
							Button("استيراد من رابط", systemImage: "link") {
								_isDownloadingPresenting = true
							}
						} label: {
							Image(systemName: "plus.circle.fill")
								.font(.system(size: 20))
						}
						
						AppStoreAccountAppIconButton {
							_isSettingsPresenting = true
						}
					}
				}
			}
			.environment(\.editMode, $_editMode)
			.sheet(item: $_selectedInfoAppPresenting) { app in
				LibraryInfoView(app: app.base)
			}
			.sheet(item: $_selectedInstallAppPresenting) { app in
				InstallPreviewView(app: app.base, isSharing: app.archive)
					.presentationDetents([.height(200)])
					.presentationDragIndicator(.visible)
			}
			.fullScreenCover(item: $_selectedSigningAppPresenting) { app in
				SigningView(app: app.base)
					.compatNavigationTransition(id: app.base.uuid ?? "", ns: _namespace)
			}
			.sheet(isPresented: $_isImportingPresenting) {
				FileImporterRepresentableView(
					allowedContentTypes: [.ipa, .tipa],
					allowsMultipleSelection: true,
					onDocumentsPicked: { urls in
						guard !urls.isEmpty else { return }
						for url in urls {
							let id = "FeatherManualDownload_\(UUID().uuidString)"
							let dl = downloadManager.startArchive(from: url, id: id)
							try? downloadManager.handlePachageFile(url: url, dl: dl)
						}
					}
				)
				.ignoresSafeArea()
			}
			.sheet(isPresented: $_isSettingsPresenting) {
				AppStore2026SettingsPopup(sources: _sources, viewModel: sourcesViewModel)
			}
			.alert("استيراد من رابط مباشر", isPresented: $_isDownloadingPresenting) {
				TextField("https://example.com/app.ipa", text: $_alertDownloadString)
					.textInputAutocapitalization(.never)
				Button("إلغاء", role: .cancel) {
					_alertDownloadString = ""
				}
				Button("استيراد") {
					if let url = URL(string: _alertDownloadString) {
						_ = downloadManager.startDownload(from: url, id: "FeatherManualDownload_\(UUID().uuidString)")
					}
				}
			}
			.onReceive(NotificationCenter.default.publisher(for: Notification.Name("Feather.installApp"))) { _ in
				if let latest = _signedApps.first {
					_selectedInstallAppPresenting = AnyApp(base: latest)
				}
			}
			.onChange(of: _editMode) { mode in
				if mode == .inactive {
					_selectedAppUUIDs.removeAll()
				}
			}
		}
		.environment(\.layoutDirection, .rightToLeft)
		.preferredColorScheme(.dark)
	}
	
	private func _oneClickSign(app: AppInfoPresentable) {
		let selectedCertIndex = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		let activeCert: CertificatePair? = {
			if _certificates.indices.contains(selectedCertIndex) {
				return _certificates[selectedCertIndex]
			}
			return _certificates.first
		}()
		
		guard let cert = activeCert else {
			UIAlertController.showAlertWithOk(
				title: "لا توجد شهادة",
				message: "يرجى إضافة شهادة توقيع أولاً من قائمة الإعدادات في الأعلى."
			)
			return
		}
		
		let uuid = app.uuid ?? ""
		UIImpactFeedbackGenerator(style: .medium).impactOccurred()
		_signingInProgressUUIDs.insert(uuid)
		_oneClickStatusMessage = "جاري توقيع \(app.name ?? "التطبيق")..."
		
		let options = OptionsManager.shared.options
		
		FR.signPackageFile(
			app,
			using: options,
			icon: nil,
			certificate: cert
		) { error in
			DispatchQueue.main.async {
				_signingInProgressUUIDs.remove(uuid)
				_oneClickStatusMessage = nil
				
				if let error {
					UINotificationFeedbackGenerator().notificationOccurred(.error)
					UIAlertController.showAlertWithOk(
						title: "فشل التوقيع",
						message: error.localizedDescription
					)
				} else {
					UINotificationFeedbackGenerator().notificationOccurred(.success)
					if let newlySigned = _signedApps.first {
						_selectedInstallAppPresenting = AnyApp(base: newlySigned)
					}
				}
			}
		}
	}
	
	private func _bulkDeleteSelectedApps() {
		var allApps: [AppInfoPresentable] = []
		if _selectedScope == .all || _selectedScope == .signed {
			allApps.append(contentsOf: _filteredSignedApps)
		}
		if _selectedScope == .all || _selectedScope == .imported {
			allApps.append(contentsOf: _filteredImportedApps)
		}
		for app in allApps where _selectedAppUUIDs.contains(app.uuid ?? "") {
			Storage.shared.deleteApp(for: app)
		}
		_selectedAppUUIDs.removeAll()
	}
	
	enum Scope: CaseIterable {
		case all
		case imported
		case signed
		
		var displayName: String {
			switch self {
			case .all:      return "الكل"
			case .imported: return "جاهزة للتوقيع"
			case .signed:   return "الموقعة"
			}
		}
	}
}
