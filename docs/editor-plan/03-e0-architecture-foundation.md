# E0 架构地基

## 阶段目标

建立 Editor 的长期模块边界和最小类型系统。E0 不追求可见功能，不接入真实绘制，也不替换 preview。它的价值是让后续 Metal preview、texture cache、输入采样、绘制和写回都沿同一套边界增长。

## 范围

包含：

- 新建 Editor 相关目录或 SwiftPM target。
- 定义核心协议、状态模型、快照模型和测试骨架。
- 把当前 `DocumentModel` 与未来 EditorCore 的职责边界写入代码结构。
- 建立 reviewer 可以执行的 import / dependency 检查口径。

不包含：

- 不实现 Metal 合成。
- 不实现绘制。
- 不改变 PSD 文件读写语义。
- 不重写当前 Viewer UI。

## 建议目录

第一步可以先在 `Apps/PSDViewer/Sources/PSDViewer` 下建立子目录，等边界稳定后再决定是否拆独立 target：

```text
Apps/PSDViewer/Sources/PSDViewer/
  EditorCore/
  RenderCore/
  MetalBackend/
  InputCore/
  AppShell/
```

如果 SwiftPM target 拆分成本可控，长期建议：

```text
Targets:
  PSDViewer
  PSDEditorCore
  PSDRenderCore
  PSDInputCore
```

E0 不强制拆 target，但必须让文件边界先体现模块边界。

## 核心类型

### EditorDocumentAdapter

屏蔽 App Shell 与 PSDKit 直接耦合，作为 EditorCore 访问文档的入口。

职责：

- 暴露 canvas size。
- 暴露 layer tree snapshot。
- 根据 selection 定位 layer。
- 提交文档变更命令。
- 通知 dirty 状态。

不职责：

- 不管理 SwiftUI alert。
- 不保存文件。
- 不持有 Metal texture。

### EditorRenderSnapshot

Renderer 的唯一文档输入。它应该是值类型或接近值类型的数据结构，避免 Renderer 直接抓活的 `PSDDocument`。

建议字段：

- `canvasSize`
- `layers`
- `documentRevision`
- `selectedLayerID`
- `viewportHint`

每个 layer snapshot 建议包含：

- `id`
- `name`
- `kind`
- `frame`
- `isVisible`
- `opacity`
- `blendMode`
- `pixelRevision`
- `pixelSource`

### EditorSelection

统一替代 UI 层散落的 `selectedLayerID` 判断。

建议能力：

- 无选择。
- 选择 layer。
- 未来可扩展到选择区域、路径或 transform handle。

### EditorTool

描述当前工具，不处理事件。

初始枚举：

- `inspect`
- `moveLayer`
- `brush`
- `eraser`
- `hand`
- `zoom`

### EditorCommand

所有编辑变更的统一入口。E0 只定义协议和基础模型，不实现完整 undo。

建议命令：

- `SetLayerFrameCommand`
- `SetLayerOpacityCommand`
- `SetLayerBlendModeCommand`
- `CommitStrokeCommand`
- `ReplaceLayerPixelsCommand`

## 任务包

### E0.1 目录与 target 设计

- 建立 EditorCore、RenderCore、MetalBackend、InputCore 的目录。
- 加入 `README.md` 或模块注释，说明每个目录允许 import 的框架。
- 明确哪些代码仍留在现有 `DocumentModel`。

退出条件：

- 目录存在。
- 每个目录至少有一个占位类型或模块说明。
- review 时能看出依赖方向。

### E0.2 文档快照模型

- 定义 `EditorRenderSnapshot`。
- 定义 `EditorLayerSnapshot`。
- 定义 pixel source 抽象，例如 `.rgbaData` 或 `.documentLayerID`。
- 从当前 `PSDDocument` 构建 snapshot。

退出条件：

- snapshot 构建不 import SwiftUI。
- snapshot 不持有 `DocumentModel`。
- 单元测试覆盖 root pixel layer 与 nested pixel layer。

### E0.3 状态与工具模型

- 定义 `EditorState`。
- 定义 `EditorSelection`。
- 定义 `EditorTool`。
- 定义 `BrushSettings`，先参考 MetalLinePOC 字段，但不引入 Metal。

退出条件：

- 工具切换可以无 UI 测试。
- brush 默认值稳定。
- 不依赖 AppKit 事件。

### E0.4 命令协议

- 定义 `EditorCommand` 协议。
- 定义 command result。
- 定义 command error。
- 定义最小 command dispatcher。

退出条件：

- 属性变更命令可以用 mock document adapter 测试。
- command 不直接触发 alert 或保存。

### E0.5 依赖检查

- 列出每个模块允许 import 的 framework。
- 在 PR review checklist 中加入边界检查。
- 可选：用简单脚本或测试扫描 forbidden imports。

退出条件：

- 能回答「这个文件为什么可以 import Metal」。
- 能回答「这个文件为什么不可以 import SwiftUI」。

## 测试建议

- `EditorRenderSnapshotTests`
- `EditorStateTests`
- `EditorCommandDispatcherTests`
- `EditorDependencyBoundaryTests`（可选）

## 验收 gate

- `EditorCore` 不 import SwiftUI、AppKit、Metal。
- `RenderCore` 不引用 `DocumentModel`。
- `MetalBackend` 不保存 PSD 文件。
- `InputCore` 不写 PSD 像素。
- 至少有 snapshot、selection、tool state 的自动化测试。

## 主要风险

| 风险 | 表现 | 处理 |
|------|------|------|
| 过早拆 target 导致构建摩擦 | SwiftPM 配置比业务设计占用更多时间 | 先拆目录，边界稳定后再拆 target |
| 协议过度抽象 | 没有实现支撑的大量空协议 | 只为 E1/E2/E3 必需路径定义协议 |
| DocumentModel 继续膨胀 | 新 Editor 状态仍然都塞进 `DocumentModel` | `DocumentModel` 只做 App session facade，核心状态进入 EditorCore |

## 进入下一阶段条件

- E0 的核心类型合并。
- 单元测试通过。
- 团队认可 import 边界。
- E1 可以只依赖 snapshot，而不是直接依赖 `DocumentModel`。
