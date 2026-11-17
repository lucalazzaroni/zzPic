import Foundation
import ImageIO

public struct MetadataRow: Identifiable, Sendable {
    public let id = UUID()
    public let label: String
    public let value: String
    public let link: URL?

    public init(_ label: String, _ value: String, link: URL? = nil) {
        self.label = label
        self.value = value
        self.link = link
    }
}

public struct MetadataSection: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let rows: [MetadataRow]
}

/// Human-readable file and EXIF information for the inspector.
public enum ImageMetadata {
    public static func sections(for url: URL) -> [MetadataSection] {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        let props = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]

        let dates = DateFormatter()
        dates.dateStyle = .medium
        dates.timeStyle = .short

        var sections: [MetadataSection] = [generalSection(for: url)]


        // Image
        var image: [MetadataRow] = []
        if var w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
           var h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue {
            let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
            if ExifOrientation.swapsDimensions(orientation) { swap(&w, &h) }
            let mp = Double(w * h) / 1_000_000
            let mpText = mp >= 0.1 ? String(format: " (%.1f MP)", mp) : ""
            image.append(MetadataRow(L("Dimensions"), "\(w) × \(h)\(mpText)"))
        }
        if let model = props[kCGImagePropertyColorModel] as? String {
            let depth = (props[kCGImagePropertyDepth] as? NSNumber)?.intValue
            image.append(MetadataRow(L("Color"), depth.map { LF("%@, %ld bit", model, $0) } ?? model))
        }
        if let profile = props[kCGImagePropertyProfileName] as? String {
            image.append(MetadataRow(L("Profile"), profile))
        }
        if let dpi = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue {
            image.append(MetadataRow(L("Resolution"), String(format: "%.0f dpi", dpi)))
        }
        if let alpha = props[kCGImagePropertyHasAlpha] as? Bool {
            image.append(MetadataRow(L("Transparency"), alpha ? L("Yes") : L("No")))
        }
        if !image.isEmpty { sections.append(MetadataSection(title: L("Image"), rows: image)) }

        // Camera
        var camera: [MetadataRow] = []
        let make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        let model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        if let model {
            let name = (make.map { model.lowercased().hasPrefix($0.lowercased()) } ?? true) ? model : "\(make!) \(model)"
            camera.append(MetadataRow(L("Model"), name))
        }
        if let lens = exif[kCGImagePropertyExifLensModel] as? String {
            camera.append(MetadataRow(L("Lens"), lens))
        }
        if let taken = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "yyyy:MM:dd HH:mm:ss"
            camera.append(MetadataRow(L("Taken"), parser.date(from: taken).map { dates.string(from: $0) } ?? taken))
        }
        if let focal = (exif[kCGImagePropertyExifFocalLength] as? NSNumber)?.doubleValue {
            var text = String(format: "%g mm", (focal * 10).rounded() / 10)
            if let eq = (exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? NSNumber)?.intValue, eq > 0 {
                text += " " + LF("(%ld mm equiv.)", eq)
            }
            camera.append(MetadataRow(L("Focal Length"), text))
        }
        if let f = (exif[kCGImagePropertyExifFNumber] as? NSNumber)?.doubleValue {
            camera.append(MetadataRow(L("Aperture"), String(format: "ƒ/%g", (f * 10).rounded() / 10)))
        }
        if let t = (exif[kCGImagePropertyExifExposureTime] as? NSNumber)?.doubleValue, t > 0 {
            let text = t < 1 ? "1/\(Int((1 / t).rounded())) s" : String(format: "%g s", t)
            camera.append(MetadataRow(L("Exposure"), text))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            camera.append(MetadataRow("ISO", iso.stringValue))
        }
        if let flash = (exif[kCGImagePropertyExifFlash] as? NSNumber)?.intValue {
            camera.append(MetadataRow(L("Flash"), flash & 1 == 1 ? L("Fired") : L("Off")))
        }
        if !camera.isEmpty { sections.append(MetadataSection(title: L("Camera"), rows: camera)) }

        // Location
        if var lat = (gps[kCGImagePropertyGPSLatitude] as? NSNumber)?.doubleValue,
           var lon = (gps[kCGImagePropertyGPSLongitude] as? NSNumber)?.doubleValue {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            let text = String(format: "%.5f° %@, %.5f° %@", abs(lat), lat >= 0 ? "N" : "S", abs(lon), lon >= 0 ? "E" : "W")
            let link = URL(string: String(format: "https://maps.apple.com/?ll=%.6f,%.6f&q=%.6f,%.6f", lat, lon, lat, lon))
            var rows = [MetadataRow(L("Coordinates"), text, link: link)]
            if let alt = (gps[kCGImagePropertyGPSAltitude] as? NSNumber)?.doubleValue {
                rows.append(MetadataRow(L("Altitude"), String(format: "%.0f m", alt)))
            }
            sections.append(MetadataSection(title: L("Location"), rows: rows))
        }

        return sections
    }

    /// Name, kind, size, dates and folder.
    public static func generalSection(for url: URL) -> MetadataSection {
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
        ])
        let dates = DateFormatter()
        dates.dateStyle = .medium
        dates.timeStyle = .short
        var file: [MetadataRow] = [MetadataRow(L("Name"), url.lastPathComponent)]
        if let kind = values?.localizedTypeDescription { file.append(MetadataRow(L("Kind"), kind)) }
        if let size = values?.fileSize {
            file.append(MetadataRow(L("Size"), ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if let created = values?.creationDate { file.append(MetadataRow(L("Created"), dates.string(from: created))) }
        if let modified = values?.contentModificationDate { file.append(MetadataRow(L("Modified"), dates.string(from: modified))) }
        file.append(MetadataRow(L("Where"), (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
        return MetadataSection(title: L("General"), rows: file)
    }

    public static func sections(for video: VideoInfo) -> [MetadataSection] {
        var rows = [
            MetadataRow(L("Dimensions"), "\(Int(video.pixelSize.width)) × \(Int(video.pixelSize.height))"),
            MetadataRow(L("Duration"), video.durationText),
        ]
        if video.frameRate > 0 { rows.append(MetadataRow(L("Frame Rate"), String(format: "%.3g fps", video.frameRate))) }
        if let codec = video.codec { rows.append(MetadataRow(L("Codec"), codec)) }
        rows.append(MetadataRow(L("Audio"), video.hasAudio ? L("Yes") : L("No")))
        return [generalSection(for: video.url), MetadataSection(title: L("Video"), rows: rows)]
    }
}
