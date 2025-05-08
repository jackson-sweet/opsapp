# Guidelines for Claude Code Assistant

## General Guidelines
- Be concise and direct in explanations
- Prioritize changes that align with existing code style and patterns
- Test changes thoroughly before confirming success

## Git Commits
- Do NOT add author information in commit messages
- Do NOT add Claude attribution in commit messages
- Keep commit messages clear and descriptive
- Use imperative style for commit messages (e.g. "Fix...", "Add...", not "Fixed..." or "Added...")

## Code Style
- Match existing project style conventions
- Avoid introducing new patterns unless requested
- Comment code only when explicitly requested
- Use meaningful variable and function names

## Testing
- Always run a build check after making changes
- Test functionality when possible
- Report any warnings or errors that appear during build

## Error Handling
- Add appropriate error handling to new code
- Enhance existing error handling as needed
- Provide user-friendly error messages

## User Data Management
- Be careful with user data persistence
- Ensure proper data clearing between sessions
- Handle authentication state carefully

## UI/UX
- Follow existing UI patterns
- Ensure UI elements are properly aligned
- Make sure text is readable and appropriately sized