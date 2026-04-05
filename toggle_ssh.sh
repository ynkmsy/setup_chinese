#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查 root 权限
[ "$(id -u)" -ne 0 ] && { echo -e "${RED}需要 root 权限，请使用 sudo 或 root 用户运行！${NC}"; exit 1; }

# SSH 配置文件路径
SSHD_CONFIG="/etc/ssh/sshd_config"
BACKUP_CONFIG="/etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)"

# 备份 SSH 配置文件
backup_config() {
    [ ! -f "$SSHD_CONFIG" ] && { echo -e "${RED}未找到 ${SSHD_CONFIG}！${NC}"; exit 1; }
    echo -e "${YELLOW}备份配置文件到 ${BACKUP_CONFIG}...${NC}"
    cp "$SSHD_CONFIG" "$BACKUP_CONFIG" || { echo -e "${RED}备份失败！${NC}"; exit 1; }
}

# 检查是否存在 sudo 普通用户
check_sudo_user() {
    local sudo_users=0
    [ ! -r /etc/passwd ] && { echo -e "${RED}无法读取 /etc/passwd！${NC}"; return 1; }
    while IFS=: read -r user _ uid _ _ _ _; do
        if [ "$uid" -ge 1000 ] && [ "$user" != "nobody" ]; then
            if id "$user" 2>/dev/null | grep -qwE "(sudo|wheel)"; then
                sudo_users=$((sudo_users + 1))
                echo -e "${GREEN}找到 sudo/wheel 用户：$user${NC}"
            fi
        fi
    done < /etc/passwd
    echo -e "${YELLOW}检测到 $sudo_users 个 sudo/wheel 用户${NC}"
    [ "$sudo_users" -eq 0 ] && {
        echo -e "${RED}警告：未找到 sudo 或 wheel 用户！禁用 root 登录可能导致无法 SSH 登录！${NC}"
        return 1
    }
    return 0
}

# 修改 SSH 配置
modify_config() {
    local key="$1" value="$2"
    # 删除所有相关配置（包括注释和大小写）再添加
    sed -i "/^\s*#\?\s*${key}\s\+/Id" "$SSHD_CONFIG"
    echo "${key} ${value}" >> "$SSHD_CONFIG"
}

# 重启 SSH 服务（包含语法检查）
restart_ssh() {
    if ! sshd -t; then
        echo -e "${RED}配置语法检查失败，SSH 服务未重启！${NC}"
        exit 1
    fi
    systemctl restart sshd 2>/dev/null || service sshd restart 2>/dev/null || {
        echo -e "${RED}重启 SSH 服务失败，请检查服务状态！${NC}"
        exit 1
    }
}

# 获取配置值（忽略注释，忽略大小写）
get_config_value() {
    grep -iE "^\s*${1}\s+" "$SSHD_CONFIG" | tail -n 1 | awk '{print tolower($2)}'
}

# 显示 SSH 配置状态
show_status() {
    PRL=$(get_config_value PermitRootLogin)
    PA=$(get_config_value PasswordAuthentication)
    echo -e "${YELLOW}当前 SSH 配置状态：${NC}"
    [[ "$PRL" == "yes" ]] && echo -e "${GREEN}允许Root账号登录${NC}" || echo -e "${RED}禁止Root账号登录${NC}"
    [[ "$PA" == "yes" ]] && echo -e "${GREEN}允许密码验证登录${NC}" || echo -e "${RED}禁止密码验证登录${NC}"
}

# 切换 PermitRootLogin
toggle_permit_root() {
    backup_config
    current=$(get_config_value PermitRootLogin)
    if [[ "$current" == "yes" ]]; then
        echo -e "${YELLOW}检查 sudo 普通用户...${NC}"
        if ! check_sudo_user; then
            while true; do
                read -p "$(echo -e "${CYAN}仍要禁用 PermitRootLogin (y/n)? ${NC}")" choice
                case "${choice,,}" in
                    y) break ;;
                    n) echo -e "${GREEN}取消操作！${NC}"; return 0 ;;
                    *) echo -e "${RED}请输入 y 或 n！${NC}" ;;
                esac
            done
            echo -e "${YELLOW}创建用户示例：${NC}"
            echo -e "${YELLOW}  useradd -m -s /bin/bash newuser${NC}"
            echo -e "${YELLOW}  passwd newuser${NC}"
            echo -e "${YELLOW}  usermod -aG sudo newuser${NC}"
        fi
        echo -e "${YELLOW}关闭 PermitRootLogin...${NC}"
        modify_config "PermitRootLogin" "no"
        state="no" color="${RED}"
    else
        echo -e "${YELLOW}开启 PermitRootLogin...${NC}"
        modify_config "PermitRootLogin" "yes"
        state="yes" color="${GREEN}"
    fi
    restart_ssh
    echo -e "${GREEN}配置已更新：${NC}"
    echo -e "${color}PermitRootLogin: ${state}${NC}"
}

# 切换 PasswordAuthentication
toggle_password_auth() {
    backup_config

    if grep -q "^PasswordAuthentication yes" "$SSHD_CONFIG"; then

        # 检查是否启用了密钥认证
        PUBKEY_AUTH=$(grep -E "^PubkeyAuthentication" "$SSHD_CONFIG" | awk '{print $2}')
        if [[ "$PUBKEY_AUTH" != "yes" ]]; then
            echo -e "${RED}检测到尚未启用密钥登录方式（PubkeyAuthentication yes）！${NC}"
            echo -e "${RED}如果关闭密码登录，且没有其他方式（如密钥、OTP、证书）将无法远程登录！${NC}"
            while true; do
                read -p "$(echo -e "${BLUE}是否仍然关闭密码登录？(y/n): ${NC}")" confirm
                case "${confirm,,}" in
                    y) break ;;
                    n) echo -e "${GREEN}操作已取消。${NC}"; return 0 ;;
                    *) echo -e "${RED}请输入 y 或 n！${NC}" ;;
                esac
            done
        fi

        echo -e "${YELLOW}禁止密码验证登录...${NC}"
        modify_config "PasswordAuthentication" "no"
        state="no"
        color="${RED}"
    else
        echo -e "${YELLOW}开启 PasswordAuthentication...${NC}"
        modify_config "PasswordAuthentication" "yes"
        state="yes"
        color="${GREEN}"
    fi

    restart_ssh
    echo -e "${GREEN}配置已更新：${NC}"
    echo -e "${color}PasswordAuthentication: ${state}${NC}"
}

# 主菜单
main_menu() {
    while true; do
        clear
        PRL=$(get_config_value PermitRootLogin)
        PA=$(get_config_value PasswordAuthentication)

        echo -e "${CYAN}===== SSH 配置管理 =====${NC}"
        show_status
        echo -e "${CYAN}------------------------${NC}"

        if [[ "$PRL" == "yes" ]]; then
            echo -e "1. ${YELLOW}禁止Root账号登录${NC}"
        else
            echo -e "1. ${YELLOW}允许Root账号登录${NC}"
        fi

        if [[ "$PA" == "yes" ]]; then
            echo -e "2. ${YELLOW}禁止密码验证登录${NC}"
        else
            echo -e "2. ${YELLOW}允许密码验证登录${NC}"
        fi

        echo -e "0. ${YELLOW}退出${NC}"
        read -p "$(echo -e "${CYAN}请输入选项 [0-2]: ${NC}")" choice
        case "$choice" in
            1) toggle_permit_root; echo -e "${YELLOW}按任意键继续...${NC}"; read -n 1 -s -r ;;
            2) toggle_password_auth; echo -e "${YELLOW}按任意键继续...${NC}"; read -n 1 -s -r ;;
            0) echo -e "${GREEN}退出脚本...${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项,按任意键继续 ！${NC}"; read -n 1 -s -r ;;
        esac
    done
}

# 执行主菜单
main_menu
