# frozen_string_literal: true

require "fileutils"
require "json"
require "net/http"
require "pathname"
require "rbconfig"
require "securerandom"
require "tmpdir"
require "time"
require "timeout"
require "uri"
require "yaml"

module NarouE2EBackend
  REPOSITORY_ROOT = Pathname(__dir__).join("..").expand_path.freeze
  RUNS_ROOT = Pathname(Dir.tmpdir).join("narou-mod-playwright-backend").freeze
  FIXTURE_SETTINGS = REPOSITORY_ROOT.join("spec", "fixtures", ".test_dot_narou").freeze
  FIXTURE_NOVELS = REPOSITORY_ROOT.join("spec", "fixtures", ".test_novel_data").freeze
  PROXY_URL = "http://127.0.0.1:9"
  SNAPSHOT_TIMEOUT_SECONDS = 30

  module_function

  def run
    abort "Playwright backend integration is not supported on Windows" if Gem.win_platform?

    rest_port = Integer(ENV.fetch("NAROU_E2E_BACKEND_PORT", "45678"), 10)
    abort "NAROU_E2E_BACKEND_PORT must leave room for the PushServer port" unless rest_port.between?(1, 65_534)

    FileUtils.mkdir_p(RUNS_ROOT)
    acquire_run_lock!
    recover_stale_runs!
    verify_outbound_proxy!

    run_id = "run-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(6)}"
    run_dir = safe_run_dir(run_id)
    prepare_fixtures(run_dir, rest_port)

    command = [
      RbConfig.ruby,
      "-S",
      "bundle",
      "exec",
      RbConfig.ruby,
      REPOSITORY_ROOT.join("scripts", "run_e2e_backend_child.rb").to_s,
      run_dir.to_s,
      rest_port.to_s
    ]
    environment = proxy_environment.merge(
      "BUNDLE_GEMFILE" => REPOSITORY_ROOT.join("Gemfile").to_s
    )

    child_pid = Process.spawn(
      environment,
      *command,
      chdir: REPOSITORY_ROOT.to_s,
      in: File::NULL,
      pgroup: true
    )
    @child_pid = child_pid
    manifest_path = run_dir.join("e2e-process.json")
    manifest = build_manifest(run_id, run_dir, child_pid, command)
    write_manifest(manifest_path, manifest)

    Signal.trap("INT") { Process.kill("INT", -child_pid) rescue nil }
    Signal.trap("TERM") { Process.kill("INT", -child_pid) rescue nil }

    _, status = Process.wait2(child_pid)
    exit_status = status.exitstatus || (128 + status.termsig.to_i)
    exit exit_status
  ensure
    cleanup_current_run(manifest_path, run_dir) if defined?(run_dir) && run_dir
    release_run_lock!
  end

  def acquire_run_lock!
    lock = File.new(RUNS_ROOT.join(".run.lock"), File::RDWR | File::CREAT, 0o600)
    unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      lock.close
      abort "Another Playwright backend integration run is already active"
    end

    @run_lock = lock
  end

  def release_run_lock!
    return unless @run_lock

    @run_lock.flock(File::LOCK_UN)
    @run_lock.close
    @run_lock = nil
  end

  def proxy_environment
    {
      "http_proxy" => PROXY_URL,
      "https_proxy" => PROXY_URL,
      "no_proxy" => "localhost,127.0.0.1,[::1]",
      "HTTP_PROXY" => nil,
      "HTTPS_PROXY" => nil,
      "NO_PROXY" => "localhost,127.0.0.1,[::1]"
    }
  end

  def verify_outbound_proxy!
    old_environment = {}
    proxy_environment.each do |key, value|
      old_environment[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end

    test_uri = URI("https://192.0.2.1/narou-e2e-proxy-check")
    proxy = test_uri.find_proxy
    unless proxy&.host == "127.0.0.1" && proxy.port == 9
      abort "HTTPS proxy guard is not active; refusing to start E2E backend"
    end

    begin
      Net::HTTP.start(
        test_uri.host,
        test_uri.port,
        use_ssl: true,
        open_timeout: 1,
        read_timeout: 1
      ) { |http| http.head(test_uri.request_uri) }
      abort "Outbound proxy guard unexpectedly allowed a connection"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH,
           SocketError, IOError, Timeout::Error
      warn_e2e "[E2E backend] outbound proxy guard verified"
    end
  ensure
    old_environment&.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def prepare_fixtures(run_dir, rest_port)
    abort "Missing E2E settings fixture: #{FIXTURE_SETTINGS}" unless FIXTURE_SETTINGS.directory?
    abort "Missing E2E novel fixture: #{FIXTURE_NOVELS}" unless FIXTURE_NOVELS.directory?

    FileUtils.mkdir_p(run_dir)
    FileUtils.cp_r(FIXTURE_SETTINGS, run_dir.join(".narou"))
    FileUtils.cp_r(FIXTURE_NOVELS, run_dir.join("小説データ"))
    FileUtils.mkdir_p(run_dir.join(".narousetting"))
    File.write(
      run_dir.join(".narousetting", "global_setting.yaml"),
      YAML.dump("server-port" => rest_port, "server-bind" => "127.0.0.1")
    )
  end

  def build_manifest(run_id, run_dir, child_pid, command)
    snapshot = wait_for_snapshot(child_pid, run_dir)
    {
      "run_id" => run_id,
      "pid" => child_pid,
      "pgid" => Process.getpgid(child_pid),
      "started_at" => snapshot.fetch("started_at"),
      "command" => snapshot.fetch("command"),
      "requested_command" => command,
      "cwd" => snapshot.fetch("cwd"),
      "created_at" => Time.now.utc.iso8601
    }
  end

  def wait_for_snapshot(pid, run_dir)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SNAPSHOT_TIMEOUT_SECONDS
    last_snapshot = nil
    expected_cwd = run_dir.realpath.to_s
    loop do
      snapshot = process_snapshot(pid)
      last_snapshot = snapshot if snapshot
      if snapshot && snapshot["cwd"] == expected_cwd && snapshot["command"].include?("run_e2e_backend_child.rb")
        return snapshot
      end
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
        raise "Backend process did not reach the expected command/cwd: #{last_snapshot.inspect}"
      end

      sleep 0.1
    end
  end

  def process_snapshot(pid)
    return nil unless process_alive?(pid)

    command = IO.popen(["ps", "-p", pid.to_s, "-o", "command="], &:read).strip
    started_at = IO.popen(["ps", "-p", pid.to_s, "-o", "lstart="], &:read).strip
    cwd = process_cwd(pid)
    return nil if command.empty? || started_at.empty? || cwd.nil?

    { "command" => command, "started_at" => started_at, "cwd" => cwd }
  end

  def process_cwd(pid)
    proc_cwd = Pathname("/proc/#{pid}/cwd")
    return proc_cwd.realpath.to_s if proc_cwd.exist?

    output = IO.popen(["lsof", "-a", "-p", pid.to_s, "-d", "cwd", "-Fn"], err: File::NULL, &:read)
    output.lines.filter_map { |line| line.delete_prefix("n").strip if line.start_with?("n") }.first
  rescue Errno::ENOENT, Errno::EACCES
    nil
  end

  def write_manifest(path, manifest)
    temporary_path = path.sub_ext(".tmp")
    File.write(temporary_path, JSON.pretty_generate(manifest))
    File.rename(temporary_path, path)
  end

  def recover_stale_runs!
    RUNS_ROOT.children.each do |candidate|
      next unless candidate.directory?

      begin
        safe_run_dir(candidate.basename.to_s)
      rescue StandardError => e
        warn_e2e "[E2E backend] skipping unrecognized run directory #{candidate}: #{e.message}"
        next
      end

      manifest_path = candidate.join("e2e-process.json")
      unless manifest_path.file?
        warn_e2e "[E2E backend] removing manifestless run directory without signaling a process: #{candidate}"
        safe_remove_run_dir(candidate)
        next
      end

      begin
        stop_owned_process!(manifest_path, remove_run_dir: true)
      rescue StandardError => e
        warn_e2e "[E2E backend] removing invalid run directory without signaling a process: #{candidate} (#{e.message})"
        safe_remove_run_dir(candidate)
      end
    end
  end

  def stop_owned_process!(manifest_path, remove_run_dir:)
    manifest = JSON.parse(manifest_path.read)
    run_dir = safe_run_dir(manifest.fetch("run_id"))
    unless manifest_path.dirname == run_dir
      warn_e2e "[E2E backend] manifest path does not match run ID; no process was signaled: #{manifest_path}"
      safe_remove_run_dir(manifest_path.dirname) if remove_run_dir
      return false
    end

    pid = Integer(manifest.fetch("pid"))
    pgid = Integer(manifest.fetch("pgid"))
    raise ArgumentError, "E2E process IDs must be positive" unless pid.positive? && pgid.positive?

    if process_alive?(pid)
      snapshot = process_snapshot(pid)
      expected = manifest.slice("command", "started_at", "cwd")
      current_pgid = Process.getpgid(pid) if snapshot == expected
      unless snapshot == expected && current_pgid == pgid && pgid == pid
        warn_e2e "[E2E backend] ownership check failed for process #{pid}; no process was signaled"
        safe_remove_run_dir(run_dir) if remove_run_dir
        return false
      end

      terminate_process_group(pid, pgid)
    end

    safe_remove_run_dir(run_dir) if remove_run_dir
    true
  rescue Errno::ESRCH
    safe_remove_run_dir(run_dir) if remove_run_dir
    true
  end

  def terminate_process_group(pid, pgid)
    Process.kill("INT", -pgid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    while process_alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.1
    end
    return unless process_alive?(pid)

    Process.kill("TERM", -pgid)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    while process_alive?(pid) && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      sleep 0.1
    end
    Process.kill("KILL", -pgid) if process_alive?(pid)
  rescue Errno::ESRCH
    nil
  end

  def cleanup_current_run(manifest_path, run_dir)
    if manifest_path&.file?
      stop_owned_process!(manifest_path, remove_run_dir: false)
    elsif defined?(@child_pid) && @child_pid && process_alive?(@child_pid)
      Process.kill("INT", -@child_pid)
      Process.wait(@child_pid)
    end
    safe_remove_run_dir(run_dir) if run_dir&.exist?
  rescue StandardError => e
    warn_e2e "[E2E backend] cleanup failed: #{e.message}"
  end

  def safe_run_dir(run_id)
    raise "Invalid E2E run ID: #{run_id.inspect}" unless run_id.match?(/\Arun-\d{14}-[0-9a-f]{12}\z/)

    candidate = RUNS_ROOT.join(run_id).cleanpath
    raise "Unsafe E2E run directory: #{candidate}" unless candidate.dirname == RUNS_ROOT

    candidate
  end

  def safe_remove_run_dir(run_dir)
    validated = safe_run_dir(run_dir.basename.to_s)
    raise "Unsafe E2E cleanup target: #{run_dir}" unless validated == run_dir

    FileUtils.remove_entry_secure(run_dir) if run_dir.exist?
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  def warn_e2e(message)
    $stderr.puts(message)
  end
end

NarouE2EBackend.run if $PROGRAM_NAME == __FILE__
