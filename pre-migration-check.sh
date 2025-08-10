#!/bin/bash

# Higress存储迁移前检查脚本
# 用于验证迁移前的环境状态

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo "=========================================="
echo "Higress存储迁移前环境检查"
echo "=========================================="
echo

# 1. 检查集群连接
log_info "1. 检查Kubernetes集群连接..."
if kubectl cluster-info &>/dev/null; then
    log_success "集群连接正常"
else
    log_error "无法连接到Kubernetes集群"
    exit 1
fi

# 2. 检查local-path-provisioner状态
log_info "2. 检查local-path-provisioner状态..."
if kubectl get deployment -n local-path-storage local-path-provisioner &>/dev/null; then
    replicas=$(kubectl get deployment -n local-path-storage local-path-provisioner -o jsonpath='{.status.readyReplicas}')
    if [[ "$replicas" == "1" ]]; then
        log_success "local-path-provisioner运行正常"
    else
        log_error "local-path-provisioner未就绪"
        exit 1
    fi
else
    log_error "local-path-provisioner未安装"
    exit 1
fi

# 3. 检查StorageClass
log_info "3. 检查StorageClass配置..."
if kubectl get storageclass local-path &>/dev/null; then
    is_default=$(kubectl get storageclass local-path -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')
    if [[ "$is_default" == "true" ]]; then
        log_success "local-path是默认StorageClass"
    else
        log_warning "local-path不是默认StorageClass"
    fi
else
    log_error "local-path StorageClass不存在"
    exit 1
fi

# 4. 检查当前需要迁移的资源
log_info "4. 检查需要迁移的存储资源..."

echo "当前local-storage类型的PV:"
kubectl get pv -o custom-columns="NAME:.metadata.name,STORAGECLASS:.spec.storageClassName,STATUS:.status.phase,CLAIM:.spec.claimRef.name" | grep local-storage || log_warning "未找到local-storage类型的PV"

echo
echo "当前local-storage类型的PVC:"
kubectl get pvc -A -o custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,STORAGECLASS:.spec.storageClassName,STATUS:.status.phase" | grep local-storage || log_warning "未找到local-storage类型的PVC"

# 5. 检查Higress监控组件状态
log_info "5. 检查Higress监控组件状态..."
echo "Higress监控组件Pod状态:"
kubectl get pods -n higress-system -l 'app in (higress-console-grafana,higress-console-prometheus,higress-console-loki)' --no-headers | while read line; do
    echo "  $line"
done

# 6. 检查节点存储空间
log_info "6. 检查节点存储空间..."
echo "节点存储使用情况:"
kubectl top nodes --no-headers 2>/dev/null | while read node cpu memory; do
    echo "  节点: $node"
done || log_warning "无法获取节点资源使用情况（需要metrics-server）"

# 7. 检查是否有其他应用使用local-storage
log_info "7. 检查其他使用local-storage的应用..."
other_pvcs=$(kubectl get pvc -A -o jsonpath='{range .items[?(@.spec.storageClassName=="local-storage")]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' | grep -v higress-system || true)
if [[ -n "$other_pvcs" ]]; then
    log_warning "发现其他应用也在使用local-storage:"
    echo "$other_pvcs"
else
    log_success "只有Higress在使用local-storage"
fi

echo
echo "=========================================="
log_info "环境检查完成"
echo "=========================================="
echo
log_info "如果所有检查都通过，可以执行迁移脚本:"
log_info "  chmod +x higress-storage-migration.sh"
log_info "  ./higress-storage-migration.sh"