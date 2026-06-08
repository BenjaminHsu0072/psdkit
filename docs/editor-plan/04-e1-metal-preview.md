# E1 Metal 预览

## 阶段目标

把当前基于 `NSImage` 的合成预览迁移为 Metal 主预览路径。E1 只做只读预览，不引入绘制，不引入 texture readback，也不改变 PSD 写入逻辑。

## 当前状态

现有 Viewer 通过 `PreviewRenderer.makeImage(from:)` 调用 `PSDDocument.compositePreviewRGBA()`，生成 `NSImage` 后交给 SwiftUI `Image(nsImage:)` 显示。

这个路径适合验证 PSDKit 的 CPU 合成语义，但不适合作为 Editor 长期渲染路径：

- 图层更新需要重新生成整张 `NSImage`。
- 视图缩放、平移、overlay 与渲染管线割裂。
- 后续 brush preview 无法自然合入。
- Metal texture cache 无处承载。

## 范围

包含：

- 新建 Metal preview view。
- 从 `EditorRenderSnapshot` 上传只读 layer texture。
- 实现基础合成 pass。
- 默认预览路径覆盖当前已支持的 `normal` / `multiply` / `add` blend mode；未支持前不得替换默认预览路径。
- 支持 checkerboard 背景。
- 支持 viewport scale/offset 的最小模型。
- 保留 CPU preview 作为参考实现。

不包含：

- 不支持绘制。
- 不支持 undo。
- 不做 texture dirty region。
- 不做 PSDKit 支持范围之外的复杂 blend mode；当前已支持的 `normal` / `multiply` / `add` 属于 E1 默认预览的冻结范围。

## 设计草案

```text
ContentView / AppShell
    │
    ▼
EditorMetalPreviewHost
    │
    ▼
MetalPreviewController
    │
    ▼
MetalPreviewRenderer
    │
    ▼
MTKView
```

### EditorMetalPreviewHost

SwiftUI / AppKit 桥接层。职责是创建和更新 `MTKView`，把 snapshot 和 viewport state 传给 renderer。

不应包含：

- shader 逻辑。
- PSD layer 遍历逻辑。
- brush 状态。

### MetalPreviewRenderer

只读渲染器。接收 `EditorRenderSnapshot`，生成屏幕输出。

初始 pass：

1. 清空背景。
2. 绘制 checkerboard。
3. 按图层顺序绘制 visible pixel layer。
4. 绘制选中 layer frame overlay，或把 overlay 留给现有 SwiftUI 过渡层。

### Shader 最小集

初始可以只需要：

- fullscreen quad vertex。
- checkerboard fragment。
- textured layer fragment。
- normal alpha over。
- multiply。
- add。

`normal` / `multiply` / `add` 是当前 PSDKit 支持子集和手工验收矩阵的一部分。E1 如果暂时不能完成三者的 Metal 实现，默认预览路径必须保留 CPU reference fallback，且 fallback 分支需要测试覆盖；不能让默认 Viewer/Editor 预览退化为只支持 `normal`。

## 任务包

### E1.1 MTKView hosting

- 新建 `EditorMetalPreviewView`。
- 创建 `MTKView`。
- 建立 renderer delegate。
- 处理 drawable size 和 backing scale。

退出条件：

- 空文档状态下能显示稳定背景。
- window resize 不 crash。

### E1.2 Snapshot 接入

- 从 `DocumentModel` 或 adapter 生成 `EditorRenderSnapshot`。
- App Shell 把 snapshot 传入 preview host。
- Renderer 只消费 snapshot。

退出条件：

- Renderer 文件不引用 `DocumentModel`。
- snapshot 更新会触发 redraw。

### E1.3 RGBA texture 上传

- 把 `PixelBuffer.rgba` 上传为 Metal texture。
- 明确像素格式：RGBA/BGRA、premultiplied alpha、row bytes。
- 记录 pixelRevision，避免重复上传。

退出条件：

- 单图层文档能正确显示颜色和透明度。
- 透明区域能看到 checkerboard。

### E1.4 基础合成

- 按图层顺序绘制。
- 支持 `normal` / `multiply` / `add` blend。
- 支持 layer opacity。
- 支持 layer frame 偏移。

退出条件：

- 标准测试文档关键区域显示正确。
- 与 CPU reference 的关键像素一致；允许的每通道误差为 `0`。如果 Metal 浮点路径导致舍入差异，必须在测试中显式冻结误差上限，且每通道误差不得超过 `1`。

### E1.5 视图操作

- 支持适应窗口。
- 支持滚轮缩放。
- 支持平移。
- 冻结 viewport single source of truth：E1 默认选择 `EditorViewport` 作为缩放、平移、fit、overlay 和输入坐标的唯一真源。
- 迁移后不再让 SwiftUI `ScrollView` 持有独立滚动偏移；如过渡期必须保留 ScrollView，只能作为无状态容器，不能参与 canvas 坐标计算。
- 所有 overlay 读取同一个 `EditorViewport` 变换矩阵。

退出条件：

- 缩放和平移不改变 canvas 坐标语义。
- 选中 layer frame 显示位置正确。
- `EditorViewport` 的 fit、zoom、pan、view/canvas 互转已有单元测试。

## 测试建议

- `MetalPreviewSnapshotTests`：验证 snapshot 输入。
- `MetalLayerUploadTests`：如果可用 mock device，则测 texture descriptor；否则保留为 renderer helper 单测。
- `PreviewReferenceComparisonTests`：用 CPU `compositePreviewRGBA()` 做小尺寸关键像素 reference。
- `EditorViewportTests`：冻结 viewport single source of truth 的变换行为。

## 手工验收

- 新建标准文档。
- 打开已有 PSD。
- 切换图层 visibility。
- 修改 opacity。
- 移动 layer frame。
- 缩放、平移、适应窗口。
- 切换 `normal` / `multiply` / `add` blend mode，并确认默认预览路径不回退。
- 打开带兼容报告的文档，确认 Compatibility Report 入口仍可达。
- 对 lossy 文档执行 Save，确认 View Details / Cancel Save / Continue Save 三个分支仍可达。
- 保存并关闭，确认现有 dirty guard 不回退。

## 验收 gate

- Metal preview 能显示当前标准文档。
- 默认预览路径支持 `normal` / `multiply` / `add`，或对暂未支持模式有明确 CPU fallback 和测试。
- 与 CPU preview 的关键像素每通道误差为 `0`；若使用浮点 shader 导致舍入差异，冻结后的误差上限不得超过 `1`。
- `EditorViewport` 是唯一坐标真源；ScrollView 不持有独立 canvas 偏移。
- Renderer 不依赖 SwiftUI 或 `DocumentModel`。
- 现有 Viewer 打开、保存、关闭、兼容报告、lossy save confirmation 测试通过。

## 主要风险

| 风险 | 表现 | 处理 |
|------|------|------|
| RGBA/BGRA 搞错 | 红蓝通道交换 | 增加纯色小图测试 |
| alpha 语义不一致 | 边缘或半透明区域偏暗/偏亮 | 明确 premultiplied 策略，用 CPU reference 对比 |
| blend 支持退化 | 默认预览只显示 normal，multiply/add 与保存结果不一致 | E1 冻结 normal/multiply/add；未完成时保留 CPU fallback |
| SwiftUI overlay 坐标错位 | frame overlay 与 Metal 内容不对齐 | 尽早统一 viewport state |
| viewport 双状态 | ScrollView offset 与 Metal offset 同时生效 | E1 冻结 `EditorViewport` 为唯一真源 |

## 进入下一阶段条件

- Metal preview 是默认显示路径，且不回退当前 `normal` / `multiply` / `add` 预览能力；未覆盖模式必须走明确 fallback。
- CPU preview 仍可作为参考测试路径。
- `EditorViewport` owner 已冻结，并有单元测试。
- layer texture 生命周期问题已经暴露并记录，准备进入 E2。
