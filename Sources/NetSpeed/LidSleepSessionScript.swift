import Foundation

/// Only fixed inline code is elevated. The user-owned marker is checked for existence,
/// never sourced; all privileged writes stay inside a root-owned lock directory.
struct LidSleepSessionScript {
    struct Paths {
        var pmset = "/usr/bin/pmset"
        var lock = "/var/run/com.t3st.netspeed.lid-awake"
        var interval = "2"
        var duration = 7200
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScript(_ shell: String) -> String {
        let command = "/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin /bin/sh -c " + quote(shell)
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "with timeout of 86400 seconds\ndo shell script \"\(escaped)\" with administrator privileges\nend timeout"
    }

    static func watchdog(marker: String, token: String, pid: Int32, uid: UInt32,
                         paths: Paths = Paths()) -> String {
        """
        PATH=/usr/bin:/bin:/usr/sbin:/sbin
        export PATH
        umask 022
        pmset=\(quote(paths.pmset))
        lock=\(quote(paths.lock))
        # Keep one inode: unlinking a flock file would let new callers bypass it.
        umask 077
        exec 9>"$lock.guard" || exit 73
        /usr/bin/lockf -s -t 0 9 || { echo 'Another session or recovery is running.' >&2; exit 73; }
        umask 022
        marker=\(quote(marker))
        token=\(quote(token))
        owner=\(pid)
        owner_uid=\(uid)
        state() { "$pmset" -g | /usr/bin/awk '$1 == "SleepDisabled" {print $2}'; }
        identity() { /bin/ps -p "$owner" -o uid= -o lstart=; }
        battery() {
            "$pmset" -g batt | /usr/bin/awk '
                /AC Power/ {ac=1}
                /Battery Power/ {batt=1}
                /%/ {if (match($0, /[0-9]+%/)) pct=substr($0,RSTART,RLENGTH-1)}
                END {if(ac) print "AC"; else if(batt && pct != "") print pct; else print "unknown"}'
        }
        check_battery() {
            level=$(battery)
            case "$level" in
                AC) return 0;;
                unknown|*[!0-9]*|'') echo 'Cannot read battery state.' >&2; return 1;;
                *) [ "$level" -gt 20 ] || { echo 'Battery is at or below 20%.' >&2; return 1; };;
            esac
        }
        [ -f "$marker" ] || exit 0
        original_identity=$(identity)
        actual_uid=$(/bin/ps -p "$owner" -o uid= | /usr/bin/tr -d ' ')
        [ "$actual_uid" = "$owner_uid" ] && [ -n "$original_identity" ] || exit 0
        /bin/mkdir "$lock" || { echo 'Another session or recovery is pending.' >&2; exit 73; }
        owned=0
        finish() {
            result=$1
            trap - EXIT HUP INT TERM
            if [ "$owned" = 1 ]; then
                restored=0
                for attempt in 1 2 3; do
                    if "$pmset" -a disablesleep 0 && [ "$(state)" = 0 ]; then restored=1; break; fi
                    /bin/sleep 1
                done
                if [ "$restored" != 1 ]; then
                    echo 'Could not restore system sleep. Use Restore System Sleep in NetSpeed.' >&2
                    exit 74
                fi
            fi
            /bin/rm -f "$lock/$token" "$lock/pid" "$lock/identity" || exit 74
            /bin/rmdir "$lock" || exit 74
            exit "$result"
        }
        trap 'finish $?' EXIT
        trap 'exit 0' HUP INT TERM
        echo "$$" > "$lock/pid" || exit 70
        /bin/ps -p $$ -o lstart= > "$lock/identity" || exit 70
        [ "$(state)" = 0 ] || { echo 'System sleep is already disabled or unreadable.' >&2; exit 65; }
        check_battery || exit 65
        [ -f "$marker" ] && [ "$(identity)" = "$original_identity" ] || exit 0
        deadline=$(( $(/bin/date +%s) + \(paths.duration) ))
        owned=1
        "$pmset" -a disablesleep 1 || exit 70
        [ "$(state)" = 1 ] || { echo 'Could not disable system sleep.' >&2; exit 70; }
        /usr/bin/touch "$lock/$token" || exit 70
        tick=0
        while [ -f "$marker" ] && [ "$(identity)" = "$original_identity" ]; do
            [ "$(/bin/date +%s)" -lt "$deadline" ] || break
            # Do not continually overwrite another application's power settings.
            [ "$(state)" = 1 ] || break
            if [ "$tick" = 0 ]; then check_battery || break; fi
            tick=$(( (tick + 1) % 5 ))
            /bin/sleep \(quote(paths.interval))
        done
        """
    }

    /// Explicit global recovery, including after reboot or a killed privileged watcher.
    /// Refuse to interfere with a live watcher; never recursively delete a directory.
    static func recovery(paths: Paths = Paths()) -> String {
        """
        lock=\(quote(paths.lock))
        pmset=\(quote(paths.pmset))
        umask 077
        exec 9>"$lock.guard" || exit 73
        /usr/bin/lockf -s -t 0 9 || { echo 'Another session or recovery is running.' >&2; exit 73; }
        "$pmset" -a disablesleep 0 || exit 74
        [ "$("$pmset" -g | /usr/bin/awk '$1 == "SleepDisabled" {print $2}')" = 0 ] || exit 74
        if [ -d "$lock" ]; then
            /bin/rm -f "$lock"/* || exit 74
            /bin/rmdir "$lock" || exit 74
        fi
        """
    }
}
