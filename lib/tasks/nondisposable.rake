# frozen_string_literal: true

namespace :nondisposable do
  namespace :tlds do
    desc "Refresh the vendored IANA TLD snapshot (maintenance task — run in a gem checkout before a release)"
    task :update do
      # Deliberately NOT `require "nondisposable"`: that loads the Engine, which
      # needs Rails, which a bare `rake` in a gem checkout doesn't have. Nothing
      # this task touches reads configuration — only `Tld.valid?`/`blocked?` do,
      # and it calls neither.
      require_relative "../nondisposable/tld"
      require_relative "../nondisposable/tld_list_updater"

      before = begin
        Nondisposable::Tld.all.size
      rescue StandardError
        0
      end

      count = Nondisposable::TldListUpdater.update

      if count.nil?
        abort "[nondisposable] TLD list unchanged. See the error above."
      else
        added = count - before
        change =
          if added.positive? then "+#{added}"
          elsif added.negative? then added.to_s
          else "no change"
          end
        puts "[nondisposable] TLD snapshot now holds #{count} entries (#{change})."
        puts "[nondisposable] IANA version: #{Nondisposable::Tld.version}"
        puts "[nondisposable] Commit data/iana_tlds.txt if it changed."
      end
    end
  end
end

namespace :nondisposable do
  namespace :psl do
    desc "Refresh the vendored Public Suffix List snapshot (maintenance task — run in a gem checkout before a release)"
    task :update do
      # Same reasoning as tlds:update: no Rails here. The parser normalizes
      # rules through Domain, so it comes along.
      require_relative "../nondisposable/domain"
      require_relative "../nondisposable/public_suffix"
      require_relative "../nondisposable/public_suffix_list_updater"

      before = begin
        Nondisposable::PublicSuffix.rule_count
      rescue StandardError
        0
      end

      count = Nondisposable::PublicSuffixListUpdater.update

      if count.nil?
        abort "[nondisposable] Public Suffix List unchanged. See the error above."
      else
        puts "[nondisposable] PSL snapshot now holds #{count} rules (was #{before})."
        puts "[nondisposable] PSL version: #{Nondisposable::PublicSuffix.version}"
        puts "[nondisposable] Commit data/public_suffix_list.dat if it changed."
      end
    end
  end
end
