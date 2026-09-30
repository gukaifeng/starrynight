#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local/checks/starry-core
cp ios/CharacterHost/Resources/{CharacterCatalog,EnvironmentCatalog,CharacterCollections,CharacterPublicProfiles}.json .local/checks/starry-core/
cp ios/CharacterHost/Resources/Music_*.caf .local/checks/starry-core/
SOURCES=(
 ios/CharacterHost/Features/Social/CharacterCollection.swift
 ios/CharacterHost/Features/Home/ModelCatalog.swift
 ios/CharacterHost/Features/Account/DemoAccount.swift
 ios/CharacterHost/Features/Account/LoginMethod.swift
 ios/CharacterHost/Features/Companion/CharacterPosture.swift
 ios/CharacterHost/Features/Companion/CharacterPerformanceProfile.swift
 ios/CharacterHost/Features/Companion/CharacterFraming.swift
 ios/CharacterHost/Features/Companion/CharacterStudio.swift
 ios/CharacterHost/Features/Companion/EnvironmentCatalog.swift
 ios/CharacterHost/Features/Viewer/CharacterViewPresets.swift
 ios/CharacterHost/Features/Companion/CharacterAI.swift
 ios/CharacterHost/Features/Companion/CompanionData.swift
 ios/CharacterHost/Features/Companion/CompanionExperiences.swift
 ios/CharacterHost/Features/Companion/CharacterPublicProfile.swift
 ios/CharacterHost/Features/Companion/ExperienceStore.swift
 ios/CharacterHost/Features/Companion/ConversationGreeting.swift
 ios/CharacterHost/Features/Companion/CompanionStore.swift
 ios/CharacterHost/Features/Social/AuthorProfile.swift
 ios/CharacterHost/Features/Social/CharacterLibrary.swift
 ios/CharacterHost/Features/Social/ConversationSearch.swift
)
TESTS=(CharacterLibraryTests)
# Keep the additional standalone harness explicit; the app's greeting flows are
# also exercised by ProactiveGreetingTests through Xcode on the iOS simulator.
if [ "${1:-}" = '--greetings' ]; then TESTS+=(ConversationGreetingTests); fi
if [ "${1:-}" = '--experiences' ]; then TESTS+=(CompanionExperienceTests); fi
for TEST in "${TESTS[@]}"; do
 swiftc -swift-version 6 -parse-as-library "${SOURCES[@]}" "scripts/tests/$TEST.swift" -o ".local/checks/starry-core/$TEST"
 ".local/checks/starry-core/$TEST"
done
