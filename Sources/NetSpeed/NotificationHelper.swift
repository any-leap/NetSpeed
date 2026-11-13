import Foundation

final class NotificationHelper {
    func send(title: String, message: String) {
        // 标题/正文含进程名（任意进程都能给自己起名），不能拼进脚本源码：
        // 只转义引号挡不住反斜杠，能跳出字符串执行任意 AppleScript。走 argv 传值。
        let script = """
        on run argv
            display notification (item 2 of argv) with title (item 1 of argv) sound name "Sosumi"
        end run
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, title, message]
        try? process.run()
        process.waitUntilExit()
    }
}
