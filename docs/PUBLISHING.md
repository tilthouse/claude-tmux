# Publishing claude-tmux

A reference for when we're ready to make `claude-tmux` available to others
via RubyGems and a Homebrew tap. Nothing here is executed yet — this is
a playbook to consult when the time comes.

## Current state (what's already in place)

- **Gem packaging** — `claude-tmux.gemspec` declares metadata, executables
  (`claude-tmux`, `cct`, `ccg`, `ccs`), runtime dep (`toml-rb ~> 2.2`), and
  sets `rubygems_mfa_required = true`.
- **Release task** — `Rakefile` includes `bundler/gem_tasks`, so
  `bundle exec rake build` produces a gem in `pkg/` and
  `bundle exec rake release` tags + pushes + publishes.
- **Tests** — RSpec suite (66 examples) covers parsers, options cascade,
  session-name resolution, project/group behavior, and the `-c`/`-r`
  guard. `bundle exec rspec` is clean.
- **Style** — `bundle exec rubocop` is clean.
- **Docs** — `README.md` covers install + usage; `CHANGELOG.md` follows
  Keep-a-Changelog; MIT `LICENSE` in place.

## Ecosystem checks (as of 2026-04-21)

- **RubyGems name `claude-tmux`** — **available**. `GET https://rubygems.org/api/v1/gems/claude-tmux.json` returns 404.
- **Existing Homebrew tap** — **`tilthouse/homebrew-tap`** (public) already
  exists, currently hosting two selenium formulas at the repo root. No
  `Formula/` subdirectory yet.

## Step 1 — RubyGems

### Prereqs (one-time)

- Create a [rubygems.org](https://rubygems.org) account on the
  `tilthouse` (or preferred) namespace.
- Generate an API key with MFA required (the gemspec already enforces
  `rubygems_mfa_required = true`).
- `gem signin` locally to cache credentials.

### Each release

1. Bump `lib/claude_tmux/version.rb`.
2. Prepend a new entry to `CHANGELOG.md` (move `[Unreleased]` → a dated version).
3. Commit: `git commit -am "v0.x.y: <summary>"`.
4. `bundle exec rake release` — this tags `v0.x.y`, pushes to origin, and
   publishes the `.gem` to rubygems.org. Aborts if the working tree is
   dirty or the tag already exists.

### End-user install (after the first release)

```bash
gem install claude-tmux
# Ensure $GEM_HOME/bin is on PATH
```

## Step 2 — Homebrew tap

### Choice: reuse the existing tap

`tilthouse/homebrew-tap` already exists, so we'd add `claude-tmux.rb` there
rather than create a new `homebrew-claude-tmux` repo. Trade-off:

- **Pro:** one tap for multiple tools; users who already tapped it get new
  formulas for free.
- **Con:** name collision risk with other tools later (mitigated by
  Homebrew's formula-name uniqueness within a tap).

Users install via:

```bash
brew tap tilthouse/tap
brew install claude-tmux
```

### Tap layout decision

Current tap has formulas at the root. Homebrew still accepts that layout,
but `Formula/<name>.rb` is the current preferred convention. **Recommended:**
move the existing selenium formulas into `Formula/` as part of adding
`claude-tmux.rb`. Low-effort cleanup, future-proofs the tap.

### `Formula/claude-tmux.rb`

```ruby
class ClaudeTmux < Formula
  desc "Per-project tmux session launcher for Claude Code"
  homepage "https://github.com/tilthouse/claude-tmux"
  url "https://rubygems.org/downloads/claude-tmux-0.3.0.gem"
  sha256 "<sha256 of the .gem file>"
  license "MIT"

  depends_on "ruby"
  depends_on "tmux"
  # Runtime deps that activate optional UX:
  #   - sesh  : ccs/ccg picker
  #   - fzf   : ccs/ccg picker
  # We intentionally don't `depends_on` these — cct works without them
  # and some users won't want the picker. Document in the tap's README.

  resource "citrus" do
    url "https://rubygems.org/downloads/citrus-3.0.2.gem"
    sha256 "<sha256>"
  end

  resource "toml-rb" do
    url "https://rubygems.org/downloads/toml-rb-2.2.0.gem"
    sha256 "<sha256>"
  end

  def install
    ENV["GEM_HOME"] = libexec

    resources.each do |r|
      r.verify_download_integrity(r.fetch)
      system "gem", "install", r.cached_download,
             "--no-document", "--install-dir", libexec, "--ignore-dependencies"
    end

    system "gem", "install", cached_download,
           "--no-document", "--install-dir", libexec, "--ignore-dependencies"

    %w[claude-tmux cct ccg ccs].each do |exe|
      (bin/exe).write_env_script libexec/"bin/#{exe}",
                                 GEM_HOME: libexec, GEM_PATH: libexec
    end
  end

  test do
    assert_match "claude-tmux #{version}", shell_output("#{bin}/claude-tmux")
  end
end
```

Compute sha256s with `shasum -a 256 <file>.gem` after downloading each
from rubygems.org. Update on every release.

## Step 3 — CI

Add `.github/workflows/ci.yml` to run tests + lint on every push and PR.

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        ruby: ['3.0', '3.1', '3.2', '3.3', '3.4']
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: ${{ matrix.ruby }}
          bundler-cache: true
      - run: bundle exec rspec
      - run: bundle exec rubocop
```

Also worth adding to the tap repo: a `.github/workflows/tests.yml` that
runs `brew test-bot` against `Formula/claude-tmux.rb` on PRs. Standard
Homebrew-tap CI — Homebrew publishes a reusable workflow.

## Step 4 — Before-first-release checklist

- [ ] Make the main repo public (verify `gh repo view tilthouse/claude-tmux`).
- [ ] Add `CONTRIBUTING.md` (short: clone, `bundle install`, `bundle exec rspec`).
- [ ] Add `.github/workflows/ci.yml`.
- [ ] Confirm rubygems.org account + API key + MFA.
- [ ] Verify `bundle exec rake release --dry-run` (if supported) or walk
      through the steps manually to catch any Rakefile gaps.
- [ ] First cut: `v0.3.0` or a fresh `v1.0.0` if you want the signal that
      the API is stable.

## Step 5 — Release playbook (manual, per release)

```bash
# 1. Main repo
vim lib/claude_tmux/version.rb                  # bump version
vim CHANGELOG.md                                # promote [Unreleased] → dated
git commit -am "v0.3.1: <summary>"
bundle exec rake release                        # tag + push + publish

# 2. Compute new sha256
curl -LO https://rubygems.org/downloads/claude-tmux-0.3.1.gem
shasum -a 256 claude-tmux-0.3.1.gem

# 3. Tap repo
cd ~/Developer/tools/homebrew-tap               # or wherever it's cloned
vim Formula/claude-tmux.rb                      # bump url + sha256 (+ any new resources)
git commit -am "claude-tmux 0.3.1"
git push
```

## Step 6 — Optional automation (defer until manual feels tedious)

Once you've cut 2-3 manual releases and know the rhythm:

- **Tag-push → RubyGems publish** via a GitHub Action on tag push in the
  main repo. Uses `rubygems/configure-rubygems-credentials-action`.
- **Tag-push → PR in tap repo** via a workflow that computes sha256 and
  uses `peter-evans/create-pull-request` (or similar) against
  `tilthouse/homebrew-tap`. This is the `repository_dispatch` pattern.

Rough shape is ~50 lines of YAML each. Skip until you're sure you don't
want to stop at a release candidate between steps.

## Step 7 — Eventually: homebrew-core

If claude-tmux builds a user base (notable stars, stable release cadence,
third-party use), submit a formula PR to `Homebrew/homebrew-core` so
users can `brew install claude-tmux` without tapping. Homebrew has
documented acceptance criteria around "notability." Not worth pursuing
until the tap has sustained uptake.

## Decisions not yet made

- Formula location in tap: root (matches existing) vs `Formula/` (cleaner).
- Whether to pin `depends_on "ruby@3.3"` or use plain `"ruby"` (latter is
  simpler; former is reproducible).
- Whether to list `sesh` / `fzf` as `:recommended` deps or only mention in
  docs.
- First public-release version number (0.3.1 continuing the current line,
  or 1.0.0 as a "stable API" signal).
