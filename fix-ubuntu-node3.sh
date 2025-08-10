#!/bin/bash
# Kubernetes Node Recovery Script for ubuntu-node3
# This script attempts to fix common issues that cause nodes to become NotReady

set -e

echo "========================================="
echo "Kubernetes Node Recovery Script"
echo "Target Node: ubuntu-node3"
echo "========================================="

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    case $1 in
        "error") echo -e "${RED}[ERROR]${NC} $2" ;;
        "success") echo -e "${GREEN}[SUCCESS]${NC} $2" ;;
        "warning") echo -e "${YELLOW}[WARNING]${NC} $2" ;;
        "info") echo -e "[INFO] $2" ;;
    esac
}

# Function to ask for confirmation
confirm() {
    read -p "$1 (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return 1
    fi
    return 0
}

# Step 1: Clean up stale container processes
print_status "info" "Step 1: Cleaning up stale container processes..."
if confirm "Clean up stale containers?"; then
    # Stop all containers
    crictl ps -q | xargs -r crictl stop || true
    # Remove all containers
    crictl ps -aq | xargs -r crictl rm || true
    print_status "success" "Cleaned up containers"
fi

# Step 2: Restart container runtime
print_status "info" "Step 2: Restarting container runtime..."
if confirm "Restart containerd service?"; then
    systemctl restart containerd
    sleep 5
    if systemctl is-active --quiet containerd; then
        print_status "success" "Containerd restarted successfully"
    else
        print_status "error" "Failed to restart containerd"
        exit 1
    fi
fi

# Step 3: Clean kubelet data if needed
print_status "info" "Step 3: Checking kubelet data directory..."
if confirm "Clean kubelet pods directory (removes all pod data)?"; then
    # Stop kubelet first
    systemctl stop kubelet
    
    # Clean pod directory
    rm -rf /var/lib/kubelet/pods/*
    
    # Clean CPU manager state
    rm -f /var/lib/kubelet/cpu_manager_state
    
    print_status "success" "Cleaned kubelet data"
fi

# Step 4: Fix common permission issues
print_status "info" "Step 4: Fixing permissions..."
chown -R root:root /var/lib/kubelet/
chmod 700 /var/lib/kubelet/pki/
chmod 600 /var/lib/kubelet/pki/*

# Step 5: Restart kubelet
print_status "info" "Step 5: Restarting kubelet service..."
systemctl daemon-reload
systemctl restart kubelet

# Wait for kubelet to start
sleep 10

# Check if kubelet started successfully
if systemctl is-active --quiet kubelet; then
    print_status "success" "Kubelet restarted successfully"
else
    print_status "error" "Failed to restart kubelet"
    print_status "info" "Checking kubelet logs..."
    journalctl -u kubelet -n 50 --no-pager
    exit 1
fi

# Step 6: Monitor node status
print_status "info" "Step 6: Monitoring node recovery..."
echo "Waiting for node to become Ready (this may take a few minutes)..."

# Wait up to 5 minutes for node to become ready
TIMEOUT=300
ELAPSED=0
INTERVAL=10

while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if we can connect to the API server
    if kubectl get node ubuntu-node3 &>/dev/null; then
        NODE_STATUS=$(kubectl get node ubuntu-node3 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
        
        if [ "$NODE_STATUS" == "True" ]; then
            print_status "success" "Node is Ready!"
            kubectl get node ubuntu-node3
            break
        else
            echo "Node status: $NODE_STATUS (waiting...)"
        fi
    else
        echo "Cannot connect to API server yet (waiting...)"
    fi
    
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    print_status "error" "Timeout waiting for node to become Ready"
    print_status "info" "Checking current status..."
    kubectl get node ubuntu-node3 || true
    print_status "info" "Recent kubelet logs:"
    journalctl -u kubelet -n 30 --no-pager
fi

# Step 7: Additional recovery steps if node is still not ready
if [ "$NODE_STATUS" != "True" ]; then
    print_status "warning" "Node is still not Ready. Attempting additional recovery steps..."
    
    # Try to rejoin the cluster
    if confirm "Attempt to rejoin the cluster (requires kubeadm)?"; then
        print_status "info" "Resetting kubeadm..."
        kubeadm reset -f
        
        print_status "warning" "Node has been reset. You will need to rejoin it to the cluster using:"
        echo "kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>"
        echo ""
        echo "You can get the join command from a control plane node by running:"
        echo "kubeadm token create --print-join-command"
    fi
fi

echo ""
echo "========================================="
echo "Recovery Script Complete"
echo "========================================="

# Final status check
print_status "info" "Final node status:"
kubectl get node ubuntu-node3 -o wide || echo "Cannot get node status"