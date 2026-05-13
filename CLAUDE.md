# OPS iOS — Project-Specific Instructions

Supplements the root `OPS LTD./CLAUDE.md`. Read both.

## Sources of Truth

- **Architecture, data models, API contracts, features:** `ops-software-bible/` — always consult before making assumptions. Always keep it updated when you change something.
- **Styling, colors, typography, spacing, icons:** `OPS/OPS/Styles/OPSStyle.swift` and the component files in `OPS/OPS/Styles/Components/`. Never improvise colors or spacing — use OPSStyle tokens.
- **Cross-platform brand rules:** `ops-software-bible/05_DESIGN_SYSTEM.md`

## Build Guidelines

- **Never use the simulator.** Always use `xcodebuild -scheme OPS -destination 'generic/platform=iOS'` for build verification. Do NOT use `-destination 'platform=iOS Simulator,...'`.

## Git Commit Guidelines

- **You may commit without asking first.** The default "ask before committing" behavior is overridden — make atomic commits as work lands. **Pushes still require explicit permission** (`git push`, force-push, rebase against shared history, branch deletion, tag-write).
- **Don't step on parallel agent work.** This repo regularly has multiple Claude sessions / worktrees running in parallel (`git worktree list` shows current ones). Before acting on shared state:
  - Do **not** stash, reset, restore, or `git add` files that have pre-existing uncommitted WIP you did not create.
  - Do **not** rebase or rewrite history on a branch a sibling worktree is using.
  - Do **not** delete, rename, or move files another session is mid-edit on.
  - Do **not** run `xcodebuild` against a DerivedData path another session is actively writing to — check `lsof` or running processes first.
  - When uncertain whether parallelism applies, ask before acting.
- **Atomic commits.** One logical change per commit.
- **Never include Claude as co-author.** No `Co-Authored-By: Claude`, no `noreply@anthropic.com`, no AI attribution of any kind in commit messages or trailers.
- **Stage by name, not bulk.** Never `git add -A` or `git add .` — name the specific files. Bulk-staging risks pulling in unrelated WIP, secrets (`Secrets.xcconfig`), or another session's files.
- **Conventional-commit style.** `feat(scope): …`, `fix(scope): …`, `docs(scope): …`, `refactor(scope): …`. Describe what changed and why, not how.

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
