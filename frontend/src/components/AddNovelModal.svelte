<!--
  小説追加モーダル

  URLまたはncodeを入力して小説を追加
  複数の小説を一括で追加可能
-->
<script lang="ts">
  import { addNovel } from "../lib/api";

  let isOpen = $state(false);
  let inputText = $state("");
  let tags = $state("");
  let forceAdd = $state(false);
  let isLoading = $state(false);
  let error = $state<string | null>(null);
  let validationMessages = $state<string[]>([]);

  const MAX_NOVELS = 50;

  export function open() {
    isOpen = true;
    inputText = "";
    tags = "";
    forceAdd = false;
    error = null;
    validationMessages = [];
  }

  export function close() {
    isOpen = false;
    inputText = "";
    tags = "";
    forceAdd = false;
    error = null;
    validationMessages = [];
  }

  /**
   * 入力テキストから小説のURL/ncodeを抽出
   */
  function parseInput(text: string): string[] {
    // 改行、スペース、カンマで分割
    const items = text
      .split(/[\n\r,\s　]+/)
      .map((item) => item.trim())
      .filter((item) => item.length > 0);

    return items;
  }

  /**
   * 入力された小説の数をリアルタイムでカウント
   */
  let novelCount = $derived.by(() => {
    const items = parseInput(inputText);
    return items.length;
  });

  async function handleSubmit(e: Event) {
    e.preventDefault();

    if (!inputText.trim()) {
      error = "URLまたはncodeを入力してください";
      return;
    }

    const novels = parseInput(inputText);

    // バリデーション
    validationMessages = [];

    if (novels.length === 0) {
      error = "URLまたはncodeを入力してください";
      return;
    }

    if (novels.length > MAX_NOVELS) {
      error = `一度に追加できる小説は最大${MAX_NOVELS}件までです（現在: ${novels.length}件）`;
      return;
    }

    isLoading = true;
    error = null;

    const results = {
      success: [] as string[],
      failed: [] as { input: string; error: string }[],
    };

    // 各小説を順番に追加
    for (const novel of novels) {
      try {
        // タグを配列に変換
        const tagArray = tags
          .split(/[,、\s]+/)
          .map((t) => t.trim())
          .filter((t) => t.length > 0);
        await addNovel(
          novel,
          forceAdd,
          tagArray.length > 0 ? tagArray : undefined
        );
        results.success.push(novel);
      } catch (err) {
        const errorMessage =
          err instanceof Error ? err.message : "ダウンロードに失敗しました";
        results.failed.push({ input: novel, error: errorMessage });
        console.error(`小説追加エラー [${novel}]:`, err);
      }
    }

    isLoading = false;

    // 結果を表示
    if (results.success.length > 0) {
      validationMessages.push(
        `✓ ${results.success.length}件の小説をダウンロードキューに追加しました`
      );
    }

    if (results.failed.length > 0) {
      validationMessages.push(
        `✗ ${results.failed.length}件の小説の追加に失敗しました:`
      );
      results.failed.forEach(({ input, error }) => {
        validationMessages.push(`  - ${input}: ${error}`);
      });
    }

    // すべて成功した場合はモーダルを閉じる
    if (results.failed.length === 0) {
      setTimeout(() => {
        close();
      }, 1500);
    }
  }

  function handleBackdropClick(e: MouseEvent) {
    if (e.target === e.currentTarget) {
      close();
    }
  }
</script>

{#if isOpen}
  <!-- モーダルバックドロップ -->
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <!-- svelte-ignore a11y_interactive_supports_focus -->
  <div
    class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50"
    onclick={handleBackdropClick}
    role="dialog"
    aria-modal="true"
    aria-labelledby="add-novel-title"
  >
    <!-- モーダルコンテンツ -->
    <div
      class="bg-white dark:bg-gray-800 rounded-lg shadow-xl w-full max-w-md mx-4"
    >
      <!-- ヘッダー -->
      <div
        class="flex items-center justify-between px-6 py-4 border-b border-gray-200 dark:border-gray-700"
      >
        <h2
          id="add-novel-title"
          class="text-xl font-semibold text-gray-900 dark:text-gray-100"
        >
          小説を追加
        </h2>
        <button
          onclick={close}
          class="text-gray-500 hover:text-gray-700 dark:text-gray-400 dark:hover:text-gray-200 text-2xl leading-none"
          aria-label="閉じる"
        >
          ×
        </button>
      </div>

      <!-- フォーム -->
      <form onsubmit={handleSubmit} class="p-6">
        <div class="mb-4">
          <label
            for="novel-input"
            class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
          >
            小説のURL または ncode
          </label>
          <textarea
            id="novel-input"
            bind:value={inputText}
            placeholder="https://ncode.syosetu.com/n9669bk/&#10;n1234ab&#10;https://kakuyomu.jp/works/..."
            rows="6"
            class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm"
            disabled={isLoading}></textarea>
          <p class="mt-2 text-xs text-gray-500 dark:text-gray-400">
            小説家になろう、カクヨムなどのURLまたはncodeを入力してください。<br
            />
            複数の場合は改行、スペース、カンマで区切ってください（最大{MAX_NOVELS}件）
          </p>
          {#if novelCount > 0}
            <p
              class="mt-1 text-sm {novelCount > MAX_NOVELS
                ? 'text-red-600 dark:text-red-400'
                : 'text-blue-600 dark:text-blue-400'}"
            >
              {novelCount}件の小説が入力されています
            </p>
          {/if}
        </div>

        <!-- オプション -->
        <div class="mb-4 space-y-3">
          <div>
            <label
              for="novel-tags"
              class="block text-sm font-medium text-gray-700 dark:text-gray-300 mb-2"
            >
              タグ（オプション）
            </label>
            <input
              id="novel-tags"
              type="text"
              bind:value={tags}
              placeholder="例: 異世界, ファンタジー"
              class="w-full px-3 py-2 border border-gray-300 dark:border-gray-600 rounded dark:bg-gray-700 dark:text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              disabled={isLoading}
            />
            <p class="mt-1 text-xs text-gray-500 dark:text-gray-400">
              追加する小説に付与するタグ（カンマ区切り）
            </p>
          </div>

          <div class="flex items-center">
            <input
              id="force-add"
              type="checkbox"
              bind:checked={forceAdd}
              class="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
              disabled={isLoading}
            />
            <label
              for="force-add"
              class="ml-2 text-sm text-gray-700 dark:text-gray-300"
            >
              凍結中や既存の小説も強制的に追加
            </label>
          </div>
        </div>

        {#if error}
          <div
            class="mb-4 p-3 bg-red-100 dark:bg-red-900 border border-red-400 dark:border-red-700 text-red-700 dark:text-red-200 rounded text-sm"
          >
            {error}
          </div>
        {/if}

        {#if validationMessages.length > 0}
          <div
            class="mb-4 p-3 bg-blue-100 dark:bg-blue-900 border border-blue-400 dark:border-blue-700 text-blue-700 dark:text-blue-200 rounded text-sm space-y-1"
          >
            {#each validationMessages as message}
              <div>{message}</div>
            {/each}
          </div>
        {/if}

        <!-- ボタン -->
        <div class="flex gap-3 justify-end">
          <button
            type="button"
            onclick={close}
            class="px-4 py-2 text-gray-700 dark:text-gray-300 bg-gray-200 dark:bg-gray-700 rounded hover:bg-gray-300 dark:hover:bg-gray-600 transition-colors"
            disabled={isLoading}
          >
            キャンセル
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:bg-gray-400 disabled:cursor-not-allowed transition-colors"
            disabled={isLoading || novelCount === 0 || novelCount > MAX_NOVELS}
          >
            {isLoading
              ? `追加中... (${novelCount}件)`
              : `追加 (${novelCount}件)`}
          </button>
        </div>
      </form>
    </div>
  </div>
{/if}
