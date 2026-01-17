## [0.2.1] - 2026-01-17

- Add `[nondisposable]` prefix to all logger calls for better log identification

## [0.2.0] - 2026-01-16

- Fixed `NoMethodError` when email is `"@"` or malformed (empty domain after split)
- Removed non-existent asset references from engine (`nondisposable/application.css` and `.js`)
- Removed buggy `railtie.rb` file that attempted to include a class instead of a module
- Added comprehensive Minitest 6 test suite with 256 tests and 90%+ line / branch coverage

## [0.1.0] - 2024-09-25

- Initial release
