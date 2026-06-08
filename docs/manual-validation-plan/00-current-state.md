# 当前状态：PSDViewer 能力与缺口

## 目标

为 [手工验收补全计划](./README.md) 建立统一基线：明确 Viewer **已有什么**、**缺什么**、以及库层需补的公开 API。

## 中期库层（已完成，本计划不重复建设）

以下能力在 `Sources/PSDKit` 与 `swift test` 中已验收，本计划默认成立：

| 能力 | 说明 |
|------|------|
| 支持子集读写 | 8-bit RGB(A)、嵌套组、`normal` / `multiply` / `add` |
| 兼容性报告 | `PSDDocument.compatibilityReport`，结构化 issue |
| 文件级硬拒绝 | 16/32-bit、CMYK/Lab/Indexed、Zip/ZipPrediction 等必须打开失败且不生成报告 |
| 嵌套组持久化 | Section divider 读写、树顺序 `index 0 = 栈底` |
| 结构编辑 API（内存 + 语义保存） | `appendLayer` / `insertLayer` / `removeLayer` |
| 往返测试 | `PersistenceRoundTripTests`、`DocumentSnapshot`（测试 internal） |
| 性能 baseline | M6 benchmark 与阈值文档 |

## 当前 PSDViewer 能力

基于 `Apps/PSDViewer` 现状（基础查看器阶段）：

### 文件与文档

| 功能 | 状态 | 说明 |
|------|------|------|
| New | ✅ | 空白 256×256 文档 |
| Open | ✅ | 8-bit RGB PSD |
| Save / Export… | ✅ | 保存到路径或另存为 |
| 错误提示 | ✅ | `PSDError.userMessage` |
| 保存状态 / 路径反馈 | ⚠️ 弱 | 仅有 `statusMessage` 文本，无 dirty 指示、无未保存警告 |
| 窗口标题 / 路径展示 | ⚠️ 弱 | 仅显示文件名，新建未保存文档无路径提示 |

### 图层树

| 功能 | 状态 | 说明 |
|------|------|------|
| 嵌套组列表展示 | ✅ | `LayerListFlattener` 扁平化带缩进 |
| 组 / 像素层图标区分 | ✅ | folder vs stack 图标 |
| 图层选择 | ✅ | `LayerPath` 选择 id |
| 图层树折叠 | ❌ | 始终全展开 |
| 同级 reorder | ❌ | 无拖拽 / 上下移动 |

### 预览

| 功能 | 状态 | 说明 |
|------|------|------|
| 合成预览 | ⚠️ 仅根级 | `compositePreviewRGBA()` 只取 `root.children` 中的 `PixelLayer` |
| 嵌套组内图层 | ❌ 不合成 | 组内 `multiply` / `add` 层不出现在预览中 |
| 混合模式预览 | ❌ 根级亦未用 | 预览路径使用 `normal` 混合 |

相关库实现：

```224:227:Sources/PSDKit/Public/PSDDocument.swift
    public func compositePreviewRGBA() -> Data {
        let layers = root.children.compactMap { $0 as? PixelLayer }
        return CompositeBuilder.compositeRGBA(canvasSize: canvasSize, layers: layers)
    }
```

### Inspector 与编辑

| 功能 | 状态 | 说明 |
|------|------|------|
| 根级像素层：改名、不透明度 | ✅ | `LayerViewerPolicy.editableRootPixel` |
| 根级像素层：可见性切换 | ✅ | 列表眼睛按钮 |
| 根级：Add Layer / Remove / Import PNG | ✅ | 仅 `appendPixelLayer` / `removePixelLayer` |
| 嵌套像素层编辑 | ❌ 只读 | Inspector 显示「嵌套图层编辑尚未启用」 |
| 组属性编辑 | ❌ 只读 | 名称、opacity、blend 仅展示 |
| blend mode 编辑 | ❌ | 只读展示 |
| frame 编辑 | ❌ | 只读 bounds 展示 |
| 组 CRUD | ❌ | 无新建组、删除组、移入移出 UI |
| 结构编辑 | ❌ | 库有 API，Viewer 未暴露 |

### 兼容性报告

| 功能 | 状态 | 说明 |
|------|------|------|
| 打开时摘要横幅 | ✅ | `compatibilityWarningMessage` 一行摘要 |
| 详情列表（kind / severity / layerName / message） | ❌ | 无法逐条查看 issue |
| 保存前有损提醒 | ❌ | 未结合 `hasLossyChanges` 做保存确认 |
| 硬拒绝文件提示 | ⚠️ 弱 | 依赖通用错误提示，未明确验收“不创建文档会话 / 不展示兼容报告” |

### 标准文档与验收工具

| 功能 | 状态 | 说明 |
|------|------|------|
| 标准中期测试 PSD 生成 | ⚠️ 仅测试 internal | `MidtermStandardDocument.make()` 在 `Tests/PSDKitTests/Helpers/` |
| Viewer 一键生成 / 导出 | ❌ | 验收者需写代码或依赖测试 helper |
| 快照 / 差异对比面板 | ❌ | `DocumentSnapshot` 未公开、Viewer 无 UI |
| 手工 checklist 集成 | ❌ | 中期 [05-roundtrip-persistence](../midterm-plan/05-roundtrip-persistence.md) 清单未嵌入 Viewer |
| Photoshop roundtrip 助手 | ❌ | 无步骤引导、无固定导出路径提示 |

## 缺口分级

### P0 — 阻塞手工验收

| 缺口 | 影响 | 主要归属 |
|------|------|----------|
| 标准文档一键生成/导出 | 无法快速获得验收用 PSD | [Library] + [Viewer] |
| 嵌套图层全树合成预览 | 预览与 Photoshop 视觉不一致 | [Library] + [Viewer] |
| 兼容报告详情 | 无法核对降级项 | [Viewer] |
| 文件级硬拒绝手工路径 | 易把不支持文件误判为可降级打开 | [Viewer] |
| `hasLossyChanges` 保存前确认 | 打开降级 PSD 后可能静默有损保存 | [Viewer] |
| 嵌套像素层编辑 | 无法验证组内属性往返 | [Viewer]（库 API 已有） |
| 保存状态与路径反馈 | 易误操作未保存关闭 | [Library] + [Viewer] |

### P1 — roundtrip 工作流

| 缺口 | 影响 | 主要归属 |
|------|------|----------|
| 结构编辑（组内新增/删除/跨组移动） | 无法手工验证 M5 编辑矩阵 | [Viewer] + 可选 [Library] `moveLayer` |
| frame 编辑 | 无法验证位移往返 | [Viewer] |
| blend mode 编辑 | 无法手工验证 M5 blend 保存往返 | [Viewer] |
| visibility 编辑 | 无法手工验证 M5 hidden flag 保存往返 | [Viewer] |
| 最小像素替换 | 无法手工验证 M5 pixel 保存往返 | [Viewer] |
| 快照/差异面板 | 难以肉眼确认多轮编辑 | [Library] + [Viewer] |
| 手工 checklist | 验收步骤易遗漏 | [Viewer] |
| Photoshop roundtrip 助手 | 手工步骤不统一 | [Viewer] |

### P2 — 可用性与覆盖

| 缺口 | 影响 | 主要归属 |
|------|------|----------|
| 组 CRUD | 无法从零搭树 | [Viewer] |
| 组属性编辑 | 无法验证组 opacity / blend | [Viewer] |
| 同级 reorder | 无法验证顺序往返 | [Viewer] + 可选 [Library] |
| 增强像素替换 / 小型像素编辑 | P1 仅要求最小 PNG 替换，尺寸策略与重复替换体验不足 | [Viewer] |
| 图层树折叠 | 深树难浏览 | [Viewer] |

## 库层可能需补的公开 API

| API | 现状 | 计划阶段 |
|-----|------|----------|
| `compositePreviewRGBA()` 递归全树 | 仅根级像素层 | P0 |
| 公开标准文档生成（如 `PSDDocument.makeMidtermStandardDocument()`） | 仅 `@testable` helper | P0 |
| 公开 `isContentDirty` 或等价 `hasUnsavedChanges` | `private(set)` | P0 |
| `compatibilityReport.hasLossyChanges` 保存前暴露路径 | API 已有，Viewer 未强制确认 | P0 |
| 公开 `DocumentSnapshot` / diff | 仅测试 internal | P1（可选） |
| `moveLayer(_:to:at:)` 便捷 API | 需手动 remove + insert | P1（可选） |

## 风险（现状相关）

| 风险 | 缓解 |
|------|------|
| 验收者以为预览代表全文档 | P0 修复合成路径并在 UI 标注预览范围 |
| 文件级硬拒绝被误展示为兼容 warning | P0 smoke pack 覆盖 16-bit、CMYK、Zip，断言无文档会话与无报告 |
| 降级 PSD 被静默覆盖保存 | 保存前基于 `hasLossyChanges` 强制确认继续 / 取消分支 |
| 嵌套编辑走通但忘记 `markContentModified()` | Viewer 编辑路径统一封装 `markDirty()`（已存在，扩展即可） |
| 测试 helper 与公开 API 行为漂移 | 公开 API 内部复用 `MidtermStandardDocument` 逻辑并加测试 |
