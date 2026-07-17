# MATLAB EEG wPLI + fsaverage 可视化

一个面向事件相关EEG的MATLAB/FieldTrip分析流程，用于计算59导或64导传感器空间的去偏平方加权相位滞后指数（debiased squared wPLI），并将网络投影到FreeSurfer `fsaverage`皮层表面进行展示。

> 研究状态：预实验代码。当前固定6个试次的设置用于流程核对，不代表已经建立可靠的临床诊断模型。

> **导数处理说明（发布版重点标注）**：代码不会把59导补成64导，也不会把64导删成59导。程序按FIF中实际标记为EEG的通道原样计算：59导输出59×59矩阵，64导输出64×64矩阵。项目数据审计得到19条64导记录和12条59导记录，两套固定导联只有54个共同通道；因此两种矩阵不得直接合并或逐边比较。正式联合分析必须限定同一布局，或从原始记录中统一提取54个公共通道后重新计算，不能对连接矩阵补零或插值。

English summary: [README_EN.md](README_EN.md)

## 功能

- 从连续MNE FIF读取59导或64导EEG。
- 当FieldTrip无法读取MNE annotations时，自动导入`markers.csv`。
- 兼容3列和4列事件表。
- 事件后0.5-2.5秒分段、线性去趋势和峰峰值质量控制。
- 固定随机种子选择相同数量的合格试次。
- 减去跨试次诱发平均，降低共同事件锁定成分。
- 使用DPSS多窗频谱和FieldTrip `wpli_debiased`。
- 输出delta（1-4 Hz）、theta（4-8 Hz）、alpha（8-13 Hz）和beta（13-30 Hz）连接矩阵，矩阵大小与EEG导数一致。
- 输出矩阵图、二维网络图和fsaverage三维投影图。
- 批处理支持扫描、预实验、全量运行、断点续跑及错误记录。
- 59导记录可以生成59x59矩阵和图片，图标题及CSV会标注“仅个体展示”。
- 导数按输入FIF中的实际EEG通道保留，不补导、不删导、不对连接矩阵补零或插值。
- 除59导、64导外的记录自动标记为`跳过-不支持的导数`。

## 依赖

- MATLAB R2020a或更新版本，开发时使用R2024b。
- [FieldTrip](https://www.fieldtriptoolbox.org/)。
- FreeSurfer `fsaverage`目录，至少包含：
  - `surf/lh.pial`
  - `surf/rh.pial`
- 预处理后的连续FIF及对应事件CSV。

本仓库不包含FieldTrip、fsaverage、MATLAB、MNE或任何参与者数据。

## 仓库结构

```text
matlab-eeg-wpli-fsaverage/
├─ batch/
│  └─ run_batch_wpli_fsaverage.m
├─ examples/
│  └─ run_single_subject_example.m
├─ src/
│  ├─ compute_one_subject_wpli.m
│  └─ render_one_wpli_fsaverage.m
├─ tools/
│  └─ check_environment.m
├─ docs/
│  ├─ 使用教程.md
│  ├─ 数据目录规范.md
│  ├─ 方法说明与解释边界.md
│  └─ GitHub发布步骤.md
├─ LICENSE
├─ NOTICE.md
└─ README.md
```

## 快速开始

### 1. 环境检查

```matlab
repo_root = 'path/to/matlab-eeg-wpli-fsaverage';
addpath(fullfile(repo_root, 'tools'));
check_environment('path/to/fieldtrip', 'path/to/fsaverage');
```

### 2. 单条记录

打开`examples/run_single_subject_example.m`，填写：

```matlab
fieldtrip_dir = 'path/to/fieldtrip';
input_fif = 'path/to/ica_clean.fif';
output_dir = 'path/to/output/sub-001/phase1';
fsaverage_dir = 'path/to/fsaverage';
```

被试标识应脱敏，例如：

```matlab
subject_id = 'sub-001';
```

### 3. 批处理

打开`batch/run_batch_wpli_fsaverage.m`，填写四个目录。第一次保持：

```matlab
run_mode = 'all';
scan_only = true;
```

检查扫描表后运行少量预实验：

```matlab
run_mode = 'pilot';
pilot_count = 4;
scan_only = false;
```

预实验通过后再全量运行：

```matlab
run_mode = 'all';
scan_only = false;
overwrite_existing = false;
```

详细步骤见[使用教程](docs/使用教程.md)。

## 核心处理参数

| 参数 | 当前值 | 说明 |
|---|---:|---|
| 时间窗 | 0.5-2.5 s | 相对于目标事件 |
| 峰峰值阈值 | 500 uV | 任一通道超阈值则剔除整试次 |
| 固定试次数 | 6 | 预实验设置，正式研究前必须评估可靠性 |
| 频谱方法 | DPSS multitaper | `mtmfft`，1 Hz平滑半带宽 |
| delta | 1-4 Hz | 1 Hz纳入，4 Hz归入theta |
| theta | 4-8 Hz | 4 Hz纳入，8 Hz归入alpha |
| alpha | 8-13 Hz | 8 Hz纳入，13 Hz归入beta |
| beta | 13-30 Hz | 13 Hz和30 Hz均纳入 |
| 连接方法 | `wpli_debiased` | 去偏平方wPLI，不是普通wPLI |

四个频段使用左闭右开的频点分配规则，最后一个beta频段包含30 Hz。因此边界频点只进入一个频段，不会在相邻频段中重复计算。DPSS频谱平滑仍会使边界附近信息存在一定混合，解释窄频段差异时需保守。

## 输出

每条记录独立输出：

```text
sub-001_phase1_O_去偏平方wPLI.mat
sub-001_phase1_O_去偏平方wPLI.png
sub-001_phase1_O_去偏平方wPLI_fsaverage脑表面.png
sub-001_phase1_O_去偏平方wPLI_fsaverage节点映射.mat
```

MAT文件同时保存`delta_matrix`、`theta_matrix`、`alpha_matrix`和`beta_matrix`，并保留旧版下游程序常用的`theta_matrix`、`alpha_matrix`变量名。二维PNG上排为四个连接矩阵，下排为四个最强连接网络；fsaverage PNG为2×2四频段脑表面图。

从v0.1.x升级后，旧MAT只有theta/alpha。批处理会检查四个矩阵字段；即使`overwrite_existing=false`，旧双频段结果也会自动重新计算，不会被误判为完整结果。

批处理另生成进度表和最终汇总表，记录成功、失败、已有结果跳过、59导个体展示及不支持导数跳过。

## 重要解释边界

1. `wpli_debiased`是去偏平方估计；少试次时出现负值不表示“负连接”。
2. fsaverage图是头皮传感器网络的皮层表面投影，不是源空间功能连接。
3. 不得将ECG/EOG通道补成EEG节点，也不应通过插值制造缺失连接节点。
4. 59导和64导输出不得直接合并或逐边比较；正式组间比较前必须统一节点集合或限定同一布局。
5. 六试次矩阵可能不稳定。必须进行分半可靠性、重抽样或其他稳定性评估。

本项目当前两套布局的交集为54个EEG通道。这里的“54”是59导与64导通道名称的交集，不是程序漏读，也不是把数据主动降为54导。只有在预先确定公共节点分析方案后，才可从每条原始记录提取这54个通道并重新计算54×54连接矩阵。

详见[方法说明与解释边界](docs/方法说明与解释边界.md)。

## 数据与隐私

- 不要上传FIF、SET、FDT、事件表、分析结果或真实姓名。
- 仓库已提供`.gitignore`，但提交前仍应执行人工隐私审查。
- 示例一律使用`sub-001`等脱敏标识符。

## 许可证

本项目代码采用MIT许可证。第三方软件、模板和数据遵循各自许可证，见[NOTICE.md](NOTICE.md)。

首次公开仓库的具体命令见[GitHub发布步骤](docs/GitHub发布步骤.md)。
