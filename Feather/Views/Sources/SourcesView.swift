import SwiftUI
import WebKit
import AVKit

// ==========================================
// MARK: - 0. الألوان والتصميم (Theme)
// ==========================================
extension Color {
    static let appGold = Color(red: 0.85, green: 0.65, blue: 0.15)
    static let darkBackground = Color(red: 0.04, green: 0.05, blue: 0.07)
}

// ==========================================
// MARK: - 1. نماذج البيانات (Models)
// ==========================================
struct TMDBResponse: Codable {
    let results: [TMDBResult]
}

struct TMDBResult: Codable {
    let id: Int
    let title: String?
    let name: String?
    let mediaType: String?
    let posterPath: String?
    let backdropPath: String?
    let voteAverage: Double?
    let releaseDate: String?
    let firstAirDate: String?
    let overview: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case voteAverage = "vote_average"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
    }
}

struct TMDBShowDetail: Codable {
    let seasons: [TMDBSeason]?
}

struct TMDBSeason: Codable {
    let seasonNumber: Int
    let name: String?
    
    enum CodingKeys: String, CodingKey {
        case seasonNumber = "season_number", name
    }
}

struct TMDBSeasonDetail: Codable {
    let episodes: [TMDBEpisode]?
}

struct TMDBEpisode: Codable {
    let episodeNumber: Int
    let name: String?
    let stillPath: String?
    
    enum CodingKeys: String, CodingKey {
        case episodeNumber = "episode_number", name, stillPath = "still_path"
    }
}

struct EpisodeItem: Identifiable, Equatable {
    let seasonNum: Int
    let episodeNum: Int
    let title: String
    let imageURL: URL?
    
    var id: String { 
        return "s\(seasonNum)-e\(episodeNum)" 
    }
}

struct CatalogItem: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let overview: String
    let posterURL: URL?
    let backdropURL: URL?
    let rating: String
    let year: String
    let isMovie: Bool
    
    var rawVideoURL: URL? = nil
    var websiteToScrape: String? = nil
    var localVideoPath: String? = nil
    
    static func == (lhs: CatalogItem, rhs: CatalogItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// نموذج قنوات الـ IPTV المباشرة
struct IPTVChannel: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let logoURL: URL?
    let streamURL: URL
    let group: String?
}

// ==========================================
// MARK: - 2. مححل وقارئ ملفات M3U (IPTV Parser)
// ==========================================
class M3UParser {
    static func parse(m3uString: String) -> [IPTVChannel] {
        var channels: [IPTVChannel] = []
        let lines = m3uString.components(separatedBy: .newlines)
        
        var currentName = ""
        var currentLogo: URL? = nil
        var currentGroup: String? = nil
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("#EXTINF:") {
                if let commaIndex = trimmed.lastIndex(of: ",") {
                    currentName = String(trimmed[trimmed.index(after: commaIndex)...]).trimmingCharacters(in: .whitespaces)
                }
                
                if let logoRange = trimmed.range(of: "tvg-logo=\"") {
                    let substring = trimmed[logoRange.upperBound...]
                    if let endQuote = substring.firstIndex(of: "\"") {
                        let logoStr = String(substring[..<endQuote])
                        currentLogo = URL(string: logoStr)
                    }
                }
                
                if let groupRange = trimmed.range(of: "group-title=\"") {
                    let substring = trimmed[groupRange.upperBound...]
                    if let endQuote = substring.firstIndex(of: "\"") {
                        currentGroup = String(substring[..<endQuote])
                    }
                }
            } else if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                if let streamURL = URL(string: trimmed), !currentName.isEmpty {
                    let channel = IPTVChannel(
                        name: currentName,
                        logoURL: currentLogo,
                        streamURL: streamURL,
                        group: currentGroup
                    )
                    channels.append(channel)
                    
                    currentName = ""
                    currentLogo = nil
                    currentGroup = nil
                }
            }
        }
        
        return channels
    }
}

@MainActor
final class IPTVManager: ObservableObject {
    @Published var channels: [IPTVChannel] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func fetchChannels(from urlString: String) async {
        guard let url = URL(string: urlString) else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                errorMessage = "تعذر تحميل قائمة القنوات."
                isLoading = false
                return
            }
            
            if let content = String(data: data, encoding: .utf8) {
                self.channels = M3UParser.parse(m3uString: content)
            }
        } catch {
            errorMessage = "خطأ في الاتصال: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

// ==========================================
// MARK: - 3. محرك السحب ومكتبات الحفظ
// ==========================================
class VideoScraper: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var extractedRawURL: URL?
    @Published var isScraping = false
    @Published var scrapeError = false
    
    private var hiddenWebView: WKWebView!
    
    override init() {
        super.init()
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        
        hiddenWebView = WKWebView(frame: .zero, configuration: config)
        hiddenWebView.navigationDelegate = self
        hiddenWebView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1"
    }
    
    func scrapeVideo(from websiteURL: String) {
        guard let url = URL(string: websiteURL) else { return }
        
        DispatchQueue.main.async {
            self.isScraping = true
            self.scrapeError = false
            self.extractedRawURL = nil
            self.hiddenWebView.load(URLRequest(url: url))
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let jsCode = """
        function findVideo() {
            var videoTag = document.querySelector('video');
            if (videoTag && videoTag.src) { return videoTag.src; }
            var sourceTag = document.querySelector('video source');
            if (sourceTag && sourceTag.src) { return sourceTag.src; }
            var allLinks = document.getElementsByTagName('a');
            for (var i = 0; i < allLinks.length; i++) {
                if (allLinks[i].href.includes('.mp4') || allLinks[i].href.includes('.m3u8')) {
                    return allLinks[i].href;
                }
            }
            return "not_found";
        }
        findVideo();
        """
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            webView.evaluateJavaScript(jsCode) { (result, error) in
                if let videoString = result as? String, videoString != "not_found", let finalURL = URL(string: videoString) {
                    self.extractedRawURL = finalURL
                    self.isScraping = false
                } else {
                    self.scrapeError = true
                    self.isScraping = false
                }
            }
        }
    }
}

class FavoritesManager: ObservableObject {
    @Published var items: [CatalogItem] = []
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "filmakk_favorites"),
           let decoded = try? JSONDecoder().decode([CatalogItem].self, from: data) {
            self.items = decoded
        }
    }
    
    func toggle(_ item: CatalogItem) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: index)
        } else {
            items.append(item)
        }
        save()
    }
    
    func isFavorite(_ item: CatalogItem) -> Bool {
        return items.contains(where: { $0.id == item.id })
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: "filmakk_favorites")
        }
    }
}

class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published var downloadedItems: [CatalogItem] = []
    @Published var downloadProgress: [Int: Double] = [:]
    
    private var downloadSession: URLSession!
    
    override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.ipablack.filmakk.downloads")
        self.downloadSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        
        if let data = UserDefaults.standard.data(forKey: "filmakk_downloads"),
           let decoded = try? JSONDecoder().decode([CatalogItem].self, from: data) {
            self.downloadedItems = decoded
        }
    }
    
    func startDownload(item: CatalogItem, quality: String) {
        if let url = item.rawVideoURL {
            let task = downloadSession.downloadTask(with: url)
            task.taskDescription = "\(item.id)"
            task.resume()
            
            DispatchQueue.main.async {
                self.downloadProgress[item.id] = 0.01
            }
        } else {
            DispatchQueue.main.async {
                self.saveDownloadedItem(item)
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let idString = downloadTask.taskDescription, let id = Int(idString) else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress[id] = progress
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let idString = downloadTask.taskDescription, let id = Int(idString) else { return }
        
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentDirectory.appendingPathComponent("movie_\(id).mp4")
        
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.downloadProgress.removeValue(forKey: id)
                if let index = self.downloadedItems.firstIndex(where: { $0.id == id }) {
                    var updatedItem = self.downloadedItems[index]
                    updatedItem.localVideoPath = destinationURL.path
                    self.downloadedItems[index] = updatedItem
                }
                self.save()
            }
        } catch {
            print("فشل حفظ الملف: \(error.localizedDescription)")
        }
    }
    
    func saveDownloadedItem(_ item: CatalogItem) {
        if !downloadedItems.contains(where: { $0.id == item.id }) {
            downloadedItems.append(item)
            save()
        }
    }
    
    func deleteDownload(_ item: CatalogItem) {
        if let index = downloadedItems.firstIndex(where: { $0.id == item.id }) {
            let removed = downloadedItems.remove(at: index)
            if let path = removed.localVideoPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            save()
        }
    }
    
    func isDownloaded(_ item: CatalogItem) -> Bool {
        return downloadedItems.contains(where: { $0.id == item.id })
    }
    
    func getProgress(for item: CatalogItem) -> Double? {
        return downloadProgress[item.id]
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(downloadedItems) {
            UserDefaults.standard.set(encoded, forKey: "filmakk_downloads")
        }
    }
}

class HistoryManager: ObservableObject {
    @Published var items: [CatalogItem] = []
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "filmakk_history"),
           let decoded = try? JSONDecoder().decode([CatalogItem].self, from: data) {
            self.items = decoded
        }
    }
    
    func add(_ item: CatalogItem) {
        var currentItems = items
        if let index = currentItems.firstIndex(where: { $0.id == item.id }) {
            currentItems.remove(at: index)
        }
        currentItems.insert(item, at: 0)
        if currentItems.count > 50 {
            currentItems.removeLast()
        }
        items = currentItems
        save()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(encoded, forKey: "filmakk_history")
        }
    }
}

class SearchHistoryManager: ObservableObject {
    @Published var history: [String] = []
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "filmakk_search_history"),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.history = decoded
        }
    }
    
    func addSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        if let index = history.firstIndex(of: trimmed) {
            history.remove(at: index)
        }
        history.insert(trimmed, at: 0)
        if history.count > 10 { history.removeLast() }
        save()
    }
    
    func clear() {
        history.removeAll()
        save()
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(encoded, forKey: "filmakk_search_history")
        }
    }
}

// ==========================================
// MARK: - 4. محرك البيانات (Filmakk Data Engine)
// ==========================================
@MainActor
final class FilmakkDataEngine: ObservableObject {
    @Published var heroMovies: [CatalogItem] = []
    @Published var dubbedAnime: [CatalogItem] = []
    @Published var newReleases: [CatalogItem] = []
    @Published var popularSeries: [CatalogItem] = []
    @Published var marvelMovies: [CatalogItem] = []
    
    @Published var searchResults: [CatalogItem] = []
    @Published var categoryResults: [CatalogItem] = []
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    @Published var isFetchingMoreCategory = false
    private var currentCategoryPage = 1
    private var currentGenreID = 28
    
    @Published var isFetchingMoreSearch = false
    private var currentSearchPage = 1
    private var currentSearchQuery = ""
    
    private let apiKey = "api_key=d50387e55111b6e309c7b99c656d73c6"
    private let baseURL = "https://api.themoviedb.org/3"
    
    func loadAllContent() async {
        guard heroMovies.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        loadDubbedAnimeMockData()
        
        do {
            if let heroData = try await fetchSinglePage(url: "\(baseURL)/trending/movie/week?\(apiKey)&language=ar-SA") {
                self.heroMovies = Array(heroData.prefix(5))
            }
            
            async let fetchNew = fetchMultiplePages(urlBase: "\(baseURL)/movie/now_playing?\(apiKey)&language=ar-SA", pages: 3)
            async let fetchSeries = fetchMultiplePages(urlBase: "\(baseURL)/tv/popular?\(apiKey)&language=ar-SA", pages: 3)
            async let fetchMarvel = fetchMultiplePages(urlBase: "\(baseURL)/discover/movie?\(apiKey)&language=ar-SA&with_companies=420&sort_by=popularity.desc", pages: 3)
            
            self.newReleases = try await fetchNew
            self.popularSeries = try await fetchSeries
            self.marvelMovies = try await fetchMarvel
            
        } catch {
            errorMessage = "حدث خطأ أثناء تحميل البيانات."
        }
        
        isLoading = false
    }
    
    private func loadDubbedAnimeMockData() {
        self.dubbedAnime = [
            CatalogItem(
                id: 9901,
                title: "المحقق كونان: الرصاصة القرمزية",
                overview: "مغامرات المحقق كونان الشيقة بالدبلجة العربية، إثارة وغموض مستمر.",
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/qSc3o46r3VUI2u6Z5lM9X2Y0zT1.jpg"),
                backdropURL: URL(string: "https://image.tmdb.org/t/p/w780/qSc3o46r3VUI2u6Z5lM9X2Y0zT1.jpg"),
                rating: "8.5",
                year: "2021",
                isMovie: true,
                rawVideoURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")
            ),
            CatalogItem(
                id: 9902,
                title: "سبايدرمان: إنتو ذا سبايدر فيرس",
                overview: "اكتشف عوالم سبايدرمان المتعددة في هذه التحفة الفنية المدبلجة للعربية بصوت نقي 4K.",
                posterURL: URL(string: "https://image.tmdb.org/t/p/w500/iiZZdoQBEYBv6id8su7ImL0oCbD.jpg"),
                backdropURL: URL(string: "https://image.tmdb.org/t/p/w780/iiZZdoQBEYBv6id8su7ImL0oCbD.jpg"),
                rating: "8.4",
                year: "2018",
                isMovie: true,
                rawVideoURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4")
            )
        ]
    }
    
    func search(query: String) async {
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        isLoading = true
        currentSearchQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        currentSearchPage = 1
        
        do {
            if let results = try await fetchSinglePage(url: "\(baseURL)/search/multi?\(apiKey)&language=ar-SA&query=\(currentSearchQuery)&page=\(currentSearchPage)") {
                self.searchResults = results
            }
        } catch {}
        
        isLoading = false
    }
    
    func loadMoreSearch() async {
        guard !isFetchingMoreSearch, !currentSearchQuery.isEmpty else { return }
        
        isFetchingMoreSearch = true
        currentSearchPage += 1
        
        if let moreItems = try? await fetchSinglePage(url: "\(baseURL)/search/multi?\(apiKey)&language=ar-SA&query=\(currentSearchQuery)&page=\(currentSearchPage)") {
            let newItems = moreItems.filter { newItem in
                !searchResults.contains(where: { $0.id == newItem.id })
            }
            searchResults.append(contentsOf: newItems)
        }
        
        isFetchingMoreSearch = false
    }
    
    func fetchCategory(genreID: Int) async {
        isLoading = true
        currentGenreID = genreID
        currentCategoryPage = 1
        
        do {
            if let results = try await fetchSinglePage(url: "\(baseURL)/discover/movie?\(apiKey)&language=ar-SA&with_genres=\(currentGenreID)&page=\(currentCategoryPage)") {
                self.categoryResults = results
            }
        } catch {}
        
        isLoading = false
    }
    
    func loadMoreCategory() async {
        guard !isFetchingMoreCategory else { return }
        
        isFetchingMoreCategory = true
        currentCategoryPage += 1
        
        if let moreItems = try? await fetchSinglePage(url: "\(baseURL)/discover/movie?\(apiKey)&language=ar-SA&with_genres=\(currentGenreID)&page=\(currentCategoryPage)") {
            let newItems = moreItems.filter { newItem in
                !categoryResults.contains(where: { $0.id == newItem.id })
            }
            categoryResults.append(contentsOf: newItems)
        }
        
        isFetchingMoreCategory = false
    }
    
    func fetchSimilar(id: Int, isMovie: Bool) async -> [CatalogItem] {
        let type = isMovie ? "movie" : "tv"
        let url = "\(baseURL)/\(type)/\(id)/similar?\(apiKey)&language=ar-SA&page=1"
        
        guard let validURL = URL(string: url),
              let (data, response) = try? await URLSession.shared.data(from: validURL),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let tmdbResponse = try? JSONDecoder().decode(TMDBResponse.self, from: data) else {
            return []
        }
        
        return tmdbResponse.results.prefix(12).compactMap { item in
            let dateStr = isMovie ? (item.releaseDate ?? "") : (item.firstAirDate ?? "")
            let year = String(dateStr.prefix(4))
            let rating = String(format: "%.1f", item.voteAverage ?? 0.0)
            
            return CatalogItem(
                id: item.id,
                title: item.title ?? item.name ?? "بدون اسم",
                overview: (item.overview?.isEmpty ?? true) ? "الوصف غير متوفر." : item.overview!,
                posterURL: item.posterPath != nil ? URL(string: "https://image.tmdb.org/t/p/w500\(item.posterPath!)") : nil,
                backdropURL: item.backdropPath != nil ? URL(string: "https://image.tmdb.org/t/p/w780\(item.backdropPath!)") : nil,
                rating: rating,
                year: year.isEmpty ? "2024" : year,
                isMovie: isMovie
            )
        }
    }
    
    func fetchSeasons(showID: Int) async -> [Int] {
        let url = "\(baseURL)/tv/\(showID)?\(apiKey)&language=ar-SA"
        
        guard let validURL = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: validURL),
              let response = try? JSONDecoder().decode(TMDBShowDetail.self, from: data) else {
            return []
        }
        
        return response.seasons?.map { $0.seasonNumber }.filter { $0 > 0 }.sorted() ?? []
    }
    
    func fetchEpisodes(showID: Int, season: Int) async -> [EpisodeItem] {
        let url = "\(baseURL)/tv/\(showID)/season/\(season)?\(apiKey)&language=ar-SA"
        
        guard let validURL = URL(string: url),
              let (data, _) = try? await URLSession.shared.data(from: validURL),
              let response = try? JSONDecoder().decode(TMDBSeasonDetail.self, from: data) else {
            return []
        }
        
        return response.episodes?.map { ep in
            EpisodeItem(
                seasonNum: season,
                episodeNum: ep.episodeNumber,
                title: ep.name ?? "الحلقة \(ep.episodeNumber)",
                imageURL: ep.stillPath != nil ? URL(string: "https://image.tmdb.org/t/p/w500\(ep.stillPath!)") : nil
            )
        } ?? []
    }
    
    private func fetchMultiplePages(urlBase: String, pages: Int) async throws -> [CatalogItem] {
        var allItems: [CatalogItem] = []
        
        for page in 1...pages {
            if let items = try await fetchSinglePage(url: "\(urlBase)&page=\(page)") {
                allItems.append(contentsOf: items)
            }
        }
        
        var uniqueItems = [CatalogItem]()
        var seenIDs = Set<Int>()
        
        for item in allItems {
            if !seenIDs.contains(item.id) {
                uniqueItems.append(item)
                seenIDs.insert(item.id)
            }
        }
        
        return uniqueItems
    }
    
    private func fetchSinglePage(url: String) async throws -> [CatalogItem]? {
        guard let validURL = URL(string: url) else { return nil }
        
        let (data, response) = try await URLSession.shared.data(from: validURL)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        let tmdbResponse = try JSONDecoder().decode(TMDBResponse.self, from: data)
        
        return tmdbResponse.results.compactMap { item in
            if let type = item.mediaType, type == "person" { return nil }
            
            let isMovie = item.mediaType == "movie" || item.title != nil
            let dateStr = isMovie ? (item.releaseDate ?? "") : (item.firstAirDate ?? "")
            let year = String(dateStr.prefix(4))
            let rating = String(format: "%.1f", item.voteAverage ?? 0.0)
            
            return CatalogItem(
                id: item.id,
                title: item.title ?? item.name ?? "بدون اسم",
                overview: (item.overview?.isEmpty ?? true) ? "الوصف غير متوفر." : item.overview!,
                posterURL: item.posterPath != nil ? URL(string: "https://image.tmdb.org/t/p/w500\(item.posterPath!)") : nil,
                backdropURL: item.backdropPath != nil ? URL(string: "https://image.tmdb.org/t/p/w780\(item.backdropPath!)") : nil,
                rating: rating,
                year: year.isEmpty ? "2024" : year,
                isMovie: isMovie
            )
        }
    }
}

// ==========================================
// MARK: - 5. الحاوية الرئيسية وشريط أبل ستور السفلي
// ==========================================
@main
struct FilmakkApp: App {
    @StateObject private var dataEngine = FilmakkDataEngine()
    @StateObject private var favManager = FavoritesManager()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var historyManager = HistoryManager()
    
    var body: some Scene {
        WindowGroup {
            FilmakkMainContainer(engine: dataEngine)
                .environmentObject(favManager)
                .environmentObject(downloadManager)
                .environmentObject(historyManager)
                .environment(\.layoutDirection, .rightToLeft)
                .preferredColorScheme(.dark)
                .task {
                    await dataEngine.loadAllContent()
                }
        }
    }
}

struct FilmakkMainContainer: View {
    @ObservedObject var engine: FilmakkDataEngine
    @State private var selectedTab = 0
    
    init(engine: FilmakkDataEngine) {
        self.engine = engine
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = UIColor(Color.darkBackground).withAlphaComponent(0.95)
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            FilmakkHomeView(engine: engine)
                .tabItem {
                    Image(systemName: selectedTab == 0 ? "house.fill" : "house")
                    Text("الرئيسية")
                }
                .tag(0)
            
            FilmakkCategoriesView(engine: engine)
                .tabItem {
                    Image(systemName: selectedTab == 1 ? "square.grid.2x2.fill" : "square.grid.2x2")
                    Text("الأقسام")
                }
                .tag(1)
            
            // قسم البث المباشر وقنوات الرياضة المدمج
            LiveChannelsView()
                .tabItem {
                    Image(systemName: selectedTab == 2 ? "tv.fill" : "tv")
                    Text("البث المباشر")
                }
                .tag(2)
            
            FilmakkSearchView(engine: engine)
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text("بحث")
                }
                .tag(3)
            
            FilmakkSettingsView(engine: engine)
                .tabItem {
                    Image(systemName: selectedTab == 4 ? "gearshape.fill" : "gearshape")
                    Text("الإعدادات")
                }
                .tag(4)
        }
        .tint(.appGold)
    }
}

// ==========================================
// MARK: - 6. شاشة البث المباشر وقنوات الرياضة
// ==========================================
struct LiveChannelsView: View {
    @StateObject private var iptvManager = IPTVManager()
    @State private var selectedChannel: IPTVChannel?
    @State private var searchText = ""
    
    private let m3uURL = "https://raw.githubusercontent.com/NEXT11DEV/bein-iptv/refs/heads/main/bein_sports.m3u"
    
    var filteredChannels: [IPTVChannel] {
        if searchText.isEmpty {
            return iptvManager.channels
        } else {
            return iptvManager.channels.filter { $0.name.localizedStandardContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.darkBackground.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // حقل بحث داخل القنوات
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.gray)
                        TextField("ابحث عن قناة رياضية...", text: $searchText)
                            .foregroundColor(.white)
                    }
                    .padding()
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)
                    
                    if iptvManager.isLoading {
                        Spacer()
                        ProgressView("جاري جلب القنوات المباشرة...")
                            .tint(.appGold)
                            .foregroundColor(.white)
                        Spacer()
                    } else if let error = iptvManager.errorMessage {
                        Spacer()
                        Text(error).foregroundColor(.red)
                        Spacer()
                    } else {
                        List(filteredChannels) { channel in
                            Button(action: {
                                selectedChannel = channel
                            }) {
                                HStack(spacing: 12) {
                                    if let logo = channel.logoURL {
                                        AsyncImage(url: logo) { image in
                                            image.resizable().scaledToFit()
                                        } placeholder: {
                                            Image(systemName: "sportscourt.fill")
                                                .foregroundColor(.appGold)
                                        }
                                        .frame(width: 40, height: 40)
                                    } else {
                                        Image(systemName: "sportscourt.fill")
                                            .frame(width: 40, height: 40)
                                            .foregroundColor(.appGold)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(channel.name)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        
                                        if let group = channel.group {
                                            Text(group)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundColor(.appGold)
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color.white.opacity(0.05))
                        }
                        .listStyle(.plain)
                        .background(Color.clear)
                    }
                }
            }
            .navigationTitle("البث المباشر والرياضة")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                if iptvManager.channels.isEmpty {
                    await iptvManager.fetchChannels(from: m3uURL)
                }
            }
            .fullScreenCover(item: $selectedChannel) { channel in
                LivePlayerView(streamURL: channel.streamURL)
            }
        }
    }
}

struct LivePlayerView: View {
    let streamURL: URL
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: AVPlayer(url: streamURL))
                .ignoresSafeArea()
                .onAppear {
                    // التشغيل التلقائي للبث
                }
            
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}

// ==========================================
// MARK: - 7. الإعدادات والمكتبة والبحث والأفلام
// ==========================================
struct FilmakkSettingsView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @State private var showFavorites = false
    @State private var showDownloads = false
    @State private var showHistory = false
    @State private var cacheClearedMessage = ""
    
    init(engine: FilmakkDataEngine) {
        self.engine = engine
        UITableView.appearance().backgroundColor = .clear
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Text("الإعدادات")
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 60)
                .padding(.horizontal, 20)
                .padding(.bottom, 10)
            
            Form {
                Section(header: Text("مكتبتي").foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .trailing)) {
                    Button(action: { showHistory = true }) {
                        HStack {
                            Image(systemName: "chevron.left").foregroundColor(.gray)
                            Spacer()
                            Text("المشاهدة مؤخراً").foregroundColor(.white)
                            Image(systemName: "clock.fill").foregroundColor(.appGold).frame(width: 30)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    Button(action: { showFavorites = true }) {
                        HStack {
                            Image(systemName: "chevron.left").foregroundColor(.gray)
                            Spacer()
                            Text("المفضلة").foregroundColor(.white)
                            Image(systemName: "heart.fill").foregroundColor(.red).frame(width: 30)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                    
                    Button(action: { showDownloads = true }) {
                        HStack {
                            Image(systemName: "chevron.left").foregroundColor(.gray)
                            Spacer()
                            Text("التنزيلات").foregroundColor(.white)
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(.appGold).frame(width: 30)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                
                Section(header: Text("إعدادات التطبيق").foregroundColor(.gray).frame(maxWidth: .infinity, alignment: .trailing)) {
                    Button(action: clearCache) {
                        HStack {
                            Text(cacheClearedMessage).font(.caption).foregroundColor(.green)
                            Spacer()
                            Text("مسح الذاكرة المؤقتة").foregroundColor(.white)
                            Image(systemName: "trash.fill").foregroundColor(.red).frame(width: 30)
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
                
                Section {
                    HStack {
                        Text("1.0.0 (فلمك)").foregroundColor(.gray)
                        Spacer()
                        Text("إصدار التطبيق").foregroundColor(.white)
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .background(Color.clear)
        }
        .environment(\.layoutDirection, .rightToLeft)
        .sheet(isPresented: $showFavorites) { FavoritesView(engine: engine) }
        .sheet(isPresented: $showDownloads) { DownloadsView(engine: engine) }
        .sheet(isPresented: $showHistory) { HistoryView(engine: engine) }
    }
    
    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: Date(timeIntervalSince1970: 0)) {
            withAnimation { cacheClearedMessage = "تم المسح" }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { cacheClearedMessage = "" }
        }
    }
}

struct HistoryView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @EnvironmentObject var historyManager: HistoryManager
    @Environment(\.presentationMode) var presentationMode
    @State private var itemToDetail: CatalogItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill").foregroundColor(.appGold)
                    Text("المشاهدة مؤخراً").font(.title2.bold()).foregroundColor(.white)
                }
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
                }
            }
            .padding().background(Color.darkBackground)
            
            if historyManager.items.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "clock.badge.xmark").font(.system(size: 50)).foregroundColor(.gray).padding()
                    Text("لم تقم بمشاهدة أي محتوى بعد").font(.headline).foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity).background(Color.darkBackground.ignoresSafeArea())
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
                        ForEach(historyManager.items) { item in
                            Button(action: { itemToDetail = item }) { MovieCard(item: item) }.buttonStyle(PlainButtonStyle())
                        }
                    }.padding()
                }.background(Color.darkBackground.ignoresSafeArea())
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .fullScreenCover(item: $itemToDetail) { item in FilmakkDetailView(item: item, engine: engine) }
    }
}

struct FavoritesView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @EnvironmentObject var favManager: FavoritesManager
    @Environment(\.presentationMode) var presentationMode
    @State private var itemToDetail: CatalogItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "heart.fill").foregroundColor(.red)
                    Text("المفضلة").font(.title2.bold()).foregroundColor(.white)
                }
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
                }
            }
            .padding().background(Color.darkBackground)
            
            if favManager.items.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "heart.slash").font(.system(size: 50)).foregroundColor(.gray).padding()
                    Text("المفضلة فارغة").font(.headline).foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity).background(Color.darkBackground.ignoresSafeArea())
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
                        ForEach(favManager.items) { item in
                            Button(action: { itemToDetail = item }) { MovieCard(item: item) }.buttonStyle(PlainButtonStyle())
                        }
                    }.padding()
                }.background(Color.darkBackground.ignoresSafeArea())
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .fullScreenCover(item: $itemToDetail) { item in FilmakkDetailView(item: item, engine: engine).environmentObject(favManager) }
    }
}

struct DownloadsView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @EnvironmentObject var downloadManager: DownloadManager
    @Environment(\.presentationMode) var presentationMode
    @State private var itemToDetail: CatalogItem?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill").foregroundColor(.appGold)
                    Text("التنزيلات").font(.title2.bold()).foregroundColor(.white)
                }
                Spacer()
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
                }
            }
            .padding().background(Color.darkBackground)
            
            if downloadManager.downloadedItems.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "arrow.down.doc").font(.system(size: 50)).foregroundColor(.gray).padding()
                    Text("لا توجد محتويات محملة").font(.headline).foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity).background(Color.darkBackground.ignoresSafeArea())
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
                        ForEach(downloadManager.downloadedItems) { item in
                            Button(action: { itemToDetail = item }) { MovieCard(item: item) }.buttonStyle(PlainButtonStyle())
                        }
                    }.padding()
                }.background(Color.darkBackground.ignoresSafeArea())
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .fullScreenCover(item: $itemToDetail) { item in FilmakkDetailView(item: item, engine: engine) }
    }
}

struct FilmakkHomeView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @State private var itemToDetail: CatalogItem?
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 30) {
                if !engine.heroMovies.isEmpty {
                    HeroCarousel(items: engine.heroMovies, onDetail: { item in itemToDetail = item })
                        .frame(height: 550)
                } else if engine.isLoading {
                    ProgressView().tint(.appGold).frame(height: 550)
                }
                
                if let error = engine.errorMessage {
                    Text(error).foregroundColor(.red).padding()
                }
                
                VStack(spacing: 45) {
                    if !engine.dubbedAnime.isEmpty {
                        ContentRow(title: "أنميشن مدبلج بالعربية", items: engine.dubbedAnime, onDetail: { item in itemToDetail = item })
                    }
                    ContentRow(title: "الإصدارات الجديدة", items: engine.newReleases, onDetail: { item in itemToDetail = item })
                    ContentRow(title: "المسلسلات الأكثر شعبية", items: engine.popularSeries, onDetail: { item in itemToDetail = item })
                    ContentRow(title: "عالم مارفل 4K", items: engine.marvelMovies, onDetail: { item in itemToDetail = item })
                }
                .padding(.bottom, 20)
            }
        }
        .ignoresSafeArea(edges: .top)
        .fullScreenCover(item: $itemToDetail) { item in FilmakkDetailView(item: item, engine: engine) }
    }
}

struct FilmakkCategoriesView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @State private var itemToDetail: CatalogItem?
    @State private var selectedGenreName = "أكشن"
    
    let genres = [("أكشن", 28), ("كوميديا", 35), ("دراما", 18), ("رعب", 27), ("خيال علمي", 878), ("أنميشن", 16), ("جريمة", 80), ("غموض", 9648)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("التصنيفات").font(.largeTitle.weight(.heavy)).foregroundColor(.white)
                Spacer()
                Menu {
                    ForEach(genres, id: \.1) { genre in
                        Button(action: {
                            selectedGenreName = genre.0
                            Task { await engine.fetchCategory(genreID: genre.1) }
                        }) {
                            Text(genre.0)
                            if selectedGenreName == genre.0 { Image(systemName: "checkmark") }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(selectedGenreName).font(.headline.weight(.bold))
                        Image(systemName: "chevron.down.circle.fill").font(.system(size: 18))
                    }
                    .foregroundColor(.black).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.appGold).clipShape(Capsule())
                    .shadow(color: Color.appGold.opacity(0.3), radius: 8, x: 0, y: 4)
                }
            }
            .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 20)
            
            if engine.isLoading {
                ProgressView().tint(.appGold).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
                        ForEach(engine.categoryResults) { item in
                            Button(action: { itemToDetail = item }) {
                                MovieCard(item: item).onAppear {
                                    if item.id == engine.categoryResults.last?.id {
                                        Task { await engine.loadMoreCategory() }
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                    
                    if engine.isFetchingMoreCategory {
                        ProgressView().tint(.appGold).padding()
                    }
                }
            }
        }
        .onAppear {
            if engine.categoryResults.isEmpty {
                Task { await engine.fetchCategory(genreID: 28) }
            }
        }
        .fullScreenCover(item: $itemToDetail) { item in FilmakkDetailView(item: item, engine: engine) }
    }
}

struct FilmakkSearchView: View {
    @ObservedObject var engine: FilmakkDataEngine
    @StateObject private var searchHistory = SearchHistoryManager()
    
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var itemToDetail: CatalogItem?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("البحث")
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 15)
            
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("ابحث عن فيلم أو مسلسل...", text: $query)
                    .foregroundColor(.white)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        isFocused = false
                        searchHistory.addSearch(query)
                    }
                
                if !query.isEmpty {
                    Button(action: {
                        query = ""
                        engine.searchResults.removeAll()
                        isFocused = false
                    }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                    }
                }
            }
            .padding().background(Color.white.opacity(0.1)).cornerRadius(12)
            .padding(.horizontal, 20).padding(.bottom, 20)
            .onChange(of: query) { val in
                searchTask?.cancel()
                if val.isEmpty {
                    engine.searchResults.removeAll()
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    await engine.search(query: val)
                    searchHistory.addSearch(val)
                }
            }
            
            if engine.isLoading {
                ProgressView().tint(.appGold).padding()
            }
            
            if query.isEmpty && !searchHistory.history.isEmpty {
                VStack(alignment: .leading) {
                    HStack {
                        Text("عمليات البحث الأخيرة").font(.headline).foregroundColor(.white)
                        Spacer()
                        Button("مسح") { searchHistory.clear() }.foregroundColor(.red)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 10)
                    
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(searchHistory.history, id: \.self) { pastQuery in
                                Button(action: {
                                    query = pastQuery
                                    isFocused = false
                                }) {
                                    HStack {
                                        Image(systemName: "clock").foregroundColor(.gray)
                                        Text(pastQuery).foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "arrow.up.backward").foregroundColor(.gray)
                                    }
                                    .padding().background(Color.white.opacity(0.05)).cornerRadius(10)
                                }
                                .padding(.horizontal, 20).padding(.bottom, 8)
                            }
                        }
                    }
                    .simultaneousGesture(DragGesture().onChanged { _ in isFocused = false })
                }
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 15) {
                        ForEach(engine.searchResults) { item in
                            Button(action: {
                                isFocused = false
                                itemToDetail = item
                            }) {
                                MovieCard(item: item).onAppear {
                                    if item.id == engine.searchResults.last?.id {
                                        Task { await engine.loadMoreSearch() }
                                    }
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20).padding(.bottom, 20)
                    
                    if engine.isFetchingMoreSearch {
                        ProgressView().tint(.appGold).padding()
                    }
                }
                .simultaneousGesture(DragGesture().onChanged { _ in isFocused = false })
            }
        }
        .onTapGesture { isFocused = false }
        .fullScreenCover(item: $itemToDetail) { item in FilmakkDetailView(item: item, engine: engine) }
    }
}

// ==========================================
// MARK: - 8. مكونات واجهة المستخدم والشاشات التابعة
// ==========================================
struct HeroCarousel: View {
    let items: [CatalogItem]
    let onDetail: (CatalogItem) -> Void
    
    var body: some View {
        TabView {
            ForEach(items) { item in
                ZStack(alignment: .bottom) {
                    if let url = item.backdropURL {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Color.darkBackground }
                        }
                    }
                    
                    LinearGradient(
                        colors: [.clear, Color.darkBackground.opacity(0.8), Color.darkBackground],
                        startPoint: .center, endPoint: .bottom
                    )
                    
                    VStack(spacing: 20) {
                        Text(item.title)
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundColor(.white).multilineTextAlignment(.center)
                            .padding(.horizontal, 20).lineLimit(2)
                        
                        Button(action: { onDetail(item) }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("شاهد الآن").font(.headline.bold())
                            }
                            .foregroundColor(.black).padding(.vertical, 14).padding(.horizontal, 40)
                            .background(Color.appGold).clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 60)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
    }
}

struct ContentRow: View {
    let title: String
    let items: [CatalogItem]
    let onDetail: (CatalogItem) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text(title).font(.title3.weight(.heavy)).foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 20)
            
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(items) { item in
                        Button(action: { onDetail(item) }) { MovieCard(item: item) }
                            .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 20).environment(\.layoutDirection, .rightToLeft)
            }
        }
    }
}

struct MovieCard: View {
    let item: CatalogItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                if let url = item.posterURL {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Rectangle().fill(Color.white.opacity(0.05)).overlay(ProgressView().tint(.appGold)) }
                    }
                } else {
                    Rectangle().fill(Color.white.opacity(0.05))
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(.appGold)
                    Text(item.rating).font(.system(size: 12, weight: .heavy)).foregroundColor(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .environment(\.colorScheme, .dark)
                .padding(8)
                
                if item.localVideoPath != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green).padding(8)
                        .background(Circle().fill(Color.white))
                        .offset(x: -95, y: 165)
                }
            }
            .frame(width: 140, height: 210).cornerRadius(12)
            .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 5)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(1)
                Text("\(item.year) • \(item.isMovie ? "فيلم" : "مسلسل")")
                    .font(.system(size: 12, weight: .medium)).foregroundColor(.gray).lineLimit(1)
            }
            .frame(width: 140, alignment: .leading)
        }
    }
}

// ==========================================
// MARK: - 9. شاشة التفاصيل والتشغيل
// ==========================================
struct FilmakkDetailView: View {
    let item: CatalogItem
    @ObservedObject var engine: FilmakkDataEngine
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var favManager: FavoritesManager
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var historyManager: HistoryManager
    
    @State private var seasons: [Int] = []
    @State private var selectedSeason: Int = 1
    @State private var episodes: [EpisodeItem] = []
    @State private var isLoadingSeries = false
    
    @State private var similarItems: [CatalogItem] = []
    @State private var isLoadingSimilar = true
    @State private var selectedSimilarItem: CatalogItem?
    
    @State private var playMovie = false
    @State private var episodeToPlay: EpisodeItem?
    @State private var showQualitySheet = false
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.darkBackground.ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .bottom) {
                        GeometryReader { geo in
                            if let url = item.backdropURL ?? item.posterURL {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { Color.darkBackground }
                                }
                                .frame(width: geo.size.width, height: 350).clipped()
                            }
                        }
                        .frame(height: 350)
                        
                        LinearGradient(
                            colors: [.clear, Color.darkBackground.opacity(0.9), Color.darkBackground],
                            startPoint: .top, endPoint: .bottom
                        )
                        .frame(height: 250)
                    }
                    
                    HStack(alignment: .bottom, spacing: 16) {
                        if let url = item.posterURL ?? item.backdropURL {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Color.darkBackground }
                            }
                            .frame(width: 110, height: 160).cornerRadius(12)
                            .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 5)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: 24, weight: .black))
                                .foregroundColor(.white).lineLimit(3)
                            
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "star.fill").foregroundColor(.appGold)
                                    Text(item.rating).foregroundColor(.white).fontWeight(.bold)
                                }
                                Text("•").foregroundColor(.gray)
                                Text(item.year).foregroundColor(.white).fontWeight(.medium)
                            }
                            
                            Text(item.isMovie ? "فيلم سينمائي" : "مسلسل تلفزيوني")
                                .font(.caption).fontWeight(.bold).foregroundColor(.black)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color.appGold).cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, -70)
                    
                    HStack(spacing: 12) {
                        if item.isMovie {
                            Button(action: { playMovie = true }) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("تشغيل الفيلم")
                                }
                                .font(.title3.bold()).foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.appGold).cornerRadius(12)
                            }
                        } else {
                            Text("اختر الحلقة من الأسفل للمشاهدة")
                                .font(.headline.bold()).foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.appGold).cornerRadius(12)
                        }
                        
                        Button(action: {
                            if downloadManager.isDownloaded(item) {
                                downloadManager.deleteDownload(item)
                            } else {
                                showQualitySheet = true
                            }
                        }) {
                            ZStack {
                                Image(systemName: downloadManager.isDownloaded(item) ? "checkmark" : "arrow.down")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(downloadManager.isDownloaded(item) ? .green : .white)
                                
                                if let progress = downloadManager.getProgress(for: item) {
                                    Circle().trim(from: 0, to: progress)
                                        .stroke(Color.appGold, lineWidth: 3)
                                        .rotationEffect(.degrees(-90))
                                }
                            }
                            .frame(width: 55, height: 55)
                            .background(Color.white.opacity(0.1)).cornerRadius(12)
                        }
                        
                        Button(action: { favManager.toggle(item) }) {
                            Image(systemName: favManager.isFavorite(item) ? "heart.fill" : "heart")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(favManager.isFavorite(item) ? .red : .white)
                                .frame(width: 55, height: 55)
                                .background(Color.white.opacity(0.1)).cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 20)
                    
                    Text(item.overview)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(8)
                        .padding(.horizontal, 20).padding(.top, 20)
                    
                    if !item.isMovie {
                        VStack(alignment: .leading, spacing: 20) {
                            HStack {
                                Text("المواسم والحلقات").font(.title2.weight(.heavy)).foregroundColor(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 20).padding(.top, 30)
                            
                            if isLoadingSeries {
                                ProgressView().tint(.appGold).frame(maxWidth: .infinity, alignment: .center).padding()
                            } else {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(seasons, id: \.self) { season in
                                            Button(action: {
                                                selectedSeason = season
                                                Task { await loadEpisodes(for: season) }
                                            }) {
                                                Text("موسم \(season)")
                                                    .font(.headline).fontWeight(.bold)
                                                    .padding(.vertical, 12).padding(.horizontal, 24)
                                                    .background(selectedSeason == season ? Color.appGold : Color.white.opacity(0.1))
                                                    .foregroundColor(selectedSeason == season ? .black : .white)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                                .environment(\.layoutDirection, .rightToLeft)
                                
                                VStack(spacing: 15) {
                                    ForEach(episodes, id: \.id) { ep in
                                        Button(action: { episodeToPlay = ep }) {
                                            HStack(spacing: 15) {
                                                if let url = ep.imageURL ?? item.backdropURL ?? item.posterURL {
                                                    AsyncImage(url: url) { phase in
                                                        if let img = phase.image { img.resizable().scaledToFill() }
                                                        else { Color.gray.opacity(0.3) }
                                                    }
                                                    .frame(width: 130, height: 80).cornerRadius(10).clipped()
                                                }
                                                
                                                VStack(alignment: .leading, spacing: 6) {
                                                    Text(ep.title)
                                                        .font(.headline.weight(.bold)).foregroundColor(.white)
                                                        .multilineTextAlignment(.leading)
                                                    Text("الحلقة \(ep.episodeNum)")
                                                        .font(.subheadline).foregroundColor(.gray)
                                                }
                                                Spacer()
                                                Image(systemName: "play.circle.fill")
                                                    .font(.system(size: 32)).foregroundColor(.white.opacity(0.8))
                                            }
                                            .padding(10).background(Color.white.opacity(0.05)).cornerRadius(16)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20).padding(.top, 10)
                            }
                        }
                    }
                    
                    if !similarItems.isEmpty {
                        VStack(alignment: .leading, spacing: 15) {
                            Text(item.isMovie ? "أفلام مشابهة" : "مسلسلات مشابهة")
                                .font(.title2.weight(.heavy)).foregroundColor(.white)
                                .padding(.horizontal, 20).padding(.top, 30)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(similarItems) { simItem in
                                        Button(action: { selectedSimilarItem = simItem }) {
                                            MovieCard(item: simItem)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal, 20).environment(\.layoutDirection, .rightToLeft)
                            }
                        }
                    } else if isLoadingSimilar {
                        ProgressView().tint(.appGold).padding(.top, 30).frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.bottom, 60).environment(\.layoutDirection, .rightToLeft)
            }
            .ignoresSafeArea(edges: .top)
            
            VStack {
                HStack {
                    Button(action: { presentationMode.wrappedValue.dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
                            .padding(10).background(.ultraThinMaterial, in: Circle())
                            .environment(\.colorScheme, .dark)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 60)
                Spacer()
            }
        }
        .confirmationDialog("اختر جودة التحميل", isPresented: $showQualitySheet, titleVisibility: .visible) {
            Button("جودة عالية (1080p)") { downloadManager.startDownload(item: item, quality: "1080p") }
            Button("جودة متوسطة (720p)") { downloadManager.startDownload(item: item, quality: "720p") }
            Button("جودة منخفضة (480p)") { downloadManager.startDownload(item: item, quality: "480p") }
            Button("إلغاء", role: .cancel) { }
        }
        .onAppear {
            historyManager.add(item)
            Task {
                isLoadingSimilar = true
                similarItems = await engine.fetchSimilar(id: item.id, isMovie: item.isMovie)
                isLoadingSimilar = false
            }
            if !item.isMovie {
                Task {
                    isLoadingSeries = true
                    seasons = await engine.fetchSeasons(showID: item.id)
                    if let first = seasons.first {
                        selectedSeason = first
                        await loadEpisodes(for: first)
                    }
                    isLoadingSeries = false
                }
            }
        }
        .fullScreenCover(item: $selectedSimilarItem) { simItem in
            FilmakkDetailView(item: simItem, engine: engine)
        }
        .fullScreenCover(isPresented: $playMovie) {
            SmartDualPlayerView(item: item, seasonNumber: nil, episodeNumber: nil).ignoresSafeArea()
        }
        .fullScreenCover(item: $episodeToPlay) { ep in
            SmartDualPlayerView(item: item, seasonNumber: ep.seasonNum, episodeNumber: ep.episodeNum).ignoresSafeArea()
        }
    }
    
    private func loadEpisodes(for season: Int) async {
        episodes = await engine.fetchEpisodes(showID: item.id, season: season)
    }
}

struct SmartDualPlayerView: View {
    let item: CatalogItem
    let seasonNumber: Int?
    let episodeNumber: Int?
    
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var scraper = VideoScraper()
    @State private var selectedServerIndex = 0
    @EnvironmentObject var downloadManager: DownloadManager
    
    var serverURLs: [URL] {
        if item.isMovie {
            return [
                "https://player.autoembed.cc/embed/movie/\(item.id)?cc=ar",
                "https://vidsrc.me/embed/movie/\(item.id)",
                "https://embed.su/embed/movie/\(item.id)"
            ].compactMap { URL(string: $0) }
        } else {
            let s = seasonNumber ?? 1
            let e = episodeNumber ?? 1
            return [
                "https://player.autoembed.cc/embed/tv/\(item.id)/\(s)/\(e)?cc=ar",
                "https://vidsrc.me/embed/tv/\(item.id)/\(s)/\(e)",
                "https://embed.su/embed/tv/\(item.id)/\(s)/\(e)"
            ].compactMap { URL(string: $0) }
        }
    }
    
    var localOfflineURL: URL? {
        if let downloadedItem = downloadManager.downloadedItems.first(where: { $0.id == item.id }),
           let path = downloadedItem.localVideoPath {
            let fileURL = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return fileURL
            }
        }
        return nil
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            playerContent
            controlsOverlay
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            if let targetURL = item.websiteToScrape {
                scraper.scrapeVideo(from: targetURL)
            }
        }
    }
    
    @ViewBuilder
    private var playerContent: some View {
        if let offlineURL = localOfflineURL {
            NativePlayerView(url: offlineURL)
        } else if let rawURL = item.rawVideoURL {
            NativePlayerView(url: rawURL)
        } else if let scrapeURL = item.websiteToScrape {
            if let finalURL = scraper.extractedRawURL {
                NativePlayerView(url: finalURL)
            } else if scraper.scrapeError {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
                    Text("حدث خطأ أثناء الاتصال بالسيرفر.").foregroundColor(.white).padding()
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView().tint(.appGold).scaleEffect(1.5)
                    Text("جاري تحضير المحتوى...").foregroundColor(.white).font(.headline)
                }
            }
        } else if !serverURLs.isEmpty {
            WebViewRepresentable(url: serverURLs[selectedServerIndex])
                .id(selectedServerIndex)
                .ignoresSafeArea()
        } else {
            Color.black
        }
    }
    
    private var controlsOverlay: some View {
        VStack {
            HStack(alignment: .center) {
                Button(action: { presentationMode.wrappedValue.dismiss() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20, weight: .bold)).foregroundColor(.white)
                        .padding(12).background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                }
                
                Spacer()
                
                if !serverURLs.isEmpty && item.rawVideoURL == nil && item.websiteToScrape == nil && localOfflineURL == nil {
                    Picker("السيرفر", selection: $selectedServerIndex) {
                        Text("سيرفر 1").tag(0)
                        Text("سيرفر 2").tag(1)
                        Text("سيرفر 3").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .background(Color.white.opacity(0.2)).cornerRadius(8).frame(width: 220)
                }
                
                if localOfflineURL != nil {
                    Text("مشاهدة بدون إنترنت")
                        .font(.caption).bold().padding(8)
                        .background(Color.green).foregroundColor(.white).cornerRadius(8)
                }
            }
            .padding(.horizontal, 20).padding(.top, 50)
            
            Spacer()
        }
    }
}

struct NativePlayerView: View {
    let url: URL
    @State private var player: AVPlayer?
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .onAppear {
            self.player = AVPlayer(url: url)
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let url: URL
    
    class Coordinator: NSObject {
        var lastURL: URL?
    }
    
    func makeCoordinator() -> Coordinator { Coordinator() }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        
        let jsCode = """
        var checkExist = setInterval(function() {
            var video = document.querySelector('video');
            if (video) {
                var tracks = video.textTracks;
                for (var i = 0; i < tracks.length; i++) {
                    if (tracks[i].language === 'ar' || tracks[i].label.toLowerCase().includes('arabic')) {
                        tracks[i].mode = 'showing';
                    }
                }
                clearInterval(checkExist);
            }
        }, 500);
        """
        
        config.userContentController.addUserScript(WKUserScript(source: jsCode, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15"
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url
        
        var request = URLRequest(url: url)
        request.setValue("https://vidsrc.xyz/", forHTTPHeaderField: "Referer")
        webView.load(request)
    }
}
