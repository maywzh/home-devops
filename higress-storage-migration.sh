#!/bin/bash

# Higress监控存储迁移脚本：从local-storage迁移到local-path
# 作者：Kilo Code
# 日期：2025-08-10

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 检查前置条件
check_prerequisites() {
    log_info "检查前置条件..."
    
    # 检查kubectl连接
    if ! kubectl cluster-info &>/dev/null; then
        log_error "无法连接到Kubernetes集群"
        exit 1
    fi
    
    # 检查local-path-provisioner
    if ! kubectl get deployment -n local-path-storage local-path-provisioner &>/dev/null; then
        log_error "local-path-provisioner未安装"
        exit 1
    fi
    
    # 检查local-path StorageClass
    if ! kubectl get storageclass local-path &>/dev/null; then
        log_error "local-path StorageClass不存在"
        exit 1
    fi
    
    log_success "前置条件检查通过"
}

# 备份当前配置
backup_current_config() {
    log_info "备份当前配置..."
    
    backup_dir="higress-migration-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    
    # 备份PVC配置
    kubectl get pvc -n higress-system higress-console-grafana higress-console-prometheus higress-console-loki -o yaml > "$backup_dir/pvc-backup.yaml" 2>/dev/null || true
    
    # 备份PV配置
    kubectl get pv higress-grafana-pv higress-loki-pv higress-prometheus-pv -o yaml > "$backup_dir/pv-backup.yaml" 2>/dev/null || true
    
    # 备份Deployment配置
    kubectl get deployment -n higress-system higress-console-grafana higress-console-prometheus higress-console-loki -o yaml > "$backup_dir/deployment-backup.yaml" 2>/dev/null || true
    
    log_success "配置已备份到: $backup_dir"
    echo "$backup_dir" > .migration-backup-dir
}

# 停止监控服务
stop_monitoring_services() {
    log_info "停止监控服务..."
    
    # 缩容到0副本
    kubectl scale deployment -n higress-system higress-console-grafana --replicas=0 --timeout=60s
    kubectl scale deployment -n higress-system higress-console-prometheus --replicas=0 --timeout=60s
    kubectl scale deployment -n higress-system higress-console-loki --replicas=0 --timeout=60s
    
    # 等待Pod完全停止
    log_info "等待Pod完全停止..."
    kubectl wait --for=delete pod -n higress-system -l app=higress-console-grafana --timeout=120s || true
    kubectl wait --for=delete pod -n higress-system -l app=higress-console-prometheus --timeout=120s || true
    kubectl wait --for=delete pod -n higress-system -l app=higress-console-loki --timeout=120s || true
    
    log_success "监控服务已停止"
}

# 清理旧存储资源
cleanup_old_storage() {
    log_info "清理旧存储资源..."
    
    # 删除PVC（会自动解绑PV）
    kubectl delete pvc -n higress-system higress-console-grafana --ignore-not-found=true --timeout=60s
    kubectl delete pvc -n higress-system higress-console-prometheus --ignore-not-found=true --timeout=60s
    kubectl delete pvc -n higress-system higress-console-loki --ignore-not-found=true --timeout=60s
    
    # 等待PVC完全删除
    log_info "等待PVC完全删除..."
    sleep 10
    
    # 删除手动创建的PV
    kubectl delete pv higress-grafana-pv --ignore-not-found=true --timeout=60s
    kubectl delete pv higress-loki-pv --ignore-not-found=true --timeout=60s
    kubectl delete pv higress-prometheus-pv --ignore-not-found=true --timeout=60s
    
    log_success "旧存储资源已清理"
}

# 创建新的PVC
create_new_pvcs() {
    log_info "创建新的PVC..."
    
    # 创建临时PVC配置文件
    cat > /tmp/higress-new-pvcs.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: higress-console-grafana
  namespace: higress-system
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: higress
    meta.helm.sh/release-namespace: higress-system
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: higress-console-prometheus
  namespace: higress-system
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: higress
    meta.helm.sh/release-namespace: higress-system
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: higress-console-loki
  namespace: higress-system
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: higress
    meta.helm.sh/release-namespace: higress-system
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 1Gi
EOF
    
    # 应用新的PVC配置
    kubectl apply -f /tmp/higress-new-pvcs.yaml
    
    # 等待PVC创建完成
    log_info "等待PVC创建完成..."
    kubectl wait --for=condition=Bound pvc -n higress-system higress-console-grafana --timeout=120s
    kubectl wait --for=condition=Bound pvc -n higress-system higress-console-prometheus --timeout=120s
    kubectl wait --for=condition=Bound pvc -n higress-system higress-console-loki --timeout=120s
    
    # 清理临时文件
    rm -f /tmp/higress-new-pvcs.yaml
    
    log_success "新PVC创建完成"
}

# 恢复监控服务
restore_monitoring_services() {
    log_info "恢复监控服务..."
    
    # 恢复副本数
    kubectl scale deployment -n higress-system higress-console-grafana --replicas=1
    kubectl scale deployment -n higress-system higress-console-prometheus --replicas=1
    kubectl scale deployment -n higress-system higress-console-loki --replicas=1
    
    # 等待Pod就绪
    log_info "等待Pod就绪..."
    kubectl wait --for=condition=Ready pod -n higress-system -l app=higress-console-grafana --timeout=300s
    kubectl wait --for=condition=Ready pod -n higress-system -l app=higress-console-prometheus --timeout=300s
    kubectl wait --for=condition=Ready pod -n higress-system -l app=higress-console-loki --timeout=300s
    
    log_success "监控服务已恢复"
}

# 验证迁移结果
verify_migration() {
    log_info "验证迁移结果..."
    
    # 检查PVC状态
    log_info "检查PVC状态:"
    kubectl get pvc -n higress-system higress-console-grafana higress-console-prometheus higress-console-loki
    
    # 检查PV状态
    log_info "检查新创建的PV:"
    kubectl get pv -l "pv.kubernetes.io/provisioned-by=rancher.io/local-path" --no-headers | grep higress || true
    
    # 检查Pod状态
    log_info "检查Pod状态:"
    kubectl get pods -n higress-system -l 'app in (higress-console-grafana,higress-console-prometheus,higress-console-loki)'
    
    # 验证StorageClass
    grafana_sc=$(kubectl get pvc -n higress-system higress-console-grafana -o jsonpath='{.spec.storageClassName}')
    prometheus_sc=$(kubectl get pvc -n higress-system higress-console-prometheus -o jsonpath='{.spec.storageClassName}')
    loki_sc=$(kubectl get pvc -n higress-system higress-console-loki -o jsonpath='{.spec.storageClassName}')
    
    if [[ "$grafana_sc" == "local-path" && "$prometheus_sc" == "local-path" && "$loki_sc" == "local-path" ]]; then
        log_success "所有PVC已成功迁移到local-path StorageClass"
    else
        log_error "StorageClass验证失败: grafana=$grafana_sc, prometheus=$prometheus_sc, loki=$loki_sc"
        return 1
    fi
    
    log_success "迁移验证通过"
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    rm -f /tmp/higress-new-pvcs.yaml
}

# 主函数
main() {
    log_info "开始Higress监控存储迁移..."
    log_info "从 local-storage 迁移到 local-path"
    echo
    
    # 确认操作
    read -p "确认开始迁移？这将重启监控组件并清空历史数据 (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "迁移已取消"
        exit 0
    fi
    
    # 设置错误处理
    trap cleanup EXIT
    
    # 执行迁移步骤
    check_prerequisites
    backup_current_config
    stop_monitoring_services
    cleanup_old_storage
    create_new_pvcs
    restore_monitoring_services
    verify_migration
    
    log_success "迁移完成！"
    echo
    log_info "迁移总结:"
    log_info "- 3个PVC已从local-storage迁移到local-path"
    log_info "- 监控服务已恢复正常运行"
    log_info "- 历史监控数据已重置，新数据将开始收集"
    
    if [[ -f .migration-backup-dir ]]; then
        backup_dir=$(cat .migration-backup-dir)
        log_info "- 配置备份保存在: $backup_dir"
        rm -f .migration-backup-dir
    fi
}

# 执行主函数
main "$@"