#!/bin/bash
#
# bump-build-number.sh
#
# Erhöht CFBundleVersion in Drops/Info.plist um 1 — wird automatisch
# als "Run Script"-Build-Phase ausgeführt. Läuft nur bei Archive-Builds
# (CONFIGURATION = Release UND ACTION = "install"), damit Debug-Builds
# nicht jedes Mal die Nummer hochzählen.
#
# CFBundleVersion ist in Info.plist mit $(CURRENT_PROJECT_VERSION)
# verknüpft — wir schreiben einen festen numerischen Wert REIN, damit
# der nächste Archive ihn als Basis nehmen kann. Beim ersten Lauf greift
# der Fallback auf $CURRENT_PROJECT_VERSION aus dem Xcode-Setting.
#
# Setup (einmalig in Xcode):
#   Target → Build Phases → "+" → New Run Script Phase
#   Phase NACH "Copy Bundle Resources" einfügen
#   Script:
#       "${SRCROOT}/scripts/bump-build-number.sh"
#   Input Files:  $(SRCROOT)/Drops/Info.plist
#   Run script: "For install builds only" anhaken
#       (oder: in den Conditions nur Release zulassen)
#
# Manueller Run außerhalb von Xcode (z.B. CI):
#   ./scripts/bump-build-number.sh

set -euo pipefail

# Pfad zur Info.plist — relativ zum SRCROOT (von Xcode gesetzt) oder
# zum Repo-Root (manueller Run).
ROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
PLIST="$ROOT/Drops/Info.plist"

if [ ! -f "$PLIST" ]; then
    echo "error: Info.plist nicht gefunden unter $PLIST" >&2
    exit 1
fi

# Nur auf Archive bumpen — sonst zählt jeder Simulator-Run hoch.
# ACTION ist nur in Xcode-Runs gesetzt. Wenn das Skript manuell läuft
# (kein ACTION), springen wir IMMER rein (CI-Use-Case).
if [ -n "${ACTION:-}" ] && [ "${ACTION}" != "install" ]; then
    echo "[bump-build-number] Skipped (ACTION=${ACTION}, only runs on 'install' / Archive)"
    exit 0
fi

current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")

# Wenn der Wert noch eine Build-Setting-Reference ist ($(CURRENT_PROJECT_VERSION)),
# benutzen wir den Setting-Wert als Startpunkt — sonst erste Iteration crasht
# bei "$current + 1".
if [[ "$current" == \$* ]] || ! [[ "$current" =~ ^[0-9]+$ ]]; then
    current="${CURRENT_PROJECT_VERSION:-1}"
fi

new=$((current + 1))

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new" "$PLIST"

echo "[bump-build-number] CFBundleVersion: $current → $new"
