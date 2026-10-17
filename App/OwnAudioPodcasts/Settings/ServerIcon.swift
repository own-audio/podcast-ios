import SwiftUI
import UIKit

/// Which picture marks a server: its own logo where the project's licence lets this app carry
/// it (own.audio, podfetch), a symbol otherwise. Audiobookshelf's and gPodder's logos are part
/// of their GPL code, with no separate licence for the artwork, so they are not copied here.
enum ServerBrand {
    case ownAudio, podfetch, audiobookshelf, gpodder, phone

    init(_ record: ServerRecord) {
        switch record.kind {
        case .ownAudio: self = .ownAudio
        case .audiobookshelf: self = .audiobookshelf
        case .gpodder: self = record.software == "podfetch" ? .podfetch : .gpodder
        }
    }

    var assetName: String? {
        switch self {
        case .ownAudio: "ServerLogo"
        case .podfetch: "PodfetchLogo"
        default: nil
        }
    }

    var symbol: String {
        switch self {
        case .ownAudio: "person.3"
        case .podfetch, .gpodder: "arrow.triangle.2.circlepath"
        case .audiobookshelf: "books.vertical"
        case .phone: "iphone"
        }
    }
}

/// A server's picture in a list, on a rounded tile.
struct ServerIcon: View {
    let brand: ServerBrand
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let name = brand.assetName {
                Image(name).resizable().scaledToFit()
            } else {
                ZStack {
                    Theme.Colors.backgroundAlt
                    Image(systemName: brand.symbol)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

extension ServerBrand {
    /// The same for a menu row, as the music app draws it: menus show a custom picture at its own
    /// size, so the logo is drawn here at the size of a menu's symbols.
    @MainActor
    func menuIcon(dark: Bool, side: CGFloat = 22) -> Image {
        guard let name = assetName,
              let source = UIImage(named: name, in: nil, compatibleWith: UITraitCollection(userInterfaceStyle: dark ? .dark : .light)) else {
            return Image(systemName: symbol)
        }
        let scale = min(side / source.size.width, side / source.size.height)
        let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let small = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            source.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2, width: drawn.width, height: drawn.height))
        }
        return Image(uiImage: small).renderingMode(.original)
    }
}
