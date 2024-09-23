# Changelog

Quokka follows [Semantic Versioning](https://semver.org) and
[Common Changelog: Guiding Principles](https://common-changelog.org/#12-guiding-principles)

## [1.0.0] - 2025-02-10

Quokka is inspired by the wonderful [`elixir-styler`](https://github.com/adobe/elixir-styler) :heart:

It maintains the same directive that consistent coding standards can help teams
iterate quickly, but allows a few more affordances
[via `.credo.exs` configuration](https://hexdocs.pm/credo/config_file.html).
This allows users with an already fine-tuned `.credo.exs` config to enjoy
the automatic rewrites and strong opinions of Quokka

More details about specific Credo rewrites and their configurability can be
found in [Quokka: Credo inspired rewrites](https://hexdocs.pm/quokka/readme.html#credo-inspired-rewrites).

Adoption of opinionated code changes can be hard in larger code bases, so
Quokka allows a few configuration options in `.formatter.exs` to help
isolate big sets of potentially controversial or code breaking changes that
may need time for adoption. However, these may be removed in a future release.
See [Quokka: Configuration](https://hexdocs.pm/quokka/readme.html#configuration)
for more details.
