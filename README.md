# 🚀 Debian 系统统一初始化与环境配置脚本

这个Shell脚本旨在简化 Debian (以及基于 Debian 的发行版如 Ubuntu) 服务器或桌面系统的初始化和环境配置过程。它将常用的系统级和用户级配置任务整合到一个交互式菜单中，大大提高了配置效率和减少了手动操作的误差。

## ✨ 主要功能

本脚本提供以下模块化功能，你可以根据需求选择性执行：

1.  **更换 APT 镜像源**: 提高软件包下载速度，支持阿里云、清华、USTC 等国内主流镜像站，并可回退到官方源。
2.  **基础系统初始化**:
    *   更新并升级系统软件包。
    *   安装常用工具 (如 `vim`, `openssh-server`)。
    *   **配置静态 IP 地址** (IP, 子网掩码, 网关, DNS)。
    *   更改 SSH 配置以支持 **root 登录和密码认证** (请注意安全性)。
3.  **配置 Oh-My-Zsh 及 Vim**:
    *   安装 `zsh`, `git`, `curl` 等依赖。
    *   设置 `zsh` 为默认 Shell。
    *   自动化安装 Oh-My-Zsh。
    *   安装 `zsh-autosuggestions` 和 `zsh-syntax-highlighting` 插件。
    *   配置 `.zshrc` 文件 (主题为 `bira`)。
    *   配置 `.vimrc` 文件 (显示行号, `desert` 颜色方案, 语法高亮)。
4.  **安装 Docker 环境**:
    *   安装 Docker Engine (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`)。
    *   安装 Docker Compose 插件 (`docker-compose-plugin`) 并创建 `docker-compose` 兼容符号链接。
    *   将当前用户添加到 `docker` 用户组，实现无 `sudo` 运行 Docker 命令。

5.  **一键执行所有操作**: 按照上述顺序执行所有模块。适用于全新安装的 Debian 系统。

## ⚠️ 安全警告

*   **网络中断风险**: **“基础系统初始化”模块会修改网络配置并重启网络服务，这可能导致你的远程 SSH 连接中断！强烈建议在具备物理访问权限的环境中或执行虚拟机快照后运行此模块。**
*   **SSH 安全性降低**: **在“基础系统初始化”模块中，默认会修改 SSH 配置以允许 `root` 用户登录和密码认证。这会显著降低 SSH 服务的安全性。在生产环境中，强烈建议使用 SSH 密钥认证并禁用这些选项！**
*   **权限**: 脚本需要 `root` 权限才能执行涉及到系统级文件和软件包安装的操作。请使用 `sudo` 运行脚本。
*   **兼容性**: 脚本在 Debian 10+ (Buster, Bullseye, Bookworm) 上进行了测试。对于其他版本或基于 Debian 的发行版（如 Ubuntu），可能需要微调。

## 🚀 如何使用

1.  **下载脚本**:
    将脚本内容保存到一个文件，例如 `debian_unified_setup.sh`。

    ```bash
    # 例如：
    # wget https://your-repo-link/debian_unified_setup.sh
    # 或手动复制粘贴
    ```

2.  **添加执行权限**:
    ```bash
    chmod +x debian_unified_setup.sh
    ```

3.  **运行脚本**:
    请确保你有 `sudo` 权限。推荐在安装了 Debian 的服务器或虚拟机上，使用非 `root` 用户登录，并通过 `sudo` 运行此脚本。

    ```bash
    sudo ./debian_unified_setup.sh
    ```

4.  **根据菜单选择**:
    脚本运行后，会显示一个交互式菜单。按照提示输入数字选择你想要执行的功能。
    -   如果你选择 2 (网络初始化) 或 5 (执行所有操作)，脚本会询问网络配置详情。
    -   如果你选择 3 (配置 Oh-My-Zsh)，脚本将自动为运行脚本的当前用户配置 Zsh 和 Vim 环境。

5.  **后续操作**:
    *   **Zsh 配置生效**: 配置 Oh-My-Zsh 后，你需要**退出当前终端会话并重新登录**，或手动运行 `source ~/.zshrc` 来应用更改。
    *   **Docker 权限**: 安装 Docker 后，也需要**退出并重新登录**，或运行 `newgrp docker` 来使当前用户添加到 `docker` 组的权限生效，从而无需 `sudo` 即可运行 `docker` 命令。

## 📁 文件备份

脚本在修改关键配置文件（如 `/etc/apt/sources.list`, `/etc/network/interfaces`, `/etc/ssh/sshd_config`, `~/.zshrc`, `~/.vimrc`）之前，都会自动创建带有日期时间戳的备份文件，例如 `/etc/apt/sources.list.bak.YYYYMMDDHHMMSS`。这有助于在出现问题时恢复到原始配置。

## 贡献

欢迎提出建议或贡献代码，帮助改进此脚本！

---
