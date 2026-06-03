# 参考实现备忘（实施用）

实施 PSDKit 时固定对照以下项目（详见 [01-landscape.md](./01-landscape.md)）：

| 子问题 | 参考 |
|--------|------|
| 二进制分段 / LayerRecord | psd-tools `psd/layer_and_mask.py` |
| Extra 长度 `xI`（1 字节 pad + UInt32） | psd-tools `read_length_block(..., fmt="xI")` |
| PackBits RLE | psd-tools `compression/rle.py` |
| 行表 RLE 解压 | psd-tools `decode_rle` |
| 测试 fixture | `Scripts/generate_fixtures.py` + psd-tools |
| 写盘（后续） | ag-psd、pytoshop、JPSD |

规范：[Adobe PSD Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
