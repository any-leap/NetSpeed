import AppKit

/// 一个菜单章节。实现者负责自己的 NSMenuItem 生命周期（强引用 item，供 refresh 更新）。
protocol MenuSection: AnyObject {
    /// 变化会影响菜单结构的摘要。相同 = 可原地 refresh；不同 = 必须 rebuild。
    var structureSignature: String { get }

    /// 追加本章节的菜单项到 menu。返回 true 表示本次有内容（MenuBuilder
    /// 会在相邻非空章节间插分隔符）；false = 空章节（条件性章节常用）。
    func addItems(to menu: NSMenu) -> Bool

    /// 菜单打开期间的原地刷新。实现者用自己保存的 item 引用更新 title / color 等。
    func refresh()
}

extension MenuSection {
    /// 默认每个章节前都要分隔符。latency/network 等合并展示的章节可覆盖为 false。
    var needsLeadingSeparator: Bool { true }
}

final class MenuBuilder {
    private let menu: NSMenu
    private(set) var sections: [MenuSection]

    init(menu: NSMenu, sections: [MenuSection]) {
        self.menu = menu
        self.sections = sections
    }

    func rebuild() {
        menu.removeAllItems()
        var previousAdded = false
        for section in sections {
            if previousAdded && section.needsLeadingSeparator {
                menu.addItem(NSMenuItem.separator())
            }
            let added = section.addItems(to: menu)
            if added { previousAdded = true }
        }
    }

    func refresh() {
        for section in sections { section.refresh() }
    }

    var structureSignature: String {
        sections.map(\.structureSignature).joined(separator: "|")
    }
}
