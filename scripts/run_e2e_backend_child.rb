# frozen_string_literal: true

require "pathname"
require "tmpdir"

repository_root = Pathname(__dir__).join("..").expand_path
run_dir = Pathname(ARGV.fetch(0)).expand_path
rest_port = Integer(ARGV.fetch(1), 10)

unless run_dir.directory? && run_dir.dirname == Pathname(Dir.tmpdir).join("narou-mod-playwright-backend")
  abort "Invalid E2E backend run directory: #{run_dir}"
end

ARGV.replace([
  "web",
  "--internal-boot",
  "--port",
  rest_port.to_s,
  "--no-frontend",
  "--no-browser"
])

Dir.chdir(run_dir)
load repository_root.join("narou.rb")
