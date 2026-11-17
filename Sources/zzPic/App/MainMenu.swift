import AppKit
import ZZPicKit

/// Builds the menu bar in code (no nib).
@MainActor
enum MainMenuBuilder {
    typealias V = ViewerWindowController

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(imageMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(goMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    // MARK: Menus

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "zzPic")
        menu.addItem(item(LF("About %@", "zzPic"), #selector(AppDelegate.showAboutPanel(_:))))
        menu.addItem(.separator())
        let services = NSMenu(title: L("Services"))
        NSApp.servicesMenu = services
        let servicesItem = item(L("Services"), nil)
        servicesItem.submenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item(LF("Hide %@", "zzPic"), #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item(L("Show All"), #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item(LF("Quit %@", "zzPic"), #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L("File"))
        menu.addItem(item(L("Open…"), #selector(AppDelegate.openDocument(_:)), "o"))

        let recent = NSMenu(title: L("Open Recent"))
        recent.addItem(item(L("Clear Menu"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        // Lets NSDocumentController fill this menu automatically.
        let setName = NSSelectorFromString("_setMenuName:")
        if recent.responds(to: setName) { recent.perform(setName, with: "NSRecentDocumentsMenu") }
        let recentItem = item(L("Open Recent"), nil)
        recentItem.submenu = recent
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(item(L("Close"), #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(.separator())
        menu.addItem(item(L("Duplicate"), #selector(V.duplicateImage(_:)), "d"))
        menu.addItem(item(L("Move to Trash"), #selector(V.moveToTrash(_:)), "\u{8}"))
        menu.addItem(.separator())
        menu.addItem(item(L("Show in Finder"), #selector(V.showInFinder(_:)), "r", [.command, .option]))
        menu.addItem(item(L("Edit in Preview"), #selector(V.openInPreview(_:)), "e"))
        menu.addItem(.separator())
        menu.addItem(item(L("Print…"), #selector(V.printImage(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L("Edit"))
        menu.addItem(item(L("Undo"), Selector(("undo:")), "z"))
        menu.addItem(item(L("Redo"), Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item(L("Copy"), #selector(V.copy(_:)), "c"))
        return menu
    }

    private static func imageMenu() -> NSMenu {
        let menu = NSMenu(title: L("Image"))
        menu.addItem(item(L("Rotate Left"), #selector(V.rotateLeft(_:)), "l"))
        menu.addItem(item(L("Rotate Right"), #selector(V.rotateRight(_:)), "r"))
        menu.addItem(.separator())
        menu.addItem(item(L("Crop…"), #selector(V.toggleCrop(_:)), "k"))
        menu.addItem(item(L("Resize…"), #selector(V.resizeImage(_:)), "r", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L("View"))
        menu.addItem(item(L("Zoom In"), #selector(V.zoomIn(_:)), "+"))
        let zoomInAlt = item(L("Zoom In"), #selector(V.zoomIn(_:)), "=")
        zoomInAlt.isHidden = true
        zoomInAlt.allowsKeyEquivalentWhenHidden = true
        menu.addItem(zoomInAlt)
        menu.addItem(item(L("Zoom Out"), #selector(V.zoomOut(_:)), "-"))
        menu.addItem(item(L("Actual Size"), #selector(V.actualSize(_:)), "0"))
        menu.addItem(item(L("Zoom to Fit"), #selector(V.zoomToFit(_:)), "9"))
        menu.addItem(.separator())

        let sort = NSMenu(title: L("Sort By"))
        let orders: [(ImageSortOrder, String)] = [(.name, L("Name")), (.dateModified, L("Date Modified")), (.size, L("Size"))]
        for (order, title) in orders {
            let entry = item(title, #selector(V.changeSortOrder(_:)))
            entry.representedObject = order.rawValue
            sort.addItem(entry)
        }
        let sortItem = item(L("Sort By"), nil)
        sortItem.submenu = sort
        menu.addItem(sortItem)
        menu.addItem(.separator())

        menu.addItem(item(L("Show Filmstrip"), #selector(V.toggleFilmstrip(_:)), "t"))
        menu.addItem(item(L("Show Info"), #selector(V.toggleInspector(_:)), "i"))
        menu.addItem(.separator())
        menu.addItem(item(L("Enter Full Screen"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: L("Go"))
        menu.addItem(item(L("Previous Image"), #selector(V.previousImage(_:)), key(NSLeftArrowFunctionKey), []))
        menu.addItem(item(L("Next Image"), #selector(V.nextImage(_:)), key(NSRightArrowFunctionKey), []))
        menu.addItem(.separator())
        menu.addItem(item(L("First Image"), #selector(V.firstImage(_:)), key(NSHomeFunctionKey), []))
        menu.addItem(item(L("Last Image"), #selector(V.lastImage(_:)), key(NSEndFunctionKey), []))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L("Window"))
        menu.addItem(item(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item(L("Zoom"), #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: L("Help"))
        menu.addItem(item(LF("%@ on GitHub", "zzPic"), #selector(AppDelegate.openRepository(_:))))
        return menu
    }

    // MARK: Helpers

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }

    private static func key(_ functionKey: Int) -> String {
        String(Character(UnicodeScalar(UInt16(functionKey))!))
    }
}
