# Editor 需求总纲

## 一句话目标

把 PSDViewer 升级为 Metal-first 的 PSD Editor，使其能够在 PSD 图层上进行高性能、可保存、可回放、可验证的图像编辑。

## 核心诉求

1. **Metal-first**
   - 图层合成、缩放、平移、变换、笔刷 stamp、实时 stroke preview 优先进入 Metal 管线。
   - 不先做 CPU 临时画笔，不把绘制能力做成独立于最终架构之外的一次性补丁。

2. **真正模块化**
   - UI 不直接修改 PSD 图层像素。
   - Renderer 不依赖 SwiftUI 或 App 状态对象。
   - EditorCore 不知道 PSD 文件格式细节。
   - PSDKit 不承担交互工具、输入采样或渲染后端职责。

3. **长期架构优先**
   - 接受阶段性重构成本。
   - 每个阶段都朝最终 Editor 架构推进。
   - 不为了短期演示效果引入未来必然拆除的耦合。

4. **可保存与可验证**
   - 所有编辑最终必须能写回 `PSDDocument`。
   - dirty、保存、关闭守卫、有损保存提醒等现有行为需要重新接入 Editor 命令体系。
   - 自动化测试覆盖核心纯逻辑，手工验收覆盖 Metal 交互与 Photoshop roundtrip。

## 用户能力目标

### P0 能力

- 打开 PSD 后使用 Metal 渲染合成预览。
- 选择像素图层后看到准确图层边界。
- 支持基础视图操作：适应窗口、缩放、平移、透明棋盘格背景。
- 保持当前 Viewer 的打开、保存、关闭、图层选择、属性查看能力。

### P1 能力

- 对选中像素图层进行基础画笔绘制。
- 支持画笔颜色、大小、硬度、流量、透明度。
- 支持鼠标输入，架构上预留数位板 pressure。
- 抬笔后把 stroke 提交为图层像素变更，并触发 dirty / preview 更新 / 保存写回。

### P2 能力

- 引入 `MetalLinePOC` 的高频采样与 pressure 模型。
- 支持数位板 pressure 控制大小和流量。
- 支持绘制中实时 Metal stroke preview，提交后合并到目标图层 texture。

### P3 能力

- 支持 undo/redo。
- 支持更完整的图层变换和非破坏性编辑预留。
- 支持更清晰的 Editor 状态持久化和调试诊断。

## 非目标

- 不在第一阶段扩展 PSD 格式支持范围，例如文字层、调整层、智能对象、蒙版、图层样式编辑。
- 不把 PSDKit 改造成 UI 或渲染框架。
- 不复制 Photoshop 全量功能。
- 不为了兼容当前 Viewer 内部结构保留不合理耦合。
- 不做脱离最终 Metal 架构的 CPU-only 绘制原型。

## 成功标准

- 渲染、编辑、输入、文档、UI 五个方向有清晰边界，互相通过协议或快照数据通信。
- Metal preview 成为主预览路径，旧 `NSImage` 合成预览退为兼容或测试辅助。
- 绘制 stroke 能以命令方式提交，支持 dirty、保存、reopen 验证。
- `swift test` 覆盖坐标映射、命令提交、像素写回、dirty 语义。
- 手工验收能证明：绘制、保存、重新打开、Photoshop 查看均符合预期。
