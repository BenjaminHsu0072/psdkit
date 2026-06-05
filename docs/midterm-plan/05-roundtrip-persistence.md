# 子计划 5：PSD 持久化往返

## 目标

证明 `.psd` 可以作为画板的中期持久化格式：

- PSDKit 写出的 PSD 可反复打开、编辑、保存。
- 支持子集内的数据不丢失、不变形。
- 不依赖私有 manifest 或私有元数据。
- 所有状态都能从标准 PSD 结构恢复。

## 往返范围

| 数据 | 必须保持 |
|------|----------|
| 画布尺寸 | 是 |
| 图层树 | 是 |
| 图层名称 | 是 |
| 图层可见性 | 是 |
| 图层 opacity | 是 |
| 图层位置与尺寸 | 是 |
| 图层 RGBA 像素 | 是 |
| 组结构 | 是 |
| 三种混合模式 | 是 |
| 图层顺序 | 是 |

## 不承诺范围

- 外部 PSD 中不支持特性的无损保留。
- Photoshop 修改过的复杂 PSD 仍保持 PSDKit 原始语义。
- 文字、调整层、智能对象、图层样式、蒙版的往返。

## 设计任务

1. 定义 `DocumentSnapshot` 测试辅助结构，用于比较文档树、元数据和像素 hash。
2. 定义反复保存测试次数：建议至少 3 轮 `open -> edit -> save`。
3. 定义编辑操作集：重命名、移动、改 opacity、改 blend、改可见性、改像素、组内增删层。
4. 定义文件级验收：PSDKit 可读、Photoshop 可打开、psd-tools 可解析。
5. 确认不使用私有 metadata 的代码审查标准。
6. 冻结 dirty 状态约束：任何原位属性或像素编辑后，测试和上层调用必须触发语义保存路径。

## Dirty 状态约束

当前保存路径存在 passthrough 与 semantic 两种模式。中期持久化测试必须显式验证编辑后不会走 passthrough。

冻结规则：

- 新建文档默认视为 dirty，保存必须走 semantic。
- 通过 `append` / `insert` / `remove` / `move` 等文档 API 修改结构时，API 必须负责标记 dirty。
- 直接修改 `name`、`frame`、`opacity`、`blendMode`、`isVisible`、`pixels` 等属性后，调用方必须调用 `document.markContentModified()`，或者在测试中显式使用 `writeMode: .semantic`。
- 中期 round-trip 测试优先调用 `document.markContentModified()`，并额外覆盖 `writeMode: .semantic` 的显式保存路径。
- 验收失败条件：属性已改但保存后再次打开没有变化，即使 `save` 没有抛错也算失败。

## 实施任务

1. 新增 round-trip 测试 helper，递归遍历 `GroupLayer` 和 `PixelLayer`。
2. 为支持子集建立标准测试文档生成器。
3. 新增多轮保存测试。
4. 新增编辑后保存测试。
5. 将 Photoshop 手动验证步骤写入 checklist。
6. 在 CI 中运行可自动化部分；Photoshop 验证保留为人工 release gate。
7. 对每个原位属性编辑测试添加 `markContentModified()` 或显式 semantic 保存断言。

## 标准测试文档

建议构造一个覆盖中期全部特性的 PSD：

```text
Canvas 256x256
├── BG normal, opaque
├── Group A
│   ├── Red multiply, opacity 200
│   └── Group B
│       └── Glow add, alpha gradient
└── Top normal, hidden
```

该文档应由 PSDKit 从零创建，不依赖外部文件。

## 编辑操作矩阵

| 操作 | Dirty 要求 | 验收 |
|------|------------|------|
| 重命名图层 | 调用 `markContentModified()` | 保存后名称一致 |
| 移动图层 frame | 调用 `markContentModified()` | 保存后 bounds 一致 |
| 修改 opacity | 调用 `markContentModified()` | 保存后 UInt8 值一致 |
| 修改 blend mode | 调用 `markContentModified()` | 保存后模式一致 |
| 修改可见性 | 调用 `markContentModified()` | 保存后 hidden flag 一致 |
| 修改像素 | 调用 `markContentModified()` | 保存后像素 hash 一致 |
| 组内新增图层 | 结构编辑 API 自动标记 dirty | 保存后新增层位置和像素一致，`child.parent` 正确 |
| 删除组内图层 | 结构编辑 API 自动标记 dirty | 保存后树结构一致，被删节点不再有有效父容器 |
| 移动图层到另一个组 | 结构编辑 API 自动标记 dirty | 保存后父子关系一致，旧父容器不再包含该节点 |

## 验收步骤

1. PSDKit 从零创建标准测试文档并保存为 PSD。
2. PSDKit 打开该 PSD，生成 `DocumentSnapshot A`。
3. 执行一组编辑操作；原位属性编辑必须调用 `markContentModified()`，结构编辑 API 必须自动标记 dirty。
4. PSDKit 再次打开，生成 `DocumentSnapshot B`，断言编辑结果符合预期。
5. 重复第 3-4 步至少 3 轮。
6. 每轮保存后的文件用 psd-tools 打开并打印层结构，无解析错误。
7. 至少一次用 Photoshop 手工打开最终 PSD，确认图层树、混合模式、可见性、视觉结果正确。
8. 增加一个负向测试：不调用 `markContentModified()` 且使用默认 passthrough 保存时，原位属性修改不应被误判为已持久化。
9. 代码审查确认保存路径没有写入私有 manifest、自定义 image resource 或自定义 tagged block。

## 测试建议

- `PersistenceRoundTripTests.testCreateOpenSaveOpenPreservesSnapshot`
- `PersistenceRoundTripTests.testThreeEditSaveCycles`
- `PersistenceRoundTripTests.testMoveLayerBetweenGroups`
- `PersistenceRoundTripTests.testPixelEditPersists`
- `PersistenceRoundTripTests.testInPlacePropertyEditRequiresDirtyMark`
- `PersistenceRoundTripTests.testGroupMoveMaintainsParentInvariant`
- `PersistenceRoundTripTests.testNoPrivateMetadataIsWritten`

## 人工验证清单

每个中期 release 前手工执行：

1. 用 PSDKit 生成标准测试 PSD。
2. 用 Photoshop 打开。
3. 检查图层面板中的组、图层名、可见性、opacity、blend mode。
4. 在 Photoshop 中另存一份。
5. 用 PSDKit 打开 Photoshop 另存文件，确认支持子集仍可读取。
6. 记录不支持特性和兼容性报告表现。

## 风险

| 风险 | 缓解 |
|------|------|
| 无私有 manifest 后无法恢复自定义字段 | 中期不允许依赖 PSD 标准无法表达的画板字段 |
| 保存多轮后 layer record 顺序漂移 | 使用递归 snapshot 对比树和顺序 |
| 原位属性编辑后忘记标记 dirty | round-trip 测试强制覆盖 `markContentModified()` 与显式 semantic 保存 |
| Photoshop 会重写部分结构 | 只承诺 PSDKit 写出的 PSD；Photoshop round-trip 作为兼容性参考 |
| 像素 hash 过大影响测试速度 | 小 fixture 做精确 hash，大 fixture 做抽样或分块 hash |

