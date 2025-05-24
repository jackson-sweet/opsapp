#!/bin/bash

# List of settings view files that need the swipe-back gesture
files=(
    "OPS/Views/Settings/OrganizationSettingsView.swift"
    "OPS/Views/Settings/ComingSoonView.swift"
    "OPS/Views/Settings/TeamMembersView.swift"
    "OPS/Views/Settings/AppSettingsView.swift"
    "OPS/Views/Settings/MapSettingsView.swift"
    "OPS/Views/Settings/ProjectHistorySettingsView.swift"
    "OPS/Views/Settings/DataStorageSettingsView.swift"
    "OPS/Views/Settings/SecuritySettingsView.swift"
    "OPS/Views/Settings/NotificationSettingsView.swift"
    "OPS/Views/Settings/ExpenseHistoryView.swift"
    "OPS/Views/Settings/Components/FeatureRequestView.swift"
)

for file in "${files[@]}"; do
    echo "Processing $file..."
    
    # Check if file has navigationBarBackButtonHidden(true)
    if grep -q "\.navigationBarBackButtonHidden(true)" "$file"; then
        # Add .swipeBackGesture() after .navigationBarBackButtonHidden(true)
        sed -i '' 's/\.navigationBarBackButtonHidden(true)/\.navigationBarBackButtonHidden(true)\
            .swipeBackGesture() \/\/ Add swipe-back gesture/g' "$file"
        echo "✓ Updated $file"
    else
        echo "⚠️  $file does not have navigationBarBackButtonHidden(true)"
    fi
done

echo "Done!"