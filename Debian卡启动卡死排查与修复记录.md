# 自定义 Debian 卡启动卡死排查与修复记录

> 板卡：Atlas 200I DK A2（hostname `davinci-mini`，Hi1910B SoC + 昇腾 310B NPU，boardid 51150）
> 固件：BIOS/UEFI **0.23.00**，**secure boot 开启**（`secure boot:1`）
> 内核：`6.6.0-72.0.0.76.h914.eulerosv2r15.ascend.aarch64`（25.5.0 包，两卡相同）
> 排查时间：2026-08-17
> 结果：**已修复**，自定义 Debian 11 rootfs 卡正常启动

---

## 1. 背景

用 `make_os_sd.sh` / `make_sd_card.py` 的 `local` 流程，从 `rootfs_Custom/rootfs.tar.bz2`
（预构建 Debian 11 bullseye）制作 SD 卡后，插到 Atlas 200I DK A2 上**启动卡死**。

对比对象：同一块板子上**另一张能正常启动**的卡（Ubuntu 22.04 + 昇腾 davinci 驱动，同为 6.6 内核）。

---

## 2. 症状

串口输出到如下位置后**一个字符都不再打印**：

```
jump kernel(3426).
[    0.000000][    T0] Booting Linux on physical CPU ...
[    0.000000][    T0] Linux version 6.6.0-72.0.0.76.h914.eulerosv2r15.ascend.aarch64 ...
[    0.000000][    T0] KASLR disabled due to lack of seed
[    0.000000][    T0] Machine model: Hisilicon PhosphorHi1910B evb
[    0.000000][    T0] earlycon: pl11 at MMIO32 0x00000000c4010000
[    0.000000][    T0] printk: bootconsole [pl11] enabled
[    0.000000][    T0] parse cmdline param err, kbox reserve memory max size = 0x8000000, cur size = 0x0
   ← 内核在这里之后卡死，无 cacheinfo、无 pinctrl、无 systemd
NOTICE:  (ATF RAS UE：MATA0 DDR 错误处理)
cpu 0 entering scheduler
>>>>>>>>>>>>LiteOS start succeed!<<<<<<<<<<<
```

正常卡在同一位置之后继续打印 `cacheinfo`(0.004879s)、`Initramfs unpacking failed`(0.052788s)、
pinctrl(0.147s)、`Welcome to Ubuntu`、systemd(11s)、`login:`。

**关键判断：卡点在 t=0 之后、cacheinfo 之前，是极早期内核初始化阶段，尚未接触 rootfs。**

---

## 3. 排查过程

### 3.1 排除 rootfs（内核没碰到它）

- 卡点在内核 t=0，早于任何文件系统访问。
- 挂载 Debian rootfs / p4 / p5 检查：**没有任何 systemd 启动痕迹**（`/var/log`、`/run` 等全是 make 时的时间戳），
  无 `/var/mini_upgraded`，无 `/etc/ascend_install.info` 的运行时更新。
- → rootfs 不是启动卡死的原因。

### 3.2 secure boot 禁止修改 dt.img（重要约束）

给 dt.img 改 bootargs（`loglevel=5`→`8`）做诊断实验后，板子报：

```
ERROR: hw_cms_check_hash fail! ... Image Auth Fail, 0x5000AA0C! Check Device Tree fail
LoadAndStartOS:[1734L]: Image check process Status = Security Violation.
```

**结论：UEFI 用 CMS hash 校验 dt.img，任何一个字节的改动都会破坏签名 → dt.img 无法就地补丁，
必须整份替换为已签名、且被本板接受的 dt.img。**

### 3.3 固件逐字节对比（锁定唯一差异）

提取正常卡的固件（A 槽：Image@16M 前 31416290B、dt.img@56M 整 2MB、itrustee@60M 前 3162786B）与 25.5.0 包 `.run` 内固件对比：

| 固件 | 25.5.0 包 | 正常卡 | 结果 |
|---|---|---|---|
| Image（内核） | `4732c5dadee2fa5d4b020a2543a7e2507ada1caa406364917511972da68ad108` | 相同 | ✅ 完全相同 |
| itrustee.img | `6cc1965500fbdb6738a52e2e3c342c26025990e86728252a8a914e6159017281` | 相同 | ✅ 完全相同 |
| dt.img | `c25e39d3af7e508863108353a9610d10031735a1cfd2467dd266baf7db7c1bc9`（15 棵 DTB，640754B） | `e4221134…`（17 棵 DTB，750375B） | ❌ **唯一固件差异** |

- 正常卡 dt.img 容器：`aa55aa55` 头 + 17 棵 DTB，bootargs 用 **`log_redirect=0x1fc000@0x22741000`**
- 25.5.0 dt.img 容器：`aa55aa55` 头 + 15 棵 DTB，bootargs 用 **`ascend_log_redirect=0x1fc000@0x22741000`**

### 3.4 bootargs 差异（根因所在）

反编译两卡 DTB[0] 的 `chosen.bootargs` 对比：

| 参数 | 正常卡（能启动） | 25.5.0（卡死） |
|---|---|---|
| 日志重定向 | `log_redirect=` | `ascend_log_redirect=` |
| 独有参数 | — | `arm_smmu_v3.disable_btm=1` |
| 独有参数 | — | `fw_devlink=permissive` |
| 独有参数 | — | `cgroup.memory=kmem,nounreliable` |
| 独有参数 | — | **`enable_acpi_dt_apei`** |
| 其余 | 完全相同（enable_fpga、loglevel=5、earlycon、root=/dev/mmcblk1p1、initrd=0x2BA00000,300M…） | 相同 |

- 内核 __setup 参数表里**同时**定义了 `ascend_log_redirect=` 与 `log_redirect=`（四个 redirect 参数），
  参数名本身都是合法的，但两者触发不同的日志重定向代码路径。
- 两卡 DTB 的 memory 节点**逐字节相同**，排除内存布局差异。
- t=0 恰好有 MATA0 DDR RAS UE 事件（两卡都有），而 **`enable_acpi_dt_apei` 只在 25.5.0 的 bootargs 里**，
  让内核注册 APEI/事件处理 → 与早期 RAS UE 处理直接相关。

**根因：25.5.0 包配套的 dt.img（bootargs/DTB 节点）与这块板的 BIOS 0.23.00 不兼容，
内核在极早期初始化阶段卡死。正常卡使用的是旧版（`log_redirect`）dt.img，与本板 BIOS 匹配。**

---

## 4. 修复

因 secure boot 限制，不能改 dt.img 内容，只能**整份替换为正常卡的 dt.img**（该 dt.img 在这块板上已通过校验）。

### 4.1 关键布局（310B SD 卡，扇区=512B）

| 组件 | A 槽 | B 槽 | 说明 |
|---|---|---|---|
| Image | 16M（32768s） | 144M（294912s） | 内核，30MB |
| **dt.img** | **56M（114688s）** | **184M（376832s）** | 2MB 槽位（DTB_OFFSET=81920s） |
| itrustee | 60M（90112s） | 188M | 4MB |
| initrd | 320M | — | 150MB（SD 启动不使用，`invalid magic` 被容忍） |
| boot_image_info | 2304s（BOOTIMGDIR_OFFSET） | — | 组件 offset/size 表，bootloader 按它读取 |
| partition_head_info | 2048s（HEAD_OFFSET），备份 2176s | — | 分区头 |

boot_image_info 解码（`aa55aa55` + 设备路径 `/dev/mmcblk1p2` + 组件表）：
仓库版用**取整 size**（kernel 40M / dtb 2M / tee 4M），正常卡用**实际 size**（kernel 31416290 / **dtb 610560** / tee 3162786）。
bootloader 按 boot_image_info 的 size 读取并校验固件区域，因此**必须连 boot_image_info 一起换**。

### 4.2 执行（脚本 `/home/shawn/fix_debian_dtb.sh /dev/sdb`）

1. **安全确认**：挂载目标卡 p2 检查 `/etc/debian_version` = `Debian GNU/Linux 11 (bullseye)`，
   防止误写正常卡。
2. **备份**：A/B 槽(各2MB) + boot_image_info → `/home/shawn/backup_debian_20260817_085156/`
   （回滚：把备份文件 dd 反向写回对应槽位）。
3. **写入**：
   - `normal_dtA.bin`（2MB）→ A 槽 56M
   - `normal_dtB.bin`（2MB）→ B 槽 184M
   - `normal_boot_image_info.bin` → 2304s
4. **校验**：写入后重读哈希全部与源文件一致（A/B 槽 `95ebef14…`，BII `49ca21f1…`）。

### 4.3 验证

上电后正常启动：内核继续打印 cacheinfo → pinctrl → **Debian 11** 的 systemd 序列 → `login:`。
✅ 修复生效。

---

## 5. 修复已固化到 make 流程（`firmware_fix/`）

修复不再依赖手工 `fix_debian_dtb.sh`，已直接打进 **`make_os_sd.sh` + `make_sd_card.py`**：
新制卡（SD 卡 310B 流程）写好 dt.img 与 boot_image_info 后即可直接启动。

### 5.1 仓库新增 `firmware_fix/`

| 文件 | 来源（宿主机良品） | 说明 |
|---|---|---|
| `firmware_fix/dt.img` | `/home/shawn/normal_dtA.bin`（= normal_dtB.bin，哈希 `95ebef14…`） | 正常卡 A/B 槽 dt.img 原始 2MB，BIOS 0.23.00 兼容 |
| `firmware_fix/boot_image_info` | `/home/shawn/normal_boot_image_info.bin`（哈希 `49ca21f1…`） | 配套 struct info，**dtb size = 0x95100 (610560)** |

> 该对与正常卡上已验证的组合**逐字节一致**。`firmware_fix/` 目录存在即启用修复；删除目录即回退到「用包内 dt.img + emmc-head 生成的 boot_image_info」。

### 5.2 `make_os_sd.sh` 三处改动

1. **`writeStructInfo()`（约 2340 行）**：写 2304s 的 `boot_image_info` 时，若 `firmware_fix/boot_image_info` 存在则优先用它，
   否则才用 `${ScriptPath}boot_image_info`（后者会被 `emmc-head` 用包内固件实际大小重写，dtb 变成 0x9c6f2=640754，是错的）。
2. **`write310BComponents()`（约 2410 行）**：写 A/B 槽（56M/184M）的 `dt.img` 时，若 `firmware_fix/dt.img` 存在则优先用它，
   否则才用 `${FWM_DIR}dt.img`（25.5.0 包内 dt.img，BIOS 0.23.00 下启动卡死）。
3. **`preInstallMinirc310BPackage()`（约 2087 行）**：把良品 `dt.img` 同步覆盖到 rootfs `/fw/dt.img`，
   保证 rootfs 里的固件与启动槽位一致，避免后续 OS 内恢复/升级引用到坏的 25.5.0 dt.img。

关键点：bootloader 按 `boot_image_info` 里的 dtb size 读取并 CMS 校验固件区域，所以 **dt.img 与 boot_image_info 必须成套替换**；
`firmware_fix/` 中两者同源（都来自正常卡），成套后 dtb=610560 与槽内 2MB 槽位一致。

### 5.3 `make_sd_card.py` 改动

`check_firmware_fix()`（约 167 行）：做卡前检查 `firmware_fix/` 是否齐全，并在 `check_minirc_run_package()` 中调用。
- 存在 → 打印 `[INFO]`，说明会写入良品 dt.img/boot_image_info。
- 缺失 → 打印 `[WARN]`，提示 25.5.0 卡在 BIOS 0.23.00 下可能卡死。

### 5.4 验证

- `bash -n make_os_sd.sh`、`python3 -m py_compile make_sd_card.py` 均通过。
- `firmware_fix/dt.img` 大小 2097152B = DTB_SIZE(4096)×512，写入完整覆盖 2MB 槽位。
- 下一次完整做卡后应直接能启动；建议留一次全新做卡日志以最终确认。

---

## 6. 遗留事项

1. **网卡/驱动**：Debian 11 是精简 rootfs，需确认 `hclgeplf`/`broadcom` 等驱动是否就绪（参考《网卡排查与修复记录.md》），
   以及 `npu-smi` 是否可用、NPU 设备是否注册（`ls /dev/davinci*`）。
2. **dt.img 版本匹配**：25.5.0 包的 dt.img 面向**新版 BIOS**，本板 BIOS 0.23.00 需搭配旧版 dt.img。
   若日后升级板子 BIOS，25.5.0 的 dt.img 或许可用，需重新验证（届时可删除 `firmware_fix/` 恢复默认行为）。
3. **启动日志**：`error.log`/`error2.log`/`normal.log`/`fix_test.log` 均为排查留档。

---

## 7. 相关文件

**仓库内（`Ascend200IA2/`）**

| 文件 | 说明 |
|---|---|
| `firmware_fix/dt.img` | 良品 dt.img（正常卡 A 槽 2MB 原始，BIOS 0.23.00 兼容） |
| `firmware_fix/boot_image_info` | 良品 boot_image_info（dtb size 610560，与 dt.img 配套） |
| `make_os_sd.sh` | 已固化修复（writeStructInfo / write310BComponents / preInstallMinirc310BPackage） |
| `make_sd_card.py` | 已加 `check_firmware_fix()` 提示 |

**宿主机**

| 文件 | 说明 |
|---|---|
| `/home/shawn/fix_debian_dtb.sh` | 手工修复脚本（已不再需要，留作参考/回滚） |
| `/home/shawn/normal_dtA.bin` `normal_dtB.bin` | 正常卡 A/B 槽 dt.img 原始 2MB |
| `/home/shawn/normal_boot_image_info.bin` | 正常卡 boot_image_info |
| `/home/shawn/backup_debian_20260817_085156/` | Debian 卡修复前备份（回滚用） |
| `/home/shawn/runpkg/firmware/` | 25.5.0 包解出的固件（Image/dt.img/itrustee/initrd…） |
| `/home/shawn/dtb0_25.5.0.dtb|.dts` / `dtb0_normal.dtb|.dts` | 两卡 DTB[0] 反编译对比 |
| `/home/shawn/parse_container*.py` `dtb_props.py` `dump_dtb.py` | dt.img 容器/DTB 解析脚本 |
