require "rspec"
require "pry"
require "simplecov"

# プロジェクトルートをロードパスに追加（相対パス地獄回避）
$LOAD_PATH.unshift File.expand_path("..", __dir__)

# Windows環境でのTempfileファイナライザー警告を抑制
# $stderrをラップして特定の警告メッセージをフィルタリング
if Gem.win_platform?
  class FilteredStderr
    def initialize(original)
      @original = original
      @filter_patterns = [
        /Exception in finalizer/,
        /Permission denied @ apply2files/,
        /RackMultipart.*\.zip/
      ]
    end

    def write(message)
      return 0 if @filter_patterns.any? { |pattern| message.to_s =~ pattern }
      @original.write(message)
    end

    def method_missing(method, *args, **kwargs, &block)
      @original.send(method, *args, **kwargs, &block)
    end

    def respond_to_missing?(method, include_private = false)
      @original.respond_to?(method, include_private)
    end
  end

  $stderr = FilteredStderr.new($stderr)
end

# ARGV退避: lib/配下のコードがrequire時にARGVを誤解釈しないように
original_argv = ARGV.dup
ARGV.clear

# lib/配下からcommandをrequireしとく
require "lib/cli/commandbase"
Dir[File.expand_path("../lib/cli/command/**/*.rb", __dir__)].sort.each { |f| require f }

# ARGV復元: RSpecが引数を正しく処理できるように
ARGV.replace(original_argv)

SimpleCov.start do
  # テスト関連
  add_filter "/spec/"

  # フロントエンド（Astro/Svelte）
  add_filter "/frontend/"

  # Legacy Web UI（静的ファイルとビュー）
  add_filter "/lib/web/public/"
  add_filter "/lib/web/views/"

  # テンプレートファイル（ERB等）
  add_filter "/lib/cli/command/markdown/"

  # ドキュメント・設定ファイル
  add_filter "/docs/"
  add_filter "/coverage/"
  add_filter "/preset/"
  add_filter "/template/"
  add_filter "/tmp/"
  add_filter "/webnovel/"

  # 小説データディレクトリ
  add_filter "/小説データ/"
  add_filter "/小説データ_perf_test/"

  # 実行スクリプト・バイナリ
  add_filter "/bin/"
  add_filter "/vendor/"
  add_filter "/.bundle/"

  # 隠しディレクトリ・ファイル
  add_filter %r{^/\.} # . で始まるファイル・ディレクトリ

  # プロジェクトルートの個別ファイル（narou.rb と clean_appserver.rb 以外）
  add_filter "/narou-mod.gemspec"
  add_filter "/narou-mod.bat"
  add_filter "/Rakefile"
  add_filter "/Gemfile"
  add_filter "/commitversion"
  add_filter "/performance_report.txt"
  add_filter "/trace_dump.txt"
  add_filter "/backend.log"
  add_filter "/sync-to-windows.sh"
  add_filter "/rsync.env"
  add_filter "/narou-mod-2.1.0.dev.gem"
end

Encoding.default_external = Encoding::UTF_8

# 環境を指定
RSpec.configure do |config|
  config.before(:suite) do
    ENV["NAROU_NONINTERACTIVE"] = "1"
    ENV["CI"] = ENV["CI"] || "true"
    ENV["NAROU_ENV"] = "test"
  end
end

# 環境に依存しないようにタイムゾーンを固定してテストする
ENV["TZ"] = "Asia/Tokyo"

Dir[File.expand_path("support/**/*.rb", __dir__)].each do |f|
  require f
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # Windows環境でのファイルハンドル解放
  # GCを実行してTempfileのファイナライザーを呼び出す
  config.after(:suite) do
    GC.start
    if Gem.win_platform?
      sleep 0.1
      GC.start
    end
  end
end

class String
  def inspect
    self.to_s
  end
end

# ---- ここから追記 ----
require "ostruct" # Ruby 3.5 で default から外れるので明示
require "time"

# String#escape が未定義なら簡易ダミー（デコレータ内で使っているため）
unless "".respond_to?(:escape)
  class String
    def escape = self
  end
end

# Tag.get_color をテスト用に安定化（spec の期待に合わせる）
unless defined?(Tag)
  class Tag
    MAP = {
      "modified" => "white",
      "end"      => "red",
      "404"      => "white" # 必要なら調整
    }.freeze
    def self.get_color(tag) = MAP[tag.to_s] || "white"
  end
end

require "lib/core/database" # あなたのプロジェクトの Database クラスを読み込む

RSpec.configure do |config|
  config.before(:suite) do
    db = Database.instance

    # ---- シード追加/修正 ----
    seed = {
      1 =>  { "id" => 1,   "novel_type" => 1, "author" => "馬場翁", "sitename" => "小説家になろう",
              "title" => "蜘蛛ですが、なにか？", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "new_arrivals_date" => Time.parse("2016-06-19 12:00 +09:00"),
              "tags" => ["modified"], "toc_url" => "http://ncode.syosetu.com/n7975cr/" },
      7 =>  { "id" => 7,   "novel_type" => 2, "author" => "作者A", "sitename" => "小説家になろう",
              "title" => "異世界でアイテムコレクター", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => [], "toc_url" => "http://example.com/ss/7" },
      22 => { "id" => 22,  "novel_type" => 1, "author" => "作者B", "sitename" => "小説家になろう",
              "title" => "もう一度ナデシコへ", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => [], "toc_url" => "http://example.com/series/22" },
      29 => { "id" => 29,  "novel_type" => 1, "author" => "作者C", "sitename" => "小説家になろう",
              "title" => "シリーズその3", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => [], "toc_url" => "http://example.com/series/29" },
      40 => { "id" => 40,  "novel_type" => 1, "sitename" => "小説家になろう",
              "title" => "孤独と共に歩む者", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => ["end", "404"], "toc_url" => "http://example.com/series/40" },
      107 => { "id" => 107, "novel_type" => 1, "sitename" => "小説家になろう",
              "title" => "私、結婚しました！", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => ["end"], "toc_url" => "http://example.com/series/107" },
      118 => { "id" => 118, "novel_type" => 1, "sitename" => "小説家になろう",
              "title" => "Asmody Story", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => ["404"], "toc_url" => "http://example.com/series/118" },
      127 => { "id" => 127, "novel_type" => 1, "sitename" => "小説家になろう",
              "title" => "複数タグの例", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => ["end", "modified"], "toc_url" => "http://example.com/series/127" },
      134 => { "id" => 134, "novel_type" => 1, "sitename" => "小説家になろう",
              "title" => "更新のみチェック", "last_update" => Time.parse("2016-07-01 00:30:00 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => [], "toc_url" => "http://example.com/series/134" },
      404 => { "id" => 404, "novel_type" => 1, "sitename" => "小説家になろう",
              "title" => "存在するID404", "last_update" => Time.parse("2015-08-03 +09:00"),
              "general_lastup" => Time.parse("2012-08-26 +09:00"), "tags" => [], "toc_url" => "http://example.com/series/404" },
    }

    # get_object が Hash ならそこへ投入
    if db.respond_to?(:get_object) && db.get_object.is_a?(Hash)
      seed.each { |id, row| db.get_object[id] = row }
    end

    # ---- tag_indexies をテスト用に固定 ----
    if db.respond_to?(:define_singleton_method)
      db.define_singleton_method(:tag_indexies) do
        { "modified" => [1, 127], "end" => [40, 107, 127], "404" => [40, 118] }
      end

      # ids の返す順序を固定
      db.define_singleton_method(:ids) do
        [7, 22, 29, 40, 107, 118, 134, 404, 1, 127]
      end

      # ID 参照ヘルパ（存在判定用）
      db.define_singleton_method(:[]) do |id|
        if respond_to?(:get_object) && get_object.is_a?(Hash)
          get_object[id]
        end
      end

      # save_database メソッド（テスト用の空実装）
      db.define_singleton_method(:save_database) do
        # テスト環境では実際の保存は不要
      end
    end

    # ---- 凍結ルール：3件(22,29,404) を true ----
    module Narou; end unless defined?(Narou)
    class << Narou
      def novel_frozen?(id)
        [22, 29, 404].include?(id.to_i)
      end
    end

    # Downloader がパス組み立てで使う archive_root_path の安全化（必要なら）
    unless Database.respond_to?(:archive_root_path)
      class << Database
        def archive_root_path
          require "pathname"
          Pathname(Dir.tmpdir || "/tmp")
        end
      end
    end
  end
end

