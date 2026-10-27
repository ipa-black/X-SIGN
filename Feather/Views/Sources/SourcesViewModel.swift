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
	
	func fetchSources<S: Collection>(_ sources: S, refresh: Bool = false, batchSize: Int = 4) async where S.Element == AltSource {
		guard isFinished else { return }
		
		// check if sources to be fetched are the same as before, if yes, return
		// also skip check if refresh is true
		if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }
		
		// isfinished is used to prevent multiple fetches at the same time
		isFinished = false
		defer { isFinished = true }
		
		self.sources = [:]

		let sourcesArray = Array(sources)
		let effectiveBatchSize = max(1, batchSize)
		
		for startIndex in stride(from: 0, to: sourcesArray.count, by: effectiveBatchSize) {
			let endIndex = min(startIndex + effectiveBatchSize, sourcesArray.count)
			// Read Core Data objects only on the main actor; child tasks receive value types.
			let requests = (startIndex..<endIndex).compactMap { index -> (Int, URL)? in
				guard let url = sourcesArray[index].sourceURL else { return nil }
				return (index, url)
			}
			
			await withTaskGroup(of: (Int, ASRepository?).self) { group in
				for (index, url) in requests {
					group.addTask {
						let repo: ASRepository? = await withCheckedContinuation { continuation in
							NBFetchService().fetch(from: url) { (result: RepositoryDataHandler) in
								continuation.resume(returning: try? result.get())
							}
						}
						return (index, repo)
					}
				}
				
				for await (index, repo) in group {
					if let repo {
						self.sources[sourcesArray[index]] = repo
					}
				}
			}
		}
	}
}
