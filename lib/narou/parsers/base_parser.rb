# frozen_string_literal: true

#
# パーサーの基底クラス
# 各サイト専用パーサーはこのクラスを継承する
#

require "nokogiri"
require "lib/narou/parsers/parser_error"
require "lib/narou/parsers/config_manager"

module Narou
  module Parsers
    class BaseParser
      attr_reader :site_setting, :user_config, :config, :logger
      # true にすると成功したセレクタの履歴を記録しない（保存を伴わない解析で使う）
      attr_writer :skip_selector_history

      def initialize(site_setting, user_config, logger: nil)
        @site_setting = site_setting  # webnovel/*.yaml または preset/parsers/*.yaml
        @user_config = user_config    # .narou/parsers/*.yaml
        @config = merge_configs(site_setting, user_config)
        @logger = logger || create_default_logger
      end

      # ユーザー設定を優先してマージ
      def merge_configs(site, user)
        # サイト設定をHashに変換（SiteSettingの場合はyamlデータを取得）
        site_hash = site.is_a?(SiteSetting) ? site.yaml : site
        merged = site_hash.dup

        # ユーザー設定をマージ
        user.each do |key, value|
          # セレクタ設定はユーザー設定を優先
          if key.end_with?("_selectors") || key == "last_successful_selectors"
            merged[key] = value
          else
            merged[key] = value unless value.nil?
          end
        end

        merged
      end

      # 各サブクラスで実装（目次ページ解析）
      def parse_toc(html)
        raise NotImplementedError, "#{self.class}#parse_toc must be implemented"
      end

      # 各サブクラスで実装（本文ページ解析）
      def parse_section(html, subtitle_info = {})
        raise NotImplementedError, "#{self.class}#parse_section must be implemented"
      end

      # 各サブクラスで実装（小説情報ページ解析）
      def parse_novel_info(html)
        raise NotImplementedError, "#{self.class}#parse_novel_info must be implemented"
      end

      protected

      # セレクタチェーンによる要素抽出（フォールバック機構）
      def extract_with_fallback(doc, selector_key, extract_type: "inner_html")
        selectors = @config[selector_key]

        unless selectors && selectors.is_a?(Array) && selectors.any?
          raise AllSelectorsFailedError.new(selector_key, []),
                "セレクタ設定が見つかりません: #{selector_key}"
        end

        tried_selectors = []
        sorted_selectors = selectors.sort_by { |s| -(s["priority"] || 0) }

        sorted_selectors.each do |config|
          selector = config["selector"]
          tried_selectors << config

          begin
            @logger.debug "Trying selector: #{selector} (priority: #{config['priority']})"

            result = doc.css(selector)

            if result.empty?
              @logger.debug "No elements found for: #{selector}"
              next
            end

            @logger.debug "Found #{result.size} element(s) for: #{selector}"

            # 成功したセレクタを記録
            update_successful_selector(selector_key, selector)

            # 抽出タイプに応じて結果を返す
            return extract_content(result, extract_type, config)
          rescue => e
            @logger.warn "Selector failed: #{selector} - #{e.message}"
            next
          end
        end

        # 全てのセレクタで失敗
        raise AllSelectorsFailedError.new(selector_key, tried_selectors)
      end

      # 要素からコンテンツを抽出
      def extract_content(result, extract_type, config)
        element = result.first

        case extract_type
        when "inner_html"
          element.inner_html
        when "text"
          element.text.strip
        when "attr"
          attr_name = config["attr"] || "href"
          element[attr_name]
        when "list"
          # 複数要素を配列で返す
          result.map { |el| extract_list_item(el, config) }
        else
          element
        end
      end

      # リストアイテムの抽出（目次ページ用）
      def extract_list_item(element, config)
        item = {}
        item_selectors = config["item_selectors"] || {}

        item_selectors.each do |key, selector|
          # セレクタに ::attr(name) が含まれる場合は属性値を取得
          if selector =~ /^(.+)::attr\((.+)\)$/
            sel = $1
            attr = $2
            node = element.css(sel).first
            item[key] = node ? node[attr] : nil
          else
            node = element.css(selector).first
            item[key] = node ? node.text.strip : nil
          end
        end

        item
      end

      # 成功したセレクタをユーザー設定に記録
      def update_successful_selector(selector_key, selector)
        return if @skip_selector_history

        domain = @config["domain"]
        engine = self.class.name.include?("Legacy") ? "legacy" : "nokogiri"

        # 履歴を記録（新規）
        ConfigManager.record_selector_history(domain, selector_key, selector, engine)
      rescue => e
        @logger.warn "Failed to update selector history: #{e.message}"
      end

      # サイト構造変更を検出
      def detect_structure_change?(html, selector_key)
        last_successful_selectors = @config["last_successful_selectors"]
        return false unless last_successful_selectors.is_a?(Hash)

        selector_info = last_successful_selectors[selector_key]
        return false unless selector_info.is_a?(Hash)

        last_successful = selector_info["selector"]
        return false unless last_successful

        doc = Nokogiri::HTML(html)
        doc.css(last_successful).empty?
      end

      # デフォルトロガー作成
      def create_default_logger
        require "logger"
        logger = ::Logger.new($stderr)
        logger.level = ::Logger::INFO
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{severity}] #{msg}\n"
        end
        logger
      end
    end
  end
end
