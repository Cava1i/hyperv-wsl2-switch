# WSL2 <-> VMware 嵌套虚拟化一键切换工具

<p align="center">
  <img src="assets/switch-decoration.svg" alt="" width="760">
</p>

用于在两种 Windows 启动模式之间切换：

- WSL2 模式：启用 WSL2 所需的 WSL、Virtual Machine Platform，并设置 `hypervisorlaunchtype=auto`。
- VMware 嵌套虚拟化模式：设置 `hypervisorlaunchtype=off`，重启后让 VMware 尽量独占 VT-x/AMD-V，从而恢复客户机里的嵌套虚拟化能力。

这里的“切换”不是转换 WSL 发行版或 VMware 虚拟机数据，而是切换 Windows 是否启动自己的 hypervisor。开启 WSL2 时 Windows Hypervisor 会占用虚拟化能力；切到 VMware 模式后，VMware 才更容易恢复嵌套虚拟化。

核心操作对应下面两条 BCD 设置：

```powershell
bcdedit /set hypervisorlaunchtype auto  # WSL2 模式
bcdedit /set hypervisorlaunchtype off   # VMware 嵌套虚拟化模式
```

## 使用方法

双击其中一个文件：

- `Run-Switch-Menu.cmd`：打开菜单，菜单里只保留两个切换入口。
- `Switch-To-WSL2.cmd`：直接切到 WSL2 模式。
- `Switch-To-VMware.cmd`：直接切到 VMware 嵌套虚拟化模式。

脚本会自动请求管理员权限。切换后必须重启 Windows 才会生效。

## 常用命令

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode Status
powershell.exe -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode WSL2
powershell.exe -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode VMware
```

如果 VMware 模式下仍然提示 Hyper-V 或 VBS 正在运行，可以改用彻底模式：

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\WSL2-VMware-Switch.ps1 -Mode VMware -DisableFeaturesForVmware
```

旧文件名 `HyperV-WSL2-Switch.ps1` 仍保留为兼容入口，会自动转到新脚本。

同时检查：

- Windows 安全中心 -> 设备安全性 -> 核心隔离 -> 内存完整性
- Windows 功能里的 Hyper-V、Virtual Machine Platform、Windows Hypervisor Platform

## 注意

这不是热切换工具。`bcdedit` 和 Windows 可选功能的变化都需要重启后才会真正生效。
