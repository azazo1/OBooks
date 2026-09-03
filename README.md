# OBooks

OBooks 是一个面向 macOS 的 EPUB 阅读器初版. 当前重点是验证阅读体验和后续跨平台架构.

## 当前能力

- 导入无 DRM 的 EPUB 2 / EPUB 3 文件.
- 解析书名, 作者, 封面, spine 和 EPUB 3 nav / EPUB 2 NCX 目录.
- 将导入内容复制到 Application Support, 不依赖原始文件位置.
- 使用 WKWebView 和自定义 URL scheme 加载章节资源.
- 基础分页和连续滚动模式.
- 主题, 字号, 行距和边距调整.
- macOS 系统语音朗读和当前章节的范围高亮.

## 尚未包含

- SwiftData 数据模型.
- 复杂 EPUB 的完整分页兼容.
- 固定版式漫画和童书.
- 划线, 笔记, 书内搜索和全文索引.
- iCloud 同步和 DRM.

## 构建

需要 macOS 14 或更高版本和 Xcode 26 或更高版本.

运行构建命令:

    just build

启动应用:

    just run

工程使用 Swift Package 管理, 可以直接在 Xcode 中打开 Package.swift.
