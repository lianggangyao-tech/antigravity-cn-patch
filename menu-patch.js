// Antigravity App 2.x - Reversible Chinese Native Menu & Tray Patch (Main Process)
// Encoding: UTF-8 (no BOM)
(function initAntigravityCnMenuPatch() {
  if (global.__AGY_CN_MENU_PATCH_LOADED__) return;
  global.__AGY_CN_MENU_PATCH_LOADED__ = true;
  try {
    const electron = require('electron');
    if (!electron || !electron.Menu || typeof electron.Menu.buildFromTemplate !== 'function') return;

    const LABEL_MAP = {
      'File': '文件(&F)',
      'Edit': '编辑(&E)',
      'View': '视图(&V)',
      'Window': '窗口(&W)',
      'Help': '帮助(&H)',
      'New Window': '新建窗口',
      'Close Window': '关闭窗口',
      'Close': '关闭',
      'Quit': '退出',
      'Exit': '退出',
      'Undo': '撤销',
      'Redo': '重做',
      'Cut': '剪切',
      'Copy': '复制',
      'Paste': '粘贴',
      'Paste and Match Style': '粘贴并匹配样式',
      'Delete': '删除',
      'Select All': '全选',
      'Reload': '重新加载',
      'Force Reload': '强制重新加载',
      'Toggle Developer Tools': '切换开发者工具',
      'Actual Size': '实际大小',
      'Reset Zoom': '重置缩放',
      'Zoom In': '放大',
      'Zoom Out': '缩小',
      'Toggle Full Screen': '切换全屏',
      'Minimize': '最小化',
      'Zoom': '缩放',
      'Docs': '帮助文档',
      'Documentation': '帮助文档',
      'About Antigravity': '关于 Antigravity',
      'Check for Updates...': '检查更新...',
      'Check for Updates': '检查更新',
      'Checking for Updates...': '正在检查更新...',
      'Downloading Update...': '正在下载更新...',
      'Restart to Update': '重启以更新',
      'Connect to WSL': '连接到 WSL',
      'Reopen Locally': '在本地重新打开',
      'Show': '显示窗口',
      'Hide': '隐藏窗口',
      'Settings': '设置',
      'Preferences': '偏好设置'
    };

    const ROLE_MAP = {
      filemenu: '文件(&F)',
      editmenu: '编辑(&E)',
      viewmenu: '视图(&V)',
      windowmenu: '窗口(&W)',
      help: '帮助(&H)',
      undo: '撤销',
      redo: '重做',
      cut: '剪切',
      copy: '复制',
      paste: '粘贴',
      pasteandmatchstyle: '粘贴并匹配样式',
      delete: '删除',
      selectall: '全选',
      reload: '重新加载',
      forcereload: '强制重新加载',
      toggledevtools: '切换开发者工具',
      resetzoom: '实际大小',
      zoomin: '放大',
      zoomout: '缩小',
      togglefullscreen: '切换全屏',
      minimize: '最小化',
      close: '关闭',
      quit: '退出',
      about: '关于 Antigravity'
    };

    function translateItem(item) {
      if (!item || typeof item !== 'object') return item;
      const copy = Object.assign({}, item);
      if (typeof copy.label === 'string' && Object.prototype.hasOwnProperty.call(LABEL_MAP, copy.label)) {
        copy.label = LABEL_MAP[copy.label];
      } else if (!copy.label && typeof copy.role === 'string') {
        const key = copy.role.toLowerCase();
        if (Object.prototype.hasOwnProperty.call(ROLE_MAP, key)) {
          copy.label = ROLE_MAP[key];
        }
      }
      if (Array.isArray(copy.submenu)) {
        copy.submenu = copy.submenu.map(translateItem);
      }
      return copy;
    }

    const origBuild = electron.Menu.buildFromTemplate.bind(electron.Menu);
    electron.Menu.buildFromTemplate = function patchedBuildFromTemplate(template) {
      if (Array.isArray(template)) {
        try {
          return origBuild(template.map(translateItem));
        } catch (_) {
          return origBuild(template);
        }
      }
      return origBuild(template);
    };
  } catch (err) {
    try { console.warn('[agy-cn-menu]', err); } catch (_) {}
  }
})();
