# Dependencies Change Log

Auto-updated by `deps_changelog`. 💪

Feel free to edit this file by hand. Updates will be inserted below the following marker:

<!-- changelog -->

_6. September 2025_
-------------------

### `ex_doc` (0.34.2 ➞ 0.38.3)

#### v0.38.3 (2025-08-17)

  * Enhancements
    * Allow configuring autocomplete limit, and default it to 10 instead of 8
    * Display description text in docs groups
    * Load discovered makeup apps for CLI

#### v0.38.2 (2025-05-27)

  * Bug fixes
    * Render documents with hardcoded `<h2>`/`<h3>` entries correctly
    * Fix padding on external links

#### v0.38.1 (2025-05-12)

  * Bug fixes
    * Ensure stripping apps for Erlang sources emit valid AST

#### v0.38.0 (2025-05-09)

  * Enhancements
    * Allow listing outside URLs in extras

  * Bug fixes
    * Ensure some cases where `<`, `>`, `&` and in headers would appear as entities in the sidebar
    * Fix outline caused by swup.js on Webkit based browsers
    * Fix bugs when computing synopsis
    * Automatically close the sidebar when navigating sections on mobile

#### v0.37.3 (2025-03-06)

  * Bug fixes
    * Handle `http-equiv=refresh` during Swup.js navigation
    * Include full error description when syntax highlighting fails

#### v0.37.2 (2025-02-19)

  * Bug fixes
    * Fix code highlighting for languages with non-alphanumeric characters

#### v0.37.1 (2025-02-10)

  * Enhancements
    * Support umbrella projects via the CLI

  * Bug fixes
    * Make sure docs are rendered inside iframes

#### v0.37.0 (2025-02-05)

Thanks to @liamcmitchell and @hichemfantar for the extensive contributions in this new release.

  * Enhancements
    * Optimize and parallelize module retriever, often leading to 20x-30x faster docs generation
    * Considerably improve page loading times in the browser
    * Allow customizing `search_data` for extra pages
    * Use native style for scroll bars
    * Enhance links between extras/pages/guides with padding and hover effects
    * Go to latest goes to the same page if it exists, root otherwise
    * Apply new style and layout for tabs
    * Increase font-weight on sidebar on Apple machines/devices
    * Improve accessibility across deprecation, links, and summaries
    * Add compatibility to Erlang/OTP 28+
    * Rely on the operating system monospace font for unified experience and better load times
    * Introduce `"exdoc:loaded"` window event to track navigation
    * Support for favicons

  * Bug fixes
    * Move action links out from heading tags

#### v0.36.1 (2024-12-24)

  * Enhancements
    * Show a progress bar if navigation takes more than 300ms

  * Bug fixes
    * Fix dark mode styling on cheatsheets
    * Ensure the sidebar closes on hosting navigation in mobile

#### v0.36.0 (2024-12-24)

  * Enhancements
    * Use swup.js for navigation on hosted sites
    * Support `:group` in documentation metadata for grouping in the sidebar
    * Support `:default_group_for_doc` in configuration to set the default group for functions, callbacks, and types
    * Add `--warnings-as-errors` flag to `mix docs`

  * Bug fixes
    * Fix typespec with `(...) -> any()`
    * Do not trap `tab` commands in the search bar

#### v0.35.1 (2024-11-21)

  * Bug fixes
    * Make sure symlinks are copied from assets directory
    * Discard private functions documented by EDoc

#### v0.35.0 (2024-11-19)

  * Enhancements
    * Store `proglang` in `searchdata.js`
    * Allow searching for atoms inside backticks
    * Add support for nominal types from Erlang/OTP 28
    * Support a new `:redirects` option which allows configuring redirects in the sidebar
    * Improve warning when referencing type from a private module
    * Rename "Search HexDocs package" modal to "Go to package docs"
    * Support built-in Erlang/OTP apps in "Go to package docs"

  * Bug fixes
    * Switch anchor `title` to `aria-label`
    * Convert admonition blockquotes to sections for screen reader users
    * Fix code copy buttons within tabsets

    * Extract title from Markdown file when preceded with comments
  * Enhancements
