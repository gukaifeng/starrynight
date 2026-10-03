#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/checks/starry-core
cp ios/StarryNight/Resources/{CharacterCatalog,EnvironmentCatalog,CharacterCollections,CharacterPublicProfiles,CharacterDelivery}.json .local/checks/starry-core/
cp ios/StarryNight/Resources/Music_*.caf .local/checks/starry-core/
# The standalone macOS harness uses the production Codable declarations. Their
# files also contain UIKit/SwiftUI views, which belong to the iOS build checks.
python3 - <<'PY'
from pathlib import Path
parts = ['import Foundation\n']
platform = Path('ios/StarryNight/Features/Account/PlatformAPI.swift').read_text()
start = platform.index('indirect enum JSONValue:')
end = platform.index('\nenum PlatformError:', start)
parts.append(platform[start:end])
resources = Path('ios/StarryNight/Features/Resources/CharacterInstalledResources.swift').read_text()
parts.append('import os\n'+resources[resources.index('enum CharacterDeliveryPolicy {'):])
# This harness checks bundled data and preference migration, not OSS install I/O.
# Installed release registration/playback are exercised by the iOS UI tests.
parts.append('enum CharacterInstalledResources { static func resource(_ name:String,extension ext:String)->URL? { nil } }')
for source, boundary in [
    ('ios/StarryNight/App/AppLanguage.swift', '@MainActor @Observable final class AppLanguageSettings'),
    ('ios/StarryNight/Features/Companion/ConversationGoals.swift', 'struct ConversationGoalsPanel: View'),
    ('ios/StarryNight/Features/Companion/MessageTranslation.swift', '@MainActor enum ReplyTranslation'),
]:
    text = Path(source).read_text()
    assert text.count(boundary) == 1, 'Data declaration boundary changed: ' + source
    data = text.split(boundary)[0]
    parts.append('\n'.join(line for line in data.splitlines() if not line.startswith('import ')))
Path('.local/checks/starry-core/CompanionWireTypes.swift').write_text('\n'.join(parts))
PY
SOURCES=(
 .local/checks/starry-core/CompanionWireTypes.swift
 ios/StarryNight/Features/Social/CharacterCollection.swift
 ios/StarryNight/Features/Home/ModelCatalog.swift
 ios/StarryNight/Features/Home/CharacterModelReview.swift
 ios/StarryNight/Features/Account/DemoAccount.swift
 ios/StarryNight/Features/Account/LoginMethod.swift
 ios/StarryNight/Features/Companion/CharacterPosture.swift
 ios/StarryNight/Features/Companion/CharacterPerformanceProfile.swift
 ios/StarryNight/Features/Companion/CharacterFraming.swift
 ios/StarryNight/Features/Companion/CharacterStudio.swift
 ios/StarryNight/Features/Companion/EnvironmentCatalog.swift
 ios/StarryNight/Features/Viewer/CharacterViewPresets.swift
 ios/StarryNight/Features/Companion/CharacterAI.swift
 ios/StarryNight/Features/Companion/VoiceTimeline.swift
 ios/StarryNight/Features/Companion/CompanionData.swift
 ios/StarryNight/Features/Companion/CompanionExperiences.swift
 ios/StarryNight/Features/Companion/CharacterPublicProfile.swift
 ios/StarryNight/Features/Companion/ExperienceStore.swift
 ios/StarryNight/Features/Companion/ConversationGreeting.swift
 ios/StarryNight/Features/Companion/CompanionStore.swift
 ios/StarryNight/Features/Social/AuthorProfile.swift
 ios/StarryNight/Features/Social/CharacterLibrary.swift
 ios/StarryNight/Features/Social/ConversationSearch.swift
)
TESTS=(CharacterLibraryTests)
# Keep the additional standalone harness explicit; the app's greeting flows are
# also exercised by ProactiveGreetingTests through Xcode on the iOS simulator.
if [ "${1:-}" = '--greetings' ]; then TESTS+=(ConversationGreetingTests); fi
if [ "${1:-}" = '--experiences' ]; then TESTS+=(CompanionExperienceTests); fi
LAUNCH_ARGS=()
if [ "${1:-}" = '--model-review' ]; then
 TESTS=(CharacterModelReviewTests)
 LAUNCH_ARGS=(--live-ai --live-reaction-prewarm --live-smart-replies)
fi
if [ "${1:-}" = '--audio' ]; then TESTS=(CharacterAudioUpgradeTests); fi

for TEST in "${TESTS[@]}"; do
 swiftc -swift-version 6 -parse-as-library -module-cache-path .local/checks/starry-core/ModuleCache "${SOURCES[@]}" "scripts/tests/$TEST.swift" -o ".local/checks/starry-core/$TEST"
 ".local/checks/starry-core/$TEST" ${LAUNCH_ARGS[@]+"${LAUNCH_ARGS[@]}"}
done
