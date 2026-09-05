# Changelog

## Unreleased

- Add a separate **Keep Running with Lid Closed** menu switch. It requires macOS administrator authorization and disables system sleep globally for up to two hours. The session restores sleep when stopped, when NetSpeed exits, or when battery power falls to 20%.
- Add **Restore System Sleep** for settings left behind after an interrupted session. Sudden power loss or forcibly killing the privileged watchdog may require this recovery action after restart.
- Clarify that the existing caffeine switch prevents idle sleep only; it does not prevent sleep when the lid closes.

Closed-lid operation continues to consume power and generate heat. Keep the Mac ventilated. Preventing sleep cannot preserve a network connection when Wi-Fi coverage is lost.
