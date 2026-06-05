# PSDKit 中期计划

> 目标：把 PSDKit 推进到可以用 `.psd` 作为画板持久化格式的阶段。  
> 边界：只承诺 **PSDKit 支持子集** 内的无损往返；遇到不支持的 PSD 特性时提示并降级或丢弃。

## 总览

| 文档 | 说明 |
|------|------|
| [00-overview.md](./00-overview.md) | 中期目标、边界、里程碑与依赖关系 |
| [01-supported-subset.md](./01-supported-subset.md) | PSDKit 支持子集与降级规则 |
| [02-compatibility-report.md](./02-compatibility-report.md) | 打开 PSD 时的兼容性报告 |
| [03-nested-groups.md](./03-nested-groups.md) | 嵌套组读写计划 |
| [04-blend-modes.md](./04-blend-modes.md) | `normal` / `multiply` / `add` 混合模式 |
| [05-roundtrip-persistence.md](./05-roundtrip-persistence.md) | `.psd` 持久化往返测试 |
| [06-performance.md](./06-performance.md) | 性能基准与优化计划 |

## 执行原则

- `.psd` 是画板中期的唯一持久化格式。
- 不写私有 manifest 或私有元数据；所有持久化状态必须能由标准 PSD 结构表达。
- 打开 PSD 只有一个入口；可安全降级并继续打开的场景生成兼容性报告，文件级硬拒绝直接返回错误且不生成报告。
- `add` 映射 Photoshop 的 **Linear Dodge (Add)**。
- 优先保证 PSDKit 自己写出的文件能反复打开、编辑、保存，不丢失当前支持子集内的数据。

