# Review：PSDKit Editor 升级规划（docs/editor-plan）

> Review 日期：2026-06-06  
> 被评审文档：`docs/editor-plan/*.md`（`README.md`、`00`-`09`）

---

## 结论（TL;DR）

- **总体评价**：架构方向正确、分阶段拆解清晰，但当前版本存在 4 个会直接影响落地与验收口径的阻塞问题。
- **是否建议冻结**：不建议
- **最小可冻结修复包**：
  1. 统一分支契约：把 `editor` 分支表述改为与仓库基线一致的 `main` 集成策略（可选本地临时分支）。
  2. 在 E1 冻结“无回退”渲染口径：至少保证 `normal/multiply/add` 在默认预览路径不退化（或明确 fallback）。
  3. 在 E0/E1 明确 viewport 单一 owner（ScrollView vs Metal viewport 二选一）及坐标真源，禁止并行双状态。
  4. 在 E5 增加可机判的保存/撤销状态机契约（含 `pendingFlush` 行为）并配套集成测试 gate。
  5. 把 E1/E6 的“差异可解释/无明显卡顿”改为可量化阈值与像素误差标准。

---

## 七维覆盖表

| 维度 | 结论（✅/⚠️） | 证据摘要 |
|---|---|---|
| 契约一致性 | ⚠️ | `README.md`/`02-execution-plan.md` 要求在 `editor` 分支推进，与仓库锁定的 `main` 直推流程冲突。 |
| 可达性 | ⚠️ | E1 对 viewport owner 保留二选一，E3 又要求统一坐标链，阶段入口条件不足以保证可达。 |
| 覆盖闭环 | ⚠️ | E1 默认仅 `normal` 合成会与现有 `multiply/add` 能力和手工验收矩阵产生回退风险。 |
| 断言唯一性 | ⚠️ | “关键像素差异可解释”“无明显卡顿/跟手”等 gate 非唯一、不可机判。 |
| 副作用与状态机 | ⚠️ | E5 有异步 flush/readback 设想，但未冻结 save/undo/close 在 `pendingFlush` 状态下的确定规则。 |
| 跨阶段承接 | ⚠️ | E3/E4 对 E1 的 viewport 语义有硬依赖，但 E1 未锁死输入/渲染坐标真源。 |
| 稳定性 | ⚠️ | 性能目标偏描述性，缺少统一统计窗口、阈值、回归判定口径。 |

---

## 阻塞问题（Critical / High）

### [S1-01][Critical][契约一致性] 分支策略与仓库基线冲突
- 现状：
  - `docs/editor-plan/README.md` 写明“本计划在 `editor` 分支推进”。
  - `docs/editor-plan/02-execution-plan.md` 也以 `editor` 作为执行原则。
- 问题：
  - 与仓库当前锁定流程（仅 `main` 集成、测试通过后直推）发生直接冲突，会导致执行路径与评审口径分叉。
- 依据：
  - `AGENTS.md`（方案 C：唯一集成分支 `main`）。
  - `docs/07-workflow.md`（仅 `main`，不走 Draft/常规 PR 流）。
- 建议（最小修复）：
  - 将 editor-plan 中“在 `editor` 分支推进”统一改为“在 `main` 集成推进；允许本地临时开发分支”。
  - 在 `02-execution-plan.md` 的执行原则增加一条“分支策略遵循 `docs/07-workflow.md`”。

### [S1-02][High][覆盖闭环] E1 默认仅 normal 合成，存在现有能力回退风险
- 现状：
  - `04-e1-metal-preview.md` 明确 E1 基础合成只支持 `normal`，并允许“关键像素差异可解释”。
  - 当前库与验收基线已覆盖 `multiply/add`（测试与手工 checklist 都把它们列为必测）。
- 问题：
  - 若 E1 成为默认预览路径却只支持 `normal`，会导致当前 Viewer 的可视结果回退，破坏既有手工验收闭环。
- 依据：
  - `Tests/PSDKitTests/CompositeBuilderTests.swift`（含 multiply/add 语义断言）。
  - `docs/manual-validation-plan/02-p1-roundtrip-workflow.md` 与 `04-acceptance-checklists.md`（blend 为必测项）。
- 建议（最小修复）：
  - 在 E1 验收 gate 增加“默认预览路径对 `normal/multiply/add` 不回退”。
  - 若 E1 不一次性实现全部 blend，则必须定义明确 fallback（如对未支持 blend 走 CPU 参考层）并写入测试。

### [S1-03][High][可达性/跨阶段承接] viewport owner 未冻结，E3 输入坐标链可能不可达
- 现状：
  - E1.5 写法是“保留当前 ScrollView 或迁移到 Metal viewport 二选一”。
  - E3 要求统一 window/view/canvas/layer 坐标链，并强调 overlay 与绘制使用同一坐标服务。
- 问题：
  - 在 E1 未锁定 viewport 真源时推进 E3/E4，容易形成双状态（ScrollView 偏移 + Metal 偏移），导致落点漂移和回归反复。
- 依据：
  - `docs/editor-plan/04-e1-metal-preview.md`（E1.5）
  - `docs/editor-plan/06-e3-input-and-coordinates.md`（统一坐标链与统一 viewport）
  - 当前 `ContentView.swift` 仍由 `ScrollView` 承载预览，`SelectedLayerFrameOverlay.swift` 依赖显示尺寸映射。
- 建议（最小修复）：
  - 在 E0 或 E1 增加“viewport single source of truth”契约：owner、变换矩阵、事件坐标入口、overlay 读取方式。
  - 把 E3 进入条件改为“E1 viewport owner 已冻结且有单测”。

### [S1-04][High][副作用与状态机/断言唯一性] E5 缺少 save/undo/flush 的确定性状态机
- 现状：
  - E5 规划了后台 readback、保存前 flush、undo/redo，但仅给出原则和风险，缺少状态机与并发时序契约。
- 问题：
  - 无法唯一判定“快速绘制 -> 立即保存 -> undo/redo -> 关闭”等关键路径行为，容易出现 preview 与文档态不一致。
- 依据：
  - `08-e5-writeback-and-undo.md`（提到后台队列与 save race，但未定义完整状态迁移）。
  - 现有 `DocumentModel` 保存语义是同步且直接落盘，缺少 pending 状态分层。
- 建议（最小修复）：
  - 在 E5 增加最小状态机定义（示例：`idle`/`strokeActive`/`pendingFlush`/`flushFailed`）。
  - 明确 `save`、`close`、`undo`、`redo` 在各状态的允许性与返回结果，并新增集成测试（尤其 race 路径）。

## 非阻塞问题（Medium / Low）

### [S2-01][Medium][断言唯一性/稳定性] 验收与性能 gate 描述偏主观，难以自动化回归
- 现状：
  - E1/E6 使用“差异可解释”“无明显卡顿”“跟手”等描述。
- 问题：
  - 缺少统一阈值会让阶段通过判定依赖主观判断，导致不同 reviewer 结论不一致。
- 依据：
  - `04-e1-metal-preview.md`、`09-e6-validation-and-performance.md` 的 gate 与目标项。
- 建议：
  - 增加可机判标准：像素误差上限、帧时阈值、commit/readback P50/P95、回归红线（例如相对基线 >15% 触发阻塞）。

### [S2-02][Medium][覆盖闭环] 未显式纳入“兼容报告/有损保存”回归点
- 现状：
  - Editor 计划强调渲染/输入/写回，但对当前 Viewer 已有的兼容报告与 lossy save guard 只做了笼统“不回退”表述。
- 问题：
  - 在 UI 架构重组阶段，容易遗漏这类流程性守卫回归，最终影响手工验收闭环。
- 依据：
  - 当前 `ContentView.swift` 与 `DocumentModel.swift` 已包含 lossy save、兼容报告、关闭保护完整流程。
  - `docs/manual-validation-plan/04-acceptance-checklists.md` 将其列为 P0/P1 必测。
- 建议：
  - 在 E1/E5/E6 各加 1 条明确 gate：兼容报告可达、lossy save 三分支（查看详情/取消/继续）不回退。

---

## 补充说明

- 本次评审边界：
  - 覆盖 `docs/editor-plan` 全部 11 份文档，并对照现有实现（`Apps/PSDViewer`、`Sources/PSDKit`）及基线文档（`AGENTS.md`、`docs/07-workflow.md`、`docs/manual-validation-plan/*`）。
- 不纳入本轮的问题：
  - shader 级算法细节（如具体 kernel 公式优选）；
  - 未来 P3+ 功能扩展（非破坏性编辑、高级工具系统）。
