// ==UserScript==
// @name         dsh web 手机端分区自适应 (JS 统计行自适应)
// @namespace    本机自用
// @version      19.0.0
// @description  一份脚本：①输入行固定百分比间距；②设置面板上下15%/卡片；③统计行 FJxK0a_root JS动态测量字号，保证完整可见且≤2行
// @match        http://127.0.0.1:3080/*
// @match        http://localhost:3080/*
// @match        http://*:3080/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';

  /* ============ 可调参数 ============ */
  var GAP = 15;                 // 设置面板上下各留(gh)
  var HEIGHT = 100 - GAP - GAP; // =70
  var ROW_GAP_PCT = 2;          // 输入行元素间距(行宽%)
  var STAT_MAX_FONT = 13;       // 统计行字号上限（两行格局用）
  var STAT_MIN_FONT = 9;        // 统计行字号下限

  /* ============ ① CSS 注入 ============ */
  var CSS = `
/* ---- 输入行 ---- */
.uV2eYG_row {
  justify-content: space-between !important;
  flex-wrap: nowrap !important;
  gap: ${ROW_GAP_PCT}% !important;
  align-items: center !important;
}
.uV2eYG_row > * { flex: 0 1 auto !important; min-width: 0 !important; }
.uV2eYG_trailing { flex: 0 1 auto !important; min-width: 0 !important; gap: ${ROW_GAP_PCT / 2}% !important; }
.uV2eYG_tools, .uV2eYG_modes { gap: ${ROW_GAP_PCT}% !important; }

/* ---- 模型/模式选择器 trigger ---- */
.uV2eYG_row [class$="_trigger"] {
  flex-wrap: nowrap !important; height: auto !important; min-height: 28px !important;
  max-width: 100% !important; gap: 2% !important; padding-left: 6px !important; padding-right: 6px !important;
}
.uV2eYG_row [class$="_triggerLabel"] {
  white-space: nowrap !important; text-overflow: ellipsis !important;
  min-width: 0 !important; flex: 0 1 auto !important; overflow: hidden !important;
}
.uV2eYG_row [class$="_triggerEffort"],
.uV2eYG_row [class$="_chevron"] { flex: 0 0 auto !important; margin-left: 2% !important; }

/* ---- 模型选择下拉菜单 ---- */
._7KE1Ra_menu {
  max-width: calc(100vw - 8px) !important; width: max-content !important; min-width: 160px !important;
}
._7KE1Ra_menu [class$="_cell"] { height: auto !important; min-height: 40px !important; flex-wrap: nowrap !important; gap: 2% !important; }
._7KE1Ra_menu [class$="_cellLabel"] { flex: 0 1 auto !important; min-width: 0 !important; white-space: nowrap !important; text-overflow: ellipsis !important; overflow: hidden !important; }
._7KE1Ra_menu [class$="_cellValue"] { flex: 0 1 auto !important; min-width: 0 !important; white-space: nowrap !important; text-overflow: ellipsis !important; overflow: hidden !important; }
._7KE1Ra_menu [class$="_cellChevron"] { flex: 0 0 auto !important; margin-left: 2% !important; }

/* ---- 设置面板 ---- */
.VOzbGW_overlay { justify-content: center !important; align-items: flex-start !important; }
.VOzbGW_panel {
  margin-top: ${GAP}vh !important; height: ${HEIGHT}vh !important; max-height: ${HEIGHT}vh !important;
  width: min(520px, calc(100vw - 16px)) !important; max-width: calc(100vw - 16px) !important;
  overflow: hidden !important; display: flex !important;
}
.VOzbGW_content { flex: 1 1 0% !important; min-height: 0 !important; min-width: 0 !important; display: flex !important; flex-direction: column !important; overflow: hidden !important; }
.VOzbGW_options { flex: 1 1 0% !important; min-height: 0 !important; overflow-y: auto !important; overflow-x: hidden !important; padding-left: 12px !important; padding-right: 12px !important; }
.VOzbGW_nav { flex: 0 0 auto !important; width: 128px !important; min-width: 96px !important; max-width: 128px !important; padding-left: 8px !important; padding-right: 8px !important; overflow: hidden !important; }
.VOzbGW_navLabel { white-space: normal !important; word-break: break-word !important; overflow-wrap: break-word !important; }
@media (max-width: 620px) {
  .VOzbGW_panel [class$="_cards"] { grid-template-columns: 1fr !important; gap: 10px !important; }
  .VOzbGW_panel [class$="_card"], .VOzbGW_panel [class$="_cardMain"] { width: 100% !important; min-width: 0 !important; max-width: 100% !important; }
  .VOzbGW_panel [class$="_cardName"], .VOzbGW_panel [class$="_cardDesc"] { white-space: normal !important; word-break: break-word !important; overflow-wrap: break-word !important; }
}
.VOzbGW_panel [class$="_row"] { flex-wrap: wrap !important; align-items: flex-start !important; gap: 6px !important; }
.VOzbGW_panel [class$="_rowText"] { flex: 1 1 0px !important; min-width: 0 !important; padding-right: 0 !important; display: block !important; }
.VOzbGW_panel [class$="_title"], .VOzbGW_panel [class$="_desc"] { font-size: clamp(12.5px, 2.4vw, 16px) !important; line-height: 1.4 !important; writing-mode: horizontal-tb !important; white-space: normal !important; word-break: break-word !important; overflow-wrap: break-word !important; max-width: 100% !important; }
`;

  var STYLE_ID = 'dsh-mobile-partition-fix';
  function injectCSS() {
    if (document.getElementById(STYLE_ID)) return;
    var tag = document.createElement('style');
    tag.id = STYLE_ID;
    tag.textContent = CSS;
    (document.head || document.documentElement).appendChild(tag);
  }

  /* ============ ③ 统计行字号自适应维持两行 ============
     目标：统计行(FJxK0a_root)始终在【≤2 行】内完整显示全部内容。
     - 二分找能放进2行的最大字号，随用户字体/屏宽自动缩放；
     - 不裁剪第3行——通过缩字号让内容天然放进2行。 */
  var fitTimer = null;

  function fitStatsLine() {
    var roots = document.querySelectorAll('.FJxK0a_root');
    roots.forEach(function (root) {
      var text = (root.innerText || '').replace(/\s+/g, ' ').trim();
      if (!text) return;

      // 让容器允许换行(为测量真实行数做准备)，但不裁剪
      root.style.whiteSpace = 'normal';
      root.style.maxWidth = '100%';
      root.style.display = 'block';
      root.style.overflow = 'visible';
      root.style.maxHeight = 'none';   // 先放开高度，测量真实行数

      var lhFactor = 1.4;
      // 二分：找「内容完整放进 ≤2 行」的最大字号
      var lo = STAT_MIN_FONT, hi = STAT_MAX_FONT, chosen = STAT_MIN_FONT;
      while (lo <= hi) {
        var mid = (lo + hi) >> 1;
        root.style.fontSize = mid + 'px';
        root.style.lineHeight = lhFactor;
        // 判断内容是否≤2行：用行高×2 与内容高度比较
        var lineH = Math.ceil(mid * lhFactor);
        var twoLinesH = lineH * 2;
        // 行数 = ceil(scrollHeight / lineH)；≤2 即内容两行内放下
        var lines = Math.ceil((root.scrollHeight + 1) / lineH);
        if (lines <= 2) {
          chosen = mid;      // 两行内放得下，字号还能再大
          lo = mid + 1;
        } else {
          hi = mid - 1;      // 超过两行，缩字号
        }
      }

      // 应用：字号自适应到两行内；不裁剪(字号已保证)
      root.style.fontSize = chosen + 'px';
      root.style.lineHeight = lhFactor;
      root.style.overflow = 'visible';
      root.style.maxHeight = 'none';   // 不限制，因为字号已保证≤2行
    });
  }

  function scheduleFit() {
    if (fitTimer) clearTimeout(fitTimer);
    fitTimer = setTimeout(fitStatsLine, 120);  // 防抖
  }

  function init() {
    injectCSS();
    // 首次 + 布局变化
    scheduleFit();
    window.addEventListener('resize', scheduleFit);
    // SPA：用 MutationObserver 监听统计行出现/变化
    if (window.MutationObserver) {
      var lastText = '';
      var mo = new MutationObserver(function () {
        // 若统计行文本变化或重新渲染，重新 fit
        var any = document.querySelector('.FJxK0a_root');
        if (any) {
          var t = (any.innerText || '').replace(/\s+/g, ' ').trim();
          if (t !== lastText) { lastText = t; scheduleFit(); }
        }
      });
      mo.observe(document.body, { childList: true, subtree: true, characterData: true, attributes: false });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
