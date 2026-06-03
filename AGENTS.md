# AGENTS.md

PSDKit：Swift PSD 读写库（8-bit RGB(A) 位图图层）。

## Git 工作流（方案 C）

- **唯一集成分支：`main`**
- 完成功能且 `swift test` 通过后：**直接 `git push origin main`**
- **不要**开 Draft PR，不要等人工 Merge
- 可选：本地用 `cursor/<name>-9904` 开发，合并后 push `main` 即可

## 基线

`main` 已包含：读/写/TDD/语义编码/复合图/Viewer/CI。

## 常用命令

```bash
swift build && swift test
pip install psd-tools pillow && python3 Scripts/generate_test_fixtures.py
cd Apps/PSDViewer && swift run PSDViewer   # macOS only
```

## 约定

- 图层顺序：index 0 = 栈底（与 psd-tools 一致）
- 编辑图层属性后调用 `document.markContentModified()`，再 `save`
- 写路径：默认 passthrough；语义重建用 `writeMode: .semantic`
- 参考实现索引：`docs/REFERENCES.md`

## 文档

- [docs/07-workflow.md](docs/07-workflow.md) — **Git 工作流（方案 C）**
- `docs/05-implementation-plan.md`、`docs/06-testing.md`
