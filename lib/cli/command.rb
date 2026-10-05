# frozen_string_literal: true

#
# Copyright 2013 whiteleaf. All rights reserved.
#

require "lib/cli/commandbase"

module Command
  # コマンド名 -> ファイル相対パス
  COMMAND_FILES = {
    "download" => "command/download",
    "update"   => "command/update",
    "list"     => "command/list",
    "convert"  => "command/convert",
    "diff"     => "command/diff",
    "setting"  => "command/setting",
    "alias"    => "command/alias",
    "inspect"  => "command/inspect",
    "send"     => "command/send",
    "folder"   => "command/folder",
    "browser"  => "command/browser",
    "remove"   => "command/remove",
    "reparse"  => "command/reparse",
    "freeze"   => "command/freeze",
    "tag"      => "command/tag",
    "web"      => "command/web",
    "mail"     => "command/mail",
    "backup"   => "command/backup",
    "csv"      => "command/csv",
    "clean"    => "command/clean",
    "log"      => "command/log",
    "trace"    => "command/trace",
    "help"     => "command/help",
    "version"  => "command/version",
    "init"     => "command/init"
  }.freeze

  # 互換API：従来の "一覧（表示順）" 相当。重いクラスは返さず、軽量に name->path を返す。
  def self.get_list
    COMMAND_FILES
  end

  # 名前一覧（help の表示順そのまま）
  def self.names
    COMMAND_FILES.keys
  end

  # camelize: "convert" → "Convert", "foo-bar" → "FooBar"
  def self.const_name(name)
    name.to_s.split(/[-_]/).map!(&:capitalize).join
  end
  private_class_method :const_name

  # 存在チェック（定義済みマップ上）
  def self.exist?(name)
    COMMAND_FILES.key?(name.to_s)
  end
  class << self
    alias exists? exist? # 互換
  end

  # 実行直前にだけ require する
  def self.require_command(name)
    path = COMMAND_FILES[name.to_s]
    return false unless path
    require_relative path
    true
  end

  def self.require_all
    COMMAND_FILES.each_key { |name| require_command(name) }
  end

  # コマンドクラスを返す（必要なときだけロード）
  # 見つからなければ nil
  def self.load_command(name)
    key = name.to_s.downcase
    return nil unless exist?(key)
    require_command(key)
    const = const_name(key)
    return nil unless Command.const_defined?(const, false)
    Command.const_get(const, false)
  rescue NameError
    nil
  end

  # ショートカット定義（1文字/2文字 → 本名）。後勝ち防止のため逆順で畳み込み。
  Shortcuts = begin
    base = names
    Hash[*base.reverse.flat_map { |s| [s[0], s, s[0, 2], s] }]
  end.freeze
end
