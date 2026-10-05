# frozen_string_literal: true

class Downloader
  #
  # Section download execution methods for Downloader
  #
  module SectionDownloader
    #
    # 小説本文をまとめてダウンロードして保存
    #
    # subtitles にダウンロードしたいものをまとめた subtitle info を渡す
    #
    def sections_download_and_save(subtitles)
      max = subtitles.size
      return if max == 0
      @stream.puts "<bold><green>#{"ID:#{@id}　#{get_title}".escape} のDL開始</green></bold>".termcolor
      save_least_one = false
      subtitles.each_with_index do |subtitle_info, i|
        index, subtitle, file_subtitle, chapter, subchapter =
          %w(index subtitle file_subtitle chapter subchapter).map { |k|
            subtitle_info[k]
          }
        info = subtitle_info.dup
        info["element"] = a_section_download(subtitle_info)

        @stream.puts "#{chapter}" unless chapter.to_s.empty?
        @stream.puts "#{subchapter}" unless subchapter.to_s.empty?

        if get_novel_type == NOVEL_TYPE_SERIES
          if index.to_s.length <= DISPLAY_LIMIT_DIGITS
            # indexの数字がでかいと見た目がみっともないので特定の桁以内だけ表示する
            @stream.print "第#{index}部分　"
          end
        else
          @stream.print "短編　"
        end
        printable_subtitle = @gurad_spoiler ? Helper.to_unprintable_words(subtitle) : subtitle
        @stream.print "#{HTML.new(printable_subtitle).delete_ruby_tag} (#{i + 1}/#{max})"

        section_file_name = "#{index} #{file_subtitle}.yaml"
        section_file_relative_path = File.join(SECTION_SAVE_DIR_NAME, section_file_name)
        section_file_full_path = get_novel_data_dir.join(section_file_relative_path)
        if section_file_full_path.exist?
          if @force
            if different_section?(section_file_relative_path, info)
              @stream.print " (更新あり)"
              move_to_cache_dir(section_file_relative_path)
            end
          else
            move_to_cache_dir(section_file_relative_path)
          end
        else
          if !@from_download || (@from_download && @force)
            @stream.print " <bold><magenta>(新着)</magenta></bold>".termcolor
            trigger(:newarrival, {
              id: @id,
              subtitle_info: subtitle_info
            })
          end
          @new_arrivals = true
        end
        save_novel_data(section_file_relative_path, info)
        save_least_one = true
        @stream.puts
      end
      remove_cache_dir unless save_least_one
    end

    #
    # raw に保存してある本文ページのHTMLを現在のパーサーで解析し直し、本文データを作り直す
    #
    # 内容が変わった話だけを保存し、変更前の本文は差分用キャッシュに退避する。
    # 解析し直した本文が空になる話は、取り出しに失敗したとみなして保存しない。
    #
    # @return [Hash] :changed（変更した話の subtitle info の配列）、:unchanged、:skipped、:failed（件数）
    #
    def reparse_sections_from_raw(dry_run: false)
      result = { changed: [], unchanged: 0, skipped: 0, failed: 0 }
      toc = load_toc_file
      subtitles = (toc && toc["subtitles"]) || []
      @cache_dir = create_cache_dir unless dry_run
      subtitles.each do |subtitle_info|
        basename = "#{subtitle_info["index"]} #{subtitle_info["file_subtitle"]}"
        raw_path = raw_dir.join("#{basename}.html")
        section_file_relative_path = File.join(SECTION_SAVE_DIR_NAME, "#{basename}.yaml")
        section = load_novel_data(section_file_relative_path)
        unless raw_path.exist? && section
          result[:skipped] += 1
          next
        end

        subtitle = @gurad_spoiler ? Helper.to_unprintable_words(subtitle_info["subtitle"]) : subtitle_info["subtitle"]
        label = "#{subtitle_info["index"]}　#{HTML.new(subtitle).delete_ruby_tag}"
        begin
          element = parse_section_source(File.read(raw_path, encoding: Encoding::UTF_8), subtitle_info.dup)
        rescue Narou::Parsers::ParserError => e
          @stream.error "#{label} の解析に失敗しました（#{e.message}）"
          result[:failed] += 1
          next
        end
        if element["body"].strip.empty? && !section.dig("element", "body").to_s.strip.empty?
          @stream.error "#{label} の本文を取り出せなかったため、保存されている本文をそのまま残します"
          result[:failed] += 1
          next
        end
        if section["element"] == element
          result[:unchanged] += 1
          next
        end

        @stream.puts "#{label} (更新あり)"
        result[:changed] << subtitle_info
        next if dry_run
        move_to_cache_dir(section_file_relative_path)
        save_novel_data(section_file_relative_path, section.merge("element" => element))
      end
      result
    ensure
      remove_cache_dir if @cache_dir && @cache_dir.glob("*").empty?
    end

    #
    # すでに保存されている内容とDLした内容が違うかどうか
    #
    def different_section?(old_relative_path, new_subtitle_info)
      path = get_novel_data_dir.join(old_relative_path)
      return true unless path.exist?
      begin
        Narou::YAMLLoader.load_file(path)["element"] != new_subtitle_info["element"]
      rescue SystemCallError
        # bootsnap on Windows can raise Errno::E01 errors, fallback to standard IO read
        Narou::YAMLLoader.load(File.read(path), filename: path)["element"] != new_subtitle_info["element"]
      rescue Narou::YAMLLoader::Error => e
        warn "[warn] YAML load failed for #{path}: #{e.message}"
        true
      end
    end

    #
    # 差分用のキャッシュとして保存
    #
    def move_to_cache_dir(relative_path)
      return if @nosave_diff
      path = get_novel_data_dir.join(relative_path)
      if path.exist? && @cache_dir
        FileUtils.mv(path, @cache_dir)
      end
    end

    def sleep_for_download
      @rate_limiter.wait_for_download(@download_wait_steps)
    end

    #
    # 指定された話数の本文をダウンロード
    #
    def a_section_download(subtitle_info)
      index = subtitle_info["index"]
      return @section_download_cache[index] if @section_download_cache[index]

      # キャッシュサイズ制限をチェック
      cleanup_cache_if_needed

      sleep_for_download
      href = subtitle_info["href"]
      subtitle_url =
        if href&.start_with?("/")
          "#{@setting["top_url"]}#{href}"
        else
          "#{@setting["toc_url"]}#{href}"
        end
      raw = download_raw_data(subtitle_url)
      save_raw_data(raw, subtitle_info, ".html")

      element = parse_section_source(raw, subtitle_info)
      subtitle_info["download_time"] = Time.now
      @section_download_cache[index] = element
      element
    end

    #
    # 本文ページのHTMLを解析して element を作成する
    #
    # subtitle_info には使用したパーサーの情報（parser_info）が記録される
    #
    def parse_section_source(raw, subtitle_info)
      # 新パーサーが利用可能な場合は新パーサーを使用
      if @parser
        result = @parser.parse_section(raw, subtitle_info)
        element = {
          "data_type" => result["data_type"] || "html",
          "introduction" => result["introduction"].to_s,
          "postscript" => result["postscript"].to_s,
          "body" => result["body"].to_s
        }

        # パーサー情報を記録（新規追加 - Nokogiriの場合）
        subtitle_info["parser_info"] = {
          "engine" => "nokogiri",
          "domain" => @setting["domain"],
          "selectors_used" => extract_used_selectors(@parser)
        }
      else
        # パーサーが初期化されていない場合は既存の multi_match を使用
        %w(introduction postscript body).each { |type| @setting[type] = nil }
        @setting.multi_match(raw, "body_pattern", "introduction_pattern", "postscript_pattern")
        element = { "data_type" => @setting["data_type"] || "html" }
        %w(introduction postscript body).each { |type|
          element[type] = @setting[type].to_s
        }

        # パーサー情報を記録（新規追加 - Legacyの場合）
        subtitle_info["parser_info"] = {
          "engine" => "legacy",
          "domain" => @setting["domain"],
          "version" => @setting["version"],
          "patterns_used" => extract_used_patterns(@setting)
        }
      end

      element
    end

    #
    # セクションキャッシュのサイズ制限とクリーンアップ
    #
    def cleanup_cache_if_needed
      return if @section_download_cache.size <= @max_cache_size

      # 古いエントリから削除（インデックスの小さいものから）
      sorted_keys = @section_download_cache.keys.sort
      keys_to_remove = sorted_keys.first(@section_download_cache.size - @max_cache_size + 1)
      keys_to_remove.each { |key| @section_download_cache.delete(key) }
    end

    #
    # Downloaderの完了時にキャッシュをクリア
    #
    def cleanup
      @section_download_cache.clear if @section_download_cache
    end

    def display_hint
      @stream.puts <<~HINT
        ヒント:
        503 がでた場合はしばらくアクセスが規制される場合があります。
        設定を変更してサーバーに対する負荷を軽減させましょう。(下記参照)
        小説家になろう系列の場合、10分程度時間を置く必要があります。
        (メンテナンス等でも503になる場合があります。公式サイトを確認してください)

        下記の設定のどれか、もしくは全てを変更することで調整できます。
        (download.interval が最重要設定。１話ごとの間隔が短すぎると規制されやすい)

        # 1話ごとに入るウェイトを変更する(単位：秒)
        narou s download.interval=1.0

        # 10話ごとに通常より長いウェイトを入れる
        narou s download.wait-steps=10

        # Update時の作品間の待機時間を変更する(単位：秒)
        narou s update.interval=3.0
      HINT
    end

    #
    # 指定したURLからデータをダウンロード
    #
    def download_raw_data(url)
      raw = nil
      retry_count = LIMIT_TO_RETRY_NETWORK
      cookie = @setting["cookie"] || ""
      begin
        open_uri_options = make_open_uri_navigation_options("Cookie" => cookie, allow_redirections: :safe)
        URI(url).open("r:#{@setting["encoding"]}", open_uri_options) do |fp|
          raw = Helper.pretreatment_source(fp.read, @setting["encoding"])
        end
      rescue OpenURI::HTTPError, Errno::ECONNRESET, Errno::ECONNABORTED, Errno::ETIMEDOUT, Net::OpenTimeout, IO::TimeoutError,
SocketError => e
        if Downloader.cloudflare_challenge?(e)
          @stream.error "#{CLOUDFLARE_CHALLENGE_MESSAGE} (#{url})"
          raise SuspendDownload
        end

        case e.message
        when /^503/
          # 503 はアクセス規制やメンテ等でリトライしてもほぼ意味がないことが多いため一度で諦める
          @stream.error "server message: #{e.message}"
          display_hint
          raise SuspendDownload
        when /^404/
          @stream.error "server message: #{e.message}"
          @stream.puts "#{url} がダウンロード出来ませんでした。時間をおいて再度試してみてください"
          raise SuspendDownload
        else
          if retry_count == 0
            @stream.error "上限までリトライしましたがファイルがダウンロード出来ませんでした"
            raise SuspendDownload
          end
          retry_count -= 1
          @stream.puts <<~MSG
            server message: #{e.message}
            リトライ待機中...
          MSG
          sleep(WAIT_TIME_TO_RETRY_NETWORK)
          retry
        end
      end
      raw
    end

    #
    # 使用されたセレクタを抽出（新規メソッド - Nokogiri用）
    #
    def extract_used_selectors(parser)
      selectors = {}
      config = parser.user_config

      %w(body_selectors introduction_selectors postscript_selectors).each do |key|
        last_success = config.dig("last_successful_selectors", key, "selector")
        selectors[key] = last_success if last_success
      end

      selectors
    end

    #
    # 使用された正規表現パターンを抽出（新規メソッド - Legacy用）
    #
    def extract_used_patterns(setting)
      patterns = {}

      %w(body_pattern introduction_pattern postscript_pattern).each do |key|
        pattern = setting[key]
        patterns[key] = pattern.to_s if pattern
      end

      patterns
    end
  end
end
