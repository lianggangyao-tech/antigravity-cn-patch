# antigravity-cn-patch

适用于 **Google Antigravity App 2.x（Windows Electron 版）** 的零依赖、100% 可逆中文界面补丁与中文输出规则配置。

> **特性与安全保障**
> - **零依赖运行**：纯 PowerShell + JavaScript 实现，无需安装 Node.js、Python 或 Git。
> - **100% 可逆还原**：首次应用自动将原版 `app.asar` 完整备份至 `backup/<版本号>/app.asar`；随时可一键无损还原至官方纯英文版。
> - **数据零触碰**：仅增量注入渲染层与原生菜单汉化脚本，**绝不触碰**账号、登录态、对话历史、项目数据或 `settings.json`。
> - **防误伤保护**：自动跳过代码块、终端、代码编辑器、输入框正文与用户内容，仅翻译界面控件与系统提示。
> - **兼容官方更新**：Antigravity 官方升级后，退出客户端重新双击 `apply-cn.bat` 即可自动识别新版本并重新汉化。

---

## 目录结构

```text
antigravity-cn-patch/
├── apply-cn.bat        # 双击运行：一键应用中文界面补丁
├── apply-cn.ps1        # 应用补丁核心脚本（自动检测路径与版本、备份、校验与注入）
├── restore-en.bat      # 双击运行：一键还原官方纯英文界面
├── restore-en.ps1      # 一键还原核心脚本
├── cn-patch.js         # 渲染层 Web UI 中文词典（3,300+ 词条与动态模板，支持 Shadow DOM）
├── menu-patch.js       # 主进程顶部原生菜单栏与系统托盘中文映射
├── rules/
│   └── GEMINI.md       # Agent 全局中文回复规则模板（让 AI 回复与步骤标题均用简体中文）
├── .gitignore
├── LICENSE             # MIT License
└── README.md
```

---

## 快速使用（三步完成）

### 1. 完全退出 Antigravity
- 关闭所有 Antigravity 窗口。
- 检查 Windows 右下角系统托盘，若仍有 Antigravity 图标，右键选择 **Quit / 退出**，确保后台进程完全结束。

### 2. 应用中文补丁
- 将本仓库下载或解压到本地目录（例如 `D:\antigravity-cn\`）。
- 双击运行 **`apply-cn.bat`**（若软件安装在 `Program Files` 下，请右键选择 **以管理员身份运行**）。
- 脚本会自动检测安装目录与版本号，备份原始 `app.asar` 后写入汉化补丁，并在结束时打印改动文件的绝对路径清单。

### 3. 重新打开验证
- 启动 Antigravity，即可看到全中文界面（侧边栏、设置面板、对话控件、顶部原生菜单与托盘菜单）。
- 建议为 `apply-cn.bat` 创建一个桌面快捷方式（如 `Antigravity 一键汉化`），日后软件自动更新后，退出 App 双击一次即可重新汉化。

---

## 让 Agent 默认使用中文回复（规则配置）

界面汉化仅改变客户端自身菜单与按钮；若希望 AI Agent 的回复正文、思考摘要与工具步骤标题也全部使用简体中文，请配置全局规则：

- 复制本仓库中的 [`rules/GEMINI.md`](rules/GEMINI.md) 到你的用户配置目录：
  `%USERPROFILE%\.gemini\GEMINI.md`
- 或者直接在 Antigravity 界面中进入 **自定义配置（Customizations） → 规则（Rules） → 编辑全局 `GEMINI.md`**，粘贴 [`rules/GEMINI.md`](rules/GEMINI.md) 的内容并保存。

---

## 一键还原与故障回滚

1. 完全退出 Antigravity（含右下角系统托盘）。
2. 双击运行 **`restore-en.bat`**，脚本会自动从 `backup/<版本号>/app.asar` 恢复官方纯净英文原版。
3. 若脚本无法运行，也可手动将 `backup\<版本号>\app.asar` 复制覆盖回 Antigravity 安装目录的 `resources\app.asar`。

---

## 自定义补充词条

- 编辑 `cn-patch.js`（界面词条）或 `menu-patch.js`（原生菜单词条），保持 **UTF-8 无 BOM** 编码保存。
- 退出 Antigravity 后重新运行 `apply-cn.bat` 即可生效（脚本始终基于 `backup/<版本号>/app.asar` 的纯净备份重新生成，不会重复叠加）。

---

## 致谢与开源协议

- 部分界面词条参考并整理自社区开源项目 [Silas-02/antigravity-desktop-cn](https://github.com/Silas-02/antigravity-desktop-cn)。
- 本项目基于 [MIT License](LICENSE) 开源。
