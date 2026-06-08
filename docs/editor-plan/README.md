# PSDKit Editor 升级规划

> 目标：把当前 PSDViewer 从「查看与验收工作台」升级为 Metal-first 的 PSD Editor。  
> 核心原则：先梳理长期架构，再分阶段实现；不为短期可见成果引入临时 CPU 绘制路径或紧耦合方案。

## 文档总览

| 文档 | 说明 |
|------|------|
| [00-requirements-brief.md](./00-requirements-brief.md) | 需求总纲、目标、非目标与成功标准 |
| [01-architecture-principles.md](./01-architecture-principles.md) | Metal-first 架构原则、模块边界与解耦标准 |
| [02-execution-plan.md](./02-execution-plan.md) | 分阶段执行计划总览、依赖关系与 review 建议 |
| [03-e0-architecture-foundation.md](./03-e0-architecture-foundation.md) | **E0**：架构地基、核心类型、模块边界和测试骨架 |
| [04-e1-metal-preview.md](./04-e1-metal-preview.md) | **E1**：Metal 只读预览、snapshot 接入和基础合成 |
| [05-e2-layer-texture-cache.md](./05-e2-layer-texture-cache.md) | **E2**：图层 texture cache、revision、dirty region 和 diagnostics |
| [06-e3-input-and-coordinates.md](./06-e3-input-and-coordinates.md) | **E3**：输入采样、viewport、canvas/layer 坐标系统 |
| [07-e4-metal-brush-pipeline.md](./07-e4-metal-brush-pipeline.md) | **E4**：Metal brush、active stroke texture、dab/stamp 和 commit |
| [08-e5-writeback-and-undo.md](./08-e5-writeback-and-undo.md) | **E5**：PSD 写回、save flush、dirty 和 undo/redo |
| [09-e6-validation-and-performance.md](./09-e6-validation-and-performance.md) | **E6**：自动化测试、手工验收、Photoshop roundtrip 和性能 |
| [10-editor-acceptance-checklist.md](./10-editor-acceptance-checklist.md) | **E6**：Editor 手工验收 checklist 与一键测试命令 |

## 背景

当前 PSDViewer 已完成基础验证：可以打开、新建、保存 PSD，展示图层树，查看合成预览，编辑图层结构和部分属性，并支撑手工验收 workflow。

下一阶段的目标不是在 Viewer 上补一个简单画笔，而是建立一个真正可演进的 Editor 架构：

- Metal 负责高性能图层合成、图像变换、笔刷 stamp 与实时预览。
- PSDKit 继续负责 PSD 文档语义、图层树、像素数据和读写。
- Editor 层负责工具、命令、坐标、状态、undo/redo 与 dirty 语义。
- SwiftUI/AppKit 只作为 UI 外壳和输入桥接，不直接承担编辑核心。

## 总体路线

```text
PSDViewer 验收工作台
        │
        ▼
Editor 架构重组
        │
        ▼
Metal 合成预览
        │
        ▼
Metal 图层纹理缓存 + 变换
        │
        ▼
Metal 笔刷实时绘制
        │
        ▼
PSD 写回 + undo/redo + 验收闭环
```

## 分支与集成策略

本计划遵循仓库现行工作流：[方案 C：直推 `main`](../07-workflow.md)。`main` 是唯一集成分支；本地可以使用 `editor` 或 `cursor/<name>-9904` 之类临时开发分支承载阶段性工作，但阶段完成、`swift test` 通过并验收后，应合并回 `main` 再推送。

当前会话已创建本地 `editor` 分支用于规划和早期实现整理；它不是新的长期集成分支。
