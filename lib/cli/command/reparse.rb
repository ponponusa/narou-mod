# frozen_string_literal: true

require "lib/core/database"
require "lib/novel/downloader"

module Command
  class Reparse < CommandBase
    def self.oneline_help
      "保存済みの本文ページから本文を解析し直します"
    end

    def initialize
      super("<target> [<target2> ...] [options]")
      @opt.separator <<-EOS

  ・ダウンロード時に保存した本文ページのHTML(raw フォルダ)を現在のパーサーで解析し直し、
    本文データを作り直します。サイトにはアクセスしません。
  ・パーサーの不具合で本文が正しく保存されなかった話の復旧に使います。
    サイトから再取得できる小説は download --force での再ダウンロードを推奨します。
  ・内容が変わった話だけを保存し、変更前の本文は差分用キャッシュに残します(diff コマンドで確認できます)。
  ・本文が変わった小説は続けて変換します。前回の変換に失敗していた小説も再変換します。
  ・raw フォルダに HTML が無い話(rawデータを保存しない設定の場合など)は解析し直せません。
  ・凍結中の小説は対象外です。

  Examples:
    narou-mod reparse n9669bk
    narou-mod reparse 0 1 2 --dry-run
    narou-mod reparse --no-convert foo     # foo タグが付いた小説を変換せずに解析し直す

  Options:
      EOS
      @opt.on("--dry-run", "保存せず、内容が変わる話を表示するだけにする") {
        @options["dry-run"] = true
      }
      @opt.on("-n", "--no-convert", "解析し直した後に変換しない") {
        @options["no-convert"] = true
      }
    end

    def execute(argv)
      super
      display_help! if argv.empty?
      tagname_to_ids(argv)
      mistook_count = 0
      argv.each_with_index do |target, i|
        Helper.print_horizontal_rule if i > 0
        data = Downloader.get_data_by_target(target)
        unless data
          error "#{target} は存在しません"
          mistook_count += 1
          next
        end
        if Narou.novel_frozen?(target)
          error "ID:#{data["id"]}　#{data["title"]} は凍結中です"
          mistook_count += 1
          next
        end
        mistook_count += 1 unless reparse_novel(target, data)
      end
      exit mistook_count if mistook_count > 0
    rescue Interrupt
      puts "解析し直しを中断しました"
      exit Narou::EXIT_INTERRUPT
    end

    #
    # 1作品分を解析し直す
    #
    # @return 失敗した話がなく、変換も成功した場合に true
    #
    def reparse_novel(target, data)
      puts "<bold><green>#{"ID:#{data["id"]}　#{data["title"]}".escape} を解析し直します</green></bold>".termcolor
      result = Downloader.new(target).reparse_sections_from_raw(dry_run: @options["dry-run"])
      changed = result[:changed].size
      summary = "更新あり #{changed} 話、変更なし #{result[:unchanged]} 話"
      summary += "、raw が無いため対象外 #{result[:skipped]} 話" if result[:skipped] > 0
      summary += "、失敗 #{result[:failed]} 話" if result[:failed] > 0
      puts summary
      if @options["dry-run"]
        puts "(--dry-run のため保存していません)" if changed > 0
      elsif (changed > 0 || data["_convert_failure"]) && !@options["no-convert"]
        puts "<yellow>前回変換できなかったので再変換します</yellow>".termcolor if changed.zero?
        return false unless convert_novel(target, data)
      end
      result[:failed].zero?
    rescue Downloader::InvalidTarget => e
      error e.message
      false
    end

    #
    # 変換する
    #
    # 失敗した場合は update と同じく記録しておき、次回の reparse や update で再変換する
    #
    def convert_novel(target, data)
      require "lib/cli/command/convert" unless defined?(Command::Convert)
      convert_status = Convert.execute!(target)
      if convert_status > 0
        data["_convert_failure"] = true
      else
        data.delete("_convert_failure")
      end
      Database.instance.save_database
      raise Interrupt if convert_status == Narou::EXIT_INTERRUPT
      convert_status.zero?
    end
  end
end
