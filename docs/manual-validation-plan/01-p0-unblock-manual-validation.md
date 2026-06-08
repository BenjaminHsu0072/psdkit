# 阶段 P0：解除手工验收阻塞

## 目标

让验收者在 **不编写代码** 的前提下，用 PSDViewer 完成中期标准 PSD 的生成、全树预览、兼容报告核对、文件级硬拒绝验证、有损保存确认、嵌套像素层编辑与保存状态感知。  
P0 完成后，可进行有意义的 Photoshop 打开验证（视觉与结构），但完整 roundtrip 编辑流仍依赖 P1。

## 进入条件

- [中期计划](../midterm-plan/README.md) M1–M6 库层能力已合并 `main`
- `swift test` 全绿
- 已阅读 [00-current-state.md](./00-current-state.md)

## 范围

### 包含

| # | 交付项 | 归属 |
|---|--------|------|
| 1 | 递归全树 `compositePreviewRGBA()`（含组内层、三种 blend） | [Library] |
| 2 | 公开标准文档生成 API + Viewer「生成标准测试文档」 | [Library] + [Viewer] |
| 3 | 公开文档 dirty 状态 + Viewer 未保存指示 | [Library] + [Viewer] |
| 4 | 兼容报告详情面板 | [Viewer] |
| 5 | 文件级硬拒绝 smoke pack：16-bit、CMYK、Zip/ZipPrediction | [Viewer] + [Test] |
| 6 | `hasLossyChanges` 保存前确认：继续保存 / 取消保存 / 跳转详情 | [Viewer] |
| 7 | 嵌套像素层 Inspector 编辑（名称、opacity、可见性、blend 只读或可选可编） | [Viewer] |
| 8 | 保存路径 / 文件名 / 状态栏增强 | [Viewer] |

### 不做范围

- 结构编辑（组内增删、跨组移动）→ P1
- frame 数值编辑 → P1
- 快照/差异面板 → P1
- 组 CRUD、组属性编辑、reorder → P2
- Photoshop 自动化、新 benchmark 场景
- 画笔级像素编辑、完整图像编辑器

## 设计任务

1. 定义递归合成语义：与 `CompositeBuilder` / 语义写路径一致，组内层按栈序合成，尊重 `isVisible`、`opacity`、`blendMode`。
2. 冻结公开标准文档 API 名称与画布规格（建议与 `MidtermStandardDocument` 树结构一致，画布可保持 16×16 或提供 `size` 参数）。
3. 冻结 `hasUnsavedChanges`（或公开 `isContentDirty`）只读语义：保存成功后清零；任何 Viewer 触发的编辑置位。
4. 设计兼容报告详情 UI：按 `severity` 分组或着色，展示 `kind`、`layerName`、`message`。
5. 设计硬拒绝打开流程：16/32-bit、CMYK/Lab/Indexed、Zip/ZipPrediction 必须打开失败，错误文案明确，不创建文档会话，不展示兼容报告。
6. 设计有损保存确认：当 `document.compatibilityReport.hasLossyChanges == true` 且文档被编辑后点击 Save，必须弹出确认框；确认框提供「继续保存」「取消保存」「查看详情」。
7. 扩展 `LayerViewerPolicy`：嵌套像素层至少支持名称、opacity、可见性编辑；blend 可保持只读直至 P1 必测路径实现。

## 实施任务

### [Library]

1. 将 `compositePreviewRGBA()` 改为递归遍历 `GroupLayer`，收集可见像素层并合成（或新增 `compositePreviewRGBAIncludingGroups()` 后废弃旧语义——实施时二选一并在 API 文档说明）。
2. 新增 `PSDDocument.makeMidtermStandardDocument(canvasSize:)`（名称可微调，但必须覆盖 BG / Group A / Group B / Red / Glow / Top 结构）。
3. 公开 `var hasUnsavedChanges: Bool { get }`（或公开 `isContentDirty`），保存成功后重置。
4. 为递归合成添加单元测试：标准文档预览非空、隐藏 `Top` 层时合成结果变化、组内 `multiply`/`add` 影响输出。
5. 标准文档公开 API 测试：生成 → 保存 → 再打开 snapshot 与 `MidtermStandardDocument` 一致。

### [Viewer]

1. 菜单或工具栏：「File → Generate Standard Test Document…」生成并打开标准文档（未保存状态）。
2. 预览 pane 使用更新后的合成 API；可选显示「全树合成」标签。
3. 未保存指示：窗口标题 `*` 或副标题「Edited」；关闭窗口时若有 dirty 则确认对话框。
4. 状态栏：显示完整路径（或「Untitled」）、图层数、dirty 状态。
5. 侧栏或 sheet：「Compatibility Report…」列表展示全部 `issues`；无 issue 时显示「支持子集内，无警告」。
6. 打开硬拒绝 fixture 时使用明确错误页或 alert：显示失败原因，当前文档保持不变；若此前无文档，则保持空状态；不得展示兼容性报告。
7. 保存有损打开会话前弹出确认框：取消分支不写文件且保持 dirty；继续保存分支写出并记录状态；查看详情打开兼容报告面板。
8. 扩展 `LayerInspectorView` / `DocumentModel`：嵌套像素层可编辑名称、opacity；列表可见性按钮支持嵌套像素层（与根级一致）。
9. 保存成功时清除 dirty 并更新状态栏。

### [Test]

1. `CompositeBuilderTests` / 新测试：嵌套合成与 blend。
2. `PSDViewerTests`：嵌套编辑 policy、`hasUnsavedChanges` 绑定、硬拒绝打开状态、有损保存确认分支（如可测）。
3. 不新增 Photoshop 自动化。

## 验收步骤

1. 启动 Viewer：`cd Apps/PSDViewer && swift run PSDViewer`。
2. 使用「生成标准测试文档」，确认图层树为 BG → Group A（Red, Group B → Glow）→ Top（隐藏）。
3. 预览区显示含组内红层与 Glow 的合成结果；切换 Glow 可见性或 Red opacity 后预览更新。
4. 选中 `Red`（组内），修改名称与 opacity，Save，重新 Open，属性保持。
5. 打开含 warning 的外部 PSD（如含蒙版或 layer style 的 fixture），摘要横幅与详情面板均能看到 issue。
6. 对该有损 PSD 修改任意属性后点击 Save：必须弹出有损确认；选择取消时文件不保存且 dirty 保留；再次 Save 并选择继续时可保存；选择查看详情时能定位到兼容报告详情。
7. 依次打开 16-bit、CMYK、Zip/ZipPrediction fixture：均打开失败，错误文案明确，不创建文档会话，不展示兼容报告。
8. 编辑后窗口显示未保存状态；Save 后清除；未保存关闭时弹出确认。
9. 导出 PSD，用 Photoshop 手工打开：图层树与混合模式显示正确（允许只做目视，不要求 P0 完成全部 roundtrip 编辑）。

## 测试命令

```bash
swift build && swift test
cd Apps/PSDViewer && swift test
```

## 阶段独立验收标准（Gate）

全部满足方可进入 P1：

- [ ] 公开 API 可生成与测试 helper 等价的标准文档
- [ ] 预览包含嵌套组内图层且 blend 生效
- [ ] 嵌套像素层可在 Viewer 编辑并保存往返
- [ ] 兼容报告可查看完整 issue 列表
- [ ] 有损 PSD 保存前必须提示，并覆盖继续保存 / 取消保存 / 查看详情分支
- [ ] 文件级硬拒绝样本打开失败，且不创建文档会话、不展示兼容报告
- [ ] dirty / 路径 / 未保存提示行为符合设计
- [ ] 上述 `swift test` 通过

## 测试建议

- `CompositePreviewTests.testNestedGroupCompositeIncludesChildLayers`
- `CompositePreviewTests.testHiddenLayerExcludedFromPreview`
- `StandardDocumentTests.testPublicAPIMatchesMidtermHelper`
- `DocumentDirtyTests.testSaveClearsUnsavedChanges`
- `CompatibilityReportTests.testHardRejectDoesNotCreateReport`
- `PSDViewerTests.testNestedPixelLayerEditPolicy`
- `PSDViewerTests.testLossySaveRequiresConfirmation`
- `PSDViewerTests.testHardRejectLeavesCurrentDocumentUnchanged`

## 风险

| 风险 | 缓解 |
|------|------|
| 递归合成与写回复合图不一致 | 共用 `CompositeBuilder` 核心；对比标准文档像素 hash |
| 公开 API 与 internal helper 重复 | 实现委托同一 factory |
| 硬拒绝被误当成 warning | smoke pack 覆盖 16-bit、CMYK、Zip，断言无兼容报告 |
| 有损确认打断正常无损保存 | 仅在 `hasLossyChanges == true` 且用户触发保存时弹出；支持子集内 PSD 不弹 |
| 嵌套编辑后 passthrough 误保存 | Viewer 统一 `markContentModified()`；保存走 semantic |
| 详情面板信息过载 | 默认折叠 message，按 severity 排序 |
