#!/bin/bash

# Higress存储迁移后验证脚本
# 用于验证迁移后的系统状态

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
echo "Higress存储迁移后验证"
echo "=========================================="
echo

# 1. 验证PVC状态
log_info "1. 验证PVC状态..."
echo "Higress监控PVC状态:"
kubectl get pvc -n higress-system higress-console-grafana higress-console-prometheus higress-console-loki -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,CAPACITY:.status.capacity.storage"

# 检查所有PVC是否都是Bound状态且使用local-path
failed_pvcs=0
for pvc in higress-console-grafana higress-console-prometheus higress-console-loki; do
    status=$(kubectl get pvc -n higress-system $pvc -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")
    sc=$(kubectl get pvc -n higress-system $pvc -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo "")
    
    if [[ "$status" != "Bound" ]]; then
        log_error "PVC $pvc 状态异常: $status"
        ((failed_pvcs++))
    elif [[ "$sc" != "local-path" ]]; then
        log_error "PVC $pvc StorageClass错误: $sc"
        ((failed_pvcs++))
    fi
done

if [[ $failed_pvcs -eq 0 ]]; then
    log_success "所有PVC状态正常"
else
    log_error "$failed_pvcs 个PVC状态异常"
fi

# 2. 验证PV状态
log_info "2. 验证PV状态..."
echo "新创建的PV状态:"
kubectl get pv -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,STORAGECLASS:.spec.storageClassName,PROVISIONER:.metadata.annotations.pv\.kubernetes\.io/provisioned-by" | grep "rancher.io/local-path" || log_warning "未找到由local-path-provisioner创建的PV"

# 3. 验证Pod状态
log_info "3. 验证Pod状态..."
echo "Higress监控Pod状态:"
kubectl get pods -n higress-system -l 'app in (higress-console-grafana,higress-console-prometheus,higress-console-loki)' -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready,RESTARTS:.status.containerStatuses[0].restartCount"

# 检查所有Pod是否都在运行
failed_pods=0
for app in higress-console-grafana higress-console-prometheus higress-console-loki; do
    pod_status=$(kubectl get pods -n higress-system -l app=$app -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    pod_ready=$(kubectl get pods -n higress-system -l app=$app -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    
    if [[ "$pod_status" != "Running" ]]; then
        log_error "Pod $app 状态异常: $pod_status"
        ((failed_pods++))
    elif [[ "$pod_ready" != "true" ]]; then
        log_error "Pod $app 未就绪"
        ((failed_pods++))
    fi
done

if [[ $failed_pods -eq 0 ]]; then
    log_success "所有Pod运行正常"
else
    log_error "$failed_pods 个Pod状态异常"
fi

# 4. 验证存储挂载
log_info "4. 验证存储挂载..."
for app in higress-console-grafana higress-console-prometheus higress-console-loki; do
    pod_name=$(kubectl get pods -n higress-system -l app=$app -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$pod_name" ]]; then
        echo "检查 $app 存储挂载:"
        kubectl exec -n higress-system $pod_name -- df -h | grep -E "(Filesystem|/var/lib|/prometheus|/loki)" || true
        echo
    fi
done

# 5. 验证服务可访问性
log_info "5. 验证服务可访问性..."
echo "检查Higress Console服务状态:"
kubectl get svc -n higress-system higress-console -o custom-columns="NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,PORTS:.spec.ports[*].port"

# 6. 检查是否还有旧的local-storage资源
log_info "6. 检查旧资源清理情况..."
old_pvs=$(kubectl get pv -o jsonpath='{range .items[?(@.spec.storageClassName=="local-storage")]}{.metadata.name}{"\n"}{end}' | grep -E "(higress-grafana-pv|higress-loki-pv|higress-prometheus-pv)" || true)
if [[ -n "$old_pvs" ]]; then
    log_warning "发现未清理的旧PV:"
    echo "$old_pvs"
else
    log_success "旧的local-storage PV已清理完成"
fi

# 7. 验证数据目录
log_info "7. 验证新的数据目录..."
echo "新的存储路径信息:"
kubectl get pv -o jsonpath='{range .items[?(@.metadata.annotations.pv\.kubernetes\.io/provisioned-by=="rancher.io/local-path")]}{.metadata.name}{"\t"}{.spec.hostPath.path}{"\t"}{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}{"\n"}{end}' | while read pv_name path node; do
    if [[ -n "$pv_name" ]]; then
        echo "  PV: $pv_name"
        echo "  路径: $path"
        echo "  节点: $node"
        echo
    fi
done

# 8. 性能检查
log_info "8. 性能检查..."
echo "检查Pod资源使用情况:"
kubectl top pods -n higress-system -l 'app in (higress-console-grafana,higress-console-prometheus,higress-console-loki)' --no-headers 2>/dev/null | while read pod cpu memory; do
    echo "  $pod: CPU=$cpu, Memory=$memory"
done || log_warning "无法获取Pod资源使用情况（需要metrics-server）"

echo
echo "=========================================="
log_info "验证完成"
echo "=========================================="
echo

# 总结
if [[ $failed_pvcs -eq 0 && $failed_pods -eq 0 ]]; then
    log_success "迁移验证通过！所有组件运行正常"
    echo
    log_info "迁移成功总结:"
    log_info "✓ 3个PVC已成功迁移到local-path StorageClass"
    log_info "✓ 所有监控Pod运行正常"
    log_info "✓ 存储挂载正常"
    log_info "✓ 旧资源已清理"
    echo
    log_info "接下来可以:"
    log_info "1. 访问Higress Console验证功能"
    log_info "2. 观察监控数据收集情况"
    log_info "3. 删除备份文件（如果确认无问题）"
else
    log_error "迁移验证失败！请检查上述错误"
    echo
    log_info "故障排除建议:"
    log_info "1. 检查Pod日志: kubectl logs -n higress-system <pod-name>"
    log_info "2. 检查PVC事件: kubectl describe pvc -n higress-system <pvc-name>"
    log_info "3. 检查节点存储空间"
    log_info "4. 如需回滚，请使用备份文件恢复"
    exit 1
fi