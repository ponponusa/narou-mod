# frozen_string_literal: true

require "spec/spec_helper"
require "lib/narou/parsers/narou_parser"
require "lib/narou/parsers/config_manager"

RSpec.describe Narou::Parsers::NarouParser do
  before do
    # Narou.root_dir と Narou.script_dir をモック
    allow(Narou).to receive(:root_dir).and_return(Pathname.new(Dir.mktmpdir))
    allow(Narou).to receive(:script_dir).and_return(Pathname.new(File.expand_path("../../", __dir__)))
  end

  let(:parser) do
    # 実際の設定ファイルを読み込む
    site_config = Narou::Parsers::ConfigManager.load_parser_config(domain, "nokogiri")
    user_config = {}
    described_class.new(site_config, user_config)
  end

  # 同じ NarouParser を使う両ドメインの preset で、前書き・後書きの分離を確認する
  %w(ncode.syosetu.com novel18.syosetu.com).each do |target_domain|
    context "#{target_domain} の設定の場合" do
      let(:domain) { target_domain }

      describe "前書き・後書きの分離" do
        let(:html_with_comments) do
          <<~HTML
            <article class="p-novel">
              <div class="p-novel__body">
                <div class="js-novel-text p-novel__text p-novel__text--preface">
                  <p id="Lp1">初めて書いた作品になります。</p>
                  <p id="Lp2">書き物自体が初めてなので、読みづらかったりする箇所も多々あるかと思いますが、宜しければご一読いただき感想などいただけると嬉しいです。</p>
                </div>

                <div class="js-novel-text p-novel__text">
                  <p id="L1">　人の熱気がすごい、今この場の湿度はどれくらいだろう？</p>
                  <p id="L2">　俺は、さして広くもない会場にごった返している人々が放つ、ムワッとした空気をその肌や鼻孔で感じていた。</p>
                  <p id="L3"><br /></p>
                  <p id="L4">　その大きくはない会場のステージの上では、多くの観客に熱い視線を向けられながら、三人の女の子が踊り歌っている。</p>
                </div>

                <div class="js-novel-text p-novel__text p-novel__text--afterword">
                  <p id="La1">これで、第一部は終了となります。</p>
                  <p id="La2">ここまで読んでいただいて、ありがとうございます。</p>
                  <p id="La3"><br /></p>
                  <p id="La4">第二部も一週間程度開けて、投稿を始めたいと思っていますので、よろしければ引き続き読んでいただけると嬉しいです。</p>
                </div>
              </div>
            </article>
          HTML
        end

        it "本文のみを抽出し、前書き・後書きを除外する" do
          result = parser.parse_section(html_with_comments)

          expect(result["body"]).to include("人の熱気がすごい")
          expect(result["body"]).to include("三人の女の子が踊り歌っている")

          # 前書き・後書きが本文に含まれていないこと
          expect(result["body"]).not_to include("初めて書いた作品になります")
          expect(result["body"]).not_to include("第一部は終了となります")
        end

        it "前書きを正しく抽出する" do
          result = parser.parse_section(html_with_comments)

          expect(result["introduction"]).to include("初めて書いた作品になります")
          expect(result["introduction"]).to include("感想などいただけると嬉しいです")

          # 本文が前書きに含まれていないこと
          expect(result["introduction"]).not_to include("人の熱気がすごい")
        end

        it "後書きを正しく抽出する" do
          result = parser.parse_section(html_with_comments)

          expect(result["postscript"]).to include("第一部は終了となります")
          expect(result["postscript"]).to include("引き続き読んでいただけると嬉しいです")

          # 本文が後書きに含まれていないこと
          expect(result["postscript"]).not_to include("人の熱気がすごい")
        end

        it "data_typeがhtmlであること" do
          result = parser.parse_section(html_with_comments)
          expect(result["data_type"]).to eq("html")
        end
      end

      describe "コメントがない場合" do
        let(:html_without_comments) do
          <<~HTML
            <article class="p-novel">
              <div class="p-novel__body">
                <div class="js-novel-text p-novel__text">
                  <p id="L1">　本文のみのケースです。</p>
                  <p id="L2">　前書きも後書きもありません。</p>
                </div>
              </div>
            </article>
          HTML
        end

        it "本文のみを抽出する" do
          result = parser.parse_section(html_without_comments)

          expect(result["body"]).to include("本文のみのケースです")
          expect(result["body"]).to include("前書きも後書きもありません")
        end

        it "前書きと後書きは空文字列になる" do
          result = parser.parse_section(html_without_comments)

          expect(result["introduction"]).to eq("")
          expect(result["postscript"]).to eq("")
        end
      end

      describe "前書きのみの場合" do
        let(:html_with_preface_only) do
          <<~HTML
            <article class="p-novel">
              <div class="p-novel__body">
                <div class="js-novel-text p-novel__text p-novel__text--preface">
                  <p id="Lp1">これは前書きです。</p>
                </div>

                <div class="js-novel-text p-novel__text">
                  <p id="L1">　本文です。</p>
                </div>
              </div>
            </article>
          HTML
        end

        it "本文と前書きを正しく分離する" do
          result = parser.parse_section(html_with_preface_only)

          expect(result["body"]).to include("本文です")
          expect(result["body"]).not_to include("これは前書きです")

          expect(result["introduction"]).to include("これは前書きです")
          expect(result["postscript"]).to eq("")
        end
      end

      describe "後書きのみの場合" do
        let(:html_with_afterword_only) do
          <<~HTML
            <article class="p-novel">
              <div class="p-novel__body">
                <div class="js-novel-text p-novel__text">
                  <p id="L1">　本文です。</p>
                </div>

                <div class="js-novel-text p-novel__text p-novel__text--afterword">
                  <p id="La1">これは後書きです。</p>
                </div>
              </div>
            </article>
          HTML
        end

        it "本文と後書きを正しく分離する" do
          result = parser.parse_section(html_with_afterword_only)

          expect(result["body"]).to include("本文です")
          expect(result["body"]).not_to include("これは後書きです")

          expect(result["introduction"]).to eq("")
          expect(result["postscript"]).to include("これは後書きです")
        end
      end
    end
  end
end
