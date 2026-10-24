//
//  IPAHandler.swift
//  Feather
//
//  Created by samara on 11.04.2025.
//

import Foundation
import Zip
import SwiftUI

final class AppFileHandler: NSObject, @unchecked Sendable {
	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
    var importedUUID: String { _uuid }
	private let _uniqueWorkDir: URL
	var uniqueWorkDirPayload: URL?

	private var _ipa: URL
	private let _install: Bool
	private let _download: Download?
	private let _sourceProvenance: SourceAppProvenance?
	
	init(
		file ipa: URL,
		install: Bool = false,
		download: Download? = nil,
		sourceProvenance: SourceAppProvenance? = nil
	) {
		self._ipa = ipa
		self._install = install
		self._download = download
		self._sourceProvenance = sourceProvenance ?? download?.sourceProvenance
		self._uniqueWorkDir = _fileManager.temporaryDirectory
			.appendingPathComponent("FeatherImport_\(_uuid)", isDirectory: true)
		
		super.init()
	}
	
	func copy() async throws {
		try _fileManager.createDirectoryIfNeeded(at: _uniqueWorkDir)
		
		let destinationURL = _uniqueWorkDir.appendingPathComponent(_ipa.lastPathComponent)

		try _fileManager.removeFileIfNeeded(at: destinationURL)
		
		if _download != nil && _ipa.pathComponents.contains("XSignDownloads") {
            try _fileManager.moveItem(at: _ipa, to: destinationURL)
        } else {
            try _fileManager.copyItem(at: _ipa, to: destinationURL)
        }
		_ipa = destinationURL
	}
	
	func extract() async throws {
		if _ipa.pathExtension == "ipa" {
			Zip.addCustomFileExtension("ipa")
		}
		if _ipa.pathExtension == "tipa" {
			Zip.addCustomFileExtension("tipa")
		}
		
		let download = self._download
        var lastProgressEmission: TimeInterval = 0
		
		try await withCheckedThrowingContinuation { continuation in
			DispatchQueue.global(qos: .utility).async {
				do {
					try Zip.unzipFile(
						self._ipa,
						destination: self._uniqueWorkDir,
						overwrite: true,
						password: nil,
						progress: { progress in
                            let now = ProcessInfo.processInfo.systemUptime
                            guard progress >= 1 || now - lastProgressEmission >= 0.1 else { return }
                            lastProgressEmission = now
							if let download = download {
								DispatchQueue.main.async {
									download.unpackageProgress = progress
									
									#if !targetEnvironment(macCatalyst)
									if #available(iOS 26.0, *) {
										BackgroundTaskManager.shared.updateProgress(for: download.id, progress: download.overallProgress)
									}
									#endif
								}
							}
						}
					)
					
					self.uniqueWorkDirPayload = self._uniqueWorkDir.appendingPathComponent("Payload")
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}
	
	func move() async throws {
		guard let payloadURL = uniqueWorkDirPayload else {
			throw ImportedFileHandlerError.payloadNotFound
		}
		
		let destinationURL = try await _directory()
		
		guard _fileManager.fileExists(atPath: payloadURL.path) else {
			throw ImportedFileHandlerError.payloadNotFound
		}
		
		try _fileManager.moveItem(at: payloadURL, to: destinationURL)
		
		try? _fileManager.removeItem(at: _uniqueWorkDir)
	}
	
    func addToDatabase() async throws {
        let directory = try await _directory()
        guard let appURL = _fileManager.getPath(in: directory, for: "app") else {
            throw ImportedFileHandlerError.payloadNotFound
        }
        let bundle = Bundle(url: appURL)
        let name = bundle?.name
        let identifier = bundle?.bundleIdentifier
        let version = bundle?.version
        let icon = bundle?.iconFileName
        try await MainActor.run {
            var insertionError: Error?
            Storage.shared.addImported(
                uuid: _uuid,
                source: _sourceProvenance?.sourceRepositoryURL,
                appName: name,
                appIdentifier: identifier,
                appVersion: version,
                appIcon: icon
            ) { insertionError = $0 }
            if let insertionError { throw insertionError }
            if let provenance = _sourceProvenance {
                Storage.shared.addSourceMetadata(for: _uuid, kind: .imported, provenance: provenance)
            }
            if Storage.shared.context.hasChanges { try Storage.shared.context.save() }
        }
    }

	private func _directory() async throws -> URL {
		// Documents/Feather/Unsigned/\(UUID)
		_fileManager.unsigned(_uuid)
	}
	
	func clean() async throws {
		try _fileManager.removeFileIfNeeded(at: _uniqueWorkDir)
	}
}

private enum ImportedFileHandlerError: Error {
	case payloadNotFound
}
