#!/bin/bash
# PVE 虚拟机快速修复脚本
# 用于修复卡住的 ubuntu-node3 虚拟机

# 需要在 PVE 主机上运行此脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=========================================${NC}"
echo -e "${BLUE}PVE 虚拟机快速修复脚本${NC}"
echo -e "${BLUE}=========================================${NC}"

# 获取虚拟机 ID
read -p "请输入 ubuntu-node3 的虚拟机 ID (VMID): " VMID

if [ -z "$VMID" ]; then
    echo -e "${RED}错误: 必须提供虚拟机 ID${NC}"
    exit 1
fi

echo -e "\n${GREEN}[步骤 1/5]${NC} 检查虚拟机当前状态..."
qm status $VMID

# 获取虚拟机状态
VM_STATUS=$(qm status $VMID | grep -oP 'status: \K\w+')
echo -e "虚拟机状态: ${YELLOW}$VM_STATUS${NC}"

echo -e "\n${GREEN}[步骤 2/5]${NC} 检查虚拟机进程..."
if ps aux | grep -q "[k]vm.*$VMID"; then
    echo -e "${YELLOW}虚拟机进程正在运行${NC}"
    PID=$(ps aux | grep "[k]vm.*$VMID" | awk '{print $2}')
    echo "进程 PID: $PID"
else
    echo -e "${RED}未找到虚拟机进程${NC}"
fi

echo -e "\n${GREEN}[步骤 3/5]${NC} 检查最近的错误日志..."
echo "最近 10 行日志:"
tail -10 /var/log/pve/qemu-server/$VMID.log 2>/dev/null || echo "无法读取日志文件"

echo -e "\n${GREEN}[步骤 4/5]${NC} 尝试修复虚拟机..."

# 尝试解锁虚拟机
echo -e "${YELLOW}尝试解锁虚拟机...${NC}"
qm unlock $VMID 2>/dev/null || echo "虚拟机未被锁定"

# 根据状态采取不同操作
if [ "$VM_STATUS" == "running" ]; then
    echo -e "${YELLOW}虚拟机显示为运行中但无响应，尝试强制重启...${NC}"
    
    # 首先尝试 ACPI 关机
    echo "发送 ACPI 关机信号..."
    qm shutdown $VMID --timeout 30 || true
    
    # 等待 30 秒
    echo "等待 30 秒..."
    sleep 30
    
    # 检查是否已关闭
    NEW_STATUS=$(qm status $VMID | grep -oP 'status: \K\w+')
    if [ "$NEW_STATUS" == "stopped" ]; then
        echo -e "${GREEN}虚拟机已成功关闭${NC}"
    else
        echo -e "${YELLOW}ACPI 关机失败，执行强制停止...${NC}"
        qm stop $VMID --skiplock || true
        sleep 5
    fi
fi

# 检查并清理锁文件
LOCK_FILE="/var/lock/qemu-server/lock-$VMID.conf"
if [ -f "$LOCK_FILE" ]; then
    echo -e "${YELLOW}发现锁文件，删除中...${NC}"
    rm -f "$LOCK_FILE"
fi

echo -e "\n${GREEN}[步骤 5/5]${NC} 启动虚拟机..."
qm start $VMID

# 等待虚拟机启动
echo "等待虚拟机启动..."
for i in {1..30}; do
    STATUS=$(qm status $VMID | grep -oP 'status: \K\w+')
    if [ "$STATUS" == "running" ]; then
        echo -e "${GREEN}虚拟机已成功启动！${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# 最终状态检查
echo -e "\n${BLUE}=========================================${NC}"
echo -e "${BLUE}最终状态检查:${NC}"
echo -e "${BLUE}=========================================${NC}"
qm status $VMID

# 如果安装了 qemu-guest-agent，尝试获取更多信息
if qm config $VMID | grep -q "agent: 1"; then
    echo -e "\n尝试通过 Guest Agent 获取信息..."
    qm agent $VMID ping 2>/dev/null && echo -e "${GREEN}Guest Agent 响应正常${NC}" || echo -e "${RED}Guest Agent 无响应${NC}"
fi

echo -e "\n${BLUE}=========================================${NC}"
echo -e "${GREEN}修复脚本执行完成！${NC}"
echo -e "${BLUE}=========================================${NC}"

echo -e "\n后续步骤建议:"
echo "1. 通过 PVE Web 控制台检查虚拟机是否正常启动"
echo "2. 尝试 SSH 连接: ssh user@192.168.2.120"
echo "3. 检查 Kubernetes 节点状态: kubectl get node ubuntu-node3"
echo ""
echo "如果问题仍然存在，请查看 pve-vm-troubleshoot.md 获取更多故障排查方法"