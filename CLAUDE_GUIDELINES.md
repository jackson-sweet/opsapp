# Guidelines for Claude Code Assistant

## General Guidelines
- Be concise and direct in explanations
- Prioritize changes that align with existing code style and patterns
- Test changes thoroughly before confirming success
- Aim for simplicity and maintainability in all solutions

## Code Quality Principles

### Clean Coding
- Write self-explanatory code with meaningful naming
- Keep functions concise and focused on a single responsibility
- Prefer clarity over cleverness
- Limit nesting to 2-3 levels maximum
- Use Swift's type system for safety and clarity
- Prefer Swift idioms and language features when appropriate

### Modularity
- Organize code into logical, reusable components
- Use MVVM architecture consistently throughout the app
- Keep view code separate from business logic
- Create clear boundaries between app layers
- Make dependencies explicit rather than implicit
- Design components for independent testing

### Preventing Redundancy
- Eliminate duplicate code through abstraction
- Create reusable component libraries for UI elements
- Consolidate common functionality into shared services
- Don't create parallel implementations of the same feature
- Prefer composition over inheritance
- Follow the DRY principle (Don't Repeat Yourself)
- Validate that new code doesn't duplicate existing functionality

### Debugging Optimization
- Use descriptive print statements with consistent formatting
- Include context information in log messages (component name, function, etc.)
- Add appropriate error handling with specific error types
- Ensure errors bubble up to appropriate UI handlers
- Include debug-only features that can be toggled off in production

## Git Commits
- Do NOT add author information in commit messages
- Do NOT add Claude attribution in commit messages
- Keep commit messages clear and descriptive
- Use imperative style for commit messages (e.g. "Fix...", "Add...", not "Fixed..." or "Added...")
- Link to relevant issues or requirements when applicable
- Group related changes into coherent commits

## Code Style
- Match existing project style conventions
- Avoid introducing new patterns unless requested
- Comment code only when explicitly requested
- Use meaningful variable and function names
- Follow Swift naming conventions:
  - Use camelCase for variables and functions
  - Use PascalCase for types
  - Use descriptive enum cases
- Structure files consistently:
  - Extensions at the bottom
  - MARK comments to separate logical sections
  - Properties before methods

## SwiftUI Patterns
- Use environment objects for dependency injection
- Prefer @Binding over @State when appropriate
- Keep view components small and focused
- Extract complex subviews into separate components
- Use preview providers for all UI components
- Leverage composition to build complex views

## Testing
- Always run a build check after making changes
- Test functionality when possible
- Report any warnings or errors that appear during build
- Consider different device sizes and orientations
- Test features in both light and dark mode
- Ensure accessibility support for UI components

## Error Handling
- Add appropriate error handling to new code
- Enhance existing error handling as needed
- Provide user-friendly error messages
- Use Swift's error handling mechanisms consistently
- Prefer structured errors over string messages
- Always log errors for debugging purposes

## User Data Management
- Be careful with user data persistence
- Ensure proper data clearing between sessions
- Handle authentication state carefully
- Use SwiftData for complex persistence
- Use UserDefaults only for simple preferences and flags
- Clear sensitive data when logging out
- Validate data integrity when loading from persistence

## UI/UX
- Follow existing UI patterns
- Ensure UI elements are properly aligned
- Make sure text is readable and appropriately sized
- Support dark mode throughout the app
- Use the established color system from OPSStyle
- Consider glove-friendly touch targets for all interactive elements
- Design for outdoor visibility and variable lighting conditions
- Create consistent visual hierarchies across screens