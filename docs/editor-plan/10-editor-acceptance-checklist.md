# Editor E6 验收 Checklist

> 本清单覆盖 E0–E5 交付 gate 的手工验收项，与 [09-e6-validation-and-performance.md](./09-e6-validation-and-performance.md) 对齐。  
> 库层/Viewer 既有流程（兼容报告、有损保存、硬拒绝）继续沿用 [manual-validation-plan/04-acceptance-checklists.md](../manual-validation-plan/04-acceptance-checklists.md) P0/P1 节，本节不重复。

## 自动化入口（开发自测）

```bash
# E6 umbrella + E1–E5 关键 editor 测试（推荐首选）
cd Apps/PSDViewer && swift test --filter 'EditorE6|Editor|Brush|Stroke|Writeback|Undo|LayerTextureCache|DocumentModelCompatibilityTests'

# PSDViewer 全量
cd Apps/PSDViewer && swift test

# 库层回归
cd /path/to/psdkit && swift test

# E6 性能/diagnostics 基线（仅记录，无硬阈值）
./Scripts/run-editor-benchmark.sh

# M6 库层回归锚点（与中期签署一致）
swift run -c release PSDKitBenchmark --preset small --warmup 1 --iterations 5 \
  --output Benchmarks/Reports/manual-validation-m6-small.json
```

GPU/Metal 相关测试在无 GPU 环境会 `XCTSkip`；CI 无 Metal 时不应因此失败。

---

## A. 基础打开与预览（E1）

- [ ] 打开标准测试文档（Generate Standard Test Document）
- [ ] 默认 Metal 预览正确显示全树合成
- [ ] `normal` / `multiply` / `add` 目视与预期一致（红 multiply、Glow add）
- [ ] 预览菜单切换「Use Metal Preview」关闭后，CPU fallback 生效且画面可读
- [ ] 含 unsupported blend 的文档自动 fallback CPU，不崩溃
- [ ] 缩放、平移、适应窗口正常；图层 frame overlay 对齐
- [ ] Compatibility Report 入口可达，内容不因 Editor shell 重组丢失

## B. 图层属性（E1/E2）

- [ ] visibility 切换后预览更新
- [ ] opacity 修改后预览更新
- [ ] frame 移动后预览与 overlay 同步
- [ ] blend mode 修改（normal/multiply/add）后预览更新
- [ ] Save → Reopen 属性保持一致

## C. 绘制与输入（E3/E4）

- [ ] 选中 pixel layer 后可绘制
- [ ] 未选中 pixel layer / 非可编辑层时不能绘制
- [ ] offset layer 绘制落点正确
- [ ] 缩放和平移后绘制落点正确
- [ ] 修改 brush size / color / opacity / flow 后笔迹变化可见
- [ ] eraser 工具可擦除已绘制区域
- [ ] cancel stroke（Esc 或等效）不产生提交
- [ ] 状态栏/调试区可见输入 diagnostics（samples、last point 等）

## D. undo/redo（E5）

- [ ] 单笔 undo 恢复笔迹
- [ ] 多笔连续 undo
- [ ] redo 恢复
- [ ] undo 后 Save → Reopen 一致
- [ ] redo 后 Save → Reopen 一致

## E. 保存与关闭（E5）

- [ ] 绘制后 dirty 状态出现
- [ ] 关闭时弹出 unsaved confirmation
- [ ] Save 后 dirty 清除
- [ ] Save As 后新文件可打开
- [ ] 快速绘制后立即保存不丢 stroke（pending flush 已提交）
- [ ] active stroke 录制中 Save/Close 被 gate 拦截
- [ ] `flushFailed` 下 Save/Close/undo 行为符合状态机（不静默丢编辑）
- [ ] lossy save confirmation 三分支可达：View Details、Cancel Save、Continue Save

## F. Photoshop roundtrip（手工 gate）

- [ ] Editor 保存 PSD → Photoshop 打开，图层位置与绘制结果可接受
- [ ] Photoshop 另存 → PSDKit/Editor 重新打开，树结构与关键视觉一致
- [ ] 归档 `editor-roundtrip-e6.psd` 与截图路径：__________

## G. 性能与 diagnostics 基线（E6）

- [ ] 运行 `./Scripts/run-editor-benchmark.sh`（或 `EditorBenchmarkSmokeTests`），JSON 报告已归档（record-only，无 CI 硬阈值）
- [ ] 报告含 snapshot build、CPU/Metal composite、brush rasterize、texture cache diagnostics
- [ ] 已知 `metalComposite` 含每次迭代的 `EditorMetalRenderer` 初始化成本；对比 steady-state 帧时需另行测量
- [ ] 同机相对既有 baseline P95 退化 >15% 时记录原因（人工审阅参考，不阻塞，除非 Major）
- [ ] M6 small/medium/stress 回归已复跑（见 manual-validation-plan §G）

## H. 签署

- [ ] 本节 A–G 必选项全部勾选
- [ ] `swift test`（根目录 + Apps/PSDViewer）全绿或 skip 项已记录
- [ ] Blocker/Major 缺陷清零或有明确延期决策
- [ ] 验收人 / 日期：__________
