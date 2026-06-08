# E4 Metal 绘制管线

## 阶段目标

建立真正的 Metal brush pipeline：绘制中实时预览 stroke，抬笔后把 stroke commit 到目标图层 texture。E4 的结果仍可以只停留在 GPU texture 层，PSD 写回放到 E5。

## 核心原则

- brush stamp 在 Metal 中完成。
- active stroke 与 committed layer 分离。
- preview 与 commit 使用同一套 alpha / dab 算法。
- 不通过 CPU 修改 `PixelLayer.pixels` 来制造绘制效果。

## 参考来源

重点参考 MetalLinePOC：

- `BrushSettings`
- `BrushTipCache`
- `SharedMetalPointStorage`
- `SharedMetalLineConsumer`
- `MetalLineRenderer`
- `Metal/Shaders.metal`

需要适配：

- 单一 canvas texture → selected layer texture。
- 固定 canvas size → layer local texture size。
- POC present → document composite present。
- POC clear canvas → active stroke lifecycle。

## 渲染模型

```text
Pointer samples
    │
    ▼
Shared point buffer
    │
    ▼
dab expansion compute
    │
    ▼
active stroke texture
    │
    ├── preview: document composite + active stroke
    │
    └── commit: active stroke over target layer texture
```

## 关键 texture

### Target layer texture

来自 E2 的 layer texture cache。它代表当前图层在 GPU 上的 committed 像素状态。

### Active stroke texture

当前 stroke 的临时纹理。

特征：

- stroke begin 时清空。
- stroke update 时 stamp dab。
- present 时叠加显示。
- stroke end 时 commit 到 target layer texture。
- stroke cancel 时丢弃。

### Brush tip texture

由 brush size/hardness 生成的 mask texture。可以复用 MetalLinePOC 的 `BrushTipCache` 思路。

## 任务包

### E4.1 BrushSettings 定稿

- 从 E0 的 `BrushSettings` 扩展到 GPU uniforms。
- 字段：size、hardness、spacing、flow、opacity、color、sizePressure、minSize、flowPressure、minFlow。
- 明确默认值。
- 明确 UI 范围和 GPU clamp 范围。

退出条件：

- brush 默认值和 clamp 有测试。
- brush 参数可转换为 GPU uniform。

### E4.2 Point buffer

- 建立 stroke sample 到 Metal buffer 的写入路径。
- 支持最大点数上限。
- 支持 generation，避免旧 stroke 写入新 stroke。
- 支持 render queue 异步消费。

退出条件：

- 高频 sample 不阻塞主线程。
- stroke cancel 后旧点不会继续 stamp。

### E4.3 Dab expansion

- 参考 POC 的 `expandStrokeDabs`。
- 根据 pressure 计算 radius 和 alpha。
- 根据 spacing 沿 segment 生成 dab。
- 小 brush 时避免断线。

退出条件：

- 同一组 sample 能生成稳定 dab count。
- spacing / pressure 参数生效。

### E4.4 Active stroke stamp

- dab instance 绘制到 active stroke texture。
- 使用 brush tip mask。
- 使用 premultiplied alpha。
- 支持 color 和 flow。

退出条件：

- 单点、直线、慢速曲线可见。
- stroke texture 透明背景正确。

### E4.5 Preview composite

- present 时把 document layers 与 active stroke 合成。
- active stroke 只显示在 selected layer 的 frame 区域。
- selected layer opacity / blend 的预览策略要明确。

退出条件：

- 绘制中看到实时 stroke。
- preview 与 commit 后结果一致。

### E4.6 Commit to layer texture

- stroke end 时把 active stroke over 到 target layer texture。
- 清理 active stroke texture。
- 标记 target layer dirty region。
- 通知 EditorCore stroke 已完成。

退出条件：

- 抬笔后 stroke 留在目标图层 texture。
- cancel 不污染目标图层。
- dirty region 覆盖 stroke bounds。

## Blend 与 alpha 策略

初始建议：

- brush dab 输出 premultiplied color。
- active stroke texture 存 premultiplied alpha。
- commit 使用 src-over。
- layer opacity 在 document composite 阶段处理，不提前烘进 layer texture。

这样可以避免 layer opacity 被重复应用。

## 测试建议

- `BrushSettingsTests`
- `BrushUniformEncodingTests`
- `DabExpansionReferenceTests`
- `StrokeDirtyBoundsTests`

GPU shader 的像素测试如果 CI 不稳定，可以先用小尺寸离屏 texture 在本地/手工 gate 验证，再把纯逻辑留给自动化。

## 手工验收

- 鼠标画单点。
- 鼠标画慢速直线。
- 鼠标快速划线不断裂。
- 调整 size。
- 调整 opacity / flow。
- 切换颜色。
- cancel stroke 不产生图层变更。
- 缩放和平移后绘制落点正确。

## 验收 gate

- 绘制中实时显示。
- 抬笔后 commit 到目标 layer texture。
- preview 与 commit 使用同一 alpha 策略。
- Renderer 不直接写 PSD。
- 绘制目标只能是可编辑 pixel layer。

## 主要风险

| 风险 | 表现 | 处理 |
|------|------|------|
| preview 与 commit 不一致 | 抬笔后颜色/透明度跳变 | 共用 shader helper 和 alpha 约定 |
| 点消费落后 | 快速绘制延迟明显 | render queue 60Hz 消费，batch stamp |
| texture 坐标错位 | stroke 偏移到错误位置 | E3 layer local 坐标必须稳定 |
| dirty bounds 不准确 | 写回漏像素或过大 | stroke bounds 加 brush radius padding |

## 进入下一阶段条件

- GPU layer texture 已经包含绘制结果。
- Dirty region 可以描述本次 stroke 影响范围。
- EditorCore 能收到 stroke commit 事件。
- E5 可以基于 target layer texture 或 dirty patch 做 PSD 写回。
