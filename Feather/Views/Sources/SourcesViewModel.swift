import Foundation
import CoreData
import AltSourceKit
import SwiftUI

@MainActor
final class SourcesViewModel: ObservableObject {
    static let shared = SourcesViewModel()
    typealias RepositoryDataHandler = Result<ASRepository, Error>

    @Published private(set) var isFinished = true
    @Published var sources: [AltSource: ASRepository] = [:]
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var loadErrors: [URL: String] = [:]

    private let loader = XSignRepositoryLoader()
    private var requestedSources: [AltSource] = []
    private var requestSerial: UInt64 = 0
    private var requestedRefresh = false

    func fetchSources(
        _ fetchedSources: FetchedResults<AltSource>,
        refresh: Bool = false,
        batchSize: Int = 3
    ) async {
        requestedSources = Array(fetchedSources)
        requestedRefresh = requestedRefresh || refresh
        requestSerial &+= 1
        guard isFinished else { return }

        isFinished = false
        defer { isFinished = true }
        let limit = max(1, min(batchSize, 4))

        while true {
            let serial = requestSerial
            let currentSources = requestedSources
            let refreshThisPass = requestedRefresh
            requestedRefresh = false

            let validIDs = Set(currentSources.map(\.objectID))
            let retained = sources.filter { validIDs.contains($0.key.objectID) }
            if retained.count != sources.count {
                sources = retained
                revision &+= 1
            }

            let pending = currentSources.filter { refreshThisPass || sources[$0] == nil }
            var seen = Set<URL>()
            let urls = pending.compactMap { source -> URL? in
                guard let url = source.sourceURL, seen.insert(url).inserted else { return nil }
                return url
            }

            for start in stride(from: 0, to: urls.count, by: limit) {
                let batch = Array(urls[start..<min(start + limit, urls.count)])
                let results = await withTaskGroup(
                    of: (URL, ASRepository?, String?).self,
                    returning: [(URL, ASRepository?, String?)].self
                ) { group in
                    for url in batch {
                        group.addTask { [loader] in
                            do { return (url, try await loader.load(url, refresh: refreshThisPass), nil) }
                            catch { return (url, nil, error.localizedDescription) }
                        }
                    }
                    var results: [(URL, ASRepository?, String?)] = []
                    for await result in group { results.append(result) }
                    return results
                }

                var updated = sources
                for (url, repository, error) in results {
                    loadErrors[url] = error
                    guard let repository else { continue }
                    for source in currentSources where source.sourceURL == url {
                        updated[source] = repository
                    }
                }
                sources = updated
                // Same-count app/version/news changes must invalidate the store cache.
                revision &+= 1
            }

            guard serial != requestSerial else { break }
        }
    }
}

private actor XSignRepositoryLoader {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "IPA.BLACK.RepositoryHTTP"
        )
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        session = URLSession(configuration: configuration)
    }

    func load(_ url: URL, refresh: Bool) async throws -> ASRepository {
        let request = URLRequest(
            url: url,
            cachePolicy: refresh ? .reloadRevalidatingCacheData : .useProtocolCachePolicy,
            timeoutInterval: 30
        )
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Actor isolation serializes JSON decoding without blocking the UI.
        return try JSONDecoder().decode(ASRepository.self, from: data)
    }
}
