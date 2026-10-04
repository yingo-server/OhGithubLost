# assets · 资源

| 目录 | 内容 | 说明 |
| --- | --- | --- |
| `icon/` | `ogl_icon.svg` | 图标**唯一事实来源**（六边形 + 双三角眼，透明底）；桌面 PNG/ICO 由 `tool/desktop_icon.py` 光栅化 |
| `i18n/` | 15 种语言 × 页面分片 json | `zh` 为源语言，`en` 为基线的键集合 |
| `boot/` | 引导相关资源 | 与 kernel 引导链配合 |
| `mods/` | Mod 包示例 | 本地深层信息的最小披露契约 |
| `theme_packs/` | 主题包 | 可选外观扩展 |

> 改图标只允许改 `icon/ogl_icon.svg`，其它格式一律由工具生成（否则多格式会分叉）。
