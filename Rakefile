# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

# nondisposable:tlds:update — refreshes data/iana_tlds.txt from the IANA root
# zone. A maintenance task for this checkout, not something host apps run; see
# the header of lib/nondisposable/tld_list_updater.rb.
Dir.glob("lib/tasks/*.rake").each { |task| load task }

Rake::TestTask.new(:test) do |t|
  t.libs << "lib"
  t.libs << "test"
  t.test_files = FileList['test/**/*_test.rb']
  t.warning = false
end

task default: %i[test]
