# Flathub Manager

Flathub Manager 是一个强大的 Flatpak 应用管理工具，专为 Linux 用户设计，用于批量管理 Flathub 应用。

## 功能特点

- **批量管理**: 同时处理多个 Flatpak 操作
- **智能排序**: 按应用大小和安装时间排序
- **分类筛选**: 按类型(system/user)、状态(已安装/可更新)筛选
- **自动清理**: 一键清理孤立依赖
- **安全设计**: 本地执行、不收集隐私、无需root权限

## 依赖要求

- Linux 操作系统
- Flatpak 已安装
- Bash 4.0+
- 标准Unix工具: awk, sed, grep, cut

## 安装

### 方式一: 使用install脚本 (推荐)

```bash
git clone https://github.com/zrwloveyl/flathub-manager.git
cd flathub-manager
chmod +x install.sh
./install.sh
```

### 方式二: 手动安装

```bash
git clone https://github.com/zrwloveyl/flathub-manager.git
cd flathub-manager
chmod +x flathub-manager.sh
# 将脚本添加到PATH或直接运行
./flathub-manager.sh
```

## 使用方法

```bash
# 查看帮助
flathub-manager.sh -h

# 列出所有已安装的flatpak
flathub-manager.sh -l

# 列出可更新的应用
flathub-manager.sh -u

# 批量更新所有应用
flathub-manager.sh -U

# 清理孤立依赖
flathub-manager.sh -c
```

## 适用场景

- Linux 桌面用户
- 需要批量管理 Flatpak 应用的用户
- 希望清理系统空间的用户
- 需要定期更新应用的用户

## 截图

![Flathub Manager 截图](assets/screenshot.png)

## 安全设计

- 所有操作在本地执行，不上传任何数据
- 不需要 root 权限
- 不修改系统关键文件
- 只操作 Flatpak 相关目录


---

## Features

- **Batch Management**: Handle multiple Flatpak operations simultaneously
- **Smart Sorting**: Sort by app size and installation time
- **Filter Options**: Filter by type (system/user) and status (installed/updatable)
- **Auto Cleanup**: Clean orphaned dependencies with one click
- **Secure Design**: Local execution, no privacy collection, no root required

## Requirements

- Linux operating system
- Flatpak installed
- Bash 4.0+
- Standard Unix tools: awk, sed, grep, cut

## Installation

### Method 1: Using install script (Recommended)

```bash
git clone https://github.com/zrwloveyl/flathub-manager.git
cd flathub-manager
chmod +x install.sh
./install.sh
```

### Method 2: Manual Installation

```bash
git clone https://github.com/zrwloveyl/flathub-manager.git
cd flathub-manager
chmod +x flathub-manager.sh
# Add to PATH or run directly
./flathub-manager.sh
```

## Usage

```bash
# Show help
flathub-manager.sh -h

# List all installed flatpaks
flathub-manager.sh -l

# List updatable apps
flathub-manager.sh -u

# Batch update all apps
flathub-manager.sh -U

# Clean orphaned dependencies
flathub-manager.sh -c
```

## Use Cases

- Linux desktop users
- Users who need batch management of Flatpak apps
- Users who want to clean up system space
- Users who need to regularly update apps

## Screenshot

![Flathub Manager Screenshot](assets/screenshot.png)

## License

MIT License

## Contributing

Pull requests are welcome!
