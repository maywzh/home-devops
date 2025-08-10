# Higress存储迁移指南：从local-storage到local-path

## 📋 概述

本文档提供了将Higress监控组件的存储从`local-storage`迁移到`local-path-provisioner`的完整方案。

### 迁移背景
- **当前状态**：Higress监控组件（Grafana、Prometheus、Loki）使用手动创建的`local-storage`类型PV
- **目标状态**：迁移到`local-path`动态存储供应器，实现自动化存储管理
- **迁移原因**：提高运维效率、统一存储方案、支持动态供应

## 🔍 当前集群存储状态

### 需要迁移的资源

| 组件 | PVC名称 | PV名称 | 存储大小 | 当前StorageClass | 绑定节点 |
|------|---------|--------|----------|------------------|----------|
| Grafana | `higress-console-grafana` | `higress-grafana-pv` | 1Gi | `local-storage` | debian-node1 |
| Prometheus | `higress-console-prometheus` | `higress-loki-pv` | 1Gi | `local-storage` | debian-node1 |
| Loki | `higress-console-loki` | `higress-prometheus-pv` | 1Gi | `local-storage` | debian-node1 |

### 已使用local-path的资源（无需迁移）

| 组件 | PVC名称 | 存储大小 | StorageClass |
|------|---------|----------|--------------|
| Dify | `dify-storage-pvc` | 10Gi | `local-path` |
| Dify Plugin | `dify-plugin-storage-pvc` | 5Gi | `local-path` |

## 🚀 迁移方案

### 迁移策略
采用**数据备份+重新部署**策略：
- ✅ 操作简单，风险可控
- ✅ 确保迁移后配置完全正确
- ⚠️ 会丢失历史监控数据（可接受）
- ⚠️ 短暂的监控服务中断（15-30分钟）

### 迁移步骤概览
1. **环境检查** - 验证前置条件
2. **配置备份** - 备份当前配置
3. **停止服务** - 缩容监控组件
4. **清理资源** - 删除旧PVC和PV
5. **创建新PVC** - 使用local-path StorageClass
6. **恢复服务** - 重启监控组件
7. **验证结果** - 确认迁移成功

## 📁 文件说明

| 文件名 | 用途 | 说明 |
|--------|------|------|
| `pre-migration-check.sh` | 迁移前检查 | 验证环境是否满足迁移条件 |
| `higress-storage-migration.sh` | 主迁移脚本 | 执行完整的迁移流程 |
| `post-migration-verify.sh` | 迁移后验证 | 验证迁移结果和系统状态 |
| `STORAGE_MIGRATION_README.md` | 文档 | 完整的迁移指南 |

## 🛠️ 执行步骤

### 1. 迁移前检查
```bash
# 赋予执行权限
chmod +x pre-migration-check.sh

# 执行环境检查
./pre-migration-check.sh
```

**检查内容：**
- Kubernetes集群连接
- local-path-provisioner状态
- StorageClass配置
- 当前存储资源状态
- Higress监控组件状态
- 节点存储空间

### 2. 执行迁移
```bash
# 赋予执行权限
chmod +x higress-storage-migration.sh

# 执行迁移（需要确认）
./higress-storage-migration.sh
```

**迁移过程：**
- 自动备份当前配置
- 停止监控服务（缩容到0副本）
- 删除旧的PVC和PV
- 创建新的local-path类型PVC
- 恢复监控服务
- 验证迁移结果

### 3. 迁移后验证
```bash
# 赋予执行权限
chmod +x post-migration-verify.sh

# 执行验证
./post-migration-verify.sh
```

**验证内容：**
- PVC状态和StorageClass
- PV创建和绑定状态
- Pod运行状态
- 存储挂载情况
- 服务可访问性
- 旧资源清理情况

## ⚠️ 风险评估

| 风险 | 影响程度 | 概率 | 缓解措施 |
|------|----------|------|----------|
| 历史监控数据丢失 | 中 | 100% | 可接受，监控数据可重新收集 |
| 监控服务短暂中断 | 低 | 100% | 业务流量不受影响，仅监控中断 |
| PVC创建失败 | 高 | 低 | 提前验证local-path-provisioner |
| Pod调度失败 | 中 | 低 | 确保节点存储空间充足 |
| 迁移脚本执行失败 | 中 | 低 | 提供配置备份和回滚方案 |

## 🔧 故障排除

### 常见问题

#### 1. local-path-provisioner未就绪
```bash
# 检查状态
kubectl get deployment -n local-path-storage local-path-provisioner

# 查看日志
kubectl logs -n local-path-storage deployment/local-path-provisioner
```

#### 2. PVC创建失败
```bash
# 检查PVC事件
kubectl describe pvc -n higress-system <pvc-name>

# 检查StorageClass
kubectl get storageclass local-path -o yaml
```

#### 3. Pod启动失败
```bash
# 查看Pod状态
kubectl get pods -n higress-system -l 'app in (higress-console-grafana,higress-console-prometheus,higress-console-loki)'

# 查看Pod日志
kubectl logs -n higress-system <pod-name>

# 查看Pod事件
kubectl describe pod -n higress-system <pod-name>
```

### 回滚方案

如果迁移失败，可以使用备份文件回滚：

```bash
# 找到备份目录
ls -la higress-migration-backup-*

# 恢复PV配置
kubectl apply -f higress-migration-backup-*/pv-backup.yaml

# 恢复PVC配置
kubectl apply -f higress-migration-backup-*/pvc-backup.yaml

# 重启服务
kubectl rollout restart deployment -n higress-system higress-console-grafana
kubectl rollout restart deployment -n higress-system higress-console-prometheus
kubectl rollout restart deployment -n higress-system higress-console-loki
```

## 📊 迁移前后对比

### 存储配置对比

| 特性 | 迁移前 (local-storage) | 迁移后 (local-path) |
|------|----------------------|---------------------|
| **PV创建方式** | 手动创建 | 自动创建 |
| **存储路径** | 固定路径 `/data/higress/*` | 动态路径 `/opt/local-path-provisioner/*` |
| **节点绑定** | 手动指定 `debian-node1` | 自动选择节点 |
| **扩展性** | 需要手动操作 | 支持动态扩展 |
| **运维复杂度** | 高 | 低 |
| **一致性** | 与集群其他应用不一致 | 与集群标准一致 |

### 预期收益

1. **运维效率提升**：无需手动创建PV，减少运维工作量
2. **配置标准化**：与集群其他应用使用统一的存储方案
3. **扩展性增强**：支持动态存储供应，便于后续扩展
4. **故障恢复简化**：PVC删除重建更简单

## 📝 注意事项

1. **数据丢失**：迁移会清空历史监控数据，请确认可接受
2. **服务中断**：监控服务会短暂中断，但不影响业务流量
3. **执行时机**：建议在业务低峰期执行
4. **备份保留**：迁移成功后建议保留备份一段时间
5. **验证充分**：迁移后务必执行完整验证

## 🎯 执行清单

- [ ] 阅读完整迁移文档
- [ ] 确认迁移时间窗口
- [ ] 执行迁移前检查
- [ ] 备份重要配置（脚本自动完成）
- [ ] 执行迁移脚本
- [ ] 执行迁移后验证
- [ ] 确认监控功能正常
- [ ] 观察系统稳定性
- [ ] 清理备份文件（可选）

## 📞 支持

如果在迁移过程中遇到问题，请：

1. 查看脚本输出的错误信息
2. 参考故障排除章节
3. 检查Kubernetes集群日志
4. 必要时使用备份文件回滚

---

**迁移完成后，您的Higress监控存储将完全使用local-path-provisioner，享受更高效的存储管理体验！**