# Editor 架构原则

## 架构目标

Editor 的核心不是「在 Viewer 上叠一个画布」，而是建立稳定的编辑系统边界：

```text
SwiftUI / AppKit Shell
        │
        ▼
InputCore ──► EditorCore ──► RenderCore / MetalBackend
                  │                    │
                  ▼                    ▼
               PSDKit ◄──────── Render Snapshot
```

## 模块边界

### PSDKit

职责：

- PSD 文档读取、写入。
- 图层树、像素层、组、frame、opacity、blend mode 等文档语义。
- 支持子集的合成语义参考实现。
- dirty 状态与保存语义。

不负责：

- 鼠标、数位板、gesture。
- SwiftUI / AppKit view state。
- Metal texture 生命周期。
- Editor 工具、brush、undo/redo UI。

### EditorCore

职责：

- Editor 状态机：当前工具、选中对象、编辑 session。
- 命令模型：stroke commit、layer transform、property edit、undo/redo。
- 坐标系统：view space、canvas space、layer local space。
- 编辑约束：哪些图层可绘制、哪些命令可提交。
- dirty 语义桥接：命令成功后通知文档层内容已修改。

依赖：

- 可以依赖 Foundation/CoreGraphics。
- 可以依赖 PSDKit 的公开文档模型或由 PSDKit 导出的编辑接口。
- 不依赖 SwiftUI。
- 不依赖 Metal 具体实现。

### RenderCore / MetalBackend

职责：

- Metal device、command queue、pipeline、texture cache。
- PSD 图层到 Metal texture 的上传和失效管理。
- 图层合成、透明背景、缩放、平移、选区/边界 overlay。
- 笔刷 dab/stamp、实时 stroke texture、commit 到 layer texture。
- 导出渲染结果或 dirty texture 区域给 EditorCore / PSDKit 写回。

依赖：

- 可以依赖 Metal、MetalKit、CoreGraphics。
- 消费稳定的 render snapshot 或 layer texture descriptor。
- 不依赖 SwiftUI。
- 不直接持有 `DocumentModel`。
- 不直接弹窗、保存文件或操作用户流程。

### InputCore

职责：

- 鼠标、触控板、数位板输入采样。
- pressure、tilt 等输入数据归一化。
- stroke session 的 begin/update/end/cancel。
- 高频采样与后台 poll 机制。

参考：

- `/Users/mini/PROJECT/draw/metal-line-poc/Sources/StrokeSampling`
- `/Users/mini/PROJECT/draw/metal-line-poc/Sources/MetalLinePOC`

依赖：

- 可以依赖 AppKit 事件类型，作为 macOS 输入桥接。
- 输出平台中立的 `PointerSample` / `StrokeSample`。
- 不写 PSD 像素。
- 不知道 Metal pipeline 细节。

### App Shell

职责：

- SwiftUI 布局、菜单、toolbar、sheet、alert。
- AppKit / MetalKit view hosting。
- 用户操作转发到 EditorCore。
- 显示 EditorCore 和 RenderCore 的状态。

不负责：

- 直接改 `PixelLayer.pixels`。
- 直接管理 Metal pipeline。
- 直接实现 brush stamp 算法。
- 直接承担 undo/redo 命令语义。

## 真解耦标准

以下标准用于后续实现和 code review：

- 如果一个模块需要 import SwiftUI，它不能成为核心编辑逻辑模块。
- 如果一个模块需要 import Metal，它不能成为 PSD 文档语义模块。
- 如果一个函数同时处理 UI 事件、坐标换算、像素写入和保存状态，说明边界错误。
- 如果 Renderer 需要读取 `DocumentModel.selectedLayerID`，说明 Renderer 输入不是稳定快照。
- 如果 UI 需要知道 RGBA buffer offset 计算，说明像素编辑接口下沉不足。
- 如果命令无法在无 UI 环境下测试，说明 EditorCore 仍然耦合 UI。

## 数据流原则

### 渲染输入

PSD 文档不应直接暴露给 Renderer 随意遍历。应由 EditorCore 或适配层生成稳定快照：

```text
PSDDocument
    │
    ▼
EditorRenderSnapshot
    │
    ▼
Metal layer texture cache
```

快照应包含：

- canvas size
- layer id
- layer order
- visibility
- opacity
- blend mode
- frame
- pixel buffer revision

### 编辑输出

MetalBackend 不直接保存 PSD。绘制提交建议输出为明确的编辑结果：

```text
Stroke session
    │
    ▼
LayerPixelPatch / DirtyTextureRegion
    │
    ▼
Editor command commit
    │
    ▼
PSDKit document mutation
```

## 与 MetalLinePOC 的关系

MetalLinePOC 是笔刷输入和 GPU stamp 的参考实现，不应整体复制成 PSDViewer 子系统。

推荐复用方向：

- `BrushSettings` 的参数模型。
- `StrokeSampling` 的输入采样分层。
- `SharedMetalPointStorage` 的点缓冲思想。
- `MetalLineRenderer` 中 stroke texture、dab expansion、commit pipeline 的设计。
- shader 中 premultiplied alpha、dab mask、stroke commit 的算法。

需要重新设计的部分：

- 固定 `1024 x 1024` canvas 改为 PSD document canvas。
- 单 canvas texture 改为多图层 texture cache。
- POC 的调试 UI 改为 Editor 状态面板。
- stroke commit 目标从 POC canvas 改为 selected layer texture，再写回 PSD pixel buffer。

## 迁移策略

1. 先建立模块边界和协议。
2. 再替换预览渲染为 Metal 合成路径。
3. 再接入图层 texture cache。
4. 再接入绘制输入和 stroke preview。
5. 最后完善写回、undo/redo、验收和性能基线。

每一步都必须能独立测试和回滚，但不要求每一步都形成完整用户功能。
