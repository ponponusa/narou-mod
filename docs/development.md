# 開発者向けガイド - Development Guide

Narou.rb MOD の開発に必要な環境構築、開発ワークフロー、ビルドについてまとめています。
アプリの利用方法については [README.md](../README.md) を参照してください。

## 必要環境 - Prerequisites

- Ruby 3.4 以上 / Bundler（CI は 2.7.2 を使用）
- Node.js 24 以上 / npm（フロントエンド開発時）
- MSYS2 環境（Windows の場合）

## バックエンド開発 - Backend Development

リポジトリルートで実行します。

```bash
# 依存関係のインストール
bundle install

# チェックアウトから Web UI / API を起動
bundle exec ruby narou.rb web

# ダウンロード・変換パスの動作確認
bundle exec ruby narou.rb download <novel_id>
```

### テスト・静的解析

```bash
bundle exec rspec                    # 全テスト（bundle exec rake でも可）
bundle exec rspec spec/xxx_spec.rb   # 対象を絞ったテスト
bundle exec rubocop                  # Ruby スタイルチェック
bundle exec reek                     # Ruby コード品質チェック
```

### ローカルプロセス管理

統合ローカルスタック（バックエンド + フロントエンド）の再起動には同梱スクリプトを使用します。

```bash
# Unix
./scripts/process_control.sh --restart
```

```powershell
# Windows
.\scripts\process_control.ps1 -Restart
```

## フロントエンド開発 - Frontend Development

モダンなフロントエンド実装が `frontend/` ディレクトリに含まれています。

### 技術スタック

- **Astro 7.x** - 静的サイトジェネレーター
- **Svelte 5.x** - リアクティブUIフレームワーク
- **Tailwind CSS 4.x** - ユーティリティファーストCSS
- **TypeScript** - 型安全な開発

### セットアップ

```bash
cd frontend
npm install
npm run dev
```

詳細は [frontend/README.md](../frontend/README.md) を参照してください。

## API開発 - API Development

このプロジェクトは REST API (API v2) を提供しており、Swagger UI で仕様を確認できます。

### API ドキュメント

- **Swagger UI**: <http://localhost:5678/api/docs>
- **OpenAPI仕様書**: <http://localhost:5678/api/openapi.yaml>
- **OpenAPIソース**: [openapi.yaml](openapi.yaml)

### API v2 エンドポイント

サーバーを起動後、以下のURLにアクセスしてください：

```bash
# サーバー起動
narou-mod web --boot

# Swagger UIを開く（ブラウザで）
http://localhost:5678/api/docs
```

Swagger UIでは以下が可能です：

- 全エンドポイントの仕様確認
- リクエスト/レスポンスの例
- インタラクティブなAPI呼び出し（Try it out機能）
- スキーマ定義の参照

### API v2 vs Legacy API

- **新規開発**: API v2 (`/api/v2/*`) の使用を推奨
- **既存コード**: Legacy API v1 (`/api/*`) は互換性のために維持
- **契約確認**: [OpenAPI仕様書](openapi.yaml) を参照

## ビルド・リリース - Build & Release

```bash
# gem のローカルビルド
gem build narou-mod.gemspec
```

- CI（`.github/workflows/ci.yml`）が `release` / `draft` ブランチへの push で
  Linux/macOS 向け（プラットフォーム指定なし: `narou-mod-<version>.gem`）と
  Windows 向け（`narou-mod-<version>-x64-mingw-ucrt.gem`）の gem をビルドし、
  GitHub Release を作成・更新します。
- リリースタグは `lib/core/version.rb` のバージョンに `commitversion` のコミットIDを付けた
  `3.1.6-<commit>` のような形式ですが、gem ファイル名のバージョンにコミットIDは含まれません。
- 通常の開発は `develop` ブランチを対象にし、`release` / `draft` への push はリリース作業時のみ行ってください。

## Windows環境への同期 - Sync to Windows

WSL環境からWindows環境へプロジェクトファイルを同期するスクリプトを提供しています。

```bash
# 設定ファイルを作成（初回のみ）
cp rsync.env.example rsync.env
nano rsync.env

# 同期スクリプトの実行
./sync-to-windows.sh

# または、引数で指定
./sync-to-windows.sh ~/git/narou-mod /mnt/c/git/narou
```

オプションの詳細は `./sync-to-windows.sh --help` で確認できます。
