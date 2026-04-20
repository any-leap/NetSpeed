# NetSpeed — macOS menu bar network/latency monitor
#
# Common tasks. Always use `make reload` after changes; do NOT `swift run`
# (the LaunchAgent expects the release binary at .build/release/NetSpeed).

SHELL        := /bin/bash
BINARY       := .build/release/NetSpeed
PLIST_TPL    := com.t3st.netspeed.plist.tpl
PLIST_DST    := $(HOME)/Library/LaunchAgents/com.t3st.netspeed.plist
LABEL        := com.t3st.netspeed
UID          := $(shell id -u)
ABS_BINARY   := $(abspath $(BINARY))

.PHONY: all build sign install uninstall reload stop start status logs tail clean

all: build

## Build release + ad-hoc codesign (required so macOS won't Gatekeeper-block it)
build:
	swift build -c release
	codesign --sign - --force --timestamp=none $(BINARY)
	@echo "✓ built and signed: $(BINARY)"

## Render plist template with absolute binary path, install into LaunchAgents, start
install: build
	@sed 's|__BINARY__|$(ABS_BINARY)|g' $(PLIST_TPL) > $(PLIST_DST)
	@launchctl bootstrap gui/$(UID) $(PLIST_DST) 2>/dev/null || true
	@echo "✓ installed at $(PLIST_DST)"
	@$(MAKE) --no-print-directory status

## Remove from LaunchAgents (stop + delete plist)
uninstall: stop
	@rm -f $(PLIST_DST)
	@echo "✓ uninstalled"

## Rebuild + restart in place (use this during development)
reload: build
	@launchctl kickstart -k gui/$(UID)/$(LABEL)
	@sleep 1
	@$(MAKE) --no-print-directory status

stop:
	@launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	@echo "✓ stopped"

start:
	@launchctl bootstrap gui/$(UID) $(PLIST_DST) 2>/dev/null || true
	@$(MAKE) --no-print-directory status

status:
	@launchctl list | grep $(LABEL) || echo "✗ not running"

## Show last 50 lines of stderr
logs:
	@tail -n 50 /tmp/netspeed.err 2>/dev/null || echo "no logs yet"

## Follow stderr in real time
tail:
	@tail -f /tmp/netspeed.err

clean:
	swift package clean
	rm -rf .build
