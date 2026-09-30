# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/cli/command/web_legacy"
require "lib/cli/command/output_helper"
require "lib/utilities/helper"

module Command
  class Web < CommandBase
    def self.oneline_help
      "WEBアプリケーション用サーバを起動します"
    end

    def initialize
      super("[options...]")
      @opt.separator <<~HELP
        ・WEBアプリケーション用サーバを起動します
        ・小説の管理及び設定をブラウザで行うことができます
        ・--port を指定しない場合、ポートは初回起動時にランダムで設定します
          (以降同じ設定を引き継ぎます)
        ・フォアグラウンドで実行されます（Ctrl+Cで停止）
        ・サーバの停止は Ctrl+C または 'narou-mod stop'

        Examples:
          narou-mod web                           # サーバーを起動
          narou-mod web -p 4567                   # ポート4567で起動
          narou-mod web --open-browser            # ブラウザを自動で開く
          narou-mod web --log-file app.log        # ログをファイルに出力
          narou-mod web --verbose                 # CLI側に詳細ログを出力

        Options:
      HELP
      @opt.on("-p", "--port PORT", Integer, "起動するポートを指定") { |port|
        @options["port"] = port
      }
      @opt.on("-n", "--no-browser", "起動時にブラウザは開かない") {
        @options["no-browser"] = true
      }
      @opt.on("-o", "--open-browser", "起動時にブラウザを開く") {
        @options["open-browser"] = true
      }
      @opt.on("--log-file FILE", "ログをファイルに出力（デフォルト: 標準出力）") { |file|
        @options["log-file"] = file
      }
      @opt.on("-v", "--verbose", "CLI側に詳細ログを出力（デフォルト: Web UIコンソールのみ）") {
        @options["verbose"] = true
      }
      @opt.on("-l", "--legacy", "旧 Haml UI を使用する (デフォルトは新 Astro UI)") {
        @options["legacy"] = true
      }
      @opt.on("-f", "--force", "既存のプロセスを強制的に停止して起動") {
        @options["force"] = true
      }
      @opt.on("--no-frontend", "Astro 開発サーバーを起動しない") {
        @options["no-frontend"] = true
      }
    end

    def execute(argv)
      # --legacy オプションが指定された場合は WebLegacy に委譲
      if argv.include?("--legacy") || argv.include?("-l")
        return WebLegacy.new.execute(argv)
      end

      # --internal-boot オプションの処理（外部ループからの内部実行用）
      if argv.include?("--internal-boot")
        argv.delete("--internal-boot")
        @rebooted = !!argv.delete("--reboot")
        super

        # OutputHelperの初期化
        Command::OutputHelper.setup_logger(@options["log-file"])

        boot
      else
        # 外部ループで再起動に対応（legacy版と同じパターン）
        # --bootオプションは外部ループ用のフラグとして使用し、内部では--internal-bootに置き換える
        argv.delete("--boot") # --bootオプションを削除
        super
        argv << "--backtrace" if $display_backtrace
        argv << "--no-color" if $disable_color
        argv << "--port" << @options["port"].to_s if @options["port"]
        argv << "--log-file" << @options["log-file"] if @options["log-file"]
        argv << "--no-browser" if @options["no-browser"]
        argv << "--open-browser" if @options["open-browser"]
        argv << "--verbose" if @options["verbose"]
        argv << "--force" if @options["force"]
        argv << "--no-frontend" if @options["no-frontend"]
        argv << "--internal-boot" # 内部実行用のフラグを追加
        argv_copy = argv.dup

        # 外部ループでのシグナルハンドラ（クリーンアップ用）
        require "lib/narou/process_manager"
        backend_manager = Narou::ProcessManager.new("narou-backend")
        frontend_manager = Narou::ProcessManager.new("narou-frontend")

        Signal.trap("INT") do
          puts "\n\nサーバーを停止しています..."
          backend_manager.stop_process(timeout: 3) if backend_manager.process_running?
          frontend_manager.stop_process(timeout: 3) if frontend_manager.process_running?
          exit 0
        end

        begin
          loop do
            system(RbConfig.ruby, "-x", $0, "web", *argv)
            break unless $?.exitstatus == Narou::EXIT_REQUEST_REBOOT

            argv = argv_copy.dup
            argv.delete("--open-browser")
            argv.delete("--no-browser")
            argv.push("--no-browser", "--reboot")
          end
        rescue Interrupt
          # シグナルハンドラで処理されるのでここには来ない
          sleep 1
        end
      end
    end

    private

    def host
      @server_host || @options["host"] || "127.0.0.1"
    end

    # 表示用のホスト名（127.0.0.1をlocalhostに変換）
    def display_host
      host == "127.0.0.1" ? "localhost" : host
    end

    # 既存プロセスをクリーンアップ
    def cleanup_existing_processes(port)
      # バックエンドプロセスのチェック
      if @backend_manager.process_running?
        info = @backend_manager.read_process_info
        Command::OutputHelper.warning("既存のバックエンドプロセスを検出しました (PID: #{info[:pid]})")

        if @options["force"]
          Command::OutputHelper.info("既存プロセスを停止しています...")
          @backend_manager.stop_process
        else
          # プロセスが存在する場合はエラー
          @backend_manager.cleanup_stale_process!
        end
      end

      # ポート競合のチェック
      @backend_manager.check_port_conflict!(port, host)
      @backend_manager.check_port_conflict!(port + 1, host) # PushServerポート

      # フロントエンドプロセスのチェック
      if should_start_frontend? && @frontend_manager
        if @frontend_manager.process_running?
          info = @frontend_manager.read_process_info
          Command::OutputHelper.warning("既存のフロントエンドプロセスを検出しました (PID: #{info[:pid]})")

          if @options["force"]
            Command::OutputHelper.info("既存プロセスを停止しています...")
            @frontend_manager.stop_process
          else
            # プロセスが存在する場合はエラー
            @frontend_manager.cleanup_stale_process!
          end
        end

        # フロントエンドポートの競合チェック
        @frontend_manager.check_port_conflict!(4321, host)
      end
    rescue Narou::ProcessManager::ProcessConflictError => e
      # プロセス競合の場合、ユーザーに選択肢を提示
      Command::OutputHelper.error(e.message)

      require "lib/utilities/tty_helper"
      raise e unless TTYHelper.ask_yes_no("自動的にクリーンアップしますか?", default: false)
      Command::OutputHelper.info("既存プロセスをクリーンアップしています...")
      @backend_manager.stop_process
      @frontend_manager&.stop_process
      sleep 1
      # 再度チェック
      @backend_manager.check_port_conflict!(port, host)
      @backend_manager.check_port_conflict!(port + 1, host)
      @frontend_manager&.check_port_conflict!(4321, host)
    end

    def boot
      # Narouモジュールとappserverを先にロード（設定ファイルの読み込みに必要）
      require "lib/core/narou"
      require "lib/narou/process_manager"
      require "lib/web/appserver"
      access_log_enabled = !!(@options["verbose"] || @options["log-file"])
      Narou::AppServer.configure_access_log(access_log_enabled)

      # 設定ファイルからポート/ホストを取得
      params = Narou::AppServer.create_address(@options["port"])
      @server_host = params[:host]
      @server_port = params[:port]

      # フロントエンド設定を更新
      update_frontend_env(@server_port) if frontend_available?

      # 起動メッセージを表示
      Command::OutputHelper.render("web_starting", {
        host: display_host,
        port: @server_port,
        frontend_enabled: should_start_frontend?
      })

      # プロセスマネージャーを初期化
      @backend_manager = Narou::ProcessManager.new("narou-backend")
      @frontend_manager = Narou::ProcessManager.new("narou-frontend") if should_start_frontend?

      # 既存プロセスのクリーンアップ
      cleanup_existing_processes(@server_port)

      # シグナルハンドラを設定（Ctrl+Cで停止）
      setup_signal_handlers

      # プロセス情報を登録
      @backend_manager.register_process(port: @server_port, metadata: {
        host: host,
        frontend_enabled: should_start_frontend?
      })

      # フロントエンドを起動
      start_frontend if should_start_frontend?

      # バックエンドサーバーを起動
      start_server
    rescue Narou::ProcessManager::ProcessConflictError, Narou::ProcessManager::PortConflictError => e
      Command::OutputHelper.error(e.message)
      exit 1
    end

    def setup_signal_handlers
      # Ctrl+C (SIGINT) と SIGTERM のハンドラを設定
      Signal.trap("INT") do
        Command::OutputHelper.info("\n\nサーバーを停止しています...")
        stop_all_servers
        exit 0
      end

      Signal.trap("TERM") do
        Command::OutputHelper.info("SIGTERMを受信しました。サーバーを停止しています...")
        stop_all_servers
        exit 0
      end
    end

    def stop_all_servers
      Command::OutputHelper.info("関連プロセスを停止しています...")

      # WebWorkerを停止
      begin
        Narou::WebWorker.stop if defined?(Narou::WebWorker)
      rescue StandardError => e
        # エラーが発生してもクリーンアップを続行
        Command::OutputHelper.error("WebWorkerの停止中にエラーが発生しました: #{e.message}")
      end

      # PushServerを停止
      begin
        push_server = Narou::PushServer.instance
        push_server&.quit
      rescue StandardError => e
        Command::OutputHelper.error("PushServerの停止中にエラーが発生しました: #{e.message}")
      end

      stop_frontend_process

      # バックエンドのPIDファイルをクリーンアップ
      @backend_manager&.cleanup_files

      Command::OutputHelper.success("すべてのプロセスを停止しました")
    end

    # フロントエンドプロセスのみを停止
    def stop_frontend_process
      # フロントエンドサーバーをProcessManager経由で停止
      return unless should_start_frontend? && @frontend_manager
      begin
        if @frontend_manager.process_running?
          Command::OutputHelper.info("フロントエンドサーバーを停止中...")
          @frontend_manager.stop_process(timeout: 5)
        end
      rescue StandardError => e
        Command::OutputHelper.error("フロントエンドの停止中にエラーが発生しました: #{e.message}")
      ensure
        @frontend_manager.cleanup_files
      end
    end

    def stop_frontend
      frontend_pid_file = File.join(Narou.tmp_dir, "pids", "narou-frontend.pid")

      return unless File.exist?(frontend_pid_file)
      pid = File.read(frontend_pid_file).to_i
      begin
        Process.kill("TERM", pid)
        File.delete(frontend_pid_file)
      rescue Errno::ESRCH
        # プロセスが既に終了している
        File.delete(frontend_pid_file) if File.exist?(frontend_pid_file)
      end
    end

    def should_start_frontend?
      # テスト環境ではフロントエンドを起動しない
      return false if ENV["NAROU_ENV"] == "test"

      # --no-frontendオプションが指定されている場合は起動しない
      return false if @options["no-frontend"]

      frontend_available?
    end

    def frontend_available?
      # 開発環境（frontend/ディレクトリが存在）の場合のみ
      frontend_dir = File.join(Narou.root_dir, "frontend")
      File.directory?(frontend_dir) && File.exist?(File.join(frontend_dir, "package.json"))
    end

    def start_frontend
      frontend_dir = File.join(Narou.root_dir, "frontend")
      frontend_log = File.join(Narou.tmp_dir, "logs", "narou-frontend.log")

      Command::OutputHelper.info("フロントエンドサーバーを起動しています...")

      # ログディレクトリを作成
      log_dir = File.dirname(frontend_log)
      FileUtils.mkdir_p(log_dir) unless File.exist?(log_dir)

      if Helper.os_windows?
        # Windows: spawn を使用してバックグラウンドでプロセスを起動
        pid = spawn(
          "npm", "run", "dev",
          chdir: frontend_dir,
          in: "NUL",
          out: [frontend_log, "a"],
          err: %i(child out),
          new_pgroup: true
        )

        # ProcessManagerにプロセス情報を登録
        @frontend_manager.register_process(pid: pid, port: 4321, metadata: {
          command: "npm run dev",
          log_file: frontend_log
        })
      else
        # Unix系: fork を使用してバックグラウンドでプロセスを起動
        pid = fork do
          # 新しいプロセスグループを作成（stop時に子プロセスも停止できるようにする）
          ::Process.setpgid(0, 0)

          Dir.chdir(frontend_dir)

          # 注意: この時点で親プロセスの$stdoutはNarou::Loggerに置き換わっているため、
          # オリジナルのSTDOUT, STDERR, STDIN定数を使用する必要がある
          # rubocop:disable Style/GlobalStdStream
          STDIN.reopen("/dev/null")
          STDOUT.reopen(frontend_log, "a")
          STDERR.reopen(STDOUT)
          STDOUT.sync = true
          STDERR.sync = true
          # rubocop:enable Style/GlobalStdStream

          # npm run dev を実行
          exec("npm", "run", "dev")
        end

        # ProcessManagerにプロセス情報を登録（プロセスグループIDを記録）
        @frontend_manager.register_process(pid: pid, port: 4321, metadata: {
          pgid: -pid, # プロセスグループIDは負の値で記録
          command: "npm run dev",
          log_file: frontend_log
        })
      end

      # プロセスをデタッチ（親プロセスが終了してもフロントエンドは継続）
      Process.detach(pid)

      Command::OutputHelper.success("フロントエンドサーバーを起動しました (PID: #{pid})")
      sleep 1 # フロントエンドサーバーの起動を待つ
    end

    def start_server
      port = @server_port

      # Web UIモードを有効化（インタラクティブプロンプトを無効化）
      Narou.web = true

      # サーバー起動完了メッセージ（$stdoutを置き換える前に表示）
      Command::OutputHelper.render("web_started", {
        host: display_host,
        port: port,
        frontend_enabled: should_start_frontend?
      })

      # PushServerの初期化と起動
      push_server = Narou::PushServer.instance
      push_server.port = port + 1
      # PushServerはメインサーバーと同じホストにバインド
      # （LANアクセス時もフロントエンドと同じホストで接続可能にするため）
      push_server.host = host
      push_server.accepted_domains = ["*"]
      Narou::AppServer.push_server = push_server

      # WorkerとWebWorkerにもpush_serverを設定
      Narou::Worker.push_server = push_server

      # PushServerを起動
      push_server.run

      # StreamingLoggerを設定（標準出力をPushServerに送信）
      require "lib/web/logging/streaming_logger"
      verbose = @options["verbose"] || false
      $stdout = Narou::StreamingLogger.new(push_server, $stdout, verbose: verbose)
      $stdout2 = if Inventory.load["concurrency"]
                   Narou::StreamingLogger.new(push_server, $stdout2, target_console: "stdout2", verbose: verbose)
                 else
                   $stdout
                 end

      # WebWorkerを起動（タスクキュー処理用）
      Narou::WebWorker.run
      # ConvertWorkerを起動（変換タスク専用処理用）
      require "lib/web/workers/convert_worker"
      Narou::ConvertWorker.run

      if @options["open-browser"]
        frontend_url = should_start_frontend? ? "http://#{display_host}:4321/" : "http://#{display_host}:#{port}/"
        Helper.open_browser(frontend_url)
      end

      Narou::AppServer.set(:bind, host)
      Narou::AppServer.set(:port, port)
      Narou::AppServer.run!
    end

    def update_frontend_env(port)
      frontend_dir = File.join(Narou.root_dir, "frontend")
      env_file = File.join(frontend_dir, ".env")

      ws_port = port + 1

      # .envファイルを読み込むか、なければテンプレートを使用
      env_content = if File.exist?(env_file)
                      File.read(env_file)
                    else
                      <<~ENV
                        # バックエンドAPIサーバーのURL
                        # 開発時はViteのプロキシを使用するため空文字列
                        PUBLIC_API_BASE_URL=

                        # PushServer WebSocketポート（HTTPサーバーポート + 1）
                        PUBLIC_PUSH_SERVER_PORT=5679

                        # 開発モード設定
                        PUBLIC_DEV_MODE=true
                      ENV
                    end

      # PUBLIC_PUSH_SERVER_PORTを更新
      env_content = env_content.gsub(/^PUBLIC_PUSH_SERVER_PORT=.*$/, "PUBLIC_PUSH_SERVER_PORT=#{ws_port}")

      File.write(env_file, env_content)

      # astro.config.mjsのプロキシ設定も更新
      config_file = File.join(frontend_dir, "astro.config.mjs")
      if File.exist?(config_file)
        config_content = File.read(config_file)
        config_content = config_content.gsub(%r{target:\s*['"]http://localhost:\d+['"]}, "target: 'http://localhost:#{port}'")
        File.write(config_file, config_content)
      end

      # ポート情報をJSONファイルとして保存（フロントエンドから読み込み可能にする）
      port_info_file = File.join(frontend_dir, "public", "backend-port.json")
      port_info_dir = File.dirname(port_info_file)
      FileUtils.mkdir_p(port_info_dir) unless File.exist?(port_info_dir)

      require "json"
      port_info = {
        backend_port: port,
        push_server_port: ws_port,
        updated_at: Time.now.iso8601
      }
      File.write(port_info_file, JSON.pretty_generate(port_info))
    end
  end
end
