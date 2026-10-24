import Foundation
import SwiftUI
import CoreData
import AltSourceKit

@MainActor
final class AppStoreCacheManager: ObservableObject {
    static let shared = AppStoreCacheManager()

    private struct Snapshot {
        var revision: UInt64 = 0
        var ipablackItems: [AppStoreAppItem] = []
        var ipablackEditorialNews: [TodayEditorialInstruction] = []
        var allCombinedItems: [AppStoreAppItem] = []
        var pureAppsOnly: [AppStoreAppItem] = []
        var pureGamesOnly: [AppStoreAppItem] = []
        var itemsByCategory: [AppStore2026Category: [AppStoreAppItem]] = [:]
    }

    @Published private var snapshot = Snapshot()
    var revision: UInt64 { snapshot.revision }
    var ipablackItems: [AppStoreAppItem] { snapshot.ipablackItems }
    var ipablackEditorialNews: [TodayEditorialInstruction] { snapshot.ipablackEditorialNews }
    var allCombinedItems: [AppStoreAppItem] { snapshot.allCombinedItems }
    var pureAppsOnly: [AppStoreAppItem] { snapshot.pureAppsOnly }
    var pureGamesOnly: [AppStoreAppItem] { snapshot.pureGamesOnly }
    var itemsByCategory: [AppStore2026Category: [AppStoreAppItem]] { snapshot.itemsByCategory }

    private var lastSignature = ""
    private var generation: UInt64 = 0
    private var buildTask: Task<Void, Never>?

    func ensureFetched(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
        await viewModel.fetchSources(sources)
        rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
    }

    func forceRefresh(sources: FetchedResults<AltSource>, viewModel: SourcesViewModel) async {
        await viewModel.fetchSources(sources, refresh: true)
        rebuildCacheIfNeeded(sources: sources, repositoriesMap: viewModel.sources)
    }

    func rebuildCacheIfNeeded(sources: FetchedResults<AltSource>, repositoriesMap: [AltSource: ASRepository]) {
        let sourceIDs = sources.map {
            "\($0.objectID.uriRepresentation().absoluteString)|\($0.sourceURL?.absoluteString ?? "")"
        }.joined(separator: "\n")
        let signature = "\(SourcesViewModel.shared.revision)|\(sourceIDs)"
        guard signature != lastSignature else { return }
        lastSignature = signature
        buildTask?.cancel()
        generation &+= 1
        let buildGeneration = generation

        // Only immutable values leave Core Data's main context.
        let repositories: [(URL?, String?, ASRepository)] = sources.compactMap { source in
            guard let repository = repositoriesMap[source] else { return nil }
            return (source.sourceURL, source.identifier, repository)
        }

        buildTask = Task.detached(priority: .userInitiated) { [weak self] in
            var result = Snapshot()
            result.revision = buildGeneration
            var seen = Set<String>()
            result.allCombinedItems.reserveCapacity(repositories.reduce(0) { $0 + $1.2.apps.count })

            for (sourceURL, sourceID, repository) in repositories {
                guard !Task.isCancelled else { return }
                let isIPABlack = ProtectedSourcesVault.isIPABlackSource(sourceURL, identifier: sourceID)
                var repositoryItems: [AppStoreAppItem] = []

                for app in repository.apps {
                    guard !Task.isCancelled else { return }
                    let key = "\(app.id ?? app.currentName)_\(sourceURL?.absoluteString ?? "")"
                    guard seen.insert(key).inserted else { continue }
                    let item = AppStoreAppItem(id: key, sourceURL: sourceURL, repository: repository, app: app)
                    result.allCombinedItems.append(item)
                    if item.isGame { result.pureGamesOnly.append(item) }
                    else { result.pureAppsOnly.append(item) }
                    if isIPABlack { repositoryItems.append(item) }
                    result.itemsByCategory[item.category, default: []].append(item)
                }

                if isIPABlack {
                    result.ipablackItems.append(contentsOf: repositoryItems)
                    let byID = Dictionary(
                        repositoryItems.compactMap { item in item.app.id.map { ($0, item) } },
                        uniquingKeysWith: { first, _ in first }
                    )
                    for news in repository.news ?? [] {
                        result.ipablackEditorialNews.append(TodayEditorialInstruction(
                            id: "\(sourceURL?.absoluteString ?? "")|\(news.id)",
                            badge: "يحدث الآن",
                            title: news.title,
                            caption: news.caption,
                            imageURL: news.imageURL,
                            tintColor: news.tintColor ?? AppStoreTheme.oceanBlue,
                            associatedApp: (news.appID ?? nil).flatMap { byID[$0] } ?? repositoryItems.first
                        ))
                    }
                }
            }

            result.itemsByCategory[.topApps] = result.pureAppsOnly
            result.itemsByCategory[.bestSellingApps] = Array(result.pureAppsOnly.reversed())
            result.itemsByCategory[.topGames] = result.pureGamesOnly
            result.itemsByCategory[.bestSellingGames] = Array(result.pureGamesOnly.reversed())
            let casual = result.pureGamesOnly.filter { $0.category == .casualGames || $0.category == .puzzleGames }
            result.itemsByCategory[.timePass] = casual.isEmpty ? result.pureGamesOnly : casual
            for category in AppStore2026Category.allCases where result.itemsByCategory[category]?.isEmpty != false {
                result.itemsByCategory[category] = category.isGameCategory ? result.pureGamesOnly : result.pureAppsOnly
            }
            if result.ipablackItems.isEmpty { result.ipablackItems = result.allCombinedItems }
            guard !Task.isCancelled else { return }
            let completed = result
            await MainActor.run {
                guard let self, self.generation == buildGeneration else { return }
                self.snapshot = completed
                self.buildTask = nil
            }
        }
    }
}
