# E3 输入与坐标

## 阶段目标

建立独立的输入采样和坐标系统，让鼠标、数位板、viewport、canvas 和 layer local 坐标都通过同一套模型表达。E3 不做绘制，但要为 E4 的 Metal brush pipeline 提供稳定输入。

E3 的前置条件是 E1 已冻结 viewport single source of truth：`EditorViewport` 是缩放、平移、fit、overlay 和输入坐标的唯一真源。E3 不重新选择 viewport owner，只扩展输入采样和坐标链。

## 当前状态

当前 Viewer 已有 `PreviewCoordinateMapper`，主要服务 frame move/resize：

- display translation → PSD delta
- frame resize handle → new frame

Editor 需要更完整的坐标链：

```text
window point
    │
    ▼
view point
    │
    ▼
canvas point
    │
    ▼
layer local point
```

还需要记录 pressure、time、device 等 stroke 信息。

## 范围

包含：

- 输入事件适配层。
- pointer sample 模型。
- stroke session 生命周期。
- viewport 模型。
- canvas/layer 坐标映射。
- 与 frame overlay 的坐标服务统一。

不包含：

- 不实现 brush stamp。
- 不写 PSD 像素。
- 不依赖 Metal pipeline 细节。

## 参考来源

优先参考：

- `/Users/mini/PROJECT/draw/metal-line-poc/Sources/StrokeSampling`
- `/Users/mini/PROJECT/draw/metal-line-poc/Sources/MetalLinePOC/MetalCaptureCanvasView.swift`

可借鉴能力：

- `PointerSample`
- `PointerDevice`
- `StrokeCaptureConfiguration`
- `MacStrokeCapture`
- `CapturePollSnapshot`
- mouse polling 与 tablet event 分离

需要改造：

- POC 固定 canvas size 改为 PSD canvas size。
- POC 内建 viewport 改为 Editor viewport state。
- POC stroke 结束只做 stats，Editor stroke 结束要提交 command。

## 核心类型

### EditorViewport

Owner：

- `EditorViewport` 由 EditorCore 持有，App Shell 只展示和转发输入。
- MetalBackend、overlay、InputCore 都只读取同一个 viewport snapshot。
- SwiftUI `ScrollView` 如仍存在，只能作为布局容器，不参与 canvas 坐标计算。

建议字段：

- `scale`
- `offset`
- `viewSize`
- `canvasSize`
- `backingScale`

能力：

- fit to view。
- zoom around anchor。
- pan by delta。
- view point to canvas point。
- canvas point to view point。

### PointerSample

建议字段：

- `locationInView`
- `locationInCanvas`
- `locationInLayer`
- `pressure`
- `time`
- `device`

layer local location 可以在 sample 生成时计算，也可以在 stroke commit 前批量计算。为了测试清晰，建议坐标转换逻辑保持纯函数。

### StrokeSession

建议状态：

- idle
- began
- active
- ended
- cancelled

建议数据：

- target layer id
- target layer frame
- brush snapshot
- samples
- dirty bounds

### StrokeInputAdapter

AppKit 事件到 InputCore sample 的桥。

职责：

- mouseDown / dragged / up。
- tabletPoint。
- scroll / magnify 可转给 viewport。
- capture active device。

不职责：

- 不 stamp。
- 不改 PSD。
- 不直接操作 texture。

## 任务包

### E3.1 Viewport 模型

- 接入 E1 已冻结的 `EditorViewport`。
- 补齐输入所需的 view/canvas/layer 映射。
- 保持 fit、zoom、pan 的单元测试。

退出条件：

- 纯单元测试覆盖缩放、平移、anchor zoom。
- 没有第二套 ScrollView offset 或 renderer-only viewport state。

### E3.2 Layer local 映射

- 实现 canvas point → layer local point。
- 支持 layer frame offset。
- 支持越界判断。
- 支持小数坐标保留，最后由 brush pipeline 决定取样方式。

退出条件：

- root layer、offset layer、nested layer 坐标测试通过。

### E3.3 Stroke session

- 定义 session 生命周期。
- 支持 begin/update/end/cancel。
- 记录 target layer 和 brush snapshot。
- 计算 dirty bounds。

退出条件：

- 无 UI 测试可以构造 stroke 并得到 bounds。

### E3.4 AppKit 输入桥

- 新建 NSView 或接入 Metal view 的事件处理。
- 转换 mouse/tablet 事件为 InputCore sample。
- 保留滚轮缩放、option pan 等交互约定。

退出条件：

- 手工能看到输入 diagnostics。
- 没有选中 pixel layer 时不会创建 drawable stroke session。

### E3.5 与现有 overlay 统一

- `SelectedLayerFrameOverlay` 的坐标逻辑逐步迁移到同一坐标服务。
- frame move/resize 和 draw 使用同一 viewport state。

退出条件：

- frame overlay 与 Metal preview 在缩放/平移下不偏移。

## 测试建议

- `EditorViewportTests`
- `LayerCoordinateMapperTests`
- `StrokeSessionTests`
- `StrokeInputAdapterTests`（可用事件 mock）

## 验收 gate

- 坐标映射全链路有单元测试。
- 缩放、平移、fit 后落点正确。
- 选中图层外输入被拒绝或裁剪。
- `EditorViewport` owner 与 E1 一致，不存在 UI 和 Metal 双 viewport。
- 输入层不 import Metal。
- 输入层不写 PSD 像素。

## 主要风险

| 风险 | 表现 | 处理 |
|------|------|------|
| 坐标系统分裂 | frame overlay 和 brush overlay 各算一套 | E3 强制统一 viewport 和 mapper |
| 小数坐标过早取整 | 低速绘制抖动或断裂 | 保留 CGFloat，stamp 阶段再处理 |
| 数位板逻辑污染绘制 | pressure 与 brush pipeline 互相耦合 | InputCore 只输出 sample，不决定 brush 算法 |
| ScrollView 与 Metal viewport 冲突 | 两套滚动状态 | E1 已冻结 `EditorViewport` 为唯一真源，E3 不再引入第二套状态 |

## 进入下一阶段条件

- E4 可以直接消费 `StrokeSession` 和 `PointerSample`。
- E1 viewport owner 已冻结且 `EditorViewportTests` 通过。
- MetalBackend 不需要知道 AppKit event。
- EditorCore 可以根据 selection 判断是否允许创建 stroke。
