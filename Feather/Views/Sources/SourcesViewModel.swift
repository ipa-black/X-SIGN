//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

// MARK: - Class
@MainActor
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()
	
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	
	var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]
	
    private nonisolated static let repositorySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpMaximumConnectionsPerHost = 1
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config)
    }()

    func fetchSources<S: Collection>(_ sources: S, refresh: Bool = false, batchSize _: Int = 1) async where S.Element == AltSource {
        guard isFinished else { return }
        if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }
        isFinished = false
        defer { isFinished = true }
        let requestedSources = Set(sources)
        self.sources = self.sources.filter { requestedSources.contains($0.key) }
        for source in Array(sources) {
            if Task.isCancelled { break }
            guard let url = source.sourceURL else { continue }
            let repo = await Task.detached(priority: .utility) { () -> ASRepository? in
                do {
                    let (data, response) = try await Self.repositorySession.data(from: url)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
                    return try JSONDecoder().decode(ASRepository.self, from: data)
                } catch { return nil }
            }.value
            if Task.isCancelled { break }
            if let repo { self.sources[source] = repo }
        }
    }
}
