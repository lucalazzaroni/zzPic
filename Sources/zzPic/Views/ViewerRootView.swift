import SwiftUI
import UniformTypeIdentifiers
import ZZPicKit

@MainActor
protocol ViewerActions: AnyObject {
    func openDocument()
    func open(urls: [URL])
    func select(index: Int)
    func undo()
    func cancelCrop()
    func applyCrop(asCopy: Bool)
    func cropAspectChanged()
    func applyResize(width: Int, height: Int, asCopy: Bool)
}

/// Wraps the AppKit canvas so it can live inside the SwiftUI layout.
struct CanvasHost: NSViewRepresentable {
    let canvas: ImageCanvasView
    func makeNSView(context: Context) -> ImageCanvasView { canvas }
    func updateNSView(_ nsView: ImageCanvasView, context: Context) {}
}

struct ViewerRootView: View {
    @Bindable var model: ViewerModel
    let canvas: ImageCanvasView
    let actions: ViewerActions

    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    CanvasHost(canvas: canvas)
                    overlays
                }
                bottomBar
            }
            if model.showInspector, model.current != nil {
                Divider()
                InspectorView(sections: model.metadata)
                    .frame(width: 280)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.showInspector)
        .animation(.easeInOut(duration: 0.2), value: model.isCropping)
        .sheet(item: $model.resizeRequest) { request in
            ResizeSheet(request: request,
                        onCancel: { model.resizeRequest = nil },
                        onApply: { width, height, asCopy in
                            model.resizeRequest = nil
                            actions.applyResize(width: width, height: height, asCopy: asCopy)
                        })
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(from: providers)
            return true
        }
    }

    @ViewBuilder
    private var overlays: some View {
        if model.files.isEmpty {
            EmptyStateView(isTargeted: dropTargeted, open: actions.openDocument)
        } else if let error = model.loadError {
            ErrorStateView(message: error)
        }

        VStack {
            if let hud = model.zoomHUD {
                HUDPill(text: hud)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Spacer()
            if let toast = model.toast {
                ToastView(toast: toast, undo: actions.undo)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.zoomHUD)
        .animation(.spring(duration: 0.35), value: model.toast)

        if model.showSpinner {
            VStack {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small).padding(14)
                }
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if model.isCropping {
            Divider()
            CropBar(model: model, actions: actions)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if model.showFilmstrip, model.files.count > 1 {
            Divider()
            FilmstripView(model: model, select: actions.select)
        }
    }

    private func loadURLs(from providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async { actions.open(urls: [url]) }
            }
        }
    }
}

// MARK: - Small pieces

struct HUDPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
    }
}

struct ToastView: View {
    let toast: Toast
    let undo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.symbol)
                .foregroundStyle(.secondary)
            Text(toast.message)
                .lineLimit(1)
                .truncationMode(.middle)
            if toast.canUndo {
                Divider().frame(height: 14)
                Button(L("Undo"), action: undo)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .fontWeight(.semibold)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        .frame(maxWidth: 520)
    }
}

struct EmptyStateView: View {
    let isTargeted: Bool
    let open: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            Text("zzPic")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(L("Open a picture to browse every image in its folder."))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: open) {
                Label(L("Open Image…"), systemImage: "photo.on.rectangle.angled")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 6)
            Text(L("or drop an image or a folder here"))
                .font(.callout)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(Color.accentColor.opacity(isTargeted ? 0.8 : 0))
                .background(Color.accentColor.opacity(isTargeted ? 0.06 : 0),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(16)
        }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

struct ErrorStateView: View {
    let message: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .zzCanvas))
    }
}
