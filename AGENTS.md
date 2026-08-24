# Antigravity Global Rules & Agent Protocol

## Universal Stream & Status Tag Contract
All workspace tools adhere to a standardized output and stream protocol:
- `stdout` (Exit `0`): Structured data (pipe-delimited), clean signatures, or success status tags `[OK: ...]`.
- `stderr` (Exit `1`): Diagnostic failures, invalid syntax, or missing resources via `[MISSING: ...]`, `[INVALID: ...]`, `[ALIAS: ...]`, or `[ERROR: ...]`.
- Path Hygiene: All tools emit sanitized leaf filenames only. Never output raw `/Users/...` absolute filesystem paths.

---

## 🛠️ MCP Tool Calling Protocol
You MUST invoke custom workspace operations through their registered **MCP tools** rather than executing terminal commands in `bash` whenever an MCP tool is available. This guarantees automated chaining, verification, and live telemetry.

### Strict Enforcement & Native Tool Overrides:
1. **Prohibit Built-In Outlines:** NEVER use `view_file_outline` on `.swift` files. ALWAYS use MCP tool `xc_swift_map` with `action: "map-swift"` or `action: "view-skeleton"`.
2. **Prohibit Built-In Patches:** NEVER use native IDE patch/edit tools directly on `.swift` files. ALWAYS use MCP tool `xcedit` (or `xc_edit`) to guarantee syntax validation and automatic header enforcement.
3. **Mandatory Telemetry:** All code discovery and mutation MUST route through `AntigravityMCP` to ensure 100% coverage in the Flight Recorder monitor.

---

## 📁 Tool Binary Path & Execution Contract
- **Core CLI Binaries Location:** All standalone underlying executables (`XCSwiftMap`, `XCEdit`, `XCSymbols`, `SDKSearcher`, `XCExtract`, `XCCleanup`, `XCPermissions`) reside in the private libexec directory: `~/.antigravity/bin/`.
- **Stream Filtering (`XCExtract`):** When executing raw build commands, invoke via the symlinked/global path or pipe directly:
  `xcodebuild <arguments> 2>&1 | XCExtract`
- **Telemetry Streaming:** All tool calls automatically dispatch out-of-band JSON telemetry over `/tmp/antigravity_telemetry.sock` to the native Flight Recorder app.

---

## 1. Build Error Extraction & Noise Reduction (`xc_extract`)
Whenever running Xcode builds, pipe the output through `xc_extract` or use `xcodebuild <args> 2>&1 | XCExtract` to filter compiler step noise.
- **Automatic Deduplication:** Deduplicates compiler error cascades by default.
- **Auto-Context:** `xc_extract` automatically attaches ±3 lines of source context to compiler errors. Never make a follow-up file-read request just to inspect a compiler error site.
- **Interpretation:** If output is empty, treat the build as a 100% successful compilation.

---

## 2. Swift Code Mapping, AST Discovery & Syntax Verification (`xc_swift_map`)
Whenever you need to analyze, explore, verify, or audit Swift codebases, targets, or files, you MUST invoke the MCP tool `xc_swift_map` to extract structural AST context rather than reading raw file text.

### Supported Operations & Subcommands
- **1-Shot Model Deep Dive:** `xc_swift_map` with `action: "inspect-model"`, `model: "<ModelName>"` (Runs schema extraction, active predicate audits, and property usages concurrently).
- **File Structure & Function Skeletons:** `xc_swift_map` with `action: "map-swift"` (or `action: "map"`), `path: "<FilePath>"`
- **Pre-Flight Syntax & Header Verification:** `xc_swift_map` with `action: "diff-check"`, `path: "<FilePath>"`, optional flags `parseOnly: true`, `noHeaderFix: true`
- **Database & Model Schemas:** `xc_swift_map` with `action: "extract-schema"`, `path: "<FilePathOrDir>"`
- **Model Filter & Predicate Audit:** `xc_swift_map` with `action: "audit-filters"`, `model: "<ModelName>"`, `path: "<path>"`
- **Symbol Usage Finder:** `xc_swift_map` with `action: "find-usage"`, `symbol: "<symbol>"`, `path: "<path>"`
- **Symbol Locator:** `xc_swift_map` with `action: "locate"`, `symbol: "<symbol>"`, `path: "<path>"`
- **Semantic Intent Search:** `xc_swift_map` with `action: "search"`, `query: "<concept>"`
- **SwiftUI Layout Skeleton:** `xc_swift_map` with `action: "view-skeleton"`, `path: "<FilePath>"`
- **SwiftUI View Modifier Scrubber:** `xc_swift_map` with `action: "view-scrub"`, `path: "<FilePath>"` (Strips styling modifiers, preserving minimal structural view hierarchy).
- **Dense Pipe-Delimited AST Context:** `xc_swift_map` with `action: "pack-context"`, `path: "<FilePath>"` (Dense transpiled declaration shorthand).
- **Hyper-Dense Index Mini-Map:** `xc_swift_map` with `action: "mini-map"`, `path: "<FilePath>"` (Exact line numbers for declarations).
- **State & Data Flow:** `xc_swift_map` with `action: "trace-state"`, `path: "<FilePath>"`
- **Logical State Lifecycle Trace:** `xc_swift_map` with `action: "trace-state-logical"`, `path: "<FilePath>"` (Chronological execution sequence of `@State`, `@Binding`, and `@Environment` variables).
- **Dependency Closure Flattening:** `xc_swift_map` with `action: "flatten-deps"`, `symbol: "<symbol>"`, `path: "<DirectoryOrFilePath>"` (Recursively resolves and concatenates raw code blocks of function dependencies).
- **SwiftData Model-View Binding Check:** `xc_swift_map` with `action: "bind-check"`, `modelPath: "<path>"`, `viewPath: "<path>"` (Validates all `@Model` mutable properties are bound in View).
- **Function Intent Git Blame:** `xc_swift_map` with `action: "intent-blame"`, `symbol: "<symbol>"`, `path: "<FilePath>"` (Extracts unique chronological commit messages for a function).
- **Memory & Retain Cycle Audit:** `xc_swift_map` with `action: "audit-memory"`, `path: "<FilePath>"`
- **Git Modified AST Diff:** `xc_swift_map` with `action: "git-diff"`
- **Git Modified Changes:** NEVER run raw `git diff` in terminal. ALWAYS invoke MCP tool `xc_swift_map` with `action: "git-diff"` to get high-signal, compressed AST change summaries.

### Anti-Hallucination & Discovery Protocol
- **NEVER** run broad workspace text searches (e.g., raw grep for single words like `Trash`, `Report`, or `Status`) that return >10 results.
- **UPDATED MANDATORY DISCOVERY SEQUENCE:**
  1. `xc_swift_map` (`action: "inspect-model"`, `model: "<Model>"`) -> **Always run first** when tasked with modifying, filtering, or reporting on a model entity.
  2. Scoped Line Reading -> Only read precise line ranges once the AST scanner isolates the target function.

---

## 3. Precise File Patching & Auto-Verification (`xc_edit`)
When modifying code, use the MCP tool `xc_edit` (or `xcedit`) for scoped line replacements to eliminate indentation drift and bracket truncation.
- `xc_edit` automatically triggers in-flight AST syntax and header verification on write.
- **Replace Lines:** `xc_edit` with `path: "<FilePath>"`, `replaceLines: [<start>, <end>]`, `with: "<NewCode>"`
- **Replace Text:** `xc_edit` with `path: "<FilePath>"`, `replaceText: "<TargetText>"`, `with: "<NewCode>"`
- **Insert Code:** `xc_edit` with `path: "<FilePath>"`, `insertAt: <line>`, `with: "<NewCode>"`
- **Delete Lines:** `xc_edit` with `path: "<FilePath>"`, `deleteLines: [<start>, <end>]`

---

## 4. SF Symbol Validation & Fuzzy Finding (`xc_symbols`)
Before outputting any SwiftUI `Image(systemName: "...")` or `Label("...", systemImage: "...")` code, you MUST validate that the symbol name is valid using the MCP tool `xc_symbols`.
- **Validation:** `xc_symbols` with `query: "<symbol-name>"`, `validate: true`
- **Fuzzy Search / Suggestions:** `xc_symbols` with `query: "<concept or icon description>"`, `semantic: true`
- **Rule:** Never guess or hallucinate SF Symbol names. If invalid, adopt the closest suggested alternative from `xc_symbols`.

---

## 5. Apple SDK & Framework Interface Extraction (`sdk_searcher`)
Whenever you need to inspect Apple SDK method signatures, availability, or protocol conformances without doc-comment noise, use the MCP tool `sdk_searcher`.
- **Dot-Notation Search:** `sdk_searcher` with `query: "SwiftUI.View.task"`
- **Framework Exact Lookup:** `sdk_searcher` with `framework: "SwiftData"`, `query: "Model"`, `exact: true`
- **JSON Serialization:** `sdk_searcher` with `framework: "SwiftUI"`, `query: "View"`, `json: true`

---

## 6. Build Cache & Maintenance (`xc_cleanup`)
Whenever encountering compiler caching issues or stale build artifacts, use the MCP tool `xc_cleanup`.
- **Dry Run Inspection:** `xc_cleanup` with `dryRun: true`
- **Full Workspace Sanitation:** `xc_cleanup` with `all: true`

---

## 7. Simulator Automation & Verification (`xc_sim`)
Use `xc_sim` for managing simulators, taking screenshots, launching apps, or inspecting logs.
- **List Devices:** `xc_sim` with `subcommand: "list-devices"`, `bootedOnly: true`
- **Screenshot:** `xc_sim` with `subcommand: "screenshot"`, `path: "<OutputPath>"`
- **Logs:** `xc_sim` with `subcommand: "logs"`, `bundleId: "<BundleId>"`

---

## 8. Permissions & Property Lists (`xc_permissions`)
Inspect and mutate `.plist` and `.entitlements` files.
- **List Keys:** `xc_permissions` with `path: "<FilePath>"`, `list: true`
- **Set Key:** `xc_permissions` with `path: "<FilePath>"`, `key: "<Key>"`, `value: "<Value>"`
- **Delete Key:** `xc_permissions` with `path: "<FilePath>"`, `key: "<Key>"`, `delete: true`

---

## 9. Git Operations & Diffs
Do NOT stage, commit, or push git changes automatically. The user will handle all git commits and repository management.
- **No Git Commits:** Do NOT stage, commit, or push git changes automatically. The user handles all repository management.
- **No Raw `git diff`:** Do NOT execute `git diff` in bash. When checking modified changes or validating edits, use `xc_swift_map` (`action: "git-diff"`).

---

## 10. Common Swift & Concurrency Guidelines
- `onChange(of:perform:)` is deprecated in iOS 17.0+: Use `onChange` with zero or two parameter action closures.
- `init(url:accessMode:preferredEncoding:)` is deprecated: Use the throwing initializer variant.
- Maintain `@MainActor` isolation on ViewModels and state containers interacting with SwiftUI views.
- Ensure all Swift concurrency closures avoid retain cycles by using `[weak self]` where appropriate.
