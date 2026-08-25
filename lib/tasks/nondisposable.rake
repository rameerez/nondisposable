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
