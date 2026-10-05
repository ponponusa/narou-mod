# frozen_string_literal: true

require "spec_helper"
require "lib/novel/downloader"
require "lib/narou/parsers/narou_parser"

RSpec.describe Downloader::SectionDownloader do
  let(:downloader) do
    # テスト用のダウンローダーインスタンスを作成
    # 実際のテストでは適切にモックする必要があります
    double("Downloader").tap do |d|
      d.extend(Downloader::SectionDownloader)
      allow(d).to receive(:instance_variable_get).with(:@setting).and_return(setting)
      allow(d).to receive(:instance_variable_get).with(:@parser).and_return(parser)
      allow(d).to receive(:instance_variable_set)
    end
  end

  let(:setting) do
    {
      "domain" => "test.example.com",
      "version" => "2.0"
    }
  end

  let(:parser) { nil }

  describe "#extract_used_selectors" do
    let(:mock_parser) do
      double("Parser").tap do |p|
        allow(p).to receive(:user_config).and_return({
          "last_successful_selectors" => {
            "body_selectors" => { "selector" => "div.body" },
            "introduction_selectors" => { "selector" => "div.intro" },
            "postscript_selectors" => { "selector" => "div.post" }
          }
        })
      end
    end

    it "パーサーから使用されたセレクタを抽出する" do
      # SectionDownloaderモジュールのインスタンスメソッドとして呼び出し
      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      selectors = instance.send(:extract_used_selectors, mock_parser)

      expect(selectors).to be_a(Hash)
      expect(selectors["body_selectors"]).to eq("div.body")
      expect(selectors["introduction_selectors"]).to eq("div.intro")
      expect(selectors["postscript_selectors"]).to eq("div.post")
    end

    it "セレクタがない場合は空のハッシュを返す" do
      empty_parser = double("Parser")
      allow(empty_parser).to receive(:user_config).and_return({})

      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      selectors = instance.send(:extract_used_selectors, empty_parser)

      expect(selectors).to eq({})
    end
  end

  describe "#extract_used_patterns" do
    let(:mock_setting) do
      {
        "body_pattern" => "<div>(?<body>.+?)</div>",
        "introduction_pattern" => "<div class=\"intro\">(?<introduction>.+?)</div>",
        "postscript_pattern" => "<div class=\"post\">(?<postscript>.+?)</div>"
      }
    end

    it "設定から使用された正規表現パターンを抽出する" do
      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      patterns = instance.send(:extract_used_patterns, mock_setting)

      expect(patterns).to be_a(Hash)
      expect(patterns["body_pattern"]).to include("<div>")
      expect(patterns["introduction_pattern"]).to include("intro")
      expect(patterns["postscript_pattern"]).to include("post")
    end

    it "パターンがない場合は空のハッシュを返す" do
      empty_setting = {}

      instance = Object.new
      instance.extend(Downloader::SectionDownloader)

      patterns = instance.send(:extract_used_patterns, empty_setting)

      expect(patterns).to eq({})
    end
  end

  describe "parser_info recording" do
    it "Nokogiriパーサー使用時にparser_infoを記録する" do
      # このテストは実際のa_section_downloadメソッドの動作を確認する統合テスト
      # モックの複雑さから、実際の動作確認は手動テストまたはE2Eテストで行うことを推奨
      skip "Integration test - requires full Downloader setup"
    end

    it "Legacyパーサー使用時にparser_infoを記録する" do
      # このテストは実際のa_section_downloadメソッドの動作を確認する統合テスト
      skip "Integration test - requires full Downloader setup"
    end
  end

  describe "#reparse_sections_from_raw" do
    let(:novel_dir) { Pathname.new(Dir.mktmpdir) }
    let(:stream) { double("stream", puts: nil, error: nil) }
    let(:subtitles) do
      [
        { "index" => "1", "subtitle" => "前書きのある話", "file_subtitle" => "前書きのある話" },
        { "index" => "2", "subtitle" => "前書きのない話", "file_subtitle" => "前書きのない話" },
        { "index" => "3", "subtitle" => "rawのない話", "file_subtitle" => "rawのない話" }
      ]
    end
    # 修正前の novel18 のセレクタで保存された状態（本文が前書きに置き換わっている）
    let(:broken_element) do
      {
        "data_type" => "html",
        "introduction" => "<p id=\"Lp1\">前書きです。</p>",
        "postscript" => "",
        "body" => "<p id=\"Lp1\">前書きです。</p>"
      }
    end
    let(:correct_element) do
      {
        "data_type" => "html",
        "introduction" => "<p id=\"Lp1\">前書きです。</p>",
        "postscript" => "",
        "body" => "<p id=\"L1\">本文です。</p>"
      }
    end
    let(:downloader) do
      Downloader.allocate.tap do |d|
        parser_config = Narou::Parsers::ConfigManager.load_parser_config("novel18.syosetu.com", "nokogiri")
        d.instance_variable_set(:@parser, Narou::Parsers::NarouParser.new(parser_config, {}, logger: Logger.new(nil)))
        d.instance_variable_set(:@setting, { "domain" => "novel18.syosetu.com" })
        d.instance_variable_set(:@stream, stream)
        allow(d).to receive(:get_novel_data_dir).and_return(novel_dir)
        allow(d).to receive(:load_toc_file).and_return({ "subtitles" => subtitles })
      end
    end

    def write_section(basename, element)
      path = novel_dir.join(Downloader::SECTION_SAVE_DIR_NAME, "#{basename}.yaml")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, YAML.dump({ "index" => basename.split(" ").first, "element" => element }))
    end

    def write_raw(basename, html)
      path = novel_dir.join(Downloader::RAW_DATA_DIR_NAME, "#{basename}.html")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, html)
    end

    def read_section(basename)
      YAML.unsafe_load_file(novel_dir.join(Downloader::SECTION_SAVE_DIR_NAME, "#{basename}.yaml"))
    end

    def cache_files
      novel_dir.glob("#{Downloader::SECTION_SAVE_DIR_NAME}/#{Downloader::CACHE_SAVE_DIR_NAME}/*/*.yaml")
    end

    before do
      # パーサーのセレクタ履歴を一時ディレクトリに書き込ませる
      allow(Narou).to receive(:root_dir).and_return(Pathname.new(Dir.mktmpdir))
      allow(Narou).to receive(:script_dir).and_return(Pathname.new(File.expand_path("../../", __dir__)))

      write_raw("1 前書きのある話", <<~HTML)
        <div class="js-novel-text p-novel__text p-novel__text--preface"><p id="Lp1">前書きです。</p></div>
        <div class="js-novel-text p-novel__text"><p id="L1">本文です。</p></div>
      HTML
      write_section("1 前書きのある話", broken_element)
      write_raw("2 前書きのない話", <<~HTML)
        <div class="js-novel-text p-novel__text"><p id="L1">前書きのない本文です。</p></div>
      HTML
      write_section("2 前書きのない話", {
        "data_type" => "html", "introduction" => "", "postscript" => "",
        "body" => "<p id=\"L1\">前書きのない本文です。</p>"
      })
      write_section("3 rawのない話", correct_element)
    end

    after do
      FileUtils.remove_entry_secure(novel_dir)
    end

    it "raw の HTML を解析し直し、内容が変わった話だけを保存する" do
      result = downloader.reparse_sections_from_raw

      expect(result[:changed].map { |info| info["index"] }).to eq ["1"]
      expect(result).to include(unchanged: 1, skipped: 1, failed: 0)
      expect(read_section("1 前書きのある話")["element"]).to eq correct_element
      expect(read_section("1 前書きのある話")["index"]).to eq "1"
    end

    it "変更前の本文を差分用キャッシュに退避する" do
      downloader.reparse_sections_from_raw

      expect(cache_files.map { |path| path.basename.to_s }).to eq ["1 前書きのある話.yaml"]
      expect(YAML.unsafe_load_file(cache_files.first)["element"]).to eq broken_element
    end

    it "dry_run では保存もキャッシュの作成もしない" do
      result = downloader.reparse_sections_from_raw(dry_run: true)

      expect(result[:changed].size).to eq 1
      expect(read_section("1 前書きのある話")["element"]).to eq broken_element
      expect(novel_dir.join(Downloader::SECTION_SAVE_DIR_NAME, Downloader::CACHE_SAVE_DIR_NAME)).not_to exist
    end

    it "本文を取り出せない話は保存されている本文を残す" do
      write_raw("1 前書きのある話", "<div class=\"unknown\">構造の変わったページ</div>")

      result = downloader.reparse_sections_from_raw

      expect(result[:changed]).to be_empty
      expect(result[:failed]).to eq 1
      expect(read_section("1 前書きのある話")["element"]).to eq broken_element
      expect(stream).to have_received(:error).with(include("本文を取り出せなかった"))
    end

    it "変更が無い場合は差分用キャッシュのディレクトリを残さない" do
      write_section("1 前書きのある話", correct_element)

      result = downloader.reparse_sections_from_raw

      expect(result[:changed]).to be_empty
      expect(novel_dir.glob("#{Downloader::SECTION_SAVE_DIR_NAME}/#{Downloader::CACHE_SAVE_DIR_NAME}/*")).to be_empty
    end
  end
end
