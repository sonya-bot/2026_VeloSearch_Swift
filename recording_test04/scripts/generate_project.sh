#!/bin/zsh

set -euo pipefail

script_dir="${0:A:h}"
project_root="${script_dir:h}"
project_file="${project_root}/recording_test04.xcodeproj/project.pbxproj"

cd "${project_root}"
tuist generate --no-open

# Firebase AnalyticsのPackage manifestが追加するStoreKitの直接リンクは、
# Personal Teamで不要なIn-App Purchase Capabilityを要求するため除外する。
perl -ni -e 'print unless /StoreKit\.framework/' "${project_file}"

echo "Generated recording_test04.xcworkspace without the StoreKit app-target link."
