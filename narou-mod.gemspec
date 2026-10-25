# frozen_string_literal: true

# -*- mode: ruby -*-
# -*- coding: utf-8 -*-

root = File.expand_path("..", __FILE__)
$LOAD_PATH.unshift(root) unless $LOAD_PATH.include?(root)

require "lib/core/version"
require "fileutils"

module Narou
  module_function

  # コミットバージョンファイルを生成
  def create_git_commit_version
    File.write("commitversion", `git describe --always`.strip)
    "commitversion"
  end

  # フロントエンドのビルド（コミットIDが異なる場合のみ実行）
  def build_frontend_if_needed
    frontend_dir = File.join(File.dirname(__FILE__), "frontend")
    dist_dir     = File.join(frontend_dir, "dist")
    commit_file  = File.join(dist_dir, ".build-commit")

    current_commit = `git describe --always`.strip

    # 既存のビルドコミットIDと比較
    if File.exist?(commit_file)
      built_commit = File.read(commit_file).strip
      return if built_commit == current_commit
    end

    # npm が利用可能かチェック
    null_device = Gem.win_platform? ? "NUL" : "/dev/null"
    unless system("npm --version > #{null_device} 2>&1")
      warn "WARNING: npm is not available. Skipping frontend build."
      warn "         Run 'npm run build' in frontend/ directory manually."
      return
    end

    warn "Building frontend (commit: #{current_commit})..."
    Dir.chdir(frontend_dir) do
      unless system("npm ci --silent")
        warn "WARNING: npm ci failed"
        return
      end
      unless system("npm run build --silent")
        warn "WARNING: npm run build failed"
        return
      end
    end

    # ビルド成功時にコミットIDを記録
    FileUtils.mkdir_p(dist_dir)
    File.write(commit_file, current_commit)
    warn "Frontend build completed."
  end
end

Encoding.default_external = Encoding::UTF_8

# gem build 時にフロントエンドをビルド
Narou.build_frontend_if_needed

# =============================================================================
# Gem Specification
# =============================================================================
Gem::Specification.new do |gem|
  # ---------------------------------------------------------------------------
  # 基本情報
  # ---------------------------------------------------------------------------
  gem.name        = "narou-mod"
  gem.version     = ::Narou::VERSION
  gem.license     = "MIT"
  gem.authors     = [
    "whiteleaf7 (original)",
    "Rumia-Channel (fork from)",
    "ponponusa (mod maintainer)"
  ]
  gem.email       = ["init0531.usa@gmail.com"]
  gem.homepage    = "https://github.com/ponponusa/narou-mod"
  gem.summary     = "Narou.rb MOD ― 小説家になろうダウンローダ＆縦書用整形スクリプト"
  gem.description = "小説家になろうで公開されている小説を管理し電子書籍データへ変換します。"

  gem.required_ruby_version = ">= 3.4.0"

  # ---------------------------------------------------------------------------
  # インストール後メッセージ
  # ---------------------------------------------------------------------------
  gem.post_install_message = <<~MSG
    ============================================================
     Narou.rb_MOD v#{::Narou::VERSION} がインストールされました 🎉

      コマンドヘルプ    :  narou-mod --help
      初期設定          :  narou-mod init
      小説の追加        :  narou-mod add <小説ID>
      小説ダウンロード  :  narou-mod download <小説ID>
      Webサーバー起動   :  narou-mod web

     更新情報: https://github.com/ponponusa/narou-mod/releases
    ============================================================
  MSG

  # ---------------------------------------------------------------------------
  # ファイル構成
  # ---------------------------------------------------------------------------
  tracked_files = `git ls-files`.split("\n").select { |fn| File.exist?(fn) }
  gem.files = tracked_files.reject { |fn| fn.start_with?("spec/") }
  gem.files << Narou.create_git_commit_version

  # フロントエンドのビルド成果物を追加（git管理外でも含める）
  if Dir.exist?("frontend/dist")
    frontend_dist = Dir.glob("frontend/dist/**/*").select { |f| File.file?(f) }
    gem.files += frontend_dist
  end

  gem.executables = gem.files.grep(%r{^bin/}).map { |f| File.basename(f) }

  # ---------------------------------------------------------------------------
  # 実行時依存関係（Runtime Dependencies）
  # ---------------------------------------------------------------------------

  # 基本ライブラリ
  gem.add_runtime_dependency "activesupport",      "~> 8.0",  ">= 8.1.4"
  gem.add_runtime_dependency "diff-lcs",           "~> 1.6",  ">= 1.6.2"
  gem.add_runtime_dependency "memoist",            "~> 0.16.2"
  gem.add_runtime_dependency "systemu",            "~> 2.6",  ">= 2.6.5"
  gem.add_runtime_dependency "termcolorlight",     "~> 1.0",  ">= 1.1.1"

  # ファイル処理
  gem.add_runtime_dependency "nokogiri",           "~> 1.19"
  gem.add_runtime_dependency "rubyzip",            "~> 3.2",  ">= 3.2.0"

  # メール送信
  gem.add_runtime_dependency "mail",               "~> 2.9",  ">= 2.9.0"
  gem.add_runtime_dependency "pony",               "~> 1",    ">= 1.13"

  # Webサーバー（Sinatra + Puma）
  gem.add_runtime_dependency "puma",               "~> 8.0"
  gem.add_runtime_dependency "rack",               ">= 3.0",  "< 4"
  gem.add_runtime_dependency "rack-session",       "~> 2.1",  ">= 2.1.1"
  gem.add_runtime_dependency "rackup",             "~> 2.1"
  gem.add_runtime_dependency "sinatra",            "~> 4.2",  ">= 4.2.0"
  gem.add_runtime_dependency "sinatra-contrib",    "~> 4.2",  ">= 4.2.0"

  # テンプレートエンジン
  gem.add_runtime_dependency "erubi",              "~> 1.13.1"
  gem.add_runtime_dependency "haml",               ">= 5.2.2", "< 6"
  gem.add_runtime_dependency "sass-embedded",      "~> 1.93", ">= 1.93.2"
  gem.add_runtime_dependency "tilt",               "~> 2.7"

  # TUI（ターミナルUI）
  gem.add_runtime_dependency "tty-box",            "~> 0.7"
  gem.add_runtime_dependency "tty-markdown",       "~> 0.7"
  gem.add_runtime_dependency "tty-prompt",         "~> 0.23"
  gem.add_runtime_dependency "tty-spinner",        "~> 0.9"

  # ネイティブ拡張・FFI
  gem.add_runtime_dependency "ffi",                "~> 1.17", ">= 1.17.2"
  gem.add_runtime_dependency "fiddle",             "~> 1.0"

  # Ruby標準ライブラリ（bundled gem化対応）
  gem.add_runtime_dependency "csv",                "~> 3.3"
  gem.add_runtime_dependency "nkf",                "~> 0.3.0"
  gem.add_runtime_dependency "ostruct",            "~> 0.6.3"
  gem.add_runtime_dependency "psych",              "~> 5.2"
  gem.add_runtime_dependency "rexml",              "~> 3.4"

  # その他
  gem.add_runtime_dependency "open_uri_redirections", "~> 0.2", ">= 0.2.1"
  gem.add_runtime_dependency "parallel",              "~> 2.3"
  gem.add_runtime_dependency "unicode-display_width", ">= 1.5", "< 3.0"

  # ---------------------------------------------------------------------------
  # プラットフォーム固有の依存関係
  # ---------------------------------------------------------------------------
  # gem build 時のプラットフォームに応じて依存関係を切り替える。
  # CI では Linux と Windows で別々に gem build を実行し、
  # それぞれのプラットフォーム向け gem をリリースする。
  #
  # NOTE: プラットフォーム固有の gem (win32ole, bootsnap) は Gemfile の
  #       platforms 指定で管理しているため、開発時の bundle install は
  #       問題なく動作する。gemspec での指定は gem install 時のみ影響。
  #
  # Windows: x64-mingw-ucrt プラットフォーム固有gem
  # Linux/macOS: Gem::Platform::RUBY (汎用gem、全アーキテクチャ対応)
  gem.platform = Gem.win_platform? ? Gem::Platform.new("x64-mingw-ucrt") : Gem::Platform::RUBY

  if Gem.win_platform?
    gem.add_runtime_dependency "win32ole", "~> 1.9"
  else
    # Linux/macOS は汎用 gem（x86_64/arm64/aarch64 等、全アーキテクチャ対応）
    gem.add_runtime_dependency "bootsnap", "~> 1"
  end

  # ---------------------------------------------------------------------------
  # 開発時依存関係（Development Dependencies）
  # ---------------------------------------------------------------------------
  gem.add_development_dependency "awesome_print",         "~> 1.9"
  gem.add_development_dependency "benchmark",             "~> 0.5"
  gem.add_development_dependency "pry",                   "~> 0.16"
  gem.add_development_dependency "pry-byebug",            "~> 3.12"
  gem.add_development_dependency "rack-test",             "~> 2.1"
  gem.add_development_dependency "rspec",                 "~> 3.13"
  gem.add_development_dependency "rspec-retry",           "~> 0.6"
  gem.add_development_dependency "rspec_junit_formatter", "~> 0.8"
  gem.add_development_dependency "rubocop",               "~> 1.92"
  gem.add_development_dependency "ruby-prof",             "~> 2.0", ">= 2.0.5"
  gem.add_development_dependency "simplecov",             "~> 1.3"
  gem.add_development_dependency "timecop",               "~> 0.9"
end
