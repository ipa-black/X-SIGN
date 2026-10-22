//
//  ContentView.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import CoreData
import NimbleViews

// MARK: - Minimalist Signing View with Top App Icon Settings Button
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
	
	@State private var _selectedAppUUIDs: Set<String> = []
	@State private var _editMode: EditMode = .inactive
	
	@State private var _searchText = ""
	@State private var _selectedScope: Scope = .all
	
	@Namespace private var _namespace
	
	private func filteredAndSortedApps<T>(from apps: FetchedResults<T>) -> [T] where T: NSManagedObject {
		apps.filter {
			_searchText.isEmpty ||
				(($0.value(forKey: "name") as? String)?.localizedCaseInsensitiveContains(_searchText) ?? false)
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
				
				if !_filteredImportedApps.isEmpty && (_selectedScope == .all || _selectedScope == .imported) {
					NBSection("جاهزة للتوقيع", secondary: _filteredImportedApps.count.description) {
						ForEach(_filteredImportedApps, id: \.uuid) { app in
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
				
				if !_filteredSignedApps.isEmpty && (_selectedScope == .all || _selectedScope == .signed) {
					NBSection("الموقعة", secondary: _filteredSignedApps.count.description) {
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
			.searchable(text: $_searchText, placement: .platform(), prompt: "بحث في التوقيع...")
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
