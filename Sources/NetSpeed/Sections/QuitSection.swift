import AppKit

final class QuitSection: MenuSection {
    private let actions: MenuActions

    init(actions: MenuActions) {
        self.actions = actions
    }

    var structureSignature: String { "Q" }

    func addItems(to menu: NSMenu) -> Bool {
        let quitItem = NSMenuItem(title: L10n.quit, action: #selector(MenuActions.quit), keyEquivalent: "q")
        quitItem.target = actions
        menu.addItem(quitItem)
        return true
    }

    func refresh() {
        // Quit 菜单无需刷新
    }
}
