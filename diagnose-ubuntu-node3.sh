#!/bin/bash
# Kubernetes Node Diagnosis and Recovery Script for ubuntu-node3
# Generated on: $(date)

set -e

echo "========================================="
echo "Kubernetes Node Diagnosis Script"
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

# Step 1: Check system basics
print_status "info" "Step 1: Checking system basics..."
echo "Hostname: $(hostname)"
echo "IP Address: $(hostname -I)"
echo "Uptime: $(uptime)"
echo "Kernel: $(uname -r)"
echo ""

# Step 2: Check kubelet service status
print_status "info" "Step 2: Checking kubelet service status..."
if systemctl is-active --quiet kubelet; then
    print_status "success" "Kubelet service is active"
    systemctl status kubelet --no-pager | head -20
else
    print_status "error" "Kubelet service is not active"
    systemctl status kubelet --no-pager | head -20
fi
echo ""

# Step 3: Check kubelet logs
print_status "info" "Step 3: Checking recent kubelet logs..."
echo "Last 50 lines of kubelet logs:"
journalctl -u kubelet -n 50 --no-pager | tail -20
echo ""

# Step 4: Check system resources
print_status "info" "Step 4: Checking system resources..."
echo "Memory usage:"
free -h
echo ""
echo "Disk usage:"
df -h
echo ""
echo "CPU load:"
top -bn1 | head -5
echo ""

# Step 5: Check network connectivity
print_status "info" "Step 5: Checking network connectivity to control plane..."
CONTROL_PLANE_IPS="192.168.2.110 192.168.2.109 192.168.2.111"
for ip in $CONTROL_PLANE_IPS; do
    if ping -c 2 -W 2 $ip > /dev/null 2>&1; then
        print_status "success" "Can reach control plane node: $ip"
    else
        print_status "error" "Cannot reach control plane node: $ip"
    fi
done
echo ""

# Step 6: Check container runtime
print_status "info" "Step 6: Checking container runtime (containerd)..."
if systemctl is-active --quiet containerd; then
    print_status "success" "Containerd service is active"
    crictl version
else
    print_status "error" "Containerd service is not active"
fi
echo ""

# Step 7: Check for port connectivity
print_status "info" "Step 7: Checking API server connectivity..."
API_SERVER_PORT=6443
for ip in $CONTROL_PLANE_IPS; do
    if timeout 2 bash -c "echo >/dev/tcp/$ip/$API_SERVER_PORT" 2>/dev/null; then
        print_status "success" "Can connect to API server at $ip:$API_SERVER_PORT"
    else
        print_status "error" "Cannot connect to API server at $ip:$API_SERVER_PORT"
    fi
done
echo ""

# Step 8: Check kubelet configuration
print_status "info" "Step 8: Checking kubelet configuration..."
if [ -f /var/lib/kubelet/config.yaml ]; then
    print_status "success" "Kubelet config file exists"
    echo "Kubelet server URL:"
    grep -E "clusterDNS|serverTLSBootstrap" /var/lib/kubelet/config.yaml || true
else
    print_status "error" "Kubelet config file not found"
fi
echo ""

# Step 9: Check for certificate issues
print_status "info" "Step 9: Checking kubelet certificates..."
CERT_DIR="/var/lib/kubelet/pki"
if [ -d "$CERT_DIR" ]; then
    echo "Certificates in $CERT_DIR:"
    ls -la $CERT_DIR/
    echo ""
    # Check certificate expiration
    for cert in $CERT_DIR/*.crt; do
        if [ -f "$cert" ]; then
            echo "Certificate: $cert"
            openssl x509 -in "$cert" -noout -dates 2>/dev/null || echo "Cannot read certificate"
            echo ""
        fi
    done
fi

# Step 10: Check for common issues
print_status "info" "Step 10: Checking for common issues..."

# Check if swap is enabled
if [ $(swapon -s | wc -l) -gt 0 ]; then
    print_status "warning" "Swap is enabled (Kubernetes requires swap to be disabled)"
else
    print_status "success" "Swap is disabled"
fi

# Check if firewall might be blocking
if command -v ufw &> /dev/null; then
    if ufw status | grep -q "Status: active"; then
        print_status "warning" "UFW firewall is active - might block Kubernetes traffic"
    else
        print_status "success" "UFW firewall is inactive"
    fi
fi

echo ""
echo "========================================="
echo "Diagnosis Complete"
echo "========================================="