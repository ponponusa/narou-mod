# Narou.rb MOD - Frontend

Narou.rb MOD の新しいフロントエンド実装です。Astro + Svelte を使用してモダンなWeb UIを提供します。

## 技術スタック

- **Astro 7.x**: 静的サイトジェネレーター / フレームワーク
- **Svelte 5.x**: リアクティブUIコンポーネント
- **Tailwind CSS 4.x**: ユーティリティファーストCSSフレームワーク
- **TypeScript 6.x**: 型安全な開発環境

## 特徴

- 🚀 モダンなフロントエンド技術スタック
- 📱 レスポンシブデザイン対応
- 🎨 ダークモード対応
- ⚡ 高速なページロード
- 🧩 コンポーネントベースの設計
- 🔒 TypeScriptによる型安全性

## 開発環境のセットアップ

### 前提条件

- Node.js 24 以上
- npm

### インストール

```bash
# 依存関係をインストール
npm install

# 環境変数を設定
cp .env.example .env
```

### 開発サーバーの起動

```bash
# 開発モードで起動
npm run dev
```

ブラウザで `http://localhost:4321` にアクセスしてください。

**WSL環境での注意**: WSL2環境では`npm run dev`の起動が遅い場合があります。その場合は以下を推奨します：

```bash
npm run build
npm run preview -- --host 0.0.0.0 --port 4321
```

詳細は [WSL_NOTES.md](WSL_NOTES.md) を参照してください。

### バックエンドとの連携

このフロントエンドは、Narou.rb の Ruby/Sinatra バックエンドAPIと連携して動作します。バックエンドのポートは初回起動時に決まり、以後は設定値を再利用します。明示的に固定する場合は `--port` を指定してください。

1. バックエンドを起動:

   ```bash
   cd /mnt/c/git/narou
   bundle exec ruby narou.rb web --port 5678 --no-frontend
   ```

2. フロントエンドを起動:

   ```bash
   cd /mnt/c/git/narou/frontend
   npm run dev
   ```

`.env` ファイルで `PUBLIC_API_BASE_URL` を変更することで、バックエンドのURLを調整できます。
`narou-mod web --no-frontend` でも `.env` と `public/backend-port.json` は更新されるため、別ターミナルで起動した `npm run dev` は同じバックエンドへ接続します。

## 🧞 コマンド

| Command                   | Action                                           |
| :------------------------ | :----------------------------------------------- |
| `npm install`             | 依存関係をインストール                            |
| `npm run dev`             | 開発サーバーを起動 (`localhost:4321`)             |
| `npm run build`           | プロダクション用ビルド (`./dist/`)                |
| `npm run preview`         | ビルド結果をプレビュー                            |
| `npm run astro ...`       | Astro CLIコマンドを実行                          |
| `npm run check`           | TypeScript / Astro 型チェック                     |

## プロジェクト構造

```text
frontend/
├── src/
│   ├── components/       # Svelteコンポーネント
│   │   ├── Header.svelte
│   │   └── NovelList.svelte
│   ├── layouts/          # Astroレイアウト
│   │   └── BaseLayout.astro
│   ├── lib/              # ユーティリティ関数
│   │   └── api.ts        # APIクライアント
│   ├── pages/            # ページコンポーネント
│   │   └── index.astro
│   ├── styles/           # グローバルスタイル
│   │   └── global.css
│   └── types/            # TypeScript型定義
│       └── api.ts
├── public/               # 静的ファイル
├── astro.config.mjs      # Astro設定
├── tailwind.config.js    # Tailwind CSS設定
├── tsconfig.json         # TypeScript設定
└── package.json          # npm設定
```

## 主要コンポーネント

### Header.svelte

ナビゲーションバーとバージョン情報を表示します。

### NovelList.svelte

小説リストをテーブル形式で表示し、以下の操作を提供:

- 小説の選択
- ダウンロード
- 変換
- 削除
- 検索・フィルタリング
- ページネーション

### BaseLayout.astro

全ページで共通のHTMLレイアウトを提供します。

## API連携

`src/lib/api.ts` にバックエンドAPIとの通信用の関数が定義されています。

主要なAPI関数:

- `getNovels()`: 小説リスト取得
- `downloadNovels()`: 小説ダウンロード
- `convertNovels()`: 小説変換
- `removeNovels()`: 小説削除
- `getTagList()`: タグリスト取得
- など

## 今後の実装予定

- [ ] タグ管理UI
- [ ] 設定画面
- [ ] ログビューア
- [ ] WebSocket対応（リアルタイム更新）
- [ ] オフライン対応（PWA化）
- [ ] テストコードの充実
- [ ] アクセシビリティの改善
- [ ] パフォーマンス最適化

## ライセンス

このプロジェクトは Narou.rb MOD の一部であり、同じライセンスが適用されます。

## 👀 参考リンク

- [Astro Documentation](https://docs.astro.build)
- [Svelte Documentation](https://svelte.dev)
- [Tailwind CSS Documentation](https://tailwindcss.com)
