import AppKit
import SwiftUI

/// 设置窗口。只从菜单的「设置…」打开；窗口不参与系统窗口恢复，
/// 所以开机/登录时不会自己弹出来（之前空白 Settings 窗口的教训）。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private let model = SettingsModel(prefs: .shared)

    override init() {
        super.init()
        // 从菜单「退出」时窗口不走 windowWillClose，也要把没提交的列表存下来。
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.model.commitLists() }
    }

    func windowWillClose(_ notification: Notification) {
        model.commitLists()
    }

    func show() {
        model.reload()
        let win = window ?? makeWindow()
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = []
        let win = NSWindow(contentViewController: hosting)
        win.title = L10n.settingsWindowTitle
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 560, height: 720))
        win.contentMinSize = NSSize(width: 480, height: 400)
        win.isRestorable = false
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        return win
    }
}

final class SettingsModel: ObservableObject {
    private let prefs: Preferences
    /// reload() 时置位，避免回填 UI 的过程又写回 UserDefaults。
    private var loading = false

    @Published var threshold: Double = 0 { didSet { if !loading { prefs.cpuThreshold = threshold } } }
    @Published var sustained: Int = 0 { didSet { if !loading { prefs.sustainedSeconds = sustained } } }
    // 多行列表是草稿，离开输入框 / 关窗 / 退出时才提交：逐字保存的话，打到一半的
    // 「ssh」会被当成关注进程触发「未运行」通知，「https://www.ba」会被拿去测速。
    @Published var ignoredText = ""
    @Published var watchedText = ""
    @Published var cnText = ""
    @Published var intlText = ""
    @Published var cnError: String?
    @Published var intlError: String?
    @Published var configPath: String?
    @Published var authPath: String?

    init(prefs: Preferences) {
        self.prefs = prefs
        reload()
    }

    func reload() {
        loading = true
        defer { loading = false }
        threshold = prefs.cpuThreshold
        sustained = prefs.sustainedSeconds
        ignoredText = prefs.ignoredProcesses.joined(separator: "\n")
        watchedText = prefs.watchedProcesses.joined(separator: "\n")
        cnText = prefs.latencyTargetsCN.joined(separator: "\n")
        intlText = prefs.latencyTargetsIntl.joined(separator: "\n")
        cnError = nil
        intlError = nil
        configPath = prefs.openVPNConfigPath
        authPath = prefs.openVPNAuthPath
    }

    func commitLists() {
        let ignored = Preferences.parseList(ignoredText)
        if ignored != prefs.ignoredProcesses { prefs.ignoredProcesses = ignored }
        let watched = Preferences.parseList(watchedText)
        if watched != prefs.watchedProcesses { prefs.watchedProcesses = watched }
        cnError = saveTargets(cnText, current: prefs.latencyTargetsCN) { self.prefs.latencyTargetsCN = $0 }
        intlError = saveTargets(intlText, current: prefs.latencyTargetsIntl) { self.prefs.latencyTargetsIntl = $0 }
    }

    func resetMonitoringDefaults() {
        prefs.resetMonitoringDefaults()
        reload()
    }

    func chooseConfig() {
        guard let path = pickFile(title: L10n.settingsOpenVPNConfig) else { return }
        prefs.openVPNConfigPath = path
        configPath = path
    }

    func clearConfig() {
        prefs.openVPNConfigPath = nil
        configPath = nil
    }

    func chooseAuth() {
        guard let path = pickFile(title: L10n.settingsOpenVPNAuth) else { return }
        prefs.openVPNAuthPath = path
        authPath = path
    }

    func useDefaultAuth() {
        prefs.openVPNAuthPath = nil
        authPath = nil
    }

    /// 合法就保存并返回 nil，否则返回错误文案、不保存。
    private func saveTargets(_ text: String, current: [String], _ save: ([String]) -> Void) -> String? {
        let list = Preferences.parseList(text)
        if list.isEmpty { return L10n.settingsNeedOneURL }
        let invalid = Preferences.invalidLatencyTargets(list)
        if !invalid.isEmpty { return L10n.settingsInvalidURLs(invalid) }
        if list != current { save(list) }
        return nil
    }

    private func pickFile(title: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @FocusState private var focused: ListField?

    enum ListField { case ignored, watched, cn, intl }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    LabeledContent(L10n.settingsThreshold) {
                        HStack {
                            Slider(value: $model.threshold, in: Preferences.cpuThresholdRange)
                            Text("\(Int(model.threshold))%")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                    Text(L10n.settingsThresholdHelp).font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $model.sustained,
                        in: Preferences.sustainedSecondsRange,
                        step: Preferences.sustainedSecondsStep) {
                    LabeledContent(L10n.settingsSustained, value: L10n.seconds(model.sustained))
                }
                listEditor(L10n.settingsIgnored, text: $model.ignoredText, field: .ignored, help: L10n.settingsIgnoredHelp)
            } header: {
                Text(L10n.settingsCPUSection)
            }

            Section(L10n.settingsWatchedSection) {
                listEditor(nil, text: $model.watchedText, field: .watched, help: L10n.settingsWatchedHelp, height: 48)
            }

            Section {
                listEditor(L10n.latencyMainland, text: $model.cnText, field: .cn, error: model.cnError)
                listEditor(L10n.latencyOverseas, text: $model.intlText, field: .intl, error: model.intlError)
            } header: {
                Text(L10n.settingsLatencySection)
            } footer: {
                Text(L10n.settingsLatencyHelp).foregroundStyle(.secondary)
            }

            Section {
                fileRow(L10n.settingsOpenVPNConfig, path: model.configPath, placeholder: L10n.settingsNotSet) {
                    Button(L10n.settingsChoose) { model.chooseConfig() }
                    Button(L10n.settingsClear) { model.clearConfig() }.disabled(model.configPath == nil)
                }
                fileRow(L10n.settingsOpenVPNAuth, path: model.authPath,
                        placeholder: Preferences.defaultOpenVPNAuthPath + L10n.settingsDefaultSuffix,
                        checkPath: model.authPath ?? Preferences.defaultOpenVPNAuthPath) {
                    Button(L10n.settingsChoose) { model.chooseAuth() }
                    Button(L10n.settingsUseDefault) { model.useDefaultAuth() }.disabled(model.authPath == nil)
                }
            } header: {
                Text(L10n.settingsOpenVPNSection)
            } footer: {
                Text(L10n.settingsOpenVPNHelp).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(L10n.settingsLiveNote).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.settingsReset) { model.resetMonitoringDefaults() }
                        .help(L10n.settingsResetHelp)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: focused) { model.commitLists() }
    }

    @ViewBuilder
    private func listEditor(_ title: String?, text: Binding<String>, field: ListField, help: String? = nil,
                            error: String? = nil, height: CGFloat = 72) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { Text(title) }
            TextEditor(text: text)
                .focused($focused, equals: field)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(4)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .stroke(error == nil ? Color.secondary.opacity(0.3) : Color.red, lineWidth: 1))
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else if let help {
                Text(help).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fileRow<Buttons: View>(_ title: String, path: String?, placeholder: String,
                                        checkPath: String? = nil,
                                        @ViewBuilder buttons: () -> Buttons) -> some View {
        let shown = checkPath ?? path
        let missing = shown.map { !FileManager.default.fileExists(atPath: $0) } ?? false
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                buttons()
            }
            Text(path.map(Self.abbreviate) ?? Self.abbreviate(placeholder))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(path == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            if missing {
                Text(L10n.settingsMissingFile).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private static func abbreviate(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }
}
