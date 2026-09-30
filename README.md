# Narou.rb MOD - 小説家になろうのダウンローダ＆縦書き整形＆管理アプリ

> [!NOTE]
> このプロジェクトは下記プロジェクトの派生です。
>
> - **Original Project : [whiteleaf7/narou](https://github.com/whiteleaf7/narou) --**[GitHub last commit](https://img.shields.io/github/last-commit/whiteleaf7/narou?style=flat&labelColor=blue&color=white)
>
> - **Forked from : [Rumia-Channel/narou](https://github.com/Rumia-Channel/narou) --**[GitHub last commit](https://img.shields.io/github/last-commit/Rumia-Channel/narou?style=flat&labelColor=gold&color=pink&link=https%3A%2F%2Fgithub.com%2FRumia-Channel%2Fnarou)
>

素晴らしいプロジェクトを作成していただいた、[whiteleaf7](https://github.com/whiteleaf7) さん、[Rumia-Channel](https://github.com/Rumia-Channel) さんに多大なる感謝を。

## 概要 - Summary

このアプリは[小説家になろう](http://syosetu.com/)などで公開されている小説の管理、
及び電子書籍データへの変換を支援します。縦書き用に特化されており、
横書きに最適化されたWEB小説を違和感なく縦書きで読むことが出来るようになります。
また、校正機能もありますので、小説としての一般的な整形ルールに矯正します。（例：感嘆符のあとにはスペースが必ずくる）

小説家になろうを含めて、下記のサイトに対応しています。

| サイト名 | URL | 備考 |
|----------|----------|----------|
| 小説家になろう | <http://syosetu.com/> | |
| ノクターンノベルズ | <http://noc.syosetu.com/> | |
| ムーンライトノベルズ | <http://mnlt.syosetu.com/> | |
| ミッドナイトノベルズ | <http://mid.syosetu.com/> | |
| ハーメルン | <https://syosetu.org/> | |
| Arcadia | <http://www.mai-net.net/> | |
| 暁 | <http://www.akatsuki-novels.com/> | （※300話以上ある作品は未対応） |
| カクヨム | <https://kakuyomu.jp/> | |

主な機能は小説家になろうの小説のダウンロード、更新管理、テキスト整形、AozoraEpub3・kindlegen連携によるEPUB/MOBI出力です。  
その他にも変換したデータを直接電子書籍端末へ送信する機能は、メールで送信する機能などもあります。

~~詳細な説明やインストール方法は **[Narou.rb_MOD説明書](https://github.com/ponponusa/narou-mod/wiki)** を御覧ください。~~（準備中）

## オリジナルプロジェクトからの変更点 - Changes from Original Project

> 現リリース晩時点での変更点です。

### 機能面

- プロモタグ抽出、分離機能搭載
  - 小説タイトルや著者名に影響を与えない形でプロモタグを分離
  - Web UI上でプロモタグを表示
- TOCチェック、テキスト変換処理の安定化・高速化
  - 大量話数の小説での特に処理速度が向上
  - ファイルIOを減らし、メモリ上での処理を増加
- 認証機能をBasic認証への変更
- 小説一覧の項目を整理

### システム面

- コマンド名を `narou` から `narou-mod` に変更
- Ruby 3.4以降を動作要件に変更
- システム全体の高速化
  - YJIT/Bootsnap対応（Windows環境では無効になります）
  - コマンド実行のモジュール読込最適化
  - 不要な外部依存ライブラリを削除
  - 古いRubyモジュールを更新
  - 古いJS/CSSライブラリを更新
- 一部機能の修正・改善
- セキュリティリスクのある実装の修正
- その他、細かなバグ修正や改善

## 動作要件 - Requirements

- Ruby 3.4以上（※元プロジェクトから変更されています）
- MSYS2環境（Windowsの場合）

## インストール - Installation

[リリースページ](https://github.com/ponponusa/narou-mod/releases)から、お使いのプラットフォームに対応した gem ファイルを取得してインストールしてください。

```bash
# Linux / macOS
gem install ./narou-mod-<version>.gem
```

```powershell
# Windows
gem install ./narou-mod-<version>-x64-mingw-ucrt.gem
```

`<version>` は `3.1.8` のようなバージョン番号です（リリースタグ末尾のコミットIDは gem ファイル名には含まれません）。バージョンごとの具体的なコマンドは、各リリースの「インストール案内」に記載されています。

## WEBサーバーの起動について - Web Server

**v2.1.0以降、WEBサーバーはフォアグラウンド実行のみ対応**しています。

```bash
# サーバー起動（フォアグラウンド実行）
narou-mod web --boot

# オプション指定
narou-mod web --boot --port 8080 --log-file app.log

# サーバー停止
# 方法1: Ctrl+C で停止
# 方法2: 別ターミナルから narou-mod stop
```

### バックグラウンド実行が必要な場合

systemdやタスクスケジューラを使用してください：

#### Linuxの場合（systemdサービス例）

```bash
# /etc/systemd/system/narou-mod.service
[Unit]
Description=Narou-mod Web Server
After=network.target

[Service]
Type=simple
User=your-user
WorkingDirectory=/path/to/narou-mod
ExecStart=/usr/bin/narou-mod web --log-file /var/log/narou-mod.log
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

#### Windowsの場合（タスクスケジューラ）

タスクスケジューラで「ログオン時に実行」「非表示」設定で起動してください。

## 更新履歴 - ChangeLog

![GitHub Release](https://img.shields.io/github/v/release/ponponusa/narou-mod)

[->リリースページへ](https://github.com/ponponusa/narou-mod/releases)

## 今後の予定 - Roadmap

- 外部Webサーバを利用しない形でのHTTPS対応
- セキュリティリスクのある実装の修正
- 変換処理の並列化による高速化
  - 今後の最適化のためにもスレッドセーフにする
- パーサーの改善
  - サイト構造の変更に強くする
- 表紙画像をWebUI上で設定できるようにする
  - 自動取得は怒られる可能性があるため検討中
- 保存容量の改善
  - 圧縮保存の検討
  - Yaml DatabaseからSQLite等への移行検討

## 開発者向け情報 - For Developers

開発環境の構築、バックエンド/フロントエンド/API の開発ワークフロー、ビルド・リリース、Windows 環境への同期については [docs/development.md](docs/development.md) を参照してください。

----

## License

- **Maintainer:** [ponponusa](https://github.com/ponponusa)
- **Copyrights:**
  - Original Project: Copyright (c) 2013-2024 whiteleaf7
  - Forked Project: Copyright (c) 2025 Rumia-Channel
  - This MOD Project: Copyright (c) 2025 ponponusa
- **License:** This project is licensed under the MIT License - see the [LICENSE](LICENSE.txt) file for details.

----

- 「小説家になろう」は株式会社ヒナプロジェクトの登録商標です。
- 本ソフトウェアを利用（入手、インストール、実行等）した時点で、[利用規約・免責事項](https://github.com/ponponusa/narou-mod/blob/develop/TERMS_AND_DISCLAIMER.md)に同意したものとみなします。ご利用の前に必ず内容をご確認ください。
