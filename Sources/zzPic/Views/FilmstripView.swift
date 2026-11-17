import SwiftUI
import ZZPicKit

/// Horizontal strip of thumbnails of the folder, like a contact sheet.
struct FilmstripView: View {
    let model: ViewerModel
    let select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(Array(model.files.enumerated()), id: \.element) { index, url in
                        ThumbnailCell(url: url, isSelected: index == model.index, revision: model.revision(of: url),
                                      isVideo: FolderScanner.isVideoFile(url))
                            .id(url)
                            .onTapGesture { select(index) }
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 78)
            }
            .onAppear {
                DispatchQueue.main.async { scroll(proxy, animated: false) }
            }
            .onChange(of: model.index) { scroll(proxy, animated: true) }
            .onChange(of: model.files) { scroll(proxy, animated: false) }
        }
        .frame(height: 78)
        .background(.bar)
    }

    private func scroll(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let url = model.current else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.22)) { proxy.scrollTo(url, anchor: .center) }
        } else {
            proxy.scrollTo(url, anchor: .center)
        }
    }
}

struct ThumbnailCell: View {
    let url: URL
    let isSelected: Bool
    let revision: Int
    let isVideo: Bool

    @State private var image: CGImage?
    @State private var hovering = false

    private let side: CGFloat = 54

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.07))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipped()
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .bottomLeading) {
            if isVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(.black.opacity(0.5), in: Circle())
                    .padding(4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                .padding(-3.5)
                .opacity(isSelected ? 1 : 0)
        }
        .opacity(isSelected || hovering ? 1 : 0.7)
        .scaleEffect(isSelected ? 1.0 : 0.94)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(url.lastPathComponent)
        .task(id: "\(url.path)#\(revision)") {
            if let cached = ThumbnailProvider.shared.cachedThumbnail(for: url) {
                image = cached
                return
            }
            image = await ThumbnailProvider.shared.thumbnail(for: url)
        }
    }
}
