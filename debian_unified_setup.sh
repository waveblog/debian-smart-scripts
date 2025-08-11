#!/bin/bash

# --- 字体颜色定义 ---
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- 全局变量 ---
CURRENT_USER=$(whoami)
USER_HOME=$(eval echo "~$CURRENT_USER") # 使用 eval 确保 ~ 扩展到实际用户主目录

# --- 函数定义 ---
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本必须以 root 用户身份运行。"
        log_error "请使用 'sudo ./debian_unified_setup.sh' 运行，或直接切换到 root 用户再执行。"
        exit 1
    fi
}

# 备份文件函数
backup_file() {
    local file_path=$1
    local backup_dir="$(dirname "$file_path")"
    local backup_name="$(basename "$file_path").bak.$(date +%Y%m%d%H%M%S)"
    local backup_full_path="${backup_dir}/${backup_name}"

    if [ -f "$file_path" ]; then
        log_info "正在备份 ${file_path} 到 ${backup_full_path}..."
        if cp "$file_path" "$backup_full_path"; then
            log_info "备份成功。"
        else
            log_error "备份 ${file_path} 失败！请检查权限或磁盘空间。"
            return 1 # 返回非零表示失败
        fi
    else
        log_warn "${file_path} 文件不存在，跳过备份。"
    fi
    return 0
}

# --- 模块函数定义 ---

# 模块0: 更换 APT 镜像源
change_apt_sources() {
    log_info "========================================="
    log_info "      0. 更换 APT 镜像源模块 - 开始    "
    log_info "========================================="
    read -p "您确定要执行 APT 镜像源更换吗？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "用户取消，跳过此模块。"
        return
    fi

    check_root # 确保此模块以 root 权限运行

    SOURCES_LIST="/etc/apt/sources.list"
    BACKUP_FILE="${SOURCES_LIST}.bak.$(date +%Y%m%d%H%M%S)"

    log_info "正在检测 Debian 发行版代号..."
    DEBIAN_CODENAME=$(
        if [ -f "/etc/os-release" ]; then
            . /etc/os-release
            echo "$VERSION_CODENAME"
        elif [ -f "/etc/debian_version" ]; then
            DEB_VER=$(cat /etc/debian_version | cut -d'.' -f1)
            case "$DEB_VER" in
                12) echo "bookworm";;
                11) echo "bullseye";; # 修正：Debian 11 是 bullseye
                10) echo "buster";;
                9) echo "stretch";;
                *) echo "";; # Unknown or no codename
            esac
        fi
    )

    if [ -z "$DEBIAN_CODENAME" ]; then
        log_error "未能检测到 Debian 发行版代号。请手动确认或更新您的系统。"
        log_error "脚本可能无法为您生成正确的 sources.list 内容。"
        log_error "请确保您运行的是 Debian 系统。"
        return 1
    else
        log_info "检测到 Debian 发行版代号为: ${DEBIAN_CODENAME}"
    fi

    if ! backup_file "$SOURCES_LIST"; then
        return 1
    fi

    echo ""
    log_info "请选择您希望使用的 Debian APT 镜像源："
    echo "1) 阿里云镜像站 (https://mirrors.aliyun.com)"
    echo "2) 清华大学镜像站 (https://mirrors.tuna.tsinghua.edu.cn)"
    echo "3) 中国科学技术大学 (USTC) 镜像站 (https://mirrors.ustc.edu.cn)"
    echo "4) 官方 Debian 镜像站 (deb.debian.org)"
    echo "5) 取消并跳过此模块"
    echo ""

    read -p "请输入您的选择 (1-5): " CHOICE

    MIRROR_URL=""
    case "$CHOICE" in
        1) MIRROR_URL="https://mirrors.aliyun.com";;
        2) MIRROR_URL="https://mirrors.tuna.tsinghua.edu.cn";;
        3) MIRROR_URL="https://mirrors.ustc.edu.cn";;
        4) MIRROR_URL="http://deb.debian.org";;
        5) log_info "用户取消，跳过此模块。"; return;;
        *) log_error "无效的选择，请重新运行脚本并输入 1-5 之间的数字。"; return 1;;
    esac

    log_info "您选择了 $MIRROR_URL 作为镜像源。"
    log_info "正在生成新的 sources.list 内容..."

    # 核心源模板
    get_source_content_template() {
        local base_url=$1
        local codename=$2
        local content=""

        content+="deb ${base_url}/debian/ ${codename} main contrib non-free non-free-firmware\n"
        content+="deb-src ${base_url}/debian/ ${codename} main contrib non-free non-free-firmware\n\n"

        content+="deb ${base_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware\n"
        content+="deb-src ${base_url}/debian/ ${codename}-updates main contrib non-free non-free-firmware\n\n"
        
        # 安全源可能需要特殊处理，但对于大多数镜像站，结构是一致的
        # 官方源 security 域名是 deb.debian.org/debian-security/
        # 其他镜像站通常是 <mirror>/debian-security/
        content+="deb ${base_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware\n"
        content+="deb-src ${base_url}/debian-security/ ${codename}-security main contrib non-free non-free-firmware\n\n"

        content+="# backports源 (提供较新版本的软件，可能不稳定)\n"
        content+="# deb ${base_url}/debian/ ${codename}-backports main contrib non-free non-free-firmware\n"
        content+="# deb-src ${base_url}/debian/ ${codename}-backports main contrib non-free non-free-firmware\n"
        echo -e "$content"
    }

    NEW_SOURCES_CONTENT=$(get_source_content_template "$MIRROR_URL" "$DEBIAN_CODENAME")

    log_info "正在写入新内容到 ${SOURCES_LIST}..."
    echo "$NEW_SOURCES_CONTENT" | tee "$SOURCES_LIST" > /dev/null
    if [ $? -eq 0 ]; then
        log_info "成功更新 ${SOURCES_LIST}。"
    else
        log_error "写入 ${SOURCES_LIST} 失败！"
        return 1
    fi

    log_info "正在执行 'apt update' 更新软件包列表..."
    if apt update; then
        log_info "'apt update' 成功完成。"
        log_warn "建议您现在运行 'apt upgrade -y' 来升级您的系统。"
    else
        log_error "'apt update' 失败！请检查您的网络连接或新的源配置。"
        log_error "如果出现 GPG 错误，您可能需要手动导入缺失的密钥。"
        return 1
    fi

    log_info "========================================="
    log_info "      0. 更换 APT 镜像源模块 - 结束    "
    log_info "========================================="
    return 0
}


# 模块1: 网络初始化和基础工具安装
network_initialization() {
    log_info "========================================="
    log_info "     1. 网络初始化及基础工具 - 开始    "
    log_info "========================================="
    log_warn "此模块将修改网络配置和 SSH 配置，可能导致远程连接中断！"
    log_warn "请确保有物理访问权限或虚拟机快照以防万一。"
    read -p "您确定要执行网络初始化吗？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "用户取消，跳过此模块。"
        return
    fi
    check_root

    log_info "--- 1.1 前期准备：更新系统及安装必要工具 ---"
    log_info "正在更新软件包列表..."
    if ! apt update; then
        log_error "apt update 失败！请检查网络连接。"
        return 1
    fi

    log_info "正在升级所有已安装的软件包..."
    if ! apt upgrade -y; then
        log_warn "apt upgrade 过程中可能出现警告或错误，但通常不致命。"
    fi

    log_info "正在安装 Vim 编辑器..."
    if ! apt install vim -y; then
        log_error "安装 Vim 失败！"
        return 1
    fi

    log_info "正在安装 OpenSSH 服务器..."
    if ! apt install openssh-server -y; then
        log_error "安装 OpenSSH 服务器失败！"
        return 1
    fi

    log_info "检查 SSH 服务状态..."
    systemctl status ssh | grep -q "active (running)"
    if [ $? -eq 0 ]; then
        log_info "SSH 服务正在运行。"
    else
        log_error "SSH 服务未运行。尝试启动 SSH 服务..."
        if systemctl start ssh; then
            log_info "SSH 服务已启动。"
        else
            log_error "启动 SSH 服务失败！"
            return 1
        fi
    fi
    log_info "前期准备完成。"

    log_info "--- 1.2 修改 IP 地址及网关 ---"
    AUTO_DETECTED_INTERFACE=$(ip -o link show | awk -F': ' '{print $2}' | grep -E "^e|^eth|^enp" | grep -v "lo" | head -n 1)
    read -p "请输入您的网卡接口名称 (例如: ens32, eth0, enp0s3) [默认: ${AUTO_DETECTED_INTERFACE}]: " NETWORK_INTERFACE
    NETWORK_INTERFACE=${NETWORK_INTERFACE:-${AUTO_DETECTED_INTERFACE}}
    if [ -z "$NETWORK_INTERFACE" ]; then
        log_error "未检测到或未输入网卡接口名称。"
        return 1
    fi
    log_info "将为网卡接口 ${NETWORK_INTERFACE} 配置静态 IP。"

    read -p "请输入静态 IP 地址 (例如: 192.168.50.13): " STATIC_IP
    read -p "请输入子网掩码 (例如: 255.255.255.0): " NETMASK
    read -p "请输入网关地址 (例如: 192.168.50.1): " GATEWAY
    read -p "请输入首选 DNS 服务器地址 (例如: 192.168.50.4 或 8.8.8.8): " NAMESERVER1
    read -p "请输入备用 DNS 服务器地址 (可选，留空则不设置): " NAMESERVER2

    if ! backup_file "/etc/network/interfaces"; then return 1; fi
    log_info "正在配置 /etc/network/interfaces..."
    cat << EOF > /etc/network/interfaces
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface - configured by script
allow-hotplug ${NETWORK_INTERFACE}
iface ${NETWORK_INTERFACE} inet static
address ${STATIC_IP}
netmask ${NETMASK}
gateway ${GATEWAY}
EOF
    log_info "已更新 /etc/network/interfaces。"

    if ! backup_file "/etc/resolv.conf"; then return 1; fi
    log_info "正在配置 /etc/resolv.conf (DNS 服务器)..."
    echo "nameserver ${NAMESERVER1}" > /etc/resolv.conf
    if [ -n "$NAMESERVER2" ]; then
        echo "nameserver ${NAMESERVER2}" >> /etc/resolv.conf
    fi
    log_info "已更新 /etc/resolv.conf。"

    log_info "正在重启网络服务 (此操作可能导致连接中断)..."
    if systemctl restart networking; then
        log_info "网络服务重启成功。请检查您的网络连接是否正常。"
    else
        log_error "网络服务重启失败！请检查 /etc/network/interfaces 配置。"
        log_error "您可能需要手动修复网络，否则可能无法连接到服务器。"
        return 1
    fi
    log_info "IP 地址及网关配置完成。"

    log_info "--- 1.3 修改 SSH 配置以允许远程连接 ---"
    log_warn "此操作将降低 SSH 安全性，允许 root 登录和密码认证！"
    log_warn "在生产环境中，强烈建议使用密钥认证并禁用这些选项。"
    SSH_CONFIG="/etc/ssh/sshd_config"
    if ! backup_file "$SSH_CONFIG"; then return 1; fi

    log_info "正在修改 ${SSH_CONFIG}..."
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
    grep -qxF 'PermitRootLogin yes' "$SSH_CONFIG" || echo 'PermitRootLogin yes' >> "$SSH_CONFIG" # Fallback if not found
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG"
    grep -qxF 'PasswordAuthentication yes' "$SSH_CONFIG" || echo 'PasswordAuthentication yes' >> "$SSH_CONFIG" # Fallback if not found
    log_info "已更新 SSH 配置。"

    log_info "正在重启 SSH 服务..."
    if systemctl restart ssh; then
        log_info "SSH 服务重启成功。root 用户和密码认证现已启用。"
    else
        log_error "SSH 服务重启失败！请检查 /etc/ssh/sshd_config 或系统日志。"
        return 1
    fi
    log_info "SSH 配置修改完成。"

    log_info "========================================="
    log_info "     1. 网络初始化及基础工具 - 结束    "
    log_info "========================================="
    return 0
}

# 模块2: 配置 Oh-My-Zsh 和 Vim
configure_user_environment() {
    log_info "========================================="
    log_info "     2. 配置 Oh-My-Zsh & Vim - 开始    "
    log_info "========================================="
    log_info "此脚本将为当前用户 (${CURRENT_USER}) 配置 Zsh 和 Vim。"
    read -p "您确定要配置 Oh-My-Zsh 和 Vim 吗？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "用户取消，跳过此模块。"
        return
    fi

    # 检查当前用户是否有sudo权限，或者直接以root/sudo执行
    if ! command -v sudo &> /dev/null; then
        log_error "系统中未安装 sudo。请安装 sudo 或以 root 用户手动执行需要权限的部分。"
        return 1
    fi

    log_info "--- 2.1 安装 Oh-My-Zsh 依赖 ---"
    log_info "正在安装 zsh, git, curl 依赖..."
    if ! sudo apt update && sudo apt install zsh git curl -y; then
        log_error "安装 zsh, git, curl 失败！请检查网络或权限。"
        return 1
    fi

    log_info "--- 2.2 设置 Zsh 为默认终端 ---"
    if [ "$SHELL" != "/bin/zsh" ]; then
        log_info "正在设置 Zsh 为当前用户的默认 shell..."
        if sudo chsh -s /bin/zsh "$CURRENT_USER"; then
            log_info "Zsh 已设置为默认 shell。下次登录时生效。"
        else
            log_error "设置 Zsh 为默认 shell 失败！请检查权限。"
        fi
    else
        log_info "Zsh 已经是当前用户的默认 shell。"
    fi

    log_info "--- 2.3 安装 Oh-My-Zsh ---"
    if [ ! -d "$USER_HOME/.oh-my-zsh" ]; then
        log_info "正在使用 Curl 安装 Oh-My-Zsh..."
        if sudo -u "$CURRENT_USER" sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
            log_info "Oh-My-Zsh 安装成功。"
        else
            log_error "Oh-My-Zsh 安装失败！请检查网络或重新尝试。"
            # 即使失败也尝试继续，以便用户手动干预
        fi
    else
        log_info "Oh-My-Zsh 已经安装，跳过安装步骤。"
    fi
    
    log_info "--- 2.4 安装常用插件 ---"
    ZSH_CUSTOM="${ZSH_CUSTOM:-$USER_HOME/.oh-my-zsh/custom}" # 确保 ZSH_CUSTOM 定义正确

    # zsh-autosuggestions
    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
        log_info "正在克隆 zsh-autosuggestions 插件..."
        if sudo -u "$CURRENT_USER" git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"; then
            log_info "zsh-autosuggestions 插件安装成功。"
        else
            log_error "zsh-autosuggestions 插件安装失败！"
        fi
    else
        log_info "zsh-autosuggestions 插件已存在，跳过克隆。"
    fi

    # zsh-syntax-highlighting
    if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
        log_info "正在克隆 zsh-syntax-highlighting 插件..."
        if sudo -u "$CURRENT_USER" git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"; then
            log_info "zsh-syntax-highlighting 插件安装成功。"
        else
            log_error "zsh-syntax-highlighting 插件安装失败！"
        fi
    else
        log_info "zsh-syntax-highlighting 插件已存在，跳过克隆。"
    fi

    log_info "--- 2.5 配置 .zshrc ---"
    ZSHRC_FILE="$USER_HOME/.zshrc"
    if ! backup_file "$ZSHRC_FILE"; then return 1; fi

    log_info "正在修改或添加 .zshrc 配置..."
    # 使用 sudo -u 来确保 .zshrc 操作正确
    sudo -u "$CURRENT_USER" sed -i '/^plugins=(/d' "$ZSHRC_FILE" # 删除旧的plugins行
    sudo -u "$CURRENT_USER" sed -i '/^ZSH_THEME=/d' "$ZSHRC_FILE" # 删除旧的ZSH_THEME行

    cat << EOF | sudo -u "$CURRENT_USER" tee -a "$ZSHRC_FILE" > /dev/null
# --- Oh-My-Zsh Scripted Configuration Start ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="bira"              # 你可以更改为其他主题，如 "agnoster", "robbyrussell"
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
)
# --- Oh-My-Zsh Scripted Configuration End ---
EOF

    # 确保 source $ZSH/oh-my-zsh.sh 在文件末尾
    if ! grep -q "source \$ZSH/oh-my-zsh.sh" "$ZSHRC_FILE"; then
        echo "source \$ZSH/oh-my-zsh.sh" | sudo -u "$CURRENT_USER" tee -a "$ZSHRC_FILE" > /dev/null
    fi
    log_info ".zshrc 配置已更新。下次登录或 'source ~/.zshrc' 后生效。"

    log_info "--- 2.6 配置 Vim ---"
    VIMRC_FILE="$USER_HOME/.vimrc"
    if ! backup_file "$VIMRC_FILE"; then return 1; fi

    log_info "正在配置 .vimrc..."
    cat << EOF | sudo -u "$CURRENT_USER" tee -a "$VIMRC_FILE" > /dev/null
" --- Vim Scripted Configuration Start ---
set nu                " 显示行号 (number)
colorscheme desert    " 设置颜色显示方案为 desert
syntax on             " 打开语法高亮
" --- Vim Scripted Configuration End ---
EOF
    log_info ".vimrc 配置已完成。"

    log_info "========================================="
    log_info "     2. 配置 Oh-My-Zsh & Vim - 结束    "
    log_info "========================================="
    log_warn "请退出当前终端会话并重新登录，以体验 Zsh 和 Vim 的新配置。"
    log_info "如果 Zsh 未生效，请手动运行 'source ~/.zshrc'。"
    return 0
}

# 模块3: 配置 Docker 环境
install_docker_environment() {
    log_info "========================================="
    log_info "      3. 配置 Docker 环境 - 开始       "
    log_info "========================================="
    read -p "您确定要安装 Docker 环境吗？(y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_info "用户取消，跳过此模块。"
        return
    fi
    check_root

    # 配置选项 - Docker Compose
    INSTALL_OLD_DOCKER_COMPOSE_BINARY=false

    log_info "正在更新系统软件包列表并安装必要的依赖..."
    if ! apt update; then
        log_error "apt update 失败！请检查网络连接或源配置。"
        return 1
    fi
    if ! apt install -y ca-certificates curl gnupg lsb-release; then
        log_error "安装必要依赖失败！"
        return 1
    fi

    log_info "正在卸载可能存在的旧版 Docker 相关软件包..."
    apt remove -y docker docker-engine docker.io containerd runc
    apt autoremove -y

    log_info "正在设置 Docker 官方 APT 仓库..."
    if ! install -m 0755 -d /etc/apt/keyrings; then
        log_error "创建 /etc/apt/keyrings 目录失败。"
        return 1
    fi
    if ! curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        log_error "下载或添加 Docker GPG 密钥失败。"
        return 1
    fi
    chmod a+r /etc/apt/keyrings/docker.gpg

    if ! echo \
      "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null; then
        log_error "添加 Docker APT 仓库失败。"
        return 1
    fi

    log_info "正在更新 apt 软件包索引以包含 Docker 仓库..."
    if ! apt update; then
        log_error "apt update (包含Docker仓库) 失败！"
        return 1
    fi

    log_info "正在安装 Docker Engine (docker-ce, docker-ce-cli, containerd.io) 和 Docker Compose 插件..."
    if ! apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        log_error "安装 Docker Engine 和 docker-compose-plugin 失败！"
        return 1
    fi
    log_info "Docker Engine 和 Docker Compose 插件安装成功。"

    if [ "$INSTALL_OLD_DOCKER_COMPOSE_BINARY" = true ]; then
        log_info "正在下载并安装旧版独立的 docker-compose 可执行文件..."
        DOCKER_COMPOSE_URL=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep browser_download_url | grep "docker-compose-$(uname -s)-$(uname -m)" | cut -d '"' -f 4)
        if [ -z "$DOCKER_COMPOSE_URL" ]; then
            log_error "未能找到最新的 docker-compose 下载链接。跳过旧版独立文件安装。"
        else
            if ! curl -L "$DOCKER_COMPOSE_URL" -o /usr/local/bin/docker-compose; then
                log_error "下载旧版 docker-compose 可执行文件失败。"
            else
                if ! chmod +x /usr/local/bin/docker-compose; then
                    log_error "为旧版 docker-compose 添加执行权限失败。"
                else
                    log_info "旧版独立的 docker-compose 安装成功。"
                    /usr/local/bin/docker-compose --version
                fi
            fi
        fi
    else
        log_info "创建 'docker-compose' 符号链接，以兼容旧版命令..."
        if [ -f "/usr/local/bin/docker-compose" ]; then
            log_warn "检测到 /usr/local/bin/docker-compose 已存在，正在删除旧链接/文件..."
            rm /usr/local/bin/docker-compose
        fi
        DOCKER_CLI_PATH=$(command -v docker)
        if [ -z "$DOCKER_CLI_PATH" ]; then
            log_error "未找到 'docker' CLI 可执行文件。无法创建 docker-compose 兼容链接。"
        else
            ln -s "$DOCKER_CLI_PATH" /usr/local/bin/docker-compose
            if [ $? -eq 0 ]; then
                log_info "已成功创建 /usr/local/bin/docker-compose -> $DOCKER_CLI_PATH 的符号链接。"
                log_info "现在可以使用 'docker-compose' 命令来调用 'docker compose' 功能。"
            else
                log_error "创建 'docker-compose' 符号链接失败。"
            fi
        fi
    fi

    # 添加当前用户到docker组
    TARGET_USER="${SUDO_USER:-$CURRENT_USER}" # 如果 SUDO_USER 不为空则用它，否则用当前用户
    if [ "$TARGET_USER" == "root" ]; then
        log_warn "当前用户是 root，root 用户通常不需要添加到 'docker' 组。"
    else
        log_info "将用户 '$TARGET_USER' 添加到 'docker' 组..."
        usermod -aG docker "$TARGET_USER"
        if [ $? -eq 0 ]; then
            log_info "用户 '$TARGET_USER' 已添加到 'docker' 组。您需要注销并重新登录或运行 'newgrp docker' 以应用更改。"
            log_warn "建议在脚本运行完毕后，手动注销并重新登录以确保权限完全生效。"
        else
            log_error "添加用户到 'docker' 组失败。请检查是否已存在该用户或权限问题。"
        fi
    fi

    log_info "验证 Docker Engine 安装..."
    if ! docker run hello-world; then
        log_error "Docker Engine 验证失败！请检查 Docker 服务状态。"
        return 1
    fi
    log_info "验证 Docker Compose 插件安装 (新方式：docker compose)..."
    if ! docker compose version; then
        log_error "Docker Compose 插件验证失败！"
        return 1
    fi
    if [ -L "/usr/local/bin/docker-compose" ]; then
        log_info "验证 'docker-compose' 兼容性（通过符号链接）..."
        if ! docker-compose version; then
             log_error "'docker-compose' 兼容性验证失败，可能符号链接有问题。"
        else
            log_info "'docker-compose' 命令兼容性良好。"
        fi
    fi

    log_info "========================================="
    log_info "      3. 配置 Docker 环境 - 结束       "
    log_info "========================================="
    log_info "所有操作完成。请在尝试运行 Docker 命令前，重新登录您的会话或运行 'newgrp docker'。"
    return 0
}


# --- 主菜单逻辑 ---
main_menu() {
    log_info "========================================="
    log_info "       Debian 统一初始化配置脚本         "
    log_info "========================================="
    log_info " 当前操作用户: ${CURRENT_USER}"
    log_info "-----------------------------------------"
    log_info "请选择您要执行的操作："
    echo "1) 更换 APT 镜像源"
    echo "2) 基础系统初始化 (更新/安装工具, 网络配置, SSH配置)"
    echo "3) 配置 Oh-My-Zsh 及 Vim 环境 (针对当前用户)"
    echo "4) 安装 Docker 环境"
    echo "5) 执行所有以上操作 (建议在全新系统上运行)"
    echo "6) 退出脚本"
    echo "-----------------------------------------"

    read -p "请输入您的选择 (1-6): " MAIN_CHOICE

    case "$MAIN_CHOICE" in
        1) change_apt_sources;;
        2) network_initialization;;
        3) configure_user_environment;;
        4) install_docker_environment;;
        5)
            log_info "您选择了执行所有配置。请注意：此操作将耗时较长，并可能导致网络中断。"
            log_info "请确保网络连接正常且有物理访问权限。"
            read -p "确定要执行所有配置吗？(y/N): " ALL_CONFIRM
            if [[ "$ALL_CONFIRM" =~ ^[Yy]$ ]]; then
                change_apt_sources && \
                network_initialization && \
                configure_user_environment && \
                install_docker_environment
                log_info "所有选定模块执行完毕。请检查日志并根据提示重启或重新登录。"
            else
                log_info "用户取消，跳过所有配置。"
            fi
            ;;
        6)
            log_info "脚本已退出。再见！"
            exit 0
            ;;
        *)
            log_error "无效的选择，请重新输入 1-6 之间的数字。"
            sleep 2
            main_menu # 递归调用菜单
            ;;
    esac
    log_info "操作完成。请返回主菜单或退出。"
    read -p "按任意键返回主菜单..."
    main_menu # 返回主菜单
}

# --- 脚本入口点 ---
main_menu
