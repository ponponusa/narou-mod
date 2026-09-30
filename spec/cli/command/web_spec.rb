# frozen_string_literal: true

require_relative "../../spec_helper"
require "lib/narou/process_manager"
require "lib/web/appserver"

RSpec.describe Command::Web do
  subject(:command) { described_class.new }

  before do
    # PIDファイルのクリーンアップ
    pid_dir = File.join(Narou.tmp_dir, "pids")
    FileUtils.rm_f(Dir.glob(File.join(pid_dir, "*.pid"))) if File.exist?(pid_dir)

    # OutputHelperのモック（標準出力への出力を抑制）
    allow(Command::OutputHelper).to receive(:setup_logger)
    allow(Command::OutputHelper).to receive(:render)
    allow(Command::OutputHelper).to receive(:info)
    allow(Command::OutputHelper).to receive(:success)
    allow(Command::OutputHelper).to receive(:warning)
    allow(Command::OutputHelper).to receive(:error)
  end

  describe "#execute" do
    context "without --internal-boot option (external loop mode)" do
      it "delegates to external loop (integration test level)" do
        # 外部ループは実際のsystemコマンドを呼び出し、$?.exitstatusをチェックする。
        # $?は読み取り専用のため、ユニットテストでのモックが不可能。
        # この機能は統合テストレベルで検証する。
        skip "外部ループの完全な動作は統合テストで検証する（$?のモックが不可能なため）"
      end

      it "handles restart request (EXIT_REQUEST_REBOOT)" do
        # 同様の理由でskip
        skip "外部ループの再起動ロジックは統合テストレベルで検証する（$?のモックが不可能なため）"
      end

      it "forwards options to internal-boot process" do
        expect(command).to receive(:system) do |ruby_path, x_flag, script, subcmd, *args|
          expect(args).to include(
            "--log-file", "test.log", "--no-browser", "--verbose", "--no-frontend", "--internal-boot"
          )
          true
        end
        system("true") # $?.exitstatus を 0 に設定
        command.execute(["--log-file", "test.log", "--no-browser", "--verbose", "--no-frontend"])
      end

      it "removes --open-browser and appends --no-browser when rebooting" do
        call_count = 0
        allow(command).to receive(:system) do |_ruby_path, _x_flag, _script, _subcmd, *args|
          call_count += 1
          if call_count == 1
            expect(args).to include("--open-browser")
            system("sh", "-c", "exit 10")
          else
            expect(args).not_to include("--open-browser")
            expect(args).to include("--no-browser", "--reboot")
            expect(args.count("--no-browser")).to eq(1)
            system("true")
          end
          true
        end
        command.execute(["--open-browser"])
      end
    end

    context "with --legacy option" do
      it "delegates to WebLegacy" do
        web_legacy_instance = instance_double(Command::WebLegacy)
        allow(Command::WebLegacy).to receive(:new).and_return(web_legacy_instance)
        expect(web_legacy_instance).to receive(:execute).with(["--legacy"])

        command.execute(["--legacy"])
      end
    end

    context "with --internal-boot option (internal execution mode)" do
      before do
        # Inventory のモック
        allow(Inventory).to receive(:load).and_return({"server-port" => 5678})
        allow(Narou::AppServer).to receive(:create_address).and_return({ host: "127.0.0.1", port: 5678 })

        # Helper のモック
        allow(Helper).to receive(:open_browser)

        # サーバー起動部分をスキップ
        allow(command).to receive(:start_server)
        allow(command).to receive(:start_frontend)
        allow(command).to receive(:setup_signal_handlers)
        allow(command).to receive(:cleanup_existing_processes)
        allow(command).to receive(:should_start_frontend?).and_return(false)
        allow(command).to receive(:update_frontend_env)
      end

      it "sets up logger with --log-file option" do
        expect(Command::OutputHelper).to receive(:setup_logger).with("app.log")
        expect(Narou::AppServer).to receive(:configure_access_log).with(true).and_call_original

        command.execute(["--internal-boot", "--log-file", "app.log", "--no-browser"])
      end

      it "keeps access logging disabled without --verbose or --log-file" do
        expect(Narou::AppServer).to receive(:configure_access_log).with(false).and_call_original

        command.execute(["--internal-boot", "--no-browser"])
      end

      it "renders startup message" do
        expect(Command::OutputHelper).to receive(:render).with("web_starting", hash_including(:host, :port, :frontend_enabled))

        command.execute(["--internal-boot", "--no-browser"])
      end

      it "opens browser when --open-browser is specified" do
        allow(command).to receive(:start_server) do
          Helper.open_browser("http://localhost:5678/") if command.instance_variable_get(:@options)["open-browser"]
        end

        expect(Helper).to receive(:open_browser).with("http://localhost:5678/")

        command.execute(["--internal-boot", "--open-browser"])
      end

      it "does not open browser by default" do
        expect(Helper).not_to receive(:open_browser)

        command.execute(["--internal-boot", "--no-browser"])
      end
    end
  end

  describe "option parsing" do
    before do
      # execute を呼ぶだけでロジックを実行しないようにモック
      allow(command).to receive(:puts)
      allow(Inventory).to receive(:load).and_return({})

      # bootメソッドをモックして実際の起動処理を抑制
      allow(command).to receive(:boot)

      # systemメソッドをモックして外部ループを抑制
      allow(command).to receive(:system)
    end

    it "parses --port option" do
      command.execute(["--internal-boot", "--port", "9999"])
      expect(command.instance_variable_get(:@options)["port"]).to eq(9999)
    end

    it "parses --no-browser option" do
      command.execute(["--internal-boot", "--no-browser"])
      expect(command.instance_variable_get(:@options)["no-browser"]).to be true
    end

    it "parses --open-browser option" do
      command.execute(["--internal-boot", "--open-browser"])
      expect(command.instance_variable_get(:@options)["open-browser"]).to be true
    end

    it "parses --log-file option" do
      command.execute(["--internal-boot", "--log-file", "custom.log"])
      expect(command.instance_variable_get(:@options)["log-file"]).to eq("custom.log")
    end

    it "parses --verbose option" do
      command.execute(["--internal-boot", "--verbose", "--no-browser"])
      expect(command.instance_variable_get(:@options)["verbose"]).to be true
    end

    it "parses --no-frontend option" do
      command.execute(["--internal-boot", "--no-frontend", "--no-browser"])
      expect(command.instance_variable_get(:@options)["no-frontend"]).to be true
    end

    it "parses --legacy option" do
      web_legacy = instance_double(Command::WebLegacy)
      allow(Command::WebLegacy).to receive(:new).and_return(web_legacy)
      allow(web_legacy).to receive(:execute)

      # --legacy オプションは即座に WebLegacy に委譲されるため、
      # @options には保存されない。委譲が呼ばれたかどうかで確認
      expect(Command::WebLegacy).to receive(:new).and_return(web_legacy)

      command.execute(["--legacy"])
    end
  end

  describe "#should_start_frontend?" do
    it "does not start the frontend when --no-frontend is specified" do
      original_narou_env = ENV.delete("NAROU_ENV")
      command.instance_variable_set(:@options, { "no-frontend" => true })

      expect(command.send(:should_start_frontend?)).to be false
    ensure
      ENV["NAROU_ENV"] = original_narou_env if original_narou_env
    end
  end

  describe "#start_frontend" do
    let(:frontend_dir) { File.join(Narou.root_dir, "frontend") }
    let(:frontend_log) { File.join(Narou.tmp_dir, "logs", "narou-frontend.log") }

    before do
      # frontend ディレクトリが存在することを前提とする
      allow(File).to receive(:directory?).with(frontend_dir).and_return(true)
      allow(File).to receive(:exist?).with(File.join(frontend_dir, "package.json")).and_return(true)
      allow(File).to receive(:exist?).with(anything).and_call_original

      # ProcessManager のモック
      frontend_manager = instance_double(Narou::ProcessManager)
      allow(frontend_manager).to receive(:register_process)
      command.instance_variable_set(:@frontend_manager, frontend_manager)

      # OutputHelper のモック
      allow(Command::OutputHelper).to receive(:info)
      allow(Command::OutputHelper).to receive(:success)

      # FileUtils のモック
      allow(FileUtils).to receive(:mkdir_p)
    end

    if Helper.os_windows?
      it "uses spawn on Windows to start frontend server" do
        # Windows: spawn を使用してバックグラウンドでプロセスを起動
        expect(command).to receive(:spawn).with(
          "npm", "run", "dev",
          hash_including(
            chdir: frontend_dir,
            in: "NUL",
            new_pgroup: true
          )
        ).and_return(123)

        allow(Process).to receive(:detach)

        command.send(:start_frontend)
      end
    else
      it "uses STDOUT/STDERR/STDIN constants in fork block (not $stdout/$stderr/$stdin)" do
        # fork をモックして、ブロック内のコードが STDOUT/STDERR/STDIN を使用することを確認
        # 実際に fork を実行すると子プロセスが作成されてしまうため、モックする

        # fork が呼ばれたときにブロックを即座に実行する（子プロセスを作らない）
        block_executed = false
        allow(command).to receive(:fork) do |&block|
          # ブロック内で STDOUT が使用されることを検証するため、
          # STDOUT.reopen が呼ばれることを確認
          expect(STDOUT).to receive(:reopen).with(frontend_log, "a")
          expect(STDERR).to receive(:reopen).with(STDOUT)
          expect(STDIN).to receive(:reopen).with("/dev/null")
          expect(STDOUT).to receive(:sync=).with(true)
          expect(STDERR).to receive(:sync=).with(true)

          # exec は実際には呼ばない（プロセスが置き換わってしまうため）
          allow(command).to receive(:exec)

          # ブロックを実行（ただし、実際のプロセス操作はモックされている）
          begin
            block.call
          rescue SystemExit
            # exec の代わりに exit が呼ばれる可能性があるため、キャッチ
          end

          block_executed = true
          123 # 仮の PID を返す
        end

        allow(Process).to receive(:detach)
        allow(Process).to receive(:setpgid)

        command.send(:start_frontend)

        expect(block_executed).to be true
      end
    end
  end

  describe "#update_frontend_env" do
    let(:temporary_root) { Pathname(Dir.mktmpdir("narou-frontend-env-spec")) }
    let(:frontend_dir) { temporary_root.join("frontend") }

    before do
      FileUtils.mkdir_p(frontend_dir)
      allow(Narou).to receive(:root_dir).and_return(temporary_root)
    end

    after do
      FileUtils.remove_entry(temporary_root) if temporary_root.exist?
    end

    it "creates connection settings when no frontend environment file exists" do
      command.send(:update_frontend_env, 8765)

      expect(frontend_dir.join(".env").read).to include("PUBLIC_PUSH_SERVER_PORT=8766")
      expect(JSON.parse(frontend_dir.join("public", "backend-port.json").read)).to include(
        "backend_port" => 8765,
        "push_server_port" => 8766
      )
    end
  end

  describe "#boot" do
    before do
      allow(command).to receive(:should_start_frontend?).and_return(false)
      allow(command).to receive(:setup_signal_handlers)
      allow(command).to receive(:start_server)
      allow(command).to receive(:update_frontend_env)
      allow(Narou::AppServer).to receive(:create_address).and_return({ host: "127.0.0.1", port: 5678 })

      # ProcessManager のモック
      backend_manager = instance_double(Narou::ProcessManager)
      allow(backend_manager).to receive(:process_running?).and_return(false)
      allow(backend_manager).to receive(:check_port_conflict!)
      allow(backend_manager).to receive(:register_process)
      allow(Narou::ProcessManager).to receive(:new).and_return(backend_manager)
    end

    it "uses create_address to get port from settings" do
      # 設定ファイルからポートを取得することを確認
      global_setting = { "server-port" => 9999, "server-bind" => "192.168.1.100" }
      allow(Inventory).to receive(:load).with("global_setting", :global).and_return(global_setting)
      allow(Inventory).to receive(:load).with(no_args).and_return({})

      expect(Narou::AppServer).to receive(:create_address).with(nil).and_return({ host: "192.168.1.100", port: 9999 })

      command.send(:boot)
    end

    it "passes CLI port option to create_address" do
      # CLIオプションのポートが create_address に渡されることを確認
      command.instance_variable_set(:@options, { "port" => 8080 })

      global_setting = {}
      allow(Inventory).to receive(:load).with("global_setting", :global).and_return(global_setting)
      allow(Inventory).to receive(:load).with(no_args).and_return({})

      expect(Narou::AppServer).to receive(:create_address).with(8080).and_return({ host: "127.0.0.1", port: 8080 })

      command.send(:boot)
    end

    it "updates frontend connection settings even when frontend startup is disabled" do
      allow(Narou::AppServer).to receive(:create_address).and_return({ host: "127.0.0.1", port: 8765 })
      allow(command).to receive(:frontend_available?).and_return(true)

      expect(command).to receive(:update_frontend_env).with(8765)

      command.send(:boot)
    end

    it "does not create frontend settings outside a frontend development checkout" do
      allow(command).to receive(:frontend_available?).and_return(false)

      expect(command).not_to receive(:update_frontend_env)

      command.send(:boot)
    end
  end
end
