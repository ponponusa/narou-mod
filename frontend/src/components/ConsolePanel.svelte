<!--
  コンソールパネルコンポーネント

  PushServerからのechoイベントを受信してコンソールログを表示する
-->
<script lang="ts" context="module">
  // ログエントリの型定義
  interface LogEntry {
    id: number;
    timestamp: Date;
    console: "stdout" | "stdout2" | "convert";
    message: string;
    isProgress?: boolean; // 進捗メッセージかどうか
    progressKey?: string; // 進捗を識別するキー
    processType?: "download" | "convert" | "skip" | "other"; // 処理タイプ
    novelId?: string; // 小説ID
  }

  // グローバルログストア（ページ遷移しても保持される）
  let globalLogs: LogEntry[] = [];
  let globalNextId = 0;
</script>

<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    getPushServer,
    type EchoMessage,
    type PushServerClient,
  } from "../lib/pushserver";
  import { LogEntry as LogEntryComponent } from "./console";

  // localStorageから設定を読み込む
  const STORAGE_KEY = "narou-console-settings";

  function loadSettings() {
    if (typeof window === "undefined") return;
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved) {
        const settings = JSON.parse(saved);
        if (typeof settings.splitView === "boolean")
          splitView = settings.splitView;
        if (typeof settings.compactProgress === "boolean")
          compactProgress = settings.compactProgress;
        if (typeof settings.autoScroll === "boolean")
          autoScroll = settings.autoScroll;
        if (typeof settings.updateThrottle === "number")
          updateThrottle = settings.updateThrottle;
        if (typeof settings.splitRatio === "number")
          splitRatio = settings.splitRatio;
      }
    } catch (e) {
      console.error("Failed to load console settings:", e);
    }
  }

  function saveSettings() {
    if (typeof window === "undefined") return;
    try {
      localStorage.setItem(
        STORAGE_KEY,
        JSON.stringify({
          splitView,
          compactProgress,
          autoScroll,
          updateThrottle,
          splitRatio,
        })
      );
    } catch (e) {
      console.error("Failed to save console settings:", e);
    }
  }

  // グローバルログストアからローカルステートを初期化（ページ遷移時にログを引き継ぐ）
  let logs = $state<LogEntry[]>([...globalLogs]);
  let isOpen = $state(false);
  let autoScroll = $state(true); // 進捗を1行で表示するか
  let compactProgress = $state(true); // 進捗を1行で表示するか
  let updateThrottle = $state(100); // 更新頻度（ms）
  let splitView = $state(true); // 左右分割表示
  let splitRatio = $state(60); // 左ペインの幅（%）
  let isResizing = $state(false); // リサイズ中かどうか
  let logContainer = $state<HTMLDivElement | undefined>();
  let leftPaneContainer = $state<HTMLDivElement | undefined>();
  let rightPaneContainer = $state<HTMLDivElement | undefined>();
  let nextId = globalNextId;
  let unsubscribe: (() => void) | null = null;
  let isConnected = $state(false);
  let lastUpdateTime = 0;
  let pendingLogs: Array<{
    console: "stdout" | "stdout2" | "convert";
    message: string;
    timestamp?: string;
  }> = [];

  // ログ変更時にグローバルストアを同期
  $effect(() => {
    globalLogs = [...logs];
    globalNextId = nextId;
  });

  // プログレスバーの状態
  let currentProgressBar: {
    console: "stdout" | "stdout2" | "convert";
    percent: number;
    logId?: number;
  } | null = null;

  // 設定変更時に保存
  $effect(() => {
    saveSettings();
  });

  // ログ数が変化したときに自動スクロール（DOM更新後に実行）
  let previousLogCount = 0;
  $effect(() => {
    const currentCount = logs.length;
    if (currentCount !== previousLogCount) {
      previousLogCount = currentCount;
      // DOM更新後にスクロール
      requestAnimationFrame(() => {
        scrollIfNeeded();
      });
    }
  });

  /**
   * コンソールを開く
   */
  export function open() {
    isOpen = true;
    // 開いた直後に最下部にスクロール
    setTimeout(() => {
      scrollToBottom();
    }, 50);
  }

  /**
   * コンソールを閉じる
   */
  export function close() {
    isOpen = false;
  }

  /**
   * コンソールをトグル
   */
  export function toggle() {
    isOpen = !isOpen;
    if (isOpen) {
      setTimeout(() => {
        scrollToBottom();
      }, 50);
    }
  }

  /**
   * コンソールの開閉状態を取得
   */
  export function getIsOpen() {
    return isOpen;
  }

  /**
   * ログをクリア
   */
  async function clearLogs() {
    logs = [];

    // バックエンドの履歴もクリア
    try {
      const response = await fetch("/api/v2/console/clear", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      });

      if (!response.ok) {
        console.error("Failed to clear backend history:", response.statusText);
      }
    } catch (error) {
      console.error("Error clearing backend history:", error);
    }
  }

  /**
   * リサイズ開始
   */
  function startResize(e: MouseEvent) {
    isResizing = true;
    e.preventDefault();
  }

  /**
   * リサイズ中
   */
  function handleResize(e: MouseEvent) {
    if (!isResizing) return;

    const consoleEl = document.querySelector(
      ".console-split-view"
    ) as HTMLElement;
    if (!consoleEl) return;

    const rect = consoleEl.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const ratio = (x / rect.width) * 100;

    // 20% ～ 80% の範囲に制限
    splitRatio = Math.max(20, Math.min(80, ratio));
  }

  /**
   * リサイズ終了
   */
  function stopResize() {
    isResizing = false;
  } /**
   * ログエントリを追加
   */
  function addLog(
    consoleType: "stdout" | "stdout2" | "convert",
    message: string,
    timestamp?: string
  ) {
    const now = Date.now();

    // スロットリング: 指定間隔内は追加をペンディング
    if (now - lastUpdateTime < updateThrottle && pendingLogs.length > 0) {
      pendingLogs.push({ console: consoleType, message, timestamp });
      return;
    }

    // ペンディングされたログがあれば処理
    if (pendingLogs.length > 0) {
      pendingLogs.forEach((log) =>
        processLog(log.console, log.message, log.timestamp)
      );
      pendingLogs = [];
    }

    processLog(consoleType, message, timestamp);
    lastUpdateTime = now;
  }

  /**
   * ログを処理して追加
   */
  function processLog(
    consoleType: "stdout" | "stdout2" | "convert",
    message: string,
    timestamp?: string
  ) {
    // タイムスタンプが提供されている場合はそれを使用、なければ現在時刻
    const logTimestamp = timestamp ? new Date(timestamp) : new Date();
    let cleanMessage = message.replace(/\n$/, ""); // 末尾の改行を削除

    // ANSI escape sequence（プログレスバーのclear()）を無視
    // \e[2K\r（行削除+行頭移動）などのエスケープシーケンスを除去
    if (/\x1b\[[\d;]*[A-Za-z]/.test(cleanMessage)) {
      // エスケープシーケンスのみのメッセージは無視
      if (
        cleanMessage
          .replace(/\x1b\[[\d;]*[A-Za-z]/g, "")
          .replace(/\r/g, "")
          .trim() === ""
      ) {
        return;
      }
      // エスケープシーケンスを削除
      cleanMessage = cleanMessage.replace(/\x1b\[[\d;]*[A-Za-z]/g, "");
    }

    // キャリッジリターン(\r)を削除（プログレスバーの上書き制御文字）
    cleanMessage = cleanMessage.replace(/\r/g, "");

    // 末尾追加メッセージの処理（「.」「（新規）」「（削除）」など）
    // これらは直前のログエントリに追加すべきメッセージ
    const appendPatterns = /^(\.+|（新規）|（削除）|（変更）|（更新）)$/;
    const decodedClean = decodeMessage(cleanMessage).trim();
    if (appendPatterns.test(decodedClean) && logs.length > 0) {
      // 直前のログエントリに追加
      const lastLog = logs[logs.length - 1];
      const lastMessage = decodeMessage(lastLog.message).trim();
      // 直前のメッセージが「.」で終わっている場合は連結
      if (decodedClean.match(/^\.+$/)) {
        logs[logs.length - 1] = {
          ...lastLog,
          message: lastLog.message + cleanMessage,
          timestamp: logTimestamp,
        };
      } else {
        // その他の追加メッセージは末尾に追加
        logs[logs.length - 1] = {
          ...lastLog,
          message: lastLog.message + " " + cleanMessage,
          timestamp: logTimestamp,
        };
      }
      logs = [...logs]; // リアクティビティをトリガー
      scrollIfNeeded();
      return;
    }

    // 処理タイプと小説IDを抽出
    const { processType, novelId } = extractProcessInfo(cleanMessage);

    // 進捗メッセージかどうかを判定
    const isProgress = isProgressMessage(cleanMessage);
    // novelIdがある場合はそれを含めたprogressKeyを生成
    const baseProgressKey = isProgress
      ? extractProgressKey(cleanMessage)
      : undefined;
    const progressKey =
      baseProgressKey && novelId
        ? `${baseProgressKey}-novel-${novelId}`
        : baseProgressKey;

    // ★プログレスバーは無効化（すべて通常メッセージとして扱う）
    const isProgressBar = false;
    // const isProgressBar = /\[[#*]+[\s.-]*\]/.test(cleanMessage) || /\d+%\s*\[[#*\s.-]*\]\s*\d+%/.test(cleanMessage);

    // コンパクトモードで進捗メッセージの場合、既存のエントリを更新
    // ただし、プログレスバーは除外（すべての状態を表示するため）
    if (compactProgress && isProgress && progressKey && !isProgressBar) {
      const existingIndex = logs.findIndex(
        (log) => log.isProgress && log.progressKey === progressKey
      );

      if (existingIndex !== -1) {
        // 既存の進捗メッセージを更新
        logs[existingIndex] = {
          ...logs[existingIndex],
          message: cleanMessage,
          timestamp: logTimestamp,
          processType,
          novelId,
        };
        logs = [...logs]; // リアクティビティをトリガー
        scrollIfNeeded();
        return;
      }
    }

    // 新しいログエントリを追加
    logs = [
      ...logs,
      {
        id: nextId++,
        timestamp: logTimestamp,
        console: consoleType,
        message: cleanMessage,
        isProgress,
        progressKey,
        processType,
        novelId,
      },
    ];

    // 最大1000件まで保持
    if (logs.length > 1000) {
      logs = logs.slice(-1000);
    }

    scrollIfNeeded();
  }

  /**
   * 進捗メッセージかどうかを判定
   */
  function isProgressMessage(message: string): boolean {
    // 空メッセージは進捗ではない
    if (decodeMessage(message).trim().length === 0) {
      return false;
    }

    const decoded = decodeMessage(message).trim();

    // プログレスバー: [###...] または [*  ] を含むパターン
    // 0%[###...]100% や [***   ] 50% などに対応
    // ★プログレスバーは無効化（常に通常メッセージとして扱う）
    // if (/\[[#*]+[\s.-]*\]/.test(decoded) || /\d+%\s*\[[#*\s.-]*\]\s*\d+%/.test(decoded)) {
    //   return true;
    // }

    // 「第n部分」だけの行は進捗メッセージ
    if (/^第[\d０-９]+部分\s*$/.test(decoded)) {
      return true;
    }

    // 章データ（「第一章」「第二章」「第１章」「第２章」「１章」「2章」など）も進捗メッセージとして扱う
    // 第○部分と同じキーで上書き更新される
    // 漢数字、全角数字、半角数字すべてに対応、「第」の有無も対応
    if (/^第?[一二三四五六七八九十百千壱弐参０-９\d]+章\s*$/.test(decoded)) {
      return true;
    }

    // 章タイトル + (n/m) パターン
    // "第一話", "第二十話" などの漢数字パターンも検出
    return /\(\d+\/\d+\)|第[一二三四五六七八九十百千]+話/.test(decoded);
  }

  /**
   * 進捗メッセージから識別キーを抽出
   */
  function extractProgressKey(message: string): string {
    const decoded = decodeMessage(message).trim();

    // 小説IDがある場合は、それを最優先でキーにする
    const idMatch = decoded.match(/ID[:：]\s*(\d+)/i);
    if (idMatch) return `progress-id-${idMatch[1]}`;

    // プログレスバー: [###...] または [*  ] を含むパターン
    // 0%[###...]100% や [***   ] 50% などに対応
    // 小説IDと組み合わせて固有のキーにする
    // ★プログレスバーは無効化（通常メッセージとして処理）
    // if (/\[[#*]+[\s.-]*\]/.test(decoded) || /\d+%\s*\[[#*\s.-]*\]\s*\d+%/.test(decoded)) {
    //   // プログレスバーは1つのキーで最新のものだけを保持
    //   return 'progress-bar';
    // }

    // 「第n部分」と「第n章」を同じグループにまとめる
    // プログレスバー → 第n部分 → 第n章 → 章タイトル (n/m) の順で来るので
    // 最終的に章タイトルのみが表示される（第n部分と第n章は上書きされて隠れる）
    if (/^第[\d０-９]+部分\s*$/.test(decoded)) {
      return "progress-chapter-download";
    }

    // 章データ: 漢数字、全角数字、半角数字すべてに対応、「第」の有無も対応
    if (/^第?[一二三四五六七八九十百千壱弐参０-９\d]+章\s*$/.test(decoded)) {
      return "progress-chapter-download";
    }

    // 章タイトル + (n/m) パターンも同じキー
    if (/.*\(\d+\/\d+\)/.test(decoded)) {
      return "progress-chapter-download";
    }

    // 「第一話」「第二十話」などの漢数字パターン
    if (/第[一二三四五六七八九十百千]+話/.test(decoded)) {
      return "progress-chapter-title";
    }

    // (n/m) 形式のパターンがある場合、その前の文字列をキーにする
    // 例: "処理中 (1/10)" -> "処理中"
    const progressMatch = decoded.match(/^(.+?)\s*\(\d+\/\d+\)/);
    if (progressMatch) return `progress-${progressMatch[1].trim()}`;

    // それ以外は先頭20文字をキーにする
    const titleMatch = decoded.match(/^(.{0,20})/);
    if (titleMatch) return `progress-${titleMatch[1].trim()}`;

    return "progress-unknown";
  }

  /**
   * ログメッセージから処理タイプと小説IDを抽出
   */
  function extractProcessInfo(message: string): {
    processType?: "download" | "convert" | "skip" | "other";
    novelId?: string;
  } {
    // 小説IDを抽出
    const idMatch = message.match(/ID[:：]\s*(\d+)/i);
    const novelId = idMatch ? idMatch[1] : undefined;

    // 処理タイプを判定
    let processType: "download" | "convert" | "skip" | "other" | undefined;

    if (/ダウンロード|download|DL/i.test(message)) {
      processType = "download";
    } else if (/スキップ|skip/i.test(message)) {
      // 変換スキップメッセージを識別
      processType = "skip";
    } else if (/変換|convert|epub/i.test(message)) {
      processType = "convert";
    } else if (novelId || /処理|progress/i.test(message)) {
      processType = "other";
    }

    return { processType, novelId };
  }

  /**
   * 最下部にスクロール（強制）
   */
  function scrollToBottom() {
    setTimeout(() => {
      if (splitView) {
        if (leftPaneContainer) {
          leftPaneContainer.scrollTop = leftPaneContainer.scrollHeight;
        }
        if (rightPaneContainer) {
          rightPaneContainer.scrollTop = rightPaneContainer.scrollHeight;
        }
      } else {
        if (logContainer) {
          logContainer.scrollTop = logContainer.scrollHeight;
        }
      }
    }, 10);
  }

  /**
   * 自動スクロール（autoScrollがtrueの場合のみ）
   */
  function scrollIfNeeded() {
    if (autoScroll) {
      scrollToBottom();
    }
  }

  /**
   * ダウンロード系のログをフィルタ
   */
  function getDownloadLogs(): LogEntry[] {
    return logs.filter(
      (log) =>
        log.console !== "convert" &&
        (log.processType === "download" ||
          (!log.processType &&
            /ダウンロード|download|DL|フェッチ|fetch/i.test(log.message)))
    );
  }

  /**
   * 変換系のログをフィルタ
   * スキップログは変換ログの上部にまとめて表示
   */
  function getConvertLogs(): LogEntry[] {
    const convertLogs = logs.filter(
      (log) =>
        log.console === "convert" ||
        log.processType === "convert" ||
        log.processType === "skip" ||
        (!log.processType &&
          /変換|convert|epub|スキップ|skip/i.test(log.message))
    );

    // スキップログと変換ログを分離
    const skipLogs = convertLogs.filter((log) => log.processType === "skip");
    const nonSkipLogs = convertLogs.filter((log) => log.processType !== "skip");

    // それぞれを時間順でソート
    skipLogs.sort((a, b) => a.id - b.id);
    nonSkipLogs.sort((a, b) => a.id - b.id);

    // スキップログを上部に、変換ログを下部に配置
    return [...skipLogs, ...nonSkipLogs];
  }

  /**
   * その他のログをフィルタ（分割時は左ペインに表示）
   * スキップログは変換ペインに表示するため除外
   */
  function getOtherLogs(): LogEntry[] {
    return logs.filter(
      (log) =>
        log.console !== "convert" &&
        log.processType !== "skip" &&
        (!log.processType || log.processType === "other")
    );
  }

  /**
   * コンパクト表示用: 進捗メッセージの重複を除外し最新のみ返す
   */
  function compactLogs(logList: LogEntry[]): LogEntry[] {
    // 空のメッセージを除外
    const filtered = logList.filter((log) => {
      const decoded = decodeMessage(log.message).trim();
      return decoded.length > 0;
    });

    if (!compactProgress) {
      return filtered;
    }

    const progressMap = new Map<string, LogEntry>();
    const nonProgressLogs: LogEntry[] = [];

    for (const log of filtered) {
      // ★プログレスバーは無効化（すべて通常メッセージとして扱う）
      const isProgressBar = false;
      // const isProgressBar = /\[[#*]+[\s.-]*\]/.test(log.message) || /\d+%\s*\[[#*\s.-]*\]\s*\d+%/.test(log.message);

      if (log.isProgress && log.progressKey && !isProgressBar) {
        // 進捗メッセージ（プログレスバー以外）は progressKey ごとに最新のものだけ保持
        const existing = progressMap.get(log.progressKey);
        if (!existing || log.timestamp > existing.timestamp) {
          progressMap.set(log.progressKey, log);
        }
      } else {
        // 非進捗メッセージとプログレスバーはすべて保持
        nonProgressLogs.push(log);
      }
    }

    // 非進捗 + プログレスバー + 最新の進捗メッセージを結合し、タイムスタンプとID順にソート
    return [...nonProgressLogs, ...Array.from(progressMap.values())].sort(
      (a, b) => {
        // まずタイムスタンプで比較
        const timeDiff = a.timestamp.getTime() - b.timestamp.getTime();
        if (timeDiff !== 0) return timeDiff;
        // タイムスタンプが同じ場合はIDで比較（追加順を保持）
        return a.id - b.id;
      }
    );
  }

  /**
   * ログをファイルにエクスポート
   */
  function exportLogs() {
    const text = logs
      .map((log) => {
        const time = formatTime(log.timestamp);
        const consoleType = formatConsoleType(log.console);
        const message = decodeMessage(log.message);
        return `[${time}] [${consoleType}] ${message}`;
      })
      .join("\n");

    const blob = new Blob([text], { type: "text/plain" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `console-${new Date().toISOString().replace(/[:.]/g, "-")}.txt`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }

  /**
   * HTMLエスケープされたメッセージをデコード
   */
  function decodeMessage(html: string): string {
    const txt = document.createElement("textarea");
    txt.innerHTML = html;
    return txt.value;
  }

  /**
   * TermColorタグをHTMLに変換
   */
  function formatMessage(message: string, progressKey?: string): string {
    // HTMLエスケープされているのでデコード
    let text = decodeMessage(message);

    // 改行を含むメッセージを1行にまとめる（調査ログのサマリなど）
    text = text.replace(/\n/g, " ").replace(/\s+/g, " ").trim();

    // TermColorタグをHTMLクラスに変換
    // <red>text</red> -> <span class="tc-red">text</span>
    const colorTags = [
      "red",
      "green",
      "blue",
      "yellow",
      "cyan",
      "magenta",
      "white",
      "black",
    ];
    colorTags.forEach((color) => {
      const regex = new RegExp(`<${color}>([^<]*)</${color}>`, "g");
      text = text.replace(regex, `<span class="tc-${color}">$1</span>`);
    });

    // <bold>text</bold> -> <strong>text</strong>
    text = text.replace(/<bold>([\s\S]*?)<\/bold>/g, "<strong>$1</strong>");

    // <underline>text</underline> -> <u>text</u>
    text = text.replace(/<underline>([\s\S]*?)<\/underline>/g, "<u>$1</u>");

    // ネストされたタグを処理するため、再帰的に適用
    // 例: <bold><green>text</green></bold>
    if (
      /<(red|green|blue|yellow|cyan|magenta|white|black|bold|underline)>/.test(
        text
      )
    ) {
      text = formatMessage(text, progressKey);
    }

    return text;
  }

  /**
   * タイムスタンプをフォーマット
   */
  function formatTime(date: Date): string {
    const h = date.getHours().toString().padStart(2, "0");
    const m = date.getMinutes().toString().padStart(2, "0");
    const s = date.getSeconds().toString().padStart(2, "0");
    return `${h}:${m}:${s}`;
  }

  /**
   * コンソールタイプを表示用にフォーマット
   *
   * - stdout: メイン標準出力（ダウンロード・更新処理など）
   * - stdout2: 並列変換時の第2標準出力（並列処理が有効な場合のみ使用）
   * - convert: 変換専用出力（EPUB/MOBI変換時）
   */
  function formatConsoleType(
    console: "stdout" | "stdout2" | "convert"
  ): string {
    if (console === "stdout2") return "parallel"; // 並列変換用出力
    if (console === "convert") return "convert"; // 変換専用出力
    return "stdout"; // メイン出力
  }

  // イベントハンドラの参照を保持
  let handleConnected: ((data: any) => void) | null = null;
  let handleDisconnected: ((data: any) => void) | null = null;
  let handleEcho: ((data: any) => void) | null = null;
  let handleProgressBarInit: ((data: any) => void) | null = null;
  let handleProgressBarStep: ((data: any) => void) | null = null;
  let handleProgressBarClear: ((data: any) => void) | null = null;
  let handleConsoleClear: ((data: any) => void) | null = null;
  let pushServerInstance: PushServerClient | null = null;

  onMount(() => {
    // 設定を読み込み
    loadSettings();

    // PushServerはブラウザ環境でのみ初期化
    pushServerInstance = getPushServer();
    if (!pushServerInstance) return;

    const pushServer = pushServerInstance;

    // デバッグ: インスタンスIDを生成
    const instanceId = Math.random().toString(36).substring(7);
    console.log(
      `[ConsolePanel ${instanceId}] Mounting, current handlers:`,
      pushServer["eventHandlers"]?.size || 0
    );

    // 接続イベント
    handleConnected = () => {
      isConnected = true;
      addLog("stdout", "[PushServer] Connected");
    };
    pushServer.on("connected", handleConnected);

    handleDisconnected = () => {
      isConnected = false;
      addLog("stdout", "[PushServer] Disconnected");
    };
    pushServer.on("disconnected", handleDisconnected);

    // echoイベント
    handleEcho = (data: EchoMessage) => {
      console.log(
        `[ConsolePanel ${instanceId}] Received echo event:`,
        data.body
      );
      if (!data.no_history) {
        addLog(data.target_console, data.body, data.timestamp);
      }
    };
    pushServer.on("echo", handleEcho);

    // プログレスバーイベント
    handleProgressBarInit = (data: any) => {
      const consoleType = (data.target_console || "stdout") as
        "stdout" | "stdout2" | "convert";

      // 進捗開始のログエントリを作成
      const newLog: LogEntry = {
        id: nextId++,
        timestamp: new Date(),
        console: consoleType,
        message: "[          ] 0%",
        isProgress: false, // プログレスバーは個別表示
      };

      currentProgressBar = {
        console: consoleType,
        percent: 0,
        logId: newLog.id,
      };

      logs = [...logs, newLog];
      scrollIfNeeded();
    };
    pushServer.on("progressbar.init", handleProgressBarInit);

    handleProgressBarStep = (data: any) => {
      if (currentProgressBar) {
        currentProgressBar.percent = data.percent || 0;
        const consoleType = (data.target_console ||
          currentProgressBar.console) as "stdout" | "stdout2" | "convert";

        // プログレスバーの表示を生成
        const percent = Math.round(currentProgressBar.percent);
        const barLength = 10;
        const filled = Math.round((percent / 100) * barLength);
        const empty = barLength - filled;
        const bar = "[" + "#".repeat(filled) + " ".repeat(empty) + "]";
        const message = `${bar} ${percent}%`;

        // 既存のプログレスバーログを更新、なければ新規作成
        if (currentProgressBar.logId !== undefined) {
          const index = logs.findIndex(
            (log) => log.id === currentProgressBar!.logId
          );
          if (index !== -1) {
            logs[index] = {
              ...logs[index],
              message,
              timestamp: new Date(),
            };
            logs = [...logs];
          } else {
            // ログが見つからない場合は新規作成
            const newLog: LogEntry = {
              id: nextId++,
              timestamp: new Date(),
              console: consoleType,
              message,
              isProgress: false, // プログレスバーは個別表示
            };
            currentProgressBar.logId = newLog.id;
            logs = [...logs, newLog];
          }
        } else {
          // 初回のプログレスバー表示
          const newLog: LogEntry = {
            id: nextId++,
            timestamp: new Date(),
            console: consoleType,
            message,
            isProgress: false, // プログレスバーは個別表示
          };
          currentProgressBar.logId = newLog.id;
          logs = [...logs, newLog];
        }

        scrollIfNeeded();
      } else {
        window.console.warn(
          "[DEBUG] Progress bar step received but no currentProgressBar"
        );
      }
    };
    pushServer.on("progressbar.step", handleProgressBarStep);

    handleProgressBarClear = (data: any) => {
      // clearイベントは無視（プログレスバーを残す）
      currentProgressBar = null;
    };
    pushServer.on("progressbar.clear", handleProgressBarClear);

    // コンソールクリアイベント
    handleConsoleClear = () => {
      console.log(`[ConsolePanel ${instanceId}] Received console.clear event`);
      logs = [];
      currentProgressBar = null;
    };
    pushServer.on("console.clear", handleConsoleClear);

    // getPushServer()が自動的に接続を管理するため、ここでは何もしない
    // 既に接続されている場合は再接続しない
  });

  onDestroy(() => {
    // イベントハンドラを解除（重複登録を防ぐため）
    if (!pushServerInstance) return;

    const pushServer = pushServerInstance;

    console.log(`[ConsolePanel] Destroying, removing handlers`);

    if (handleConnected) {
      pushServer.off("connected", handleConnected);
    }
    if (handleDisconnected) {
      pushServer.off("disconnected", handleDisconnected);
    }
    if (handleEcho) {
      pushServer.off("echo", handleEcho);
      console.log(`[ConsolePanel] Removed echo handler`);
    }
    if (handleProgressBarInit) {
      pushServer.off("progressbar.init", handleProgressBarInit);
    }
    if (handleProgressBarStep) {
      pushServer.off("progressbar.step", handleProgressBarStep);
    }
    if (handleProgressBarClear) {
      pushServer.off("progressbar.clear", handleProgressBarClear);
    }
    if (handleConsoleClear) {
      pushServer.off("console.clear", handleConsoleClear);
      console.log(`[ConsolePanel] Removed console.clear handler`);
    }

    // 共有インスタンスなので切断しない（他のページで使用される可能性がある）
    // pushServer.disconnect();
  });
</script>

{#if isOpen}
  <div
    class="fixed bottom-0 left-0 right-0 z-40 bg-gray-900 dark:bg-gray-950 border-t border-gray-700 shadow-lg"
    data-console-panel
    data-is-open="true"
  >
    <!-- ヘッダー -->
    <div
      class="flex items-center justify-between px-4 py-2 bg-gray-800 dark:bg-gray-900 border-b border-gray-700"
    >
      <div class="flex items-center gap-3">
        <h3 class="text-sm font-semibold text-gray-100">コンソール</h3>
        <div class="flex items-center gap-2">
          <div
            class="w-2 h-2 rounded-full {isConnected
              ? 'bg-green-500'
              : 'bg-red-500'}"
          ></div>
          <span class="text-xs text-gray-400">
            {isConnected ? "接続中" : "切断"}
          </span>
        </div>
        <span class="text-xs text-gray-500">
          {logs.length} 件
        </span>
      </div>

      <div class="flex items-center gap-2">
        <label
          class="flex items-center gap-2 text-xs text-gray-400 cursor-pointer"
          title="進捗を1行で表示"
        >
          <input
            type="checkbox"
            bind:checked={compactProgress}
            class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-gray-900"
          />
          コンパクト
        </label>
        <label
          class="flex items-center gap-2 text-xs text-gray-400 cursor-pointer"
          title="ダウンロードと変換を分割表示"
        >
          <input
            type="checkbox"
            bind:checked={splitView}
            class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-gray-900"
          />
          分割表示
        </label>
        <label
          class="flex items-center gap-2 text-xs text-gray-400 cursor-pointer"
        >
          <input
            type="checkbox"
            bind:checked={autoScroll}
            class="rounded border-gray-600 bg-gray-700 text-blue-600 focus:ring-blue-500 focus:ring-offset-gray-900"
          />
          自動スクロール
        </label>
        <select
          bind:value={updateThrottle}
          class="text-xs bg-gray-700 border-gray-600 text-gray-300 rounded px-2 py-1 focus:ring-blue-500 focus:border-blue-500"
          title="更新頻度"
        >
          <option value={50}>高速 (50ms)</option>
          <option value={100}>標準 (100ms)</option>
          <option value={500}>低速 (500ms)</option>
          <option value={1000}>最低速 (1s)</option>
        </select>
        <button
          onclick={exportLogs}
          class="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded transition-colors"
          title="ログをエクスポート"
        >
          保存
        </button>
        <button
          onclick={clearLogs}
          class="px-3 py-1 text-xs bg-gray-700 hover:bg-gray-600 text-gray-300 rounded transition-colors"
          title="ログをクリア"
        >
          クリア
        </button>
        <button
          onclick={close}
          class="text-gray-400 hover:text-gray-200 text-xl leading-none"
          title="閉じる"
        >
          ×
        </button>
      </div>
    </div>

    <!-- ログ表示エリア -->
    {#if splitView}
      <!-- 左右分割表示 -->
      <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
      <div
        class="console-split-view flex h-64 relative"
        role="group"
        onmousemove={handleResize}
        onmouseup={stopResize}
        onmouseleave={stopResize}
      >
        <!-- 左ペイン: ダウンロード・その他 -->
        <div
          class="flex flex-col border-r border-gray-700"
          style="width: {splitRatio}%"
        >
          <div
            class="px-3 py-1 bg-gray-800 border-b border-gray-700 text-xs font-semibold text-blue-300"
          >
            📥 ダウンロード・フェッチ
          </div>
          <div
            bind:this={leftPaneContainer}
            class="flex-1 overflow-y-auto px-4 py-2 font-mono text-xs bg-gray-900 dark:bg-black text-gray-300"
          >
            {#if getDownloadLogs().length === 0 && getOtherLogs().length === 0}
              <div class="text-gray-500 text-center py-8">ログがありません</div>
            {:else}
              {#each compactLogs( [...getDownloadLogs(), ...getOtherLogs()] ) as log (log.id)}
                <LogEntryComponent
                  {log}
                  {formatTime}
                  {formatConsoleType}
                  {formatMessage}
                />
              {/each}
            {/if}
          </div>
        </div>

        <!-- リサイザー -->
        <!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
        <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
        <div
          class="w-1 bg-gray-700 hover:bg-blue-500 cursor-col-resize transition-colors absolute top-0 bottom-0 {isResizing
            ? 'bg-blue-500'
            : ''}"
          style="left: {splitRatio}%"
          onmousedown={startResize}
          role="separator"
          aria-label="リサイズ"
          tabindex="0"
        ></div>

        <!-- 右ペイン: 変換 -->
        <div class="flex flex-col" style="width: {100 - splitRatio}%">
          <div
            class="px-3 py-1 bg-gray-800 border-b border-gray-700 text-xs font-semibold text-green-300"
          >
            ⚙️ 変換・EPUB生成
          </div>
          <div
            bind:this={rightPaneContainer}
            class="flex-1 overflow-y-auto px-4 py-2 font-mono text-xs bg-gray-900 dark:bg-black text-gray-300"
          >
            {#if getConvertLogs().length === 0}
              <div class="text-gray-500 text-center py-8">ログがありません</div>
            {:else}
              {#each compactLogs(getConvertLogs()) as log (log.id)}
                <LogEntryComponent
                  {log}
                  {formatTime}
                  {formatConsoleType}
                  {formatMessage}
                  isConvertPane={true}
                />
              {/each}
            {/if}
          </div>
        </div>
      </div>
    {:else}
      <!-- 統合表示 -->
      <div
        bind:this={logContainer}
        class="overflow-y-auto h-64 px-4 py-2 font-mono text-xs bg-gray-900 dark:bg-black text-gray-300"
      >
        {#if logs.length === 0}
          <div class="text-gray-500 text-center py-8">ログがありません</div>
        {:else}
          {#each compactLogs(logs) as log (log.id)}
            <LogEntryComponent
              {log}
              {formatTime}
              {formatConsoleType}
              {formatMessage}
            />
          {/each}
        {/if}
      </div>
    {/if}
  </div>
{/if}

<!-- フローティング開閉ボタン（閉じている時） -->
{#if !isOpen}
  <button
    onclick={open}
    class="fixed bottom-4 right-4 z-40 px-4 py-2 bg-gray-800 hover:bg-gray-700 text-white rounded-lg shadow-lg border border-gray-700 flex items-center gap-2 transition-colors"
    title="コンソールを開く"
    data-console-panel
    data-is-open="false"
  >
    <span
      class="w-2 h-2 rounded-full {isConnected ? 'bg-green-500' : 'bg-red-500'}"
    ></span>
    <span class="text-sm">コンソール</span>
    {#if logs.length > 0}
      <span class="px-2 py-0.5 bg-blue-600 text-white text-xs rounded-full">
        {logs.length}
      </span>
    {/if}
  </button>
{/if}

<style>
  /* TermColor タグのスタイル */
  :global(.tc-red) {
    color: #ef4444;
  }
  :global(.tc-green) {
    color: #22c55e;
  }
  :global(.tc-blue) {
    color: #3b82f6;
  }
  :global(.tc-yellow) {
    color: #eab308;
  }
  :global(.tc-cyan) {
    color: #06b6d4;
  }
  :global(.tc-magenta) {
    color: #d946ef;
  }
  :global(.tc-white) {
    color: #f3f4f6;
  }
  :global(.tc-black) {
    color: #1f2937;
  }
</style>
