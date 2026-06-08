# 阶段 P1：Roundtrip 工作流

## 目标

在 P0 基础上，使验收者能完成 [中期 roundtrip 编辑矩阵](../midterm-plan/05-roundtrip-persistence.md) 对应的 **手工操作路径**：结构编辑、frame 调整、blend mode、visibility、pixel 替换、多轮保存对比，并配合嵌入式 checklist 与 Photoshop roundtrip 助手统一手工步骤。

P1 完成后，具备执行中期 **Photoshop 手工验收最终 gate** 的条件（在支持子集范围内）。P1 Gate 必须覆盖 `blend`、`visibility`、`pixel` 三项手工保存往返，不得后置到 P2；最终签署还需完成 Photoshop 证据归档与 M6 benchmark 回归锚点。

## 进入条件

- [P0 阶段](./01-p0-unblock-manual-validation.md) Gate 全部通过
- P0 公开 API 已合并 `main`

## 范围

### 包含

| # | 交付项 | 归属 |
|---|--------|------|
| 1 | 组内新增像素层、删除图层、跨组移动 | [Viewer] + 可选 [Library] |
| 2 | 像素层 frame 数值编辑（left/top/width/height 或 LTRB） | [Viewer] |
| 3 | 像素层 blend mode 编辑（`normal` / `multiply` / `add`） | [Viewer] |
| 4 | 嵌套与根级像素层 visibility 编辑 | [Viewer] |
| 5 | 最小像素替换路径：对选中像素层 `Replace from PNG…` | [Viewer] |
| 6 | 公开或 Viewer 内嵌 snapshot / diff 对比 | [Library] + [Viewer] |
| 7 | 手工验收 checklist 面板（可勾选、可重置） | [Viewer] |
| 8 | Photoshop roundtrip 助手（步骤引导、建议导出路径） | [Viewer] |
| 9 | 可选 `moveLayer(_:to:at:)` 便捷 API | [Library]（可选） |

### 不做范围

- 组 CRUD（新建空组、删除组）→ P2（P1 可在已有组内操作）
- 组属性编辑（组 opacity / blend）→ P2
- 同级 reorder 拖拽 → P2
- 高级像素编辑（画笔、选区、滤镜、历史记录栈）→ 不做；P1 仅要求最小 PNG 替换以覆盖像素持久化
- Photoshop 脚本自动化
- 扩展 M6 benchmark 或新性能场景；最终签署只复用既有 M6 benchmark 做回归锚点

## 设计任务

1. 定义 Viewer 结构编辑交互：选中层 → 目标组选择器 / 拖放；删除需确认。
2. 定义 frame 编辑校验：不超出画布合理范围；修改后刷新预览与 Inspector。
3. 定义 blend / visibility 编辑交互：支持三种中期 blend mode；切换可见性后立即刷新预览并标记 dirty。
4. 定义最小 pixel 替换：选中像素层导入 PNG，替换 `pixels`；可保持原 frame，若 PNG 尺寸不同则必须明确选择「保持 frame 裁剪 / 匹配 PNG 尺寸」之一。
5. 决定是否公开 `DocumentSnapshot`：
   - **方案 A**：公开 `PSDDocumentSnapshot.capture(from:)` + `diff(from:)`，测试与 Viewer 共用。
   - **方案 B**：Viewer 内嵌简化 diff（树路径 + 属性字符串），仅验收用。
   - 实施前在 PR 描述中冻结所选方案。
6. Checklist 内容来源：[04-acceptance-checklists.md](./04-acceptance-checklists.md) P1 + Photoshop 节。
7. Roundtrip 助手：固定流程「PSDKit 导出 → PS 打开检查 → PS 另存 → PSDKit 再打开」，每步可勾选。

## 实施任务

### [Library]（可选但推荐）

1. 新增 `moveLayer(_ layer: any LayerProtocol, to parent: GroupLayer, at index: Int)`，封装 remove + insert 并保持 `markContentModified()`。
2. 若选方案 A：将 `DocumentSnapshot` 移至 `Sources/PSDKit` 公开模块（或 `PSDKitTesting` 产品），提供 `capture` 与 `diffDescription`。
3. 结构移动、frame 变更的往返测试（可复用 `PersistenceRoundTripTests` 模式）。

### [Viewer]

1. 工具栏 / 上下文菜单：「Add Layer to Group…」「Move to Group…」「Delete Layer」— 调用 `appendLayer` / `insertLayer` / `removeLayer`（或 `moveLayer`）。
2. Inspector frame 区：可编辑数字字段 + 应用按钮；修改后 `markContentModified()` 并刷新预览。
3. Inspector 属性区：像素层可编辑 blend mode；根级与嵌套像素层 visibility 切换后立即预览、标记 dirty。
4. 「Replace from PNG…」：替换选中像素层像素数据，用于 P1 pixel roundtrip；高级像素编辑留到后续。
5. 「Snapshot」面板：保存当前快照标签（如 "Before edit" / "After save"），显示与当前文档的树/属性/pixel hash diff。
6. 「Manual Validation」侧边栏或 sheet：展示 P1 checklist，状态持久化到 `UserDefaults`（仅本机）。
7. 「Photoshop Roundtrip」助手：分步说明 +「Reveal in Finder」导出文件 + 建议文件名 `midterm-roundtrip.psd`。
8. 跨组移动后自动选中在新位置的层；删除后选中相邻层。

### [Test]

1. `PersistenceRoundTripTests` 已有用例保持全绿；新增 Viewer policy 测试覆盖结构编辑、blend、visibility、pixel 替换启用条件。
2. 若公开 snapshot：新增公开 API 稳定性测试。

## 验收步骤

1. 从标准文档开始，在 `Group A` 内新增像素层，Save，Reopen，层存在且 parent 正确。
2. 将 `Glow` 从 `Group B` 移动到 `Group A` 根下（或另一组），Save，Reopen，树结构一致。
3. 删除某像素层，Save，Reopen，层已消失。
4. 修改 `Red` 的 frame（如右移 4px），预览更新，Save，Reopen，bounds 一致。
5. 修改 `Red` 的 blend mode（如 `multiply` → `normal` → `multiply`），Save，Reopen，blend 一致。
6. 切换 `Top` 或任一嵌套像素层 visibility，Save，Reopen，可见性一致。
7. 对选中像素层执行最小 `Replace from PNG…`，Save，Reopen，像素 hash 一致。
8. 执行至少 3 轮「编辑 → Save → Reopen」，用 Snapshot 面板确认仅预期字段变化。
9. 按 Roundtrip 助手完成 Photoshop 流程：
   - PSDKit 导出
   - Photoshop 检查图层树、blend、可见性
   - Photoshop 另存
   - PSDKit 再打开，兼容报告可接受，支持子集内可编辑
10. P1 checklist 全部可勾选并对应实际操作。

## 测试命令

```bash
swift build && swift test
cd Apps/PSDViewer && swift test
```

## 阶段独立验收标准（Gate）

- [ ] 组内增删、跨组移动可手工完成且保存往返
- [ ] frame 编辑保存往返
- [ ] blend mode 编辑保存往返
- [ ] visibility 编辑保存往返
- [ ] pixel 替换保存往返
- [ ] Snapshot / diff 可辨认编辑前后差异
- [ ] Checklist 与 PS 助手可引导完整手工流程
- [ ] 已导出供 Photoshop 最终 gate 使用的 P1 roundtrip PSD，并记录建议检查点：结构、混合模式、可见性、替换像素
- [ ] `swift test` 全绿

## 测试建议

- `PersistenceRoundTripTests.testMoveLayerBetweenGroups`（库层，应已存在）
- `PersistenceRoundTripTests.testThreeEditSaveCycles`
- `PersistenceRoundTripTests.testBlendVisibilityAndPixelEditPersist`
- `LayerTreeTests.testMoveLayerConvenienceAPI`（若新增 moveLayer）
- `PSDViewerTests.testStructureEditPolicy`
- `PSDViewerTests.testP1EditMatrixPolicy`

## 风险

| 风险 | 缓解 |
|------|------|
| 结构编辑 UI 误删组 | 删除组放 P2；P1 仅删像素层或移出层 |
| Snapshot 公开 API 泄露测试细节 | diff 输出面向人类可读，不暴露内部 hash 实现细节 |
| Photoshop 另存后结构变化 | 助手中说明「仅验证支持子集」；兼容报告查看降级 |
| frame 编辑导致像素与 bounds 不一致 | 仅改 frame 不重采样；与库语义一致 |
| 最小 pixel 替换膨胀为图像编辑器 | P1 只支持 PNG 替换以覆盖像素持久化，不加入画笔 / 选区 / 滤镜 |
