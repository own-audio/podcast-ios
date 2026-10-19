import Foundation
import UIKit

/// Show and episode pictures, cached in memory and on disk at the size they are drawn. Shaped
/// like the books app's `CoverLoader`. Keyed by the address without a signature query
/// (own.audio's `?e=…&s=…` changes each week), so a re-signed link finds the same picture, and
/// pictures already seen show offline.
actor ArtworkLoader {
    static let shared = ArtworkLoader()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("artwork", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.countLimit = 400
    }

    /// The picture at `url`, scaled to `pixels` on its longer side.
    func image(_ url: URL, pixels: Int) async -> UIImage? {
        let key = Self.key(url) + "@\(pixels)"
        if let cached = memory.object(forKey: key as NSString) { return cached }
        if let task = inFlight[key] { return await task.value }
        let task = Task { await load(url, key: key, pixels: pixels) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }

    private func load(_ url: URL, key: String, pixels: Int) async -> UIImage? {
        let file = directory.appendingPathComponent(Self.fileName(key))
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        var request = URLRequest(url: url)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        request.setValue("own.audio Podcasts/\(version) iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let full = UIImage(data: data) else { return nil }
        let image = Self.scaled(full, pixels: pixels)
        memory.setObject(image, forKey: key as NSString)
        if let jpeg = image.jpegData(compressionQuality: 0.85) { try? jpeg.write(to: file, options: .atomic) }
        return image
    }

    /// The address without a signature, so a newly signed link is the same picture.
    static func key(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        let signature: Set<String> = ["e", "s", "exp", "sig", "token", "X-Amz-Signature", "X-Amz-Date", "X-Amz-Expires", "X-Amz-Credential", "X-Amz-SignedHeaders", "X-Amz-Algorithm"]
        parts.queryItems = parts.queryItems?.filter { !signature.contains($0.name) }
        if parts.queryItems?.isEmpty == true { parts.queryItems = nil }
        return parts.string ?? url.absoluteString
    }

    private static func fileName(_ key: String) -> String {
        Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").prefix(200) + ".jpg"
    }

    private static func scaled(_ image: UIImage, pixels: Int) -> UIImage {
        let longer = max(image.size.width, image.size.height) * image.scale
        guard longer > CGFloat(pixels) else { return image }
        let factor = CGFloat(pixels) / longer
        let size = CGSize(width: image.size.width * image.scale * factor, height: image.size.height * image.scale * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}
