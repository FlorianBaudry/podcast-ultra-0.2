import SwiftUI
import UIKit

// MARK: – Shared image cache (64 MB memory, 256 MB disk) + Decoded UIImage NSCache
private let imageCache: URLCache = {
    let cache = URLCache(
        memoryCapacity: 64 * 1024 * 1024,
        diskCapacity:   256 * 1024 * 1024,
        diskPath:       "com.podcastultra.imagecache"
    )
    return cache
}()

final class DecodedImageMemoryCache: @unchecked Sendable {
    static let shared = DecodedImageMemoryCache()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 96 * 1024 * 1024
    }
    
    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }
    
    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: url.absoluteString as NSString, cost: cost)
    }
}

private let imageSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.urlCache = imageCache
    config.requestCachePolicy = .returnCacheDataElseLoad
    config.httpMaximumConnectionsPerHost = 8
    config.timeoutIntervalForRequest = 20
    return URLSession(configuration: config)
}()

// MARK: – CachedAsyncImage
/// High-performance drop-in replacement for AsyncImage that keeps decoded UIImages in NSCache
/// and compressed responses in URLCache for 120Hz zero-hitch scrolling.
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let maxPixelSize: CGFloat
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var uiImage: UIImage?
    @State private var loadedURL: URL?
    @State private var task: Task<Void, Never>? = nil

    init(
        url: URL?,
        maxPixelSize: CGFloat = 500,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.maxPixelSize = maxPixelSize
        self.content = content
        self.placeholder = placeholder
        if let url, let memCached = DecodedImageMemoryCache.shared.image(for: url) {
            _uiImage = State(initialValue: memCached)
            _loadedURL = State(initialValue: url)
        } else {
            _uiImage = State(initialValue: nil)
            _loadedURL = State(initialValue: nil)
        }
    }

    var body: some View {
        Group {
            if let currentImg = resolvedImage {
                content(Image(uiImage: currentImg))
            } else {
                placeholder()
            }
        }
        .onAppear { loadIfNeeded() }
        .onDisappear { task?.cancel(); task = nil }
        .onChange(of: url) { _, newURL in
            if let newURL, let mem = DecodedImageMemoryCache.shared.image(for: newURL) {
                uiImage = mem
                loadedURL = newURL
            } else {
                uiImage = nil
                loadedURL = nil
                loadIfNeeded()
            }
        }
    }
    
    private var resolvedImage: UIImage? {
        if let url, loadedURL == url, let uiImage {
            return uiImage
        }
        if let url, let mem = DecodedImageMemoryCache.shared.image(for: url) {
            return mem
        }
        return uiImage
    }

    private func loadIfNeeded() {
        guard let url else { return }
        if let mem = DecodedImageMemoryCache.shared.image(for: url) {
            if uiImage !== mem || loadedURL != url {
                uiImage = mem
                loadedURL = url
            }
            return
        }

        let targetMaxDimension = maxPixelSize
        task?.cancel()
        task = Task.detached(priority: .utility) {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            
            // 1. Check disk/memory URLCache off the main thread
            if let cached = imageCache.cachedResponse(for: request),
               let decoded = Self.decodeAndDownsample(data: cached.data, maxDimension: targetMaxDimension) {
                DecodedImageMemoryCache.shared.insert(decoded, for: url)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self.uiImage = decoded
                    self.loadedURL = url
                }
                return
            }

            // 2. Network fetch
            do {
                let (data, response) = try await imageSession.data(for: request)
                guard !Task.isCancelled else { return }

                if let httpResp = response as? HTTPURLResponse, (200..<300).contains(httpResp.statusCode) {
                    imageCache.storeCachedResponse(
                        CachedURLResponse(response: httpResp, data: data),
                        for: request
                    )
                }

                if let decoded = Self.decodeAndDownsample(data: data, maxDimension: targetMaxDimension) {
                    DecodedImageMemoryCache.shared.insert(decoded, for: url)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        self.uiImage = decoded
                        self.loadedURL = url
                    }
                }
            } catch {
                // Ignore cancelled or failed image loads
            }
        }
    }
    
    nonisolated private static func decodeAndDownsample(data: Data, maxDimension: CGFloat) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longestSide = max(size.width, size.height)
        if longestSide > maxDimension, longestSide > 0 {
            let scale = maxDimension / longestSide
            let targetSize = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
            if let thumb = image.preparingThumbnail(of: targetSize) {
                return thumb
            }
        }
        return image.preparingForDisplay() ?? image
    }
}
