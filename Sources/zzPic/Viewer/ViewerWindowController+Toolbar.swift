import AppKit
import ZZPicKit

extension NSToolbarItem.Identifier {
    static let navigation = Self("zzpic.navigation")
    static let zoom = Self("zzpic.zoom")
    static let rotate = Self("zzpic.rotate")
    static let crop = Self("zzpic.crop")
    static let resize = Self("zzpic.resize")
    static let share = Self("zzpic.share")
    static let trash = Self("zzpic.trash")
    static let inspector = Self("zzpic.inspector")
    static let print = Self("zzpic.print")
    static let duplicate = Self("zzpic.duplicate")
    static let preview = Self("zzpic.preview")
    static let filmstrip = Self("zzpic.filmstrip")
}

extension ViewerWindowController: NSToolbarDelegate, NSSharingServicePickerToolbarItemDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.navigation, .flexibleSpace, .zoom, .rotate, .crop, .resize, .space, .share, .trash, .inspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.navigation, .zoom, .rotate, .crop, .resize, .share, .trash, .inspector,
         .print, .duplicate, .preview, .filmstrip, .space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .navigation:
            return group(id, label: L("Navigate"), [
                ("chevron.left", L("Previous"), #selector(previousImage(_:))),
                ("chevron.right", L("Next"), #selector(nextImage(_:))),
            ])
        case .zoom:
            return group(id, label: L("Zoom"), [
                ("minus.magnifyingglass", L("Zoom Out"), #selector(zoomOut(_:))),
                ("plus.magnifyingglass", L("Zoom In"), #selector(zoomIn(_:))),
            ])
        case .rotate:
            return group(id, label: L("Rotate"), [
                ("rotate.left", L("Rotate Left"), #selector(rotateLeft(_:))),
                ("rotate.right", L("Rotate Right"), #selector(rotateRight(_:))),
            ])
        case .crop:
            return button(id, "crop", L("Crop"), #selector(toggleCrop(_:)))
        case .resize:
            return button(id, "arrow.up.left.and.arrow.down.right", L("Resize"), #selector(resizeImage(_:)))
        case .trash:
            return button(id, "trash", L("Move to Trash"), #selector(moveToTrash(_:)))
        case .inspector:
            return button(id, "info.circle", L("Info"), #selector(toggleInspector(_:)))
        case .print:
            return button(id, "printer", L("Print"), #selector(printImage(_:)))
        case .duplicate:
            return button(id, "plus.square.on.square", L("Duplicate"), #selector(duplicateImage(_:)))
        case .preview:
            return button(id, "pencil.and.outline", L("Edit in Preview"), #selector(openInPreview(_:)))
        case .filmstrip:
            return button(id, "rectangle.split.3x1", L("Filmstrip"), #selector(toggleFilmstrip(_:)))
        case .share:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: id)
            item.delegate = self
            item.label = L("Share")
            item.paletteLabel = L("Share")
            item.toolTip = L("Share")
            return item
        default:
            return nil
        }
    }

    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        model.current.map { [$0] } ?? []
    }

    func updateShareItem() {
        let enabled = model.current != nil && !model.isCropping
        window?.toolbar?.items.first { $0.itemIdentifier == .share }?.isEnabled = enabled
    }

    private func button(_ id: NSToolbarItem.Identifier, _ symbol: String, _ label: String,
                        _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = true
        return item
    }

    private func group(_ id: NSToolbarItem.Identifier, label: String,
                       _ parts: [(symbol: String, label: String, action: Selector)]) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: id)
        group.subitems = parts.enumerated().map { index, part in
            button(NSToolbarItem.Identifier("\(id.rawValue).\(index)"), part.symbol, part.label, part.action)
        }
        group.label = label
        group.paletteLabel = label
        return group
    }
}
