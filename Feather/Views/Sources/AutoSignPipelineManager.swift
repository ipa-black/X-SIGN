import Foundation
import SwiftUI
import CoreData
import AltSourceKit
import UIKit

@MainActor
final class AutoSignPipelineManager: ObservableObject {
    static let shared = AutoSignPipelineManager()
    enum Stage: Equatable { case downloading, signing, ready }

    @Published private(set) var activeStates: [String: Stage] = [:]
    @Published private(set) var readyToInstallApp: AnyApp?

    private var readyApps: [String: AnyApp] = [:]
    private var readyOrder: [String] = []
    private var pendingInstallations: [AnyApp] = []

    static func key(for app: ASRepository.App) -> String {
        [app.id ?? app.currentName, app.currentVersion ?? "", app.currentDownloadUrl?.absoluteString ?? ""]
            .joined(separator: "|")
    }

    func downloadAndAutoSign(app: ASRepository.App, sourceProvenance: SourceAppProvenance? = nil) {
        let key = Self.key(for: app)
        if let ready = readyApps[key] {
            if isUsable(ready) {
                offerInstallation(ready)
                return
            }
            readyApps[key] = nil
            readyOrder.removeAll { $0 == key }
            activeStates[key] = nil
        }
        guard activeStates[key] == nil, let url = app.currentDownloadUrl else { return }
        activeStates[key] = .downloading
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        DownloadManager.shared.startDownload(from: url, id: "AutoSign_\(UUID().uuidString)", sourceProvenance: sourceProvenance) { [weak self] result in
            Task { @MainActor in self?.importFinished(result, appKey: key) }
        }
    }

    private func importFinished(_ result: Result<String, Error>, appKey: String) {
        switch result {
        case .failure(let error):
            activeStates[appKey] = nil
            if (error as NSError).code != NSURLErrorCancelled { showError(error) }
        case .success(let uuid):
            let request = NSFetchRequest<Imported>(entityName: "Imported")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "uuid == %@", uuid)
            guard let app = try? Storage.shared.context.fetch(request).first else {
                activeStates[appKey] = nil
                return
            }
            guard let certificate = activeCertificate() else {
                activeStates[appKey] = nil
                UIAlertController.showAlertWithOk(
                    title: "تم التنزيل",
                    message: "التطبيق محفوظ في مكتبة التوقيع. أضف شهادة من الإعدادات لتوقيعه."
                )
                return
            }

            activeStates[appKey] = .signing
            FR.signPackageFileWithResult(
                app,
                using: OptionsManager.shared.options,
                icon: nil,
                certificate: certificate
            ) { [weak self] result in
                Task { @MainActor in self?.signingFinished(result, appKey: appKey) }
            }
        }
    }

    private func signingFinished(_ result: Result<String, Error>, appKey: String) {
        switch result {
        case .failure(let error):
            activeStates[appKey] = nil
            showError(error)
        case .success(let uuid):
            let request = NSFetchRequest<Signed>(entityName: "Signed")
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "uuid == %@", uuid)
            guard let app = try? Storage.shared.context.fetch(request).first else {
                activeStates[appKey] = nil
                return
            }
            let ready = AnyApp(base: app)
            readyApps[appKey] = ready
            readyOrder.removeAll { $0 == appKey }
            readyOrder.append(appKey)
            // Successful button state remains bounded even in long-running sessions.
            while readyOrder.count > 32 {
                let evicted = readyOrder.removeFirst()
                readyApps[evicted] = nil
                activeStates[evicted] = nil
            }
            activeStates[appKey] = .ready
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            offerInstallation(ready)
        }
    }

    private func isUsable(_ app: AnyApp) -> Bool {
        guard let object = app.base as? NSManagedObject,
              !object.isDeleted, object.managedObjectContext != nil,
              app.base.uuid != nil else { return false }
        return Storage.shared.getAppDirectory(for: app.base) != nil
    }

    private func offerInstallation(_ app: AnyApp) {
        guard isUsable(app), readyToInstallApp?.id != app.id,
              !pendingInstallations.contains(where: { $0.id == app.id }) else { return }
        if readyToInstallApp == nil { readyToInstallApp = app }
        else { pendingInstallations.append(app) }
    }

    func dismissInstallation(id: String) {
        if readyToInstallApp?.id == id { readyToInstallApp = nil }
        while readyToInstallApp == nil, !pendingInstallations.isEmpty {
            let next = pendingInstallations.removeFirst()
            if isUsable(next) { readyToInstallApp = next }
        }
    }

    private func activeCertificate() -> CertificatePair? {
        let request = NSFetchRequest<CertificatePair>(entityName: "CertificatePair")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)]
        guard let certificates = try? Storage.shared.context.fetch(request), !certificates.isEmpty else { return nil }
        let index = UserDefaults.standard.integer(forKey: "feather.selectedCert")
        return certificates.indices.contains(index) ? certificates[index] : certificates.first
    }

    private func showError(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        UIAlertController.showAlertWithOk(title: "تعذر تجهيز التطبيق", message: error.localizedDescription)
    }
}
