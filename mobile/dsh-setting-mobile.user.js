// ==UserScript==
// @name         dsh web 设置面板固定定位适配
// @namespace    本机自用
// @version      11.0.0
// @description  设置面板：顶部留 15% + 底部留 15% 距离（上下各留白），内层滚动 + 左栏限宽 + 卡片自适应
// @match        http://127.0.0.1:3080/*
// @match        http://localhost:3080/*
// @match        http://*:3080/*
// @run-at       document-idle
// @grant        none
// ==/UserScript==

(function () {
  'use strict';
  /* ============ 可调参数 ============
     上、下各留多少（vh 百分比）。你要求各 15。 */
  var GAP = 15;
  var HEIGHT = 100 - GAP - GAP;  // = 70
  /* ================================== */

  var CSS = `
/* 面板：上下各留空 GAP%（15%），水平居中 */
[class$="_overlay"] {
  justify-content: center !important;
  align-items: flex-start !important;  /* 面板从顶部开始，不用垂直居中 */
}
[class$="_panel"] {
  position: relative !important;
  margin-top: ${GAP}vh !important;      /* 距顶留 15vh */
  height: ${HEIGHT}vh !important;       /* 70vh，底部自然留 15vh */
  max-height: ${HEIGHT}vh !important;
  width: min(520px, calc(100vw - 16px)) !important;
  max-width: calc(100vw - 16px) !important;
  overflow: hidden !important;
  display: flex !important;
}

/* 内层滚动 */
[class$="_content"] {
  flex: 1 1 0% !important;
  min-height: 0 !important;
  min-width: 0 !important;
  display: flex !important;
  flex-direction: column !important;
  overflow: hidden !important;
}
[class$="_options"] {
  flex: 1 1 0% !important;
  min-height: 0 !important;
  overflow-y: auto !important;
  overflow-x: hidden !important;
  padding-left: 12px !important;
  padding-right: 12px !important;
}

/* 左栏限宽 */
[class$="_nav"] {
  flex: 0 0 auto !important;
  width: 128px !important;
  min-width: 96px !important;
  max-width: 128px !important;
  padding-left: 8px !important;
  padding-right: 8px !important;
  overflow: hidden !important;
}
[class$="_navLabel"] {
  white-space: normal !important;
  word-break: break-word !important;
  overflow-wrap: break-word !important;
}

/* 卡片：窄屏单列自适应 */
@media (max-width: 620px) {
  [class$="_cards"] {
    grid-template-columns: 1fr !important;
    gap: 10px !important;
  }
  [class$="_card"], [class$="_cardMain"] {
    width: 100% !important;
    min-width: 0 !important;
    max-width: 100% !important;
  }
  [class$="_cardName"], [class$="_cardDesc"] {
    white-space: normal !important;
    word-break: break-word !important;
    overflow-wrap: break-word !important;
  }
}

/* 内容项防溢出 + 自适应字体 */
[class$="_content"] [class$="_row"] {
  flex-wrap: wrap !important;
  align-items: flex-start !important;
  gap: 6px !important;
}
[class$="_content"] [class$="_rowText"] {
  flex: 1 1 0px !important;
  min-width: 0 !important;
  padding-right: 0 !important;
  display: block !important;
}
[class$="_content"] [class$="_title"],
[class$="_content"] [class$="_desc"] {
  font-size: clamp(12.5px, 2.4vw, 16px) !important;
  line-height: 1.4 !important;
  writing-mode: horizontal-tb !important;
  white-space: normal !important;
  word-break: break-word !important;
  overflow-wrap: break-word !important;
  max-width: 100% !important;
}

/* 全局防溢出 */
[class$="_panel"] * {
  max-width: 100% !important;
  box-sizing: border-box !important;
}
`;

  var ID = 'dsh-settings-fix';
  function inject() {
    if (document.getElementById(ID)) return;
    var tag = document.createElement('style');
    tag.id = ID;
    tag.textContent = CSS;
    (document.head || document.documentElement).appendChild(tag);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', inject);
  else inject();
})();
