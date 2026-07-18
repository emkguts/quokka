## Project Overview

Quokka is an Elixir formatter plugin that combines `mix format` with Credo rule enforcement. It automatically rewrites code to fix style violations instead of just reporting them. Quokka is a fork of Adobe's Styler that integrates with Credo configuration to determine which rules to apply.

## Development Commands

```sh
mix format # Always run before considering a change complete
mix test
mix test test/path/to/foo_test.exs # Run specific test file
mix test test/path/to/foo_test.exs:123 # Run the test at a particular line
mix deps.get # Install dependencies
```

## Architecture

### Core Components

**Main Entry Point**: `lib/styler.ex` (Quokka module)
- Implements `Mix.Tasks.Format` behavior
- Orchestrates the styling process by applying multiple style modules
- Handles error recovery and file processing

**Configuration**: `lib/quokka/config.ex`
- Manages Quokka and Credo configuration integration
- Extracts settings from `.credo.exs` and `.formatter.exs`
- Provides configuration accessors for all style modules

**Style Modules**: `lib/style/`
- `blocks.ex` - Code block formatting
- `comment_directives.ex` - Special comment handling (e.g., `# quokka:sort`)
- `configs.ex` - Mix config file formatting
- `defs.ex` - Function definition optimization
- `deprecations.ex` - Deprecation rewriting
- `module_directives.ex` - Import/alias/use organization
- `pipes.ex` - Pipe chain optimization
- `single_node.ex` - Single AST node transformations
- `tests.ex` - Test assertion rewriting

**NOTE**: As an LLM, you should *never* create a new `Quokka.Style` module unless the user explicitly requests it. Instead, you should add to an existing style module. (Quokka's speed depends on *not* traversing the AST more than absolutely necessary.)

**Utilities**: 
- `lib/zipper.ex` - AST traversal and manipulation
- `lib/style_error.ex` - Error handling for style transformations

### Key Constraints
- Must preserve code semantics while transforming style
- Should integrate with existing Credo configuration
- Error recovery is critical; individual failures shouldn't break entire formatting
- Performance matters for large codebases (uses persistent_term for caching)

## Adding a new rewrite

Before you can begin adding a rewrite, the user needs to at least briefly describe for you a few examples of code they want to be rewritten and what the rewrite should be.

### Guidelines

1. Always write the tests first (follow existing patterns in `test/*_test.exs`); test-driven development is by far the superior way to work with this stuff. Use the `assert_style/2` macro for before/after code comparisons.
2. Feel free to add temporary debugging output (`IO.inspect`, `dbg`, etc.) to the check and repeatedly rerun the tests to figure out what the AST looks like in the cases you care about.
3. When your tests are all passing, run `mix format` as well as `mix test` to ensure you didn't break tests elsewhere.
4. If there are changes to installation, configuration, usage, or the project overview, update the @README.md
5. Updated the relevant `/docs/*.md` file to show off the new rewrite
