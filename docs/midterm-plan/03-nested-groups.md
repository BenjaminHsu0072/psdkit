# 子计划 3：嵌套组读写

## 目标

让 `GroupLayer` 成为真实图层模型的一等公民：

- PSDKit 能读取 Photoshop/PSDKit 写出的嵌套组。
- PSDKit 能写出 Photoshop 可识别的嵌套组。
- 图层顺序保持 `index 0 = 栈底`。
- 组内图层、空组、多层嵌套组可以反复保存不变形。

## 背景

当前代码已有 `GroupLayer` 类型，但读取路径主要把像素层平铺到根组。中期需要根据 PSD 的 Section Divider 信息构建真实树，并在写回时重新生成对应的 group boundary records。

## PSD 映射

| 画板模型 | PSD 结构 |
|----------|----------|
| `GroupLayer` | Section Divider tagged block |
| 组标题边界 | `lsct` / `lsdk` section divider，类型为 `bounding` |
| 组开始 / 结束 | 与组标题边界成对的 `openFolder` 或 `closedFolder` section divider |
| 组内子节点 | 位于 group boundary records 之间的 layer records |
| 根节点 | 不写为 PSD 图层，仅作为内存容器 |

具体 key 和 record 顺序必须通过 Photoshop 与 psd-tools fixture 验证，不能只按猜测实现。

## 顺序规范样例

中期冻结的内存树顺序：`children[0]` 是栈底，`children.last` 是栈顶。

测试必须同时断言：

- 从 PSD layer records 构建出的内存树。
- 从内存树写回后的 PSD layer records 顺序和 section divider 类型。

每个组在 manifest 中必须用成对边界表达：

```text
groupBoundary:
  title:
    name: <group name>
    section: bounding
  folder:
    name: <group name>
    section: openFolder | closedFolder
```

读取与写回都必须校验组合：

- 每个 `GroupLayer` 必须对应 1 个 `bounding` 记录和 1 个 `openFolder` 或 `closedFolder` 记录。
- `bounding` 与 folder 记录的组名必须一致，除非真实 Photoshop fixture 证明名称字段存在兼容性差异；若存在差异，manifest 必须记录 expected display name。
- `openFolder` / `closedFolder` 只表达 Photoshop 面板展开状态，不改变 `children` 语义。
- 缺少任一边界、边界嵌套不平衡、或边界顺序无法形成树时，读取返回 `corruptStructure`。

### 样例 A：兄弟混排

期望内存树：

```text
root
├── BG
├── Group A
│   ├── A-1
│   └── A-2
└── FG
```

期望语义：

- `BG` 为最底层。
- `FG` 为最顶层。
- `A-1` 在 `A-2` 下方。
- `Group A` 位于 `BG` 上方、`FG` 下方。

PSD raw record 样例必须在 fixture manifest 中显式记录：

```text
records:
  - name: BG
    kind: pixel
  - name: Group A
    kind: sectionBoundary
    section: bounding
  - name: A-1
    kind: pixel
  - name: A-2
    kind: pixel
  - name: Group A
    kind: sectionBoundary
    section: openFolder
  - name: FG
    kind: pixel
```

验收断言：

- 读取后 `root.children.map(\.name) == ["BG", "Group A", "FG"]`。
- `Group A.children.map(\.name) == ["A-1", "A-2"]`。
- manifest 中 `Group A` 同时存在 `bounding` 与 `openFolder` 记录，且二者成对。
- 写回后 manifest 中的 raw record 名称和 `section` 值与 fixture 真值一致。

### 样例 B：空组

期望内存树：

```text
root
├── BG
├── Empty Group
└── FG
```

PSD raw record 样例必须在 fixture manifest 中显式记录：

```text
records:
  - name: BG
    kind: pixel
  - name: Empty Group
    kind: sectionBoundary
    section: bounding
  - name: Empty Group
    kind: sectionBoundary
    section: openFolder
  - name: FG
    kind: pixel
```

验收断言：

- 读取后 `Empty Group.children.isEmpty == true`。
- 保存后 Photoshop 图层面板仍显示空组。
- 写回后 raw record 中仍存在 `Empty Group` 的 `bounding` 与 `openFolder` 成对 section boundary records。

说明：上面的 raw record 顺序是计划冻结的测试真值格式；如果通过 Photoshop fixture 发现实际 PSD 存储顺序需要反转，应先更新本节和 fixture manifest，再实现代码。

## Manifest Schema 要求

每个 group fixture 的 manifest 必须同时记录树结构与 raw records：

```text
expectedTree:
  - name: BG
    kind: pixel
  - name: Group A
    kind: group
    children:
      - name: A-1
        kind: pixel
      - name: A-2
        kind: pixel

rawRecords:
  - name: BG
    kind: pixel
  - name: Group A
    kind: sectionBoundary
    section: bounding
    pairId: group-a
  - name: A-1
    kind: pixel
  - name: A-2
    kind: pixel
  - name: Group A
    kind: sectionBoundary
    section: openFolder
    pairId: group-a
```

`pairId` 是测试 manifest 内部字段，不写入 PSD。它用于自动断言 `bounding` 与 `openFolder` / `closedFolder` 的成对关系。

## 设计任务

1. 明确内存树顺序：`children[0]` 为栈底，`children.last` 为栈顶。
2. 明确 PSD layer record 顺序与内存顺序的转换规则。
3. 定义空组、嵌套组、组可见性、组 opacity、组 blend mode 的行为。
4. 冻结 group blend mode：公开可编辑模式仍只有 `normal` / `multiply` / `add`；`pass-through` 仅作为读取和写入组边界时的内部 PSD 语义，不暴露给像素层创建 API。
5. 定义错误处理：遇到不匹配的 section boundary 时返回 `corruptStructure`。
6. 定义父子关系不变量：`append` / `insert` / `remove` / `move` 后，`child.parent` 必须与所在父容器一致。

## 实施任务

1. 新增 `LayerTreeBuilder` 或重构 `DocumentBuilder`，从 layer records 构建树。
2. 解析 Section Divider tagged block，识别 group start/end。
3. 写入时从 `GroupLayer` 树生成扁平 layer records。
4. 确保 `append`、`insert`、`remove` 能作用于任意组。
5. 更新 Viewer 图层列表，按嵌套深度缩进展示。
6. 增加 group fixture 和 golden manifest，manifest 必须包含 raw record 顺序与期望树结构。
7. 为组编辑 API 增加 parent 不变量断言。

## Fixture 矩阵

| Fixture | 覆盖点 |
|---------|--------|
| `group-single-layer` | 一个组包含一个像素层 |
| `group-two-layers` | 一个组包含多个像素层 |
| `group-nested-2-level` | 两层嵌套组 |
| `group-nested-3-level` | 三层嵌套组 |
| `group-empty` | 空组 |
| `group-hidden` | 隐藏组 |
| `group-opacity` | 组 opacity |
| `group-sibling-order` | 组与普通图层混排 |

## 验收步骤

1. 用 psd-tools 或 Photoshop 生成 `group-single-layer`，PSDKit 读取后根组包含一个 `GroupLayer`，该组包含一个 `PixelLayer`。
2. 读取 `group-nested-3-level`，断言每层 group 名称、深度、子节点数量正确。
3. 新建含空组的 PSD，保存后 Photoshop 图层面板能看到空组。
4. 新建含组和普通图层混排的 PSD，保存后 Photoshop 中视觉堆叠顺序正确。
5. 对一个嵌套组 PSD 执行 `open -> save -> open`，断言树结构完全一致。
6. 在组内新增、删除、重命名图层，保存后再次读取，修改保持正确。
7. 对每个 group fixture 同时断言期望树结构和 raw record 顺序。
8. 对每个 group fixture 断言 `bounding` 与 `openFolder` / `closedFolder` 通过 `pairId` 成对，缺失或多余都失败。
9. 对 `append`、`insert`、`remove`、`move` 后的节点断言 `child.parent` 与父容器一致。
10. 运行 `swift test`，既有扁平图层 fixture 不回归。
11. Viewer 展示嵌套组时有缩进，用户能区分组和像素层。

## 测试建议

- `LayerTreeBuilderTests.testReadsSingleGroup`
- `LayerTreeBuilderTests.testReadsNestedGroups`
- `LayerTreeBuilderTests.testRejectsUnbalancedSectionDividers`
- `GroupWriteTests.testWritesEmptyGroup`
- `GroupWriteTests.testNestedGroupRoundTrip`
- `GroupWriteTests.testRawRecordOrderMatchesManifest`
- `GroupWriteTests.testSectionDividerPairsMatchManifest`
- `DocumentEditTests.testAppendLayerInsideGroup`
- `DocumentEditTests.testGroupEditMaintainsParentInvariant`

## 风险

| 风险 | 缓解 |
|------|------|
| PSD layer record 顺序容易反 | 每个 group fixture 同时断言结构和像素堆叠 |
| Photoshop 与 psd-tools 对空组表现不同 | 以 Photoshop 可打开和 psd-tools 可读为双验收 |
| 组 pass-through 语义复杂 | 中期先明确画板语义，只支持可稳定往返的行为 |
| 旧扁平 API 被破坏 | 保留根组遍历辅助方法，更新 README 示例 |

