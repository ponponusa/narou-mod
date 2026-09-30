<script lang="ts">
  /**
   * テーマ切り替えトグルコンポーネント
   *
   * ダークモード/ライトモードの切り替え機能を提供
   * LocalStorageでテーマ設定を永続化
   */
  import { onMount } from "svelte";

  let isDark = $state(false);

  onMount(() => {
    // LocalStorageからテーマ設定を復元（デフォルトはライトモード）
    const savedTheme = localStorage.getItem("theme");

    if (savedTheme === "dark") {
      isDark = true;
      document.documentElement.classList.add("dark");
    } else {
      // 明示的にライトモードまたは未設定の場合
      isDark = false;
      document.documentElement.classList.remove("dark");
    }
  });

  function toggleTheme() {
    isDark = !isDark;

    if (isDark) {
      document.documentElement.classList.add("dark");
      localStorage.setItem("theme", "dark");
    } else {
      document.documentElement.classList.remove("dark");
      localStorage.setItem("theme", "light");
    }
  }
</script>

<button
  type="button"
  onclick={toggleTheme}
  class="theme-toggle"
  aria-label={isDark ? "ライトモードに切り替え" : "ダークモードに切り替え"}
  title={isDark ? "ライトモードに切り替え" : "ダークモードに切り替え"}
>
  <span class="toggle-container">
    <!-- ライトモードアイコン（左側） -->
    <span class="icon-wrapper" class:active={!isDark}>
      <i class="fas fa-sun"></i>
    </span>

    <!-- スライダー -->
    <span class="slider" class:dark={isDark}></span>

    <!-- ダークモードアイコン（右側） -->
    <span class="icon-wrapper" class:active={isDark}>
      <i class="fas fa-moon"></i>
    </span>
  </span>
</button>

<style>
  .theme-toggle {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0;
    border: none;
    background: transparent;
    cursor: pointer;
  }

  .toggle-container {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 4rem;
    height: 2rem;
    padding: 0.25rem;
    border-radius: 9999px;
    background-color: #e5e7eb;
    transition: background-color 0.2s;
  }

  :global(.dark) .toggle-container {
    background-color: #4b5563;
  }

  .icon-wrapper {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.5rem;
    height: 1.5rem;
    font-size: 0.75rem;
    color: #9ca3af;
    transition: color 0.2s;
    z-index: 2;
  }

  .icon-wrapper.active {
    color: #fff;
  }

  .slider {
    position: absolute;
    left: 0.25rem;
    width: 1.5rem;
    height: 1.5rem;
    border-radius: 9999px;
    background-color: #fbbf24;
    transition:
      transform 0.2s,
      background-color 0.2s;
    z-index: 1;
  }

  .slider.dark {
    transform: translateX(2rem);
    background-color: #60a5fa;
  }

  .theme-toggle:hover .toggle-container {
    background-color: #d1d5db;
  }

  :global(.dark) .theme-toggle:hover .toggle-container {
    background-color: #6b7280;
  }

  .theme-toggle:active .slider {
    transform: scale(0.95) translateX(0);
  }

  .theme-toggle:active .slider.dark {
    transform: scale(0.95) translateX(2rem);
  }
</style>
