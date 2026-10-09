# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "yaml"
require "fileutils"
require "ostruct"
require "cgi"
require "lib/core/narou"
require "lib/narou/promo_tag_extractor"
require "lib/narou/parsers/parser_selector"
require "lib/utilities/helper"
require "lib/novel/sitesetting"
require "lib/novel/novelsetting"
require "lib/conversion/template"
require "lib/output/progressbar"
require "lib/core/database"
require "lib/core/inventory"
require "lib/utilities/eventable"
require "lib/conversion/html"
require "lib/cli/input"
require "lib/narou/yaml_loader"
require "lib/novel/downloader/errors"
require "lib/novel/downloader/sanitize"
require "lib/novel/downloader/class_methods"
require "lib/novel/downloader/file_operations"
require "lib/novel/downloader/database_updater"
require "lib/novel/downloader/rate_limiter"
require "lib/novel/downloader/section_downloader"
require "lib/novel/downloader/toc_processor"

#
# 小説サイトからのダウンロード
#
class Downloader
  extend Downloader::ClassMethods
  include Downloader::FileOperations
  include Downloader::DatabaseUpdater
  include Downloader::SectionDownloader
  include Downloader::TocProcessor
  include Narou::Eventable
  extend Memoist

  SECTION_SAVE_DIR_NAME = "本文"    # 本文を保存するディレクトリ名
  CACHE_SAVE_DIR_NAME = "cache"   # 差分用キャッシュ保存用ディレクトリ名
  RAW_DATA_DIR_NAME = "raw" # 本文の生データを保存するディレクトリ名
  TOC_FILE_NAME = "toc.yaml"
  STEPS_WAIT_TIME = 5 # 数話ごとにかかるwaitの秒数
  WAIT_TIME_TO_RETRY_NETWORK = 10 # タイムアウト等でリトライするまでの待機時間
  LIMIT_TO_RETRY_NETWORK = 5 # タイムアウト等でリトライする回数上限
  NOVEL_TYPE_SERIES = 1   # 連載
  NOVEL_TYPE_SS = 2       # 短編
  DISPLAY_LIMIT_DIGITS = 4 # indexの表示桁数限界
  DEFAULT_INTERVAL_WAIT = 0.7 # download.interval のデフォルト値(秒)

  attr_reader :id, :setting

  def initialize(target, options = {})
    id = Downloader.get_id_by_target(target)
    options = {
      force: false, from_download: false,
      stream: $stdout
    }.merge(options)
    setting = Downloader.get_sitesetting_by_target(target)

    unless setting
      case type = Downloader.get_target_type(target)
      when :url, :ncode
        raise InvalidTarget, "対応外の#{type}です(#{target})"
      when :id
        raise InvalidTarget, "指定のID(#{target})は存在しません"
      when :other
        raise InvalidTarget, "指定の小説(#{target})は存在しません"
      end
    end

    initialize_variables(id, setting, options)
  end

  #
  # 変数初期化
  #
  def initialize_variables(id, setting, options)
    @id = id || database.create_new_id
    @title = nil
    @setting = setting
    @force = options[:force]
    @stream = options[:stream]
    @cache_dir = nil
    @new_arrivals = false
    @new_novel = record.!
    @from_download = options[:from_download]
    @section_download_cache = {}
    @max_cache_size = 20 # セクションキャッシュの上限
    @download_wait_steps = Inventory.load("local_setting")["download.wait-steps"] || 0
    @download_use_subdirectory = use_subdirectory?
    if @setting["is_narou"] && (@download_wait_steps > 10 || @download_wait_steps == 0)
      @download_wait_steps = 10
    end
    @nosave_diff = Narou.economy?("nosave_diff")
    @nosave_raw = Narou.economy?("nosave_raw")
    @gurad_spoiler = Inventory.load("local_setting")["guard-spoiler"]

    # 新パーサーの初期化
    @parser = Narou::Parsers::ParserSelector.select(@setting, novel_id: @id) rescue nil

    # RateLimiter のシングルトンインスタンスを取得
    @rate_limiter = RateLimiter.instance
  end

  def database
    self.class.database
  end

  def record
    database[@id]
  end

  #
  # サブディレクトリに保存してあるかどうか
  #
  def use_subdirectory?
    if @new_novel
      # 新規DLする小説
      Inventory.load("local_setting")["download.use-subdirectory"] || false
    else
      # すでにDL済みの小説
      record["use_subdirectory"] || false
    end
  end

  #
  # 18歳以上か確認する
  #
  def confirm_over18?
    global_setting = Inventory.load("global_setting", :global)
    if global_setting.include?("over18")
      return global_setting["over18"]
    end
    if Narou::Input.confirm("年齢認証：あなたは18歳以上ですか")
      global_setting["over18"] = true
      global_setting.save
      true
    else
      false
    end
  end

  #
  # ダウンロードを処理本体を起動
  #
  def start_download
    @status = run_download
    OpenStruct.new(
      :id => @id,
      :new_arrivals => @new_arrivals,
      :status => @status
      ).freeze
  end

  def load_toc_file
    load_novel_data(TOC_FILE_NAME)
  end

  #
  # ダウンロード処理本体
  #
  def run_download
    old_toc = @new_novel ? nil : load_toc_file
    latest_toc = get_latest_table_of_contents(old_toc)
    unless latest_toc
      @stream.error @setting["toc_url"] + " の目次データが取得出来ませんでした"
      return :failed
    end
    latest_toc_subtitles = latest_toc["subtitles"]
    if @setting["confirm_over18"]
      unless confirm_over18?
        @stream.puts "18歳以上のみ閲覧出来る小説です。ダウンロードを中止しました"
        return :canceled
      end
    end
    unless old_toc
      init_novel_dir
      old_toc = {}
      @new_arrivals = true
    end
    init_raw_dir
    if old_toc.empty? || @force
      update_subtitles = latest_toc_subtitles
    else
      update_subtitles = update_body_check(old_toc["subtitles"], latest_toc_subtitles)
    end

    if old_toc.empty? && update_subtitles.size.zero?
      @stream.error "#{@setting['title']} の目次がありません"
      return :failed
    end

    unless @force
      if process_digest(old_toc, latest_toc)
        return :canceled
      end
    end

    id_and_title = "ID:#{@id}　#{@title}"

    return_status =
      case
      when update_subtitles.size > 0
        @cache_dir = create_cache_dir if old_toc.length > 0
        sections_download_and_save(update_subtitles)
        if @cache_dir && @cache_dir.glob("*").count == 0
          remove_cache_dir
        end
        update_database
        :ok
      when old_toc["subtitles"].size > latest_toc_subtitles.size
        # 削除された節がある（かつ更新がない）場合
        @stream.puts "#{id_and_title} は一部の話が削除されています"
        :ok
      when old_toc["title"] != latest_toc["title"]
        # タイトルが更新されている場合
        @stream.puts "#{id_and_title} のタイトルが更新されています"
        update_database
        :ok
      when old_toc["story"] != latest_toc["story"]
        # あらすじが更新されている場合
        @stream.puts "#{id_and_title} のあらすじが更新されています"
        :ok
      when old_toc["author"] != latest_toc["author"]
        # 著者名が更新されている場合
        @stream.puts "#{id_and_title} の著者名が更新されています"
        update_database
        :ok
      else
        :none
      end

    auto_add_tags = Inventory.load("local_setting")["auto-add-tags"]
    if @setting["tag"] && auto_add_tags
      clean_tag = Sanitize.fragment(@setting["tag"]).gsub(/キーワードが設定されていません/, "").gsub(/キーワード/, "").gsub(/\"?\(\?\.\+\?\)\"?/, "").gsub(
/\(\?\<?[^)]*\)/, ""
).strip
      if clean_tag.length > 0
        new_tags = clean_tag.split(/[ 　]+/).uniq
        old_tags = (record && record["tags"]) ? record["tags"] : []
        if (new_tags - old_tags).any?
          @stream.puts "#{id_and_title} のタグが更新されています"
          update_database
          return_status = :ok if return_status == :none
        end
      end
    end

    record["general_all_no"] = latest_toc_subtitles.size

    save_toc_once(latest_toc)
    tags = @new_novel ? [] : record["tags"] || []
    case novel_end?
    when true
      unless tags.include?("end")
        update_database if update_subtitles.count == 0
        require "cli/command/tag" unless defined?(Command::Tag)
        Command::Tag.execute!(%W(#{id} --add end --color white --no-overwrite-color), io: Narou::NullIO.new)
        msg = old_toc.empty? ? "完結しているようです" : "完結したようです"
        @stream.puts "<cyan>#{id_and_title.escape} は#{msg}</cyan>".termcolor
        return_status = :ok
      end
    when false
      if tags.include?("end")
        update_database if update_subtitles.size == 0
        require "cli/command/tag" unless defined?(Command::Tag)
        Command::Tag.execute!(@id, "--delete", "end", io: Narou::NullIO.new)
        @stream.puts "<cyan>#{id_and_title.escape} は連載を再開したようです</cyan>".termcolor
        return_status = :ok
      end
    end
    return_status
  rescue Interrupt, SuspendDownload
    if latest_toc.present?
      save_toc_once(latest_toc)
      update_database(suspend: true)
    end
    raise Interrupt
  ensure
    @setting.clear
  end

  CHOICES = {
    "1" => "このまま更新する",
    "2" => "更新をキャンセル",
    "3" => "更新をキャンセルして小説を凍結する",
    "4" => "バックアップを作成する",
    "5" => "最新のあらすじを表示する",
    "6" => "小説ページをブラウザで開く",
    "7" => "保存フォルダを開く",
    "8" => "変換する",
    default: "2"
  }.freeze

  #
  # ダイジェスト化に関する処理
  #
  # @return true = 更新をキャンセル、false = 更新する
  #
  def process_digest(old_toc, latest_toc)
    return false unless old_toc["subtitles"]
    latest_subtitles_count = latest_toc["subtitles"].size
    old_subtitles_count = old_toc["subtitles"].size
    if latest_subtitles_count < old_subtitles_count
      title = latest_toc["title"]
      message = <<~EOS
        更新後の話数が保存されている話数より減少していることを検知しました。
        ダイジェスト化されている可能性があるので、更新に関しての処理を選択して下さい。

        保存済み話数: #{old_subtitles_count}
        更新後の話数: #{latest_subtitles_count}

      EOS

      auto_choices = Inventory.load("local_setting")["download.choices-of-digest-options"]
      auto_choices &&= auto_choices.split(",")

      loop do
        if auto_choices
          # 自動入力
          choice = auto_choices.shift || CHOICES[:default]
          puts title
          puts message
          puts self.class.choices_to_string
          puts "> #{choice}"
        else
          choice = Narou::Input.choose(title, message, CHOICES)
        end

        case choice
        when "1"
          return false
        when "2"
          return true
        when "3"
          require "cli/command/freeze" unless defined?(Command::Freeze)
          Command::Freeze.execute!(latest_toc["toc_url"])
          return true
        when "4"
          require "cli/command/backup" unless defined?(Command::Backup)
          Command::Backup.execute!(latest_toc["toc_url"])
        when "5"
          if Narou.web?
            message = "あらすじ\n#{latest_toc["story"]}\n"
          else
            puts "あらすじ"
            puts latest_toc["story"]
          end
        when "6"
          Helper.open_browser(latest_toc["toc_url"])
        when "7"
          Helper.open_directory(Downloader.get_novel_data_dir_by_target(latest_toc["toc_url"]))
        when "8"
          require "cli/command/convert" unless defined?(Command::Convert)
          Command::Convert.execute!(latest_toc["toc_url"], sync: true)
        end
        unless Narou.web?
          message = "" # 長いので二度は表示しない
        end
      end
    else
      false
    end
  end

  #
  # 小説を格納するためのディレクトリ名を取得する
  #
  def get_file_title
    # すでにデータベースに登録されているならそれを引き続き使うようにする
    file_title = record&.dig("file_title")
    return file_title if file_title
    ncode = @setting["ncode"]
    return ncode unless @setting["append_title_to_folder_name"]
    scrubbed_title = Helper.replace_filename_special_chars(get_title, true).strip
    Helper.truncate_folder_title("#{ncode} #{scrubbed_title}")
  end
  memoize :get_file_title
  memoize :get_novel_data_dir
  memoize :get_novel_status

  #
  # 小説のタイトルを取得する
  #
  def get_title
    return @title if @title
    @title = @setting["title"] || record["title"]
    if @setting["title_strip_pattern"]
      @title = @title.gsub(/#{@setting["title_strip_pattern"]}/, "").gsub(/^[　\s]*(.+?)[　\s]*?$/, "\\1")
    end
    @title
  end

  def replace_external_properties_of_setting
    @setting["title"] = @setting["title"].delete("\r\n")
    @setting["author"] = @setting["author"].delete("\r\n")
  end
end

# ==== UTF-8 Hotfix: avoid "UTF-8 and ASCII-8BIT" clashes ====
# このブロックは downloader.rb の最下部にそのまま追記してください。
# 既存コードには手を入れず、戻り値の文字列だけを UTF-8 に正規化します。

module Narou
  module Utf8Hotfix
    module_function
    def utf8(v)
      case v
      when String
        # BINARY(ASCII-8BIT) を含む可能性があるので強制的に UTF-8 + scrub
        v.encoding == Encoding::UTF_8 ? v : v.dup.force_encoding(Encoding::UTF_8).scrub
      when Array
        v.map { |e| utf8(e) }
      when Hash
        # 値側を再帰的に正規化。キーはそのまま（シンボルや固定文字列想定）
        v.transform_values { |e| utf8(e) }
      else
        v
      end
    end
  end
end

if defined?(Narou::Downloader)
  class Narou::Downloader
    # get_latest_table_of_contents の戻り値を UTF-8 に正規化
    if method_defined?(:get_latest_table_of_contents)
      alias __orig_get_latest_table_of_contents get_latest_table_of_contents
      def get_latest_table_of_contents(...)
        res = __orig_get_latest_table_of_contents(...)
        Narou::Utf8Hotfix.utf8(res)
      end
    end

    # 念のため run_download の戻り値も正規化（TOC 以外の経路対策）
    if method_defined?(:run_download)
      alias __orig_run_download run_download
      def run_download(...)
        res = __orig_run_download(...)
        Narou::Utf8Hotfix.utf8(res)
      end
    end
  end
end
# ==== /UTF-8 Hotfix ====
