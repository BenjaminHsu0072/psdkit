# PSDKit 手工验收补全计划

> 目标：在 [中期自动化目标](../midterm-plan/README.md) 已完成的前提下，把 **PSDViewer** 补全为可支撑 Photoshop / 手工验收的工作台。  
> 边界：不引入 Photoshop 自动化、不扩展重 benchmark 场景、不把 Viewer 做成完整图像编辑器；最终签署前需复用既有 M6 benchmark 做回归锚点。

## 背景

中期计划在库层（`Sources/PSDKit`）已建立：

- 支持子集读写、兼容性报告、嵌套组、三种混合模式
- `.psd` 持久化往返测试矩阵与性能 baseline

但当前 **PSDViewer** 仍是基础查看器：能打开/新建/保存/导入 PNG、展示嵌套图层树、编辑根级像素层，不足以系统化完成 Photoshop 手工验证与 roundtrip 工作流，也缺少硬拒绝路径、有损保存提醒和最终性能回归锚点。本计划补齐 Viewer 与少量公开 API，使每阶段可**独立验收**。

## 总览

| 文档 | 说明 |
|------|------|
| [00-current-state.md](./00-current-state.md) | 当前 Viewer 能力与缺口盘点 |
| [01-p0-unblock-manual-validation.md](./01-p0-unblock-manual-validation.md) | **P0**：打通手工验收阻塞项 |
| [02-p1-roundtrip-workflow.md](./02-p1-roundtrip-workflow.md) | **P1**：结构编辑与 roundtrip 工作流 |
| [03-p2-usability-and-coverage.md](./03-p2-usability-and-coverage.md) | **P2**：可用性与覆盖补全 |
| [04-acceptance-checklists.md](./04-acceptance-checklists.md) | 各阶段独立验收 checklist + Photoshop 手工清单 |

## 阶段与优先级

| 阶段 | 优先级 | 依赖 | 一句话目标 |
|------|--------|------|------------|
| P0 | 必须 | 中期计划 M1–M6 已完成 | 能生成标准文档、预览全树合成、看清兼容报告、拦截硬拒绝文件、提醒有损保存、编辑嵌套像素层、感知保存状态 |
| P1 | 高 | P0 验收通过 | 能完成结构编辑、frame、blend、visibility、pixel 的手工 roundtrip，提供快照对比与 Photoshop 助手工作流 |
| P2 | 中 | P1 验收通过（部分任务可与 P1 尾期并行） | 组 CRUD、组属性、reorder、增强像素替换、图层树折叠 |

```text
中期库层 (已完成)
        │
        ▼
   P0 解除阻塞 ──验收──► P1 roundtrip 工作流 ──验收──► P2 可用性补全
```

**P0 是手工验收的前置 gate**：未完成 P0 时，不应把「中期 Photoshop 验收」记为通过。  
**P1 是中期手工 sign-off 的功能 gate**：必须覆盖 M5 编辑矩阵中的 `blend`、`visibility`、`pixel` 手工保存往返。P2 可分批交付，但不得承载中期 sign-off 的必测项；每批必须满足该文档中的进入条件与验收步骤后方可合并。

## 工作分层

| 层级 | 路径 | 本计划职责 |
|------|------|------------|
| **库 API** | `Sources/PSDKit` | 递归全树合成预览、公开标准文档生成、公开 dirty 状态、可选 snapshot/diff、可选 `moveLayer` |
| **Viewer UI** | `Apps/PSDViewer` | 菜单/面板/交互，把库能力暴露给手工验收者 |
| **测试** | `Tests/PSDKitTests`、`Apps/PSDViewer/Tests` | 自动化断言；Photoshop 步骤保留为人工 gate |

实施时应在各阶段文档的「实施任务」中标注 `[Library]` / `[Viewer]` / `[Test]`。

## 验收策略

1. **分阶段 gate**：每阶段有独立 checklist（见 [04-acceptance-checklists.md](./04-acceptance-checklists.md)），全部勾选方可进入下一阶段。
2. **自动化优先**：库 API 与 Viewer 逻辑改动必须有 `swift test` 覆盖；Photoshop 步骤不自动化。
3. **标准文档锚点**：验收 PSD 优先使用与 `MidtermStandardDocument` 等价的公开生成入口，避免手工拼 fixture。
4. **最终签署闭环**：P1 + Photoshop gate 通过后，仍需复用既有 M6 benchmark 命令确认未越过回归阈值。
5. **不做范围显式排除**：各阶段文档列出「不做范围」，防止 scope creep。

## 建议执行顺序

| 顺序 | 工作包 | 说明 |
|------|--------|------|
| 1 | P0 库 API（合成、标准文档、dirty） | 解除 Viewer 与测试对内部 helper 的依赖 |
| 2 | P0 Viewer（预览、报告详情、硬拒绝、有损保存提醒、嵌套编辑、保存反馈） | 使验收者可端到端操作 |
| 3 | P0 验收 | 跑通 [04](./04-acceptance-checklists.md) P0 checklist |
| 4 | P1 库 API（snapshot/diff、moveLayer） | 支撑结构编辑与对比 |
| 5 | P1 Viewer（结构编辑、frame、blend、visibility、pixel、快照面板、PS 助手） | 完成 M5 手工 roundtrip 工作流 |
| 6 | P1 验收 | Photoshop roundtrip 手工 gate |
| 7 | 最终签署 | 复用 M6 benchmark，并按证据规范归档截图 / 导出文件 / 缺陷记录 |
| 8 | P2 按需交付 | 提升日常验收效率，非阻塞中期 sign-off |

实际排期以 `swift test`、Viewer 手工走查和 Photoshop 验证为准。

## 非目标（全计划）

- **Photoshop 自动化**（脚本批处理、像素级自动对比）
- **重 benchmark 扩展**（M6 baseline 已足够；本计划不新增压力场景，但最终签署前复用既有 M6 命令做回归确认）
- **完整图像编辑器**（画笔、选区、滤镜、历史记录栈）
- **新 PSD 格式特性**（蒙版、文字层、调整层、智能对象、图层样式编辑）
- **修改** `docs/midterm-plan/*`（中期计划已冻结，本计划仅引用）

## 与中期计划的关系

| 中期计划 | 本计划 |
|----------|--------|
| 证明库层支持子集可持久化 | 证明验收者能用 Viewer + Photoshop **实际操作并确认** |
| `MidtermStandardDocument` 等测试内部 helper | 提供公开、一键可达的同等能力 |
| M5/M6 自动化 roundtrip / benchmark | 提供覆盖 `blend` / `visibility` / `pixel` 的手工 checklist、UI 助手与最终 M6 回归锚点，不重复建设场景 |
