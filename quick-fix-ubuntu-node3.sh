#!/bin/bash
# Quick Fix Script for ubuntu-node3
# This script performs the most common fixes without requiring confirmations

set -e

echo "========================================="
echo "Quick Fix for ubuntu-node3"
echo "Starting at: $(date)"
echo "========================================="

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Step 1: Restart network services
echo -e "\n${GREEN}[1/5]${NC} Restarting network services..."
systemctl restart systemd-networkd
systemctl restart systemd-resolved
sleep 2

# Step 2: Flush iptables rules that might be blocking
echo -e "\n${GREEN}[2/5]${NC} Checking iptables rules..."
# Save current rules first
iptables-save > /tmp/iptables-backup-$(date +%Y%m%d-%H%M%S).rules
# Ensure Kubernetes required rules are present
iptables -P FORWARD ACCEPT
iptables -P INPUT ACCEPT
iptables -P OUTPUT ACCEPT

# Step 3: Restart container runtime
echo -e "\n${GREEN}[3/5]${NC} Restarting container runtime..."
systemctl restart containerd
sleep 5

# Step 4: Clean and restart kubelet
echo -e "\n${GREEN}[4/5]${NC} Cleaning and restarting kubelet..."
# Remove CPU manager state file that might be corrupted
rm -f /var/lib/kubelet/cpu_manager_state
# Remove memory manager state file
rm -f /var/lib/kubelet/memory_manager_state

# Restart kubelet
systemctl daemon-reload
systemctl restart kubelet

# Step 5: Wait and check status
echo -e "\n${GREEN}[5/5]${NC} Waiting for services to stabilize..."
sleep 15

# Check final status
echo -e "\n========================================="
echo "Quick Fix Complete - Checking Status:"
echo "========================================="

# Check kubelet
if systemctl is-active --quiet kubelet; then
    echo -e "${GREEN}✓${NC} Kubelet is running"
else
    echo -e "${RED}✗${NC} Kubelet is not running"
    journalctl -u kubelet -n 20 --no-pager
fi

# Check containerd
if systemctl is-active --quiet containerd; then
    echo -e "${GREEN}✓${NC} Containerd is running"
else
    echo -e "${RED}✗${NC} Containerd is not running"
fi

# Try to get node status
echo -e "\nAttempting to check node status from cluster..."
timeout 10 kubectl get node ubuntu-node3 2>/dev/null || echo "Cannot reach API server yet"

echo -e "\n========================================="
echo "Quick fix completed at: $(date)"
echo "========================================="
echo ""
echo "If the node is still NotReady, please run:"
echo "1. ./diagnose-ubuntu-node3.sh - for detailed diagnosis"
echo "2. ./fix-ubuntu-node3.sh - for interactive recovery"