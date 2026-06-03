# AGENTS.md

PSDKit：Swift PSD 读写库（8-bit RGB(A) 位图图层）。

## 基线

- **默认分支：`main`**（含读/写/TDD/语义编码/复合图/Viewer）
- 新功能：`git checkout main && git pull` → `git checkout -b cursor/<name>-9904`

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

`docs/05-implementation-plan.md`、`docs/06-testing.md`
