# OPS iOS — Project-Specific Instructions

Supplements the root `OPS LTD./CLAUDE.md`. Read both.

## Sources of Truth

- **Architecture, data models, API contracts, features:** `ops-software-bible/` — always consult before making assumptions. Always keep it updated when you change something.
- **Styling, colors, typography, spacing, icons:** `OPS/OPS/Styles/OPSStyle.swift` and the component files in `OPS/OPS/Styles/Components/`. Never improvise colors or spacing — use OPSStyle tokens.
- **Cross-platform brand rules:** `ops-software-bible/05_DESIGN_SYSTEM.md`

## Build Guidelines

- **Never use the simulator.** Always use `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` for build verification. Do NOT use `-destination 'platform=iOS Simulator,...'`.

## Git Commit Guidelines

- **Never include Claude as co-author.** Do not add Claude or any AI attribution to git commits.
- **Clear commit messages.** Write concise, descriptive messages that explain the changes.
- **Atomic commits.** Each commit should represent a single logical change.

## Field-First Implementation

- **Touch targets:** Minimum 44x44pt, prefer 60x60pt for primary actions
- **Text sizes:** Minimum 16pt, prefer 18-20pt for important information
- **Contrast ratios:** Minimum 7:1 for normal text, 4.5:1 for large text
- **Offline storage:** Cache all data needed for current day's work
- **Sync strategy:** Queue changes locally, sync opportunistically
- **Error handling:** Always provide actionable next steps
- **Haptics are mandatory** for meaningful interactions. Light impact on arrivals/transitions. Medium impact on commits/confirmations. Success notification on key moments. No haptic spam — each one earned.

## Testing Requirements

- **Test with gloves** — ensure all touch targets work with reduced precision
- **Test in sunlight** — verify contrast and readability outdoors
- **Test offline** — confirm all critical features work without connectivity
- **Test on older devices** — support 3-year-old hardware minimum

## Quick Decisions

When in doubt:
1. Choose reliability over features
2. Choose simplicity over flexibility
3. Choose clarity over cleverness
4. Choose field needs over office preferences
5. Choose proven patterns over innovation
