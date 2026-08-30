#!/bin/bash

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用 root 权限运行此脚本。"
  exit 1
fi

# 安装或配置保活服务
function install_service() {
    echo ""
    echo "==== 配置保活参数 ===="
    read -p "请输入需要占用的 CPU 百分比 (输入 1-100，输入 0 则不占用 CPU): " cpu_pct
    read -p "请输入需要占用的内存大小 (单位 MB，输入 0 则不占用内存): " mem_mb

    if [[ ! "$cpu_pct" =~ ^[0-9]+$ ]] || [[ ! "$mem_mb" =~ ^[0-9]+$ ]]; then
        echo "输入错误，请输入纯数字。"
        return
    fi

    # 拼接运行参数
    ARGS=""
    if [ "$cpu_pct" -gt 0 ]; then
        ARGS="$ARGS -c $cpu_pct"
    fi
    if [ "$mem_mb" -gt 0 ]; then
        ARGS="$ARGS -m ${mem_mb}MB"
    fi

    if [ -z "$ARGS" ]; then
        echo "CPU 和内存均设置为 0，服务无需启动。"
        return
    fi

    echo "正在检查并安装编译环境 (这可能需要半分钟)..."
    apt-get update -y >/dev/null 2>&1
    apt-get install -y curl build-essential tar >/dev/null 2>&1

    # 如果系统中没有 lookbusy 则进行下载编译
    if [ ! -f "/usr/local/bin/lookbusy" ]; then
        echo "正在下载并编译底层控制组件 lookbusy..."
        cd /tmp
        curl -sLO http://www.devin.com/lookbusy/download/lookbusy-1.4.tar.gz
        tar -zxf lookbusy-1.4.tar.gz
        cd lookbusy-1.4
        ./configure >/dev/null 2>&1
        make >/dev/null 2>&1
        make install >/dev/null 2>&1
        cd /tmp
        rm -rf lookbusy-1.4*
    fi

    echo "正在创建系统守护进程..."
    cat > /etc/systemd/system/lookbusy.service <<EOF
[Unit]
Description=Custom Keep-Alive Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/lookbusy $ARGS
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable lookbusy >/dev/null 2>&1
    systemctl restart lookbusy
    
    echo "================================================="
    echo " 设置成功！保活服务已经在后台静默运行。"
    echo " 当前参数为：$ARGS"
    echo " 您可以随时重新运行此脚本来修改参数或卸载服务。"
    echo "================================================="
}

# 卸载保活服务
function uninstall_service() {
    echo ""
    echo "正在停止并清理服务..."
    systemctl stop lookbusy >/dev/null 2>&1
    systemctl disable lookbusy >/dev/null 2>&1
    rm -f /etc/systemd/system/lookbusy.service
    systemctl daemon-reload
    rm -f /usr/local/bin/lookbusy
    echo "已彻底卸载保活服务，您的系统已恢复纯净。"
}

# 主菜单循环
while true; do
    echo ""
    echo "================================================="
    echo "             轻量级精准保活一键脚本"
    echo "================================================="
    echo "  1. 安装 / 重新配置保活服务 (自定义 CPU 与内存)"
    echo "  2. 卸载保活服务"
    echo "  3. 退出脚本"
    echo "================================================="
    read -p "请输入数字选择功能 (1-3): " choice

    case $choice in
        1)
            install_service
            ;;
        2)
            uninstall_service
            ;;
        3)
            echo "已退出，祝您使用愉快！"
            break
            ;;
        *)
            echo "无效输入，请输入 1、2 或 3。"
            ;;
    esac
done
