# E2 图层纹理缓存

## 阶段目标

建立 PSD 图层到 Metal texture 的稳定缓存与失效机制。E2 的重点不是新增用户功能，而是让后续绘制、变换和局部更新有可靠的资源生命周期。

## 为什么需要单独阶段

如果没有独立 texture cache，绘制管线很容易变成：

```text
UI event → DocumentModel → PixelLayer.pixels → 重新上传整图 → 重新合成
```

这会导致：

- 绘制中无法高频更新。
- GPU 与 PSD 文档状态边界混乱。
- undo/redo 很难区分 texture 临时态和文档持久态。
- 局部 dirty region 无法表达。

E2 要把 layer texture 变成一等资源。

## 范围

包含：

- layer texture descriptor。
- texture cache key。
- pixel revision 与 upload revision。
- layer property 变化的 render invalidation。
- dirty region 数据结构。
- cache diagnostics。

不包含：

- 不实现 brush stamp。
- 不实现 texture readback 写回 PSD。
- 不实现完整 undo。

## 核心类型

### LayerTextureKey

建议字段：

- `documentID`
- `layerID`
- `pixelRevision`
- `colorSpaceHint`
- `pixelFormat`

### LayerTextureRecord

建议字段：

- `texture`
- `size`
- `pixelRevision`
- `lastUploadedAt`
- `dirtyRegion`
- `usage`

### TextureInvalidationReason

建议枚举：

- `pixelsChanged`
- `frameChanged`
- `visibilityChanged`
- `opacityChanged`
- `blendModeChanged`
- `documentReloaded`
- `memoryPressure`

### DirtyRegion

建议支持：

- empty
- full layer
- rect list
- union rect

初期可以只实现 union rect，但接口应允许未来扩展。

## 任务包

### E2.1 Texture cache manager

- 新建 `LayerTextureCache`。
- 支持 lookup、create、remove、clear。
- 支持按 document 清理。
- 支持内存警告或窗口关闭时释放。

退出条件：

- 同一 layer 重复渲染不重复创建 texture。
- 文档关闭后 cache 清空。

### E2.2 Pixel revision

- 为 snapshot 中的 pixel layer 建立 revision。
- 像素内容变更时 revision 增加。
- 属性变更不误增 pixel revision。

退出条件：

- opacity/frame 变化不会触发像素重传。
- replace pixels 会触发 texture 重新上传。

### E2.3 Property invalidation

- visibility、opacity、blend mode、frame 只影响 render pass。
- pixel data 变更影响 texture。
- layer order 变更影响 command encoding 顺序。

退出条件：

- 每类变更都有明确 invalidation reason。
- 调试日志能说明为什么重绘。

### E2.4 Dirty region 基础

- 定义 dirty region 数据结构。
- 支持 full layer dirty。
- 支持 union rect dirty。
- 为 E4/E5 预留 stroke dirty region 输入。

退出条件：

- 当前阶段即使仍 full upload，也不影响接口表达局部 dirty。

### E2.5 Diagnostics

- 记录 texture count。
- 记录 upload count。
- 记录 last invalidation reason。
- 记录 total estimated texture memory。

退出条件：

- 调试面板或日志能看到 cache 行为。

## 测试建议

- `LayerTextureCacheTests`
- `PixelRevisionTests`
- `TextureInvalidationTests`
- `DirtyRegionTests`

对于无法在 CI 稳定创建 Metal device 的测试，尽量把 key、revision、dirty region、invalidation 逻辑做成纯 Swift 单元测试。

## 验收 gate

- 多次 redraw 不重复上传未变更 layer。
- 替换像素会更新 texture。
- frame/opacity/visibility 不误触发像素上传。
- layer order 保持 PSDKit 语义：index 0 = 栈底。
- E1 的 Metal preview 行为不回退。

## 主要风险

| 风险 | 表现 | 处理 |
|------|------|------|
| revision 来源不稳定 | 每次 snapshot 都被当作新 texture | revision 与 layer id / pixel mutation 绑定 |
| cache 持有过期 layer | 文档关闭后内存增长 | document close 清理 cache |
| 属性变更和像素变更混在一起 | 小操作导致全量上传 | invalidation reason 分层 |
| dirty region 过早复杂化 | rect list 合并逻辑拖慢进度 | 初期只做 union rect |

## 进入下一阶段条件

- E1 preview 通过 texture cache 渲染。
- cache 行为可测试、可诊断。
- 输入与绘制可以拿到稳定的 selected layer texture 目标。
