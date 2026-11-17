import SwiftUI
import ZZPicKit

/// Side panel with file and EXIF details.
struct InspectorView: View {
    let sections: [MetadataSection]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(section.title.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.7)
                            .foregroundStyle(.secondary)
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 7) {
                            ForEach(section.rows) { row in
                                GridRow {
                                    Text(row.label)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                        .lineLimit(1)
                                    value(for: row)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }

    @ViewBuilder
    private func value(for row: MetadataRow) -> some View {
        if let link = row.link {
            Link(row.value, destination: link)
        } else {
            Text(row.value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
