# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../../scripts/run_e2e_backend"

RSpec.describe NarouE2EBackend do
  let(:run_id) { "run-20260813000000-012345abcdef" }
  let(:run_dir) { described_class::RUNS_ROOT.join(run_id) }
  let(:temporary_root) { Pathname(Dir.mktmpdir("narou-e2e-backend-spec")) }

  before do
    stub_const("NarouE2EBackend::RUNS_ROOT", temporary_root.join("runs"))
    FileUtils.mkdir_p(described_class::RUNS_ROOT)
  end

  after do
    described_class.release_run_lock!
    FileUtils.remove_entry(temporary_root) if temporary_root.exist?
  end

  describe ".recover_stale_runs!" do
    it "removes a manifestless run directory without signaling a process" do
      FileUtils.mkdir_p(run_dir)

      expect(described_class).not_to receive(:terminate_process_group)

      described_class.recover_stale_runs!

      expect(run_dir).not_to exist
    end

    it "removes an ownership-mismatched run directory without signaling a process" do
      FileUtils.mkdir_p(run_dir)
      manifest_path = run_dir.join("e2e-process.json")
      manifest_path.write(JSON.generate({
        "run_id" => run_id,
        "pid" => 12_345,
        "pgid" => 12_345,
        "command" => "expected command",
        "started_at" => "expected start",
        "cwd" => run_dir.to_s
      }))
      allow(described_class).to receive(:process_alive?).with(12_345).and_return(true)
      allow(described_class).to receive(:process_snapshot).with(12_345).and_return({
        "command" => "reused pid command",
        "started_at" => "different start",
        "cwd" => "/tmp/unrelated"
      })
      expect(described_class).not_to receive(:terminate_process_group)

      described_class.recover_stale_runs!

      expect(run_dir).not_to exist
    end

    it "removes a malformed manifest directory without signaling a process" do
      FileUtils.mkdir_p(run_dir)
      run_dir.join("e2e-process.json").write("not-json")
      expect(described_class).not_to receive(:terminate_process_group)

      expect { described_class.recover_stale_runs! }.not_to raise_error

      expect(run_dir).not_to exist
    end

    it "leaves unrecognized directories untouched without blocking recovery" do
      unrecognized = described_class::RUNS_ROOT.join("manual-inspection")
      FileUtils.mkdir_p(unrecognized)

      expect { described_class.recover_stale_runs! }.not_to raise_error

      expect(unrecognized).to exist
    end
  end

  describe ".acquire_run_lock!" do
    it "refuses a concurrent backend wrapper without touching its run directory" do
      active_run = described_class::RUNS_ROOT.join("run-20260813000001-fedcba987654")
      FileUtils.mkdir_p(active_run)
      lock = File.new(described_class::RUNS_ROOT.join(".run.lock"), File::RDWR | File::CREAT, 0o600)
      lock.flock(File::LOCK_EX | File::LOCK_NB)

      expect { described_class.acquire_run_lock! }.to raise_error(SystemExit)
      expect(active_run).to exist
    ensure
      lock&.close
    end
  end
end
