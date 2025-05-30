#!/bin/bash
cd "/Users/jacksonsweet/Desktop/OPS APP/OPS"
git add OPS/DataModels/UserRole.swift
git add OPS/Utilities/DataController.swift
git add OPS/Views/Settings/TeamMembersView.swift
git commit -m "$(cat <<'EOF'
Add Admin user role and automatic admin detection

- Added Admin case to UserRole enum
- Updated TeamMembersView to use standardized EmptyStateView component
- Implemented automatic admin role assignment when syncing company data
  - Checks if current user ID is in company's admin list from API
  - Updates user role to Admin when detected in admin list

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"