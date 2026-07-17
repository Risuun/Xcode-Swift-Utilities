Add to AGENTS.md:

## Swift Code Mapping & Architecture Discovery
Whenever you need to analyze, explore, or understand Swift codebases, targets, or files, you MUST use `XCSwiftMap` to extract a high-signal structural map rather than wasting context tokens reading raw lines directly.
- Task-Specific Command Choices:
  * **General Code Search:** Use `XCSwiftMap <path>` to extract standard properties, types, and methods.
  * **SwiftData Engineering:** Use `XCSwiftMap extract-schema <path>` to map out database trees before drafting database queries.
  * **SwiftUI Layout Refactoring:** Use `XCSwiftMap view-skeleton <file-path>` to strip visual styling modifiers and expose the pure view hierarchy.
  * **Data Flow Diagnosis:** Use `XCSwiftMap trace-state <path>` to audit data distribution ownership (`@State` vs `@Binding`).
  * **Memory Auditing:** Run `XCSwiftMap audit-memory <path>` against any newly written async managers or ViewModels as a pre-build check to catch silent retain cycles.
  * **Dependency Analysis:** Run `XCSwiftMap spm-summary` at the start of a branch to discover valid third-party modules.
  * **Git Context Reduction:** Run `XCSwiftMap git-diff [--branch <branch>]` to analyze feature branch changes using a high-signal semantic AST outline rather than reading raw git diff lines.
