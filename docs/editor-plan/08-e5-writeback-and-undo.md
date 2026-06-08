# E5 PSD 写回与 undo

## 阶段目标

把 E4 中已经提交到 GPU layer texture 的编辑结果写回 PSDKit 文档模型，并纳入 dirty、save、close guard 和 undo/redo。E5 是 Editor 从实时渲染工具变成可持久化编辑器的关键阶段。

## 核心原则

- GPU texture 是编辑工作态，不是最终持久态。
- PSDKit 文档是保存前的权威文档态。
- 所有持久变更必须通过 Editor command。
- 保存前必须 flush GPU dirty 内容。
- `save`、`close`、`undo`、`redo` 在 GPU dirty / flush 状态下必须有确定行为，不能依赖时序碰巧完成。

## 数据流

```text
Metal stroke commit
    │
    ▼
Layer dirty region
    │
    ▼
Texture readback / pixel patch
    │
    ▼
EditorCommand
    │
    ▼
PSDKit PixelLayer.pixels
    │
    ▼
document.markContentModified()
```

## 写回状态机

E5 必须冻结最小状态机，作为实现和测试共同依据。

### 状态

| 状态 | 含义 |
|------|------|
| `idleClean` | 没有未保存文档变更，也没有 GPU dirty 内容 |
| `idleDirty` | PSDKit 文档已有未保存变更，但没有 pending GPU flush |
| `strokeActive` | 当前有 active stroke，尚未 commit 到 target layer texture |
| `pendingFlush` | GPU layer texture 已变更，但 patch/readback 尚未同步到 PSDKit 文档 |
| `flushing` | 正在执行 readback / patch apply |
| `flushFailed` | flush 失败，PSDKit 文档不是最新编辑结果，保存必须被阻止 |

### 状态迁移

| 事件 | 前置状态 | 后置状态 | 规则 |
|------|----------|----------|------|
| begin stroke | `idleClean` / `idleDirty` | `strokeActive` | 记录 target layer、brush snapshot、起始 revision |
| cancel stroke | `strokeActive` | 原 idle 状态 | 丢弃 active stroke texture，不产生 command |
| end stroke commit | `strokeActive` | `pendingFlush` | active stroke 合入 target layer texture，记录 dirty region |
| start flush | `pendingFlush` | `flushing` | drain render queue 后 readback |
| flush success | `flushing` | `idleDirty` | apply patch，生成 undo entry，`markContentModified()` |
| flush failure | `flushing` | `flushFailed` | 保留错误和 dirty texture，禁止保存 |
| retry flush success | `flushFailed` | `idleDirty` | 清除错误，恢复可保存 |
| save success | `idleDirty` | `idleClean` | 保存 PSDKit 文档后清 dirty |

### 操作规则

| 操作 | `strokeActive` | `pendingFlush` | `flushing` | `flushFailed` |
|------|----------------|----------------|------------|---------------|
| save | 先 end/cancel 当前 stroke，或拒绝并提示 | 同步等待 flush；成功后保存 | 等待 flush；成功后保存 | 拒绝保存，提示重试或取消 |
| close | 弹出 unsaved guard，不能静默丢弃 active/pending 内容 | 弹出 unsaved guard，关闭前需 flush 或确认丢弃 | 等待或取消关闭 | 弹出错误，不能直接保存关闭 |
| undo | 当前 stroke 未结束时禁用或先 cancel | 先 flush，再 undo | 等待 flush 后 undo | 禁用，直到 retry/cancel dirty texture |
| redo | 当前 stroke 未结束时禁用 | 先 flush，再 redo | 等待 flush 后 redo | 禁用 |

这些规则必须成为集成测试，而不是仅作为 UI 文案约定。

## 写回策略

### 方案 A：Dirty region readback

只读取 stroke dirty bounds 对应区域。

优点：

- 性能较好。
- 与后续大画布编辑更匹配。

缺点：

- row alignment、区域合并、边界 padding 更复杂。
- patch 应用逻辑需要更谨慎。

### 方案 B：Full layer readback

每次 stroke commit 后读取整个 layer texture。

优点：

- 实现简单。
- 更容易验证正确性。

缺点：

- 大图层性能差。
- 与长期架构不完全匹配。

建议：

- 接口按 dirty region 设计。
- 初始实现可以允许 full layer fallback。
- 从第一版开始记录 readback 区域和耗时，避免 fallback 被误认为最终方案。

## 核心类型

### LayerPixelPatch

建议字段：

- `layerID`
- `rect`
- `rgba`
- `rowBytes`
- `pixelFormat`
- `sourceRevision`
- `resultRevision`

### PixelPatchApplier

职责：

- 验证 patch rect 是否在 layer bounds 内。
- 把 patch 写入 `PixelBuffer.rgba`。
- 增加 pixel revision。
- 返回 undo 所需的 before patch。

### EditorUndoEntry

建议字段：

- command id
- label
- forward patch
- inverse patch
- affected layer ids
- timestamp

## 任务包

### E5.1 写回接口

- 定义 `LayerPixelPatch`。
- 定义 texture readback service。
- 定义 patch applier。
- 明确 RGBA / premultiplied 转换策略。

退出条件：

- 小尺寸 patch 可以写入 `PixelBuffer.rgba`。
- patch 越界会失败，不会静默截断。

### E5.2 Stroke commit command

- E4 stroke end 生成 `CommitStrokeCommand`。
- command 持有 patch 或 patch provider。
- command apply 后更新 PSDKit。
- command 成功后触发 dirty。

退出条件：

- 绘制后 `document.hasUnsavedChanges == true`。
- status message 能说明提交成功。

### E5.3 保存前 flush

- 保存命令前检查 GPU dirty queue。
- 未 flush 的 layer 先 readback。
- flush 失败则阻止保存并显示错误。
- 保存路径必须覆盖 `pendingFlush`、`flushing`、`flushFailed` 三种状态。

退出条件：

- 快速绘制后立即保存不会丢 stroke。
- 保存失败不会清 dirty。
- `pendingFlush -> save -> flush success -> save success` 有集成测试。
- `pendingFlush -> save -> flush failure -> save blocked` 有集成测试。

### E5.4 Undo/redo 栈

- 实现命令 history。
- 支持 undo stroke。
- 支持 redo stroke。
- 更新 texture cache 与 PSDKit 文档。
- undo/redo 前必须确保没有 pending GPU dirty；若存在，按状态机先 flush 或禁用。

退出条件：

- undo 后 preview 和 PSD pixel buffer 一致。
- redo 后 preview 和 PSD pixel buffer 一致。
- `pendingFlush -> undo` 和 `flushFailed -> undo` 行为有测试。

### E5.5 与现有 Viewer 行为整合

- close guard 继续使用 dirty 状态。
- lossy save confirmation 不回退。
- snapshot/diff 可以识别 pixel edit。
- manual validation workflow 更新 Editor 步骤。

退出条件：

- 现有 DocumentModel compatibility tests 通过。
- 新增 Editor pixel edit tests 通过。

## 测试建议

- `LayerPixelPatchTests`
- `PixelPatchApplierTests`
- `CommitStrokeCommandTests`
- `EditorUndoRedoTests`
- `SaveFlushTests`
- `EditorWritebackStateMachineTests`

## 手工验收

- 绘制一笔，保存，重新打开。
- 绘制多笔，undo，redo，保存。
- 绘制后关闭，确认 dirty close guard 弹出。
- 绘制后 Save As，重新打开导出文件。
- Photoshop 打开保存后的 PSD，确认 stroke 存在。

## 验收 gate

- GPU 编辑结果能写回 PSDKit。
- 保存后 reopen 能看到绘制结果。
- undo/redo 至少覆盖 stroke。
- dirty/save/close guard 正确。
- `pendingFlush`、`flushing`、`flushFailed` 下的 save/close/undo/redo 行为可机判并有集成测试。
- readback 区域和耗时可诊断。

## 主要风险

| 风险 | 表现 | 处理 |
|------|------|------|
| readback 阻塞 UI | 抬笔后卡顿 | 放入后台队列，保存前强制 flush |
| premultiplied 转换错误 | 保存后颜色变暗或透明异常 | 明确 PSDKit 期望 RGBA 语义并加像素测试 |
| undo 只改文档不改 texture | preview 与保存结果不一致 | undo/redo 同时更新 PSDKit 和 texture cache |
| 保存 race | stroke 还在 GPU commit，保存已开始 | save 前等待 render queue drain |
| flush 状态不可判 | 快速保存/撤销/关闭时行为依赖异步完成顺序 | 冻结写回状态机并做集成测试 |

## 进入下一阶段条件

- 真实 PSD roundtrip 通过。
- Photoshop 能看到绘制结果。
- undo/redo 不破坏 texture cache。
- E6 可以专注验收、性能和诊断，不再补核心语义。
