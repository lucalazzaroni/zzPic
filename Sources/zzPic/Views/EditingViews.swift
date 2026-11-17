import SwiftUI
import ZZPicKit

/// Bottom bar shown while cropping.
struct CropBar: View {
    @Bindable var model: ViewerModel
    let actions: ViewerActions

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "crop")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            Picker(L("Aspect Ratio"), selection: $model.cropAspect) {
                ForEach(CropAspect.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .labelsHidden()
            .fixedSize()

            Button {
                model.cropPortrait.toggle()
            } label: {
                Image(systemName: model.cropPortrait ? "rectangle.portrait" : "rectangle")
            }
            .disabled(!model.cropAspect.canFlip)
            .help(L("Swap Orientation"))

            Text(verbatim: "\(Int(model.cropPixelSize.width)) × \(Int(model.cropPixelSize.height)) px")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Button(L("Cancel"), action: actions.cancelCrop)
                .keyboardShortcut(.cancelAction)
            Button(L("Save as Copy")) { actions.applyCrop(asCopy: true) }
            Button(L("Crop")) { actions.applyCrop(asCopy: false) }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canOverwrite)
        }
        .controlSize(.regular)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
        .onChange(of: model.cropAspect) { actions.cropAspectChanged() }
        .onChange(of: model.cropPortrait) { actions.cropAspectChanged() }
    }
}

/// "Resize Image" sheet.
struct ResizeSheet: View {
    let request: ResizeRequest
    let onCancel: () -> Void
    let onApply: (_ width: Int, _ height: Int, _ asCopy: Bool) -> Void

    @State private var widthText: String
    @State private var heightText: String
    @State private var keepProportions = true

    init(request: ResizeRequest, onCancel: @escaping () -> Void,
         onApply: @escaping (_ width: Int, _ height: Int, _ asCopy: Bool) -> Void) {
        self.request = request
        self.onCancel = onCancel
        self.onApply = onApply
        _widthText = State(initialValue: String(Int(request.pixelSize.width)))
        _heightText = State(initialValue: String(Int(request.pixelSize.height)))
    }

    private var aspect: Double { request.pixelSize.width / max(1, request.pixelSize.height) }
    private var width: Int? { Int(widthText).flatMap { (1...60_000).contains($0) ? $0 : nil } }
    private var height: Int? { Int(heightText).flatMap { (1...60_000).contains($0) ? $0 : nil } }

    private var widthBinding: Binding<String> {
        Binding(get: { widthText }, set: { text in
            widthText = text.filter(\.isNumber)
            if keepProportions, let w = Int(widthText) {
                heightText = String(max(1, Int((Double(w) / aspect).rounded())))
            }
        })
    }

    private var heightBinding: Binding<String> {
        Binding(get: { heightText }, set: { text in
            heightText = text.filter(\.isNumber)
            if keepProportions, let h = Int(heightText) {
                widthText = String(max(1, Int((Double(h) * aspect).rounded())))
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Resize Image")).font(.headline)
                    Text(LF("Current size: %ld × %ld px", Int(request.pixelSize.width), Int(request.pixelSize.height)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text(L("Width:")).gridColumnAlignment(.trailing)
                    TextField("", text: widthBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("px").foregroundStyle(.secondary)
                }
                GridRow {
                    Text(L("Height:"))
                    TextField("", text: heightBinding)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                    Text("px").foregroundStyle(.secondary)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle(L("Keep proportions"), isOn: $keepProportions)
                        .toggleStyle(.checkbox)
                        .gridCellColumns(2)
                }
            }

            HStack(spacing: 6) {
                ForEach([25, 50, 75], id: \.self) { percent in
                    Button(String("\(percent)%")) { scale(Double(percent) / 100) }
                }
                Menu(L("Longest side")) {
                    ForEach([3840, 2560, 1920, 1600, 1280, 1024, 800, 640], id: \.self) { side in
                        Button(String("\(side) px")) { longestSide(side) }
                    }
                }
                .fixedSize()
            }
            .controlSize(.small)

            HStack {
                Spacer()
                Button(L("Cancel"), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(L("Save as Copy")) {
                    if let width, let height { onApply(width, height, true) }
                }
                .disabled(width == nil || height == nil)
                if request.canOverwrite {
                    Button(L("Resize")) {
                        if let width, let height { onApply(width, height, false) }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(width == nil || height == nil)
                }
            }
        }
        .padding(22)
        .frame(width: 400)
    }

    private func scale(_ factor: Double) {
        widthText = String(max(1, Int((request.pixelSize.width * factor).rounded())))
        heightText = String(max(1, Int((request.pixelSize.height * factor).rounded())))
    }

    private func longestSide(_ side: Int) {
        let longest = max(request.pixelSize.width, request.pixelSize.height)
        scale(Double(side) / max(1, longest))
    }
}
