# 验收 Checklist

本文档提供各阶段**独立验收**勾选清单与 **Photoshop 手工验收**统一清单。  
每阶段 Gate 要求：**该阶段所有必选项勾选**，且 [阶段文档](./README.md) 中「测试命令」通过。

使用方式：

- 开发自测：实现阶段文档后按序勾选
- Release gate：P1 + Photoshop 节 + M6 benchmark 回归锚点全部通过后，可宣布中期手工验收完成
- P2 为增强项，不承载中期 sign-off 必测项

---

## P0 Gate：解除手工验收阻塞

### 库 API

- [ ] `compositePreviewRGBA()`（或等价公开 API）合成结果包含嵌套组内可见像素层
- [ ] 组内 `multiply` / `add` 层影响合成输出（与测试 fixture 预期一致）
- [ ] 隐藏图层不参与合成
- [ ] 公开标准文档 API 生成树结构：BG → Group A（Red, Group B → Glow）→ Top（hidden）
- [ ] 公开 `hasUnsavedChanges`（或 `isContentDirty`）在编辑后为 `true`，保存成功后为 `false`

### Viewer UI

- [ ] 可从菜单/工具栏一键生成并打开标准测试文档
- [ ] 预览区展示全树合成（非仅根级像素层）
- [ ] 嵌套像素层可编辑名称、opacity；可见性可切换
- [ ] 嵌套像素层编辑后 Save → Reopen 属性保持
- [ ] 兼容报告详情可查看每条 issue 的 severity / kind / layerName / message
- [ ] 无 issue 时详情区明确提示「支持子集内」
- [ ] `hasLossyChanges == true` 的文档保存前弹出有损确认
- [ ] 有损确认的「查看详情」可打开兼容报告详情
- [ ] 有损确认的「取消保存」不写文件，dirty 状态保留
- [ ] 有损确认的「继续保存」写出文件，并按保存成功状态更新 UI
- [ ] 窗口或状态栏显示 dirty 状态
- [ ] 未保存关闭文档时提示确认
- [ ] 状态栏显示文件路径或「Untitled」

### 文件级硬拒绝

- [ ] 16-bit fixture 打开失败，错误文案明确
- [ ] CMYK / Lab / Indexed fixture 至少覆盖一类，打开失败，错误文案明确
- [ ] Zip 或 ZipPrediction fixture 打开失败，错误文案明确
- [ ] 上述硬拒绝场景不创建新的 `PSDDocument` 会话
- [ ] 上述硬拒绝场景不展示兼容性报告，不出现“降级后成功”的假成功状态

### 自动化

- [ ] `swift test` 全绿
- [ ] `cd Apps/PSDViewer && swift test` 全绿

### P0 快速手工路径（约 25 分钟）

1. [ ] Generate Standard Test Document
2. [ ] 目视预览含红色 multiply 与 Glow add 效果
3. [ ] 编辑组内 `Red` opacity → Save → Reopen
4. [ ] 打开含 warning 的 fixture → 查看报告详情
5. [ ] 修改该有损文档 → Save → 覆盖查看详情 / 取消保存 / 继续保存分支
6. [ ] 打开 16-bit、CMYK、Zip smoke pack → 均硬拒绝且无兼容报告
7. [ ] 确认 dirty 提示 → Save → dirty 清除

---

## P1 Gate：Roundtrip 工作流

### 结构编辑

- [ ] 在指定组内新增像素层，Save → Reopen，parent 正确
- [ ] 删除像素层，Save → Reopen，层已移除
- [ ] 跨组移动图层，Save → Reopen，旧父无该层、新父有该层

### Frame 编辑

- [ ] 修改像素层 frame（至少一项：left / top / width / height）
- [ ] 预览随 frame 更新
- [ ] Save → Reopen，bounds 一致

### Blend / Visibility / Pixel 编辑

- [ ] 修改像素层 blend mode（`normal` / `multiply` / `add` 至少覆盖一次切换）
- [ ] Save → Reopen，blend mode 一致
- [ ] 切换根级或嵌套像素层 visibility
- [ ] Save → Reopen，可见性一致
- [ ] 对选中像素层执行最小 `Replace from PNG…`
- [ ] Save → Reopen，像素 hash 一致；若 hash 工具不可用，必须记录替换 PNG、目标图层、截图和人工判断理由

### 快照 / 差异

- [ ] 可捕获至少两个快照标签（如 Before / After）
- [ ] diff 可辨认树路径、属性变化或 pixel hash 变化（人类可读）

### 工作流 UI

- [ ] 嵌入式 P1 checklist 可勾选、可重置进度
- [ ] Photoshop Roundtrip 助手列出分步说明
- [ ] 助手可「在 Finder 中显示」导出文件

### 多轮编辑

- [ ] 至少 3 轮「编辑 → Save → Reopen」后，支持子集内数据与预期一致
- [ ] 使用 Snapshot 确认无意外漂移
- [ ] 三轮中至少覆盖一次结构编辑、一次属性编辑（frame / blend / visibility 之一）、一次 pixel 替换

### 自动化

- [ ] `swift test` 全绿（含 `PersistenceRoundTripTests`）
- [ ] `cd Apps/PSDViewer && swift test` 全绿（若 Viewer 测试 target 可用）

---

## P2 Gate：可用性与覆盖

### 组操作

- [ ] 新建组并添加子层，Save → Reopen
- [ ] 删除空组
- [ ] 删除含子层组（有确认），Save → Reopen

### 组属性

- [ ] 编辑组名称，Save → Reopen
- [ ] 编辑组 opacity / blend（若产品承诺支持），Save → Reopen；若不支持则 UI 禁用并文档化

### 顺序与像素

- [ ] 同父两层 reorder，Save → Reopen，顺序正确（栈底 index 0）
- [ ] 增强 Replace PNG 的尺寸策略 / 确认分支，Save → Reopen，像素更新

### 浏览

- [ ] 折叠组隐藏子孙，展开恢复
- [ ] 折叠状态不影响 Save 结果

### 自动化

- [ ] `swift test` 全绿

---

## Photoshop 手工验收 Checklist

> **执行时机**：P1 Gate 通过后，作为中期手工验收最终 gate。  
> **环境**：macOS，本地安装 Photoshop；PSDViewer 从 `main` 构建。

### 证据归档规范

- [ ] 建立本次验收目录：`manual-validation/YYYYMMDD-<validator>/`
- [ ] 保留 PSD 文件：`midterm-standard.psd`、`midterm-standard-ps.psd`、`midterm-roundtrip-p1.psd`
- [ ] 保留 Viewer 截图：`viewer-standard-layers.png`、`viewer-standard-composite.png`、`viewer-compatibility-report.png`
- [ ] 保留 Photoshop 截图：`photoshop-standard-layers.png`、`photoshop-standard-composite.png`
- [ ] 所有截图需能看出文件名或路径、图层面板、合成视图；若因窗口尺寸无法同时展示，拆成两张并在记录中说明
- [ ] 任何“可接受差异”必须记录：文件名、观察位置、预期、实际、判断理由、关联 issue（若有）

### 准备

- [ ] `swift build && swift test` 已通过
- [ ] Viewer 可启动：`cd Apps/PSDViewer && swift run PSDViewer`
- [ ] 准备记录本（截图或文字）：PS 版本、文件路径、异常说明
- [ ] 已记录证据归档目录路径

### A. PSDKit 生成标准文档

- [ ] 在 Viewer 生成标准测试文档
- [ ] 导出为 `midterm-standard.psd`（或助手建议路径）
- [ ] 记录图层树截图或文字描述

### B. Photoshop 打开（PSDKit 写出）

- [ ] Photoshop 可打开，无致命错误
- [ ] 图层面板：组 `Group A`、`Group B` 层级正确
- [ ] 图层名：BG、Red、Glow、Top 正确
- [ ] `Top` 层隐藏状态正确
- [ ] Red：`multiply`，opacity ≈ 78%（200/255）正确
- [ ] Glow：`Linear Dodge (Add)` 或等价显示正确
- [ ] 合成结果与 Viewer 全树预览对齐；按证据规范归档截图，任何可见差异均已记录（允许 PS 查看器缩放差异）

### C. Photoshop 另存后 PSDKit 再打开

- [ ] PS 另存为 `midterm-standard-ps.psd`
- [ ] PSDKit 打开另存文件
- [ ] 支持子集内图层树可读
- [ ] 兼容性报告：记录所有 warning；无静默丢层
- [ ] 对组内层做一项小编辑 → Save → Reopen 成功

### D. P1 编辑矩阵抽样

- [ ] 在 Viewer 中修改 blend mode → Save → Reopen → Photoshop 打开，显示符合预期
- [ ] 在 Viewer 中修改 visibility → Save → Reopen → Photoshop 打开，显示符合预期
- [ ] 在 Viewer 中执行 `Replace from PNG…` → Save → Reopen → Photoshop 打开，像素结果符合预期
- [ ] 归档对应 `midterm-roundtrip-p1.psd`、Viewer 截图与 Photoshop 截图

### E. 外部 PSD 抽样

- [ ] 打开一个含 layer style / 蒙版的简单外部 PSD
- [ ] 兼容性报告详情与预期 kind 一致
- [ ] 修改任意属性后保存前弹出 `hasLossyChanges` 确认
- [ ] 覆盖确认框「查看详情」「取消保存」「继续保存」三个分支

### F. 文件级硬拒绝 Smoke Pack

- [ ] 16-bit fixture：PSDKit / Viewer 打开失败，错误文案明确
- [ ] CMYK / Lab / Indexed fixture 至少一类：PSDKit / Viewer 打开失败，错误文案明确
- [ ] Zip 或 ZipPrediction fixture：PSDKit / Viewer 打开失败，错误文案明确
- [ ] 每个硬拒绝样本均不创建文档会话、不展示兼容性报告

### G. M6 Benchmark 回归锚点

复用既有 M6 benchmark，不新增 preset 或压力场景：

```bash
swift run -c release PSDKitBenchmark --preset small --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/manual-validation-m6-small.json
swift run -c release PSDKitBenchmark --preset medium --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/manual-validation-m6-medium.json
swift run -c release PSDKitBenchmark --preset stress --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/manual-validation-m6-stress.json
```

如需 Markdown 证据，再以相同 preset 追加 `--format markdown` 并输出 `.md` 文件。

- [ ] 三档 benchmark 均运行成功
- [ ] 报告包含硬件、系统、Swift 版本、Release 构建配置、预热与迭代次数
- [ ] Small / Medium / Stress 的 P50 与峰值内存未超过 [M6 阈值](../midterm-plan/06-performance.md)
- [ ] 同机相对既有 M6 baseline P50 回归超过 15% 时，已记录原因或阻塞签署
- [ ] JSON 报告已归档到本次证据目录，或记录 `Benchmarks/Reports/` 中的文件路径；Markdown 报告可选

### H. 签署

- [ ] P0 checklist 全部完成
- [ ] P1 checklist 全部完成
- [ ] 本节 A–G 全部完成
- [ ] 证据归档路径：__________
- [ ] 验收人 / 日期：__________

---

## 缺陷记录模板

| 日期 | 阶段 | 步骤 | 证据文件 | 预期 | 实际 | 严重度 | Issue |
|------|------|------|----------|------|------|--------|-------|
| | P0/P1/P2/PS/M6 | | | | | P0/P1/P2 | |

严重度指引：

- **P0**：阻塞手工验收，须修复后重验
- **P1**：roundtrip 或编辑流受损
- **P2**：体验问题，可延期
