# WSL2 <-> VMware 嵌套虚拟化切换工具

这个工具用于在两种 Windows 启动模式之间切换：

- WSL2 模式：启用 WSL2 所需的 Windows 功能，并设置 `hypervisorlaunchtype=auto`。
- VMware 模式：设置 `hypervisorlaunchtype=off`，让 VMware 在重启后尽量独占 VT-x/AMD-V，恢复虚拟机里的嵌套虚拟化能力。

它不会转换 WSL 发行版，也不会修改 VMware 虚拟机数据；它只切换 Windows 是否在启动时加载自己的 hypervisor。

## 文件说明

- `WSL2-VMware-Switch.ps1`：主脚本。
- `Run-Switch-Menu.cmd`：打开交互菜单。
- `Switch-To-WSL2.cmd`：直接切换到 WSL2 模式。
- `Switch-To-VMware.cmd`：直接切换到 VMware 模式。

旧兼容入口和装饰图片已经移除，日常只需要保留上面 4 个文件。

## 安装

1. 将整个文件夹放到一个固定位置，例如 `D:\Tools\hyperv-wsl2-switch`。
2. 如果 Windows 提示脚本来自互联网而被阻止，右键 `.ps1` 文件打开“属性”，勾选“解除锁定”，或在 PowerShell 中执行：

```powershell
Unblock-File .\WSL2-VMware-Switch.ps1
```

3. 建议使用 `.cmd` 文件启动；它们会调用主脚本并自动请求管理员权限。

## 使用

双击其中一个文件：

- `Run-Switch-Menu.cmd`：打开菜单，在菜单里选择 WSL2 或 VMware。
- `Switch-To-WSL2.cmd`：启用 WSL2 所需功能，并允许 Windows Hypervisor 启动。
- `Switch-To-VMware.cmd`：关闭 Windows Hypervisor 启动，让 VMware 在重启后使用硬件虚拟化。

切换完成后必须重启 Windows 才会真正生效。

## 命令行用法

查看当前状态：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode Status
```

切换到 WSL2：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode WSL2
```

切换到 VMware：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode VMware
```

如果 VMware 仍提示 Hyper-V 或 VBS 正在运行，可以使用彻底模式禁用相关 Windows 可选功能：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode VMware -DisableFeaturesForVmware
```

彻底模式会禁用 `Virtual Machine Platform`、`Hyper-V` 和 `Windows Hypervisor Platform`；回到 WSL2 模式时，脚本会重新启用 WSL2 所需功能。

## 核心原理

脚本的核心操作对应这两条 BCD 设置：

```powershell
bcdedit /set hypervisorlaunchtype auto  # WSL2 模式
bcdedit /set hypervisorlaunchtype off   # VMware 模式
```

WSL2 需要 Windows Hypervisor；VMware 嵌套虚拟化通常需要 Windows Hypervisor 不在启动时占用 VT-x/AMD-V。

## 注意事项

- 这不是热切换工具，`bcdedit` 和 Windows 可选功能变更都需要重启后才会生效。
- 如果 VMware 模式重启后仍不可用，请检查“Windows 安全中心 -> 设备安全性 -> 核心隔离 -> 内存完整性”。
- 如果你手动关闭过 Windows 可选功能，回到 WSL2 模式后可能需要再重启一次。
