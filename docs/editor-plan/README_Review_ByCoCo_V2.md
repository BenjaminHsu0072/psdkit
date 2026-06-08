# Review：PSDKit Editor 升级规划（docs/editor-plan）

> Review 日期：2026-06-06  
> 被评审文档：`docs/editor-plan/*.md`（修订版，含 `README.md`、`00`-`09`）

---

## 结论（TL;DR）

- **总体评价**：本轮修订已闭合上轮提出的 4 个阻塞问题（分支契约、E1 blend 回退、viewport 真源、E5 状态机），方案已具备冻结条件。
- **是否建议冻结**：建议
- **最小可冻结修复包**：
  1. 明确 `flushFailed` 下 `close` 的“放弃未同步 GPU 变更并关闭”分支与状态迁移，并补集成测试。
  2. 将 `README.md` 中“当前会话已创建本地 editor 分支”改为更长期有效的表述（或移至变更记录）。

---

## 七维覆盖表

| 维度 | 结论（✅/⚠️） | 证据摘要 |
|---|---|---|
| 契约一致性 | ✅ | `README.md` 与 `02-execution-plan.md` 已对齐 `docs/07-workflow.md` 的 `main` 集成策略。 |
| 可达性 | ✅ | `04-e1-metal-preview.md` 已冻结 viewport 单一真源，`06-e3-input-and-coordinates.md` 以前置条件承接。 |
| 覆盖闭环 | ✅ | E1 已冻结 `normal/multiply/add` 默认预览能力与 CPU fallback 约束，并纳入测试口径。 |
| 断言唯一性 | ⚠️ | E5 大部分状态机已可机判，但 `flushFailed` 下 close 的“可否丢弃后关闭”尚未写成唯一规则。 |
| 副作用与状态机 | ⚠️ | E5 已有完整状态与迁移表；仅剩 `flushFailed` close 分支的最终动作需再显式化。 |
| 跨阶段承接 | ✅ | E1→E3→E4 承接关系较清晰，阶段入口条件与测试 gate 已联动。 |
| 稳定性 | ✅ | E1/E6 已引入像素误差、P95/P99、回归红线（15%/30%）等可量化口径。 |

---

## 阻塞问题（Critical / High）

本轮未发现 Critical/High 阻塞问题。

## 非阻塞问题（Medium / Low）

### [S2-01][Medium][断言唯一性/副作用与状态机] `flushFailed` 下 close 分支仍有实现歧义
- 现状：
  - `08-e5-writeback-and-undo.md` 的操作规则里，`flushFailed` + `close` 写为“弹出错误，不能直接保存关闭”。
- 问题：
  - 目前未明确“是否允许用户放弃未同步 GPU dirty 并执行 Close Without Saving”，以及对应状态迁移；不同实现者可能给出不同行为。
- 依据：
  - 当前 Viewer 现有关闭守卫流程是明确三分支（取消/不保存关闭/保存后关闭）；E5 若不补齐 `flushFailed` 分支，可能与既有工作流口径不一致。
- 建议：
  - 在 E5 状态机中显式补一条：`flushFailed + closeWithoutSaving -> idleClean`（清理或丢弃 GPU dirty，记录告警）。
  - 同时新增集成测试覆盖：`flushFailed -> close without saving`、`flushFailed -> retry flush -> close`。

### [S2-02][Low][可维护性] `README.md` 含会话时态描述，长期可读性偏弱
- 现状：
  - `README.md` 包含“当前会话已创建本地 `editor` 分支用于规划和早期实现整理”的时态语句。
- 问题：
  - 该信息会随时间失效，长期看更像变更记录而非稳定方案约束。
- 依据：
  - 方案文档通常用于长期协作与复审，建议保留稳定约束、移除短期会话状态。
- 建议：
  - 改为“可使用本地临时分支（例如 `editor`）进行阶段整理”。
  - 如需保留“本次修订背景”，建议放入单独 changelog 或 PR 描述。

---

## 补充说明

- 本次评审边界：
  - 重点复核上轮阻塞项在 `README.md`、`02`、`04`、`06`、`08`、`09` 的修订兑现情况，并与现有基线文档和实现行为做一致性检查。
- 不纳入本轮的问题：
  - 具体 shader/Metal 算法实现优选；
  - 尚未落地代码阶段的微观 API 命名偏好。
