# Editor 分阶段执行计划总览

## 执行原则

- 分支策略遵循 [方案 C：直推 `main`](../07-workflow.md)：`main` 是唯一集成分支，本地临时分支仅用于阶段性开发整理。
- 先搭架构边界，再迁移功能。
- 每个阶段都朝 Metal-first Editor 目标前进。
- 不新增与最终架构无关的 CPU-only 绘制路径。
- 每阶段必须有自动化测试或明确的手工验收 gate。

## 阶段总览

| 阶段 | 文档 | 主题 | 目标 |
|------|------|------|------|
| E0 | [03-e0-architecture-foundation.md](./03-e0-architecture-foundation.md) | 架构地基 | 建立模块目录、核心协议、数据模型和测试骨架 |
| E1 | [04-e1-metal-preview.md](./04-e1-metal-preview.md) | Metal 预览 | 用 Metal 承接当前合成预览，形成只读渲染主路径 |
| E2 | [05-e2-layer-texture-cache.md](./05-e2-layer-texture-cache.md) | 图层纹理缓存 | 建立 PSD layer 到 Metal texture 的稳定缓存与失效机制 |
| E3 | [06-e3-input-and-coordinates.md](./06-e3-input-and-coordinates.md) | 输入与坐标 | 建立输入采样、viewport、canvas/layer 坐标转换 |
| E4 | [07-e4-metal-brush-pipeline.md](./07-e4-metal-brush-pipeline.md) | Metal 绘制管线 | 接入 brush、stroke texture、dab/stamp、实时 preview |
| E5 | [08-e5-writeback-and-undo.md](./08-e5-writeback-and-undo.md) | PSD 写回与 undo | 将绘制提交写回 PSDKit，并纳入 dirty/save/undo |
| E6 | [09-e6-validation-and-performance.md](./09-e6-validation-and-performance.md) | 验收与性能 | Photoshop roundtrip、性能基线、调试诊断 |

## 依赖关系

```text
E0 架构地基
    │
    ▼
E1 Metal 预览 ──► E2 图层纹理缓存
    │                  │
    ▼                  ▼
E3 输入与坐标 ──► E4 Metal 绘制管线
                       │
                       ▼
              E5 PSD 写回与 undo
                       │
                       ▼
              E6 验收与性能
```

E1 和 E2 强依赖 E0，但 E3 可以在 E1 后半段并行准备。E4 不应早于 E2/E3 的接口稳定，否则绘制管线会反向污染模块边界。E5 必须等 E4 的 stroke commit 语义明确后再落地，避免把 GPU 临时状态直接写进 PSDKit。

## 阶段切分口径

- **E0 解决边界**：先定义谁可以依赖谁，哪些数据跨模块传递。
- **E1 解决显示**：让 Metal 成为预览主路径，但保持只读。
- **E2 解决资源生命周期**：让图层 texture 可以被稳定复用、局部失效、按需上传。
- **E3 解决输入语义**：让鼠标和数位板输入变成平台输入样本，再映射到图层局部坐标。
- **E4 解决实时绘制**：让 brush stroke 在 GPU 内实时 stamp 和 preview。
- **E5 解决持久化**：让 GPU 编辑结果变成 PSDKit 的文档变更，并纳入 undo/redo。
- **E6 解决交付质量**：建立测试、验收、性能和调试闭环。

## 第一批建议落地任务

1. 先执行 [E0 架构地基](./03-e0-architecture-foundation.md)，只做目录、协议、模型和测试骨架。
2. E0 验收通过后，进入 [E1 Metal 预览](./04-e1-metal-preview.md) 的最小只读 preview。
3. E1 开始后即可并行预研 [E3 输入与坐标](./06-e3-input-and-coordinates.md) 中的 `StrokeSampling` 提取方案，但不要提前接入绘制。
4. E2/E3 接口稳定后再进入 [E4 Metal 绘制管线](./07-e4-metal-brush-pipeline.md)。

## 主要风险

| 风险 | 说明 | 缓解 |
|------|------|------|
| Metal 与 PSD 像素语义不一致 | premultiplied alpha、blend mode、opacity 顺序可能出现差异 | 用 `compositePreviewRGBA()` 做参考测试，关键像素对比 |
| 模块边界滑坡 | UI、DocumentModel、Renderer 互相直接调用 | E0 先定义协议和依赖规则，review 时强制检查 import |
| texture readback 成本高 | 每笔 stroke 后全图读回会影响性能 | 先以 dirty region 为单位设计接口，必要时批量 flush |
| 输入采样复杂 | 鼠标、数位板、pressure、polling 行为不同 | 复用 MetalLinePOC 的 StrokeSampling 分层 |
| 现有 Viewer 功能被破坏 | 保存、dirty、关闭确认、兼容报告不能回退 | 每阶段跑 PSDViewer 测试并补 Editor 回归 |

## Review 建议

同事 review 时建议按顺序看：

1. [01-architecture-principles.md](./01-architecture-principles.md)
2. 本文件
3. [03-e0-architecture-foundation.md](./03-e0-architecture-foundation.md)
4. 需要参与实现的具体阶段文件

如果 review 中发现某阶段任务必须跨越多个模块边界，应先回到 E0 调整协议，而不是直接在实现里加临时依赖。
