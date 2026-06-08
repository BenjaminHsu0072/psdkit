# 阶段 P2：可用性与覆盖补全

## 目标

提升日常手工验收与演示效率：支持组级操作、顺序调整、增强像素替换与深树浏览。  
P2 **不阻塞**中期 sign-off（P1 完成且最终 Photoshop / M6 回归 gate 通过后即可宣布手工验收完成），但可在 P1 尾期并行部分任务。中期必测的 `blend`、`visibility`、`pixel` 保存往返已前移到 P1，P2 不再承载这些冻结项。

## 进入条件

- [P1 阶段](./02-p1-roundtrip-workflow.md) Gate 全部通过
- 或：明确记录「P2 某任务与 P1 并行」且不影响 P1 Gate 项

## 范围

### 包含

| # | 交付项 | 归属 |
|---|--------|------|
| 1 | 组 CRUD：新建组、删除空组/含子树确认删除 | [Viewer] |
| 2 | 组属性编辑：名称、opacity、blend mode（支持子集内） | [Viewer] |
| 3 | 同级 reorder：上移/下移或拖拽 | [Viewer] + 可选 [Library] |
| 4 | 增强像素替换：尺寸策略、错误提示、重复替换体验 | [Viewer] |
| 5 | 图层树折叠 / 展开 | [Viewer] |

### 不做范围

- 完整图像编辑器（画笔、图层蒙版编辑、调整层）
- 批量 Photoshop 对比、像素 diff 自动化
- 新 blend mode、新压缩格式
- 性能 benchmark 新一轮优化（沿用 M6 文档即可）
- 移动端 / Web Viewer

## 设计任务

1. 组 CRUD 与 PSD section divider 语义对齐：新建组默认 `openFolder`；删除组递归处理子节点。
2. 组属性编辑后合成预览是否包含组 opacity / blend：与库层合成语义一致（若组 blend 中期仅 passthrough，UI 应标注）。
3. Reorder 仅在同父 `children` 内调整 index；跨父移动仍用 P1 移动 UI。
4. 增强 Replace PNG：P1 已提供最小 pixel roundtrip 路径；P2 补尺寸策略、预览确认、错误提示与重复替换体验。
5. 折叠状态：仅 UI 状态，不写入 PSD。

## 实施任务

### [Library]（按需）

1. 若 reorder 需稳定 API：考虑 `moveLayer` 扩展或 `reorderLayer(at:in:to:)`；否则 Viewer 直接 `remove` + `insert`。
2. 组 blend / opacity 是否参与合成：若当前 `CompositeBuilder` 忽略组属性，在 P2 文档与 UI 中明确，或补库层合成（小 scope 时）。

### [Viewer]

1. 「Add Group」：在根或选中组下创建 `GroupLayer`。
2. 「Delete Group」：确认对话框，调用 `removeLayer` 递归移除。
3. 组 Inspector：可编辑 name、opacity、blend（下拉限定 `normal` / `multiply` / `add`）。
4. 列表或 Inspector：Move Up / Move Down；或拖拽排序（同父）。
5. 增强「Replace from PNG…」：补充尺寸不匹配处理、替换前预览或确认、失败提示；不得改变 P1 已验收的最小路径语义。
6. 组行 disclosure：折叠隐藏子孙；记住展开状态（会话级）。

### [Test]

1. Viewer policy：组编辑、reorder 边界。
2. 库层 reorder 往返测试（若新增 API）。

## 验收步骤

1. 在根下新建组，拖入两层，Save，Reopen，组与子层完整。
2. 删除空组与含子层组（含确认），Save，Reopen，树正确。
3. 修改组 opacity / blend，预览变化符合预期（或 UI 标明不支持并禁用）。
4. 同父两层 reorder 后 Save，Reopen，顺序与 `index 0 = 栈底` 一致。
5. 对像素层执行增强 Replace PNG，覆盖尺寸策略或确认分支；Save，Reopen，像素一致。
6. 深嵌套文档（标准文档即可）折叠组后列表可读，展开恢复。
7. [04-acceptance-checklists.md](./04-acceptance-checklists.md) P2 节全部勾选。

## 测试命令

```bash
swift build && swift test
cd Apps/PSDViewer && swift test
```

## 阶段独立验收标准（Gate）

- [ ] 组 CRUD 保存往返
- [ ] 组属性编辑（在承诺范围内）保存往返
- [ ] 同级 reorder 保存往返
- [ ] 增强 Replace PNG 的尺寸策略 / 确认分支保存往返
- [ ] 折叠 / 展开不影响保存结果
- [ ] `swift test` 全绿

## 测试建议

- `LayerTreeTests.testReorderSiblings`（若新增）
- `PersistenceRoundTripTests.testGroupOpacityRoundTrip`（若支持）
- `PSDViewerTests.testGroupCRUDPolicy`

## 风险

| 风险 | 缓解 |
|------|------|
| 组 blend 合成语义与 PS 不一致 | 文档标注；优先对齐 `CompositeBuilder` |
| 删除组误操作 | 强确认 + 不可撤销提示 |
| Reorder 与 section divider 写回顺序 | 依赖既有 M3 写路径 + roundtrip 测试 |
| P2 scope 膨胀 | 严格不做范围；与完整编辑器划界 |
