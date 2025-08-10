# dify k8s 配置与集群实际状态对比报告

## 1. 命名空间
- **期望**：dify 存在
- **实际**：存在（Active）

## 2. 配置与密钥
- **ConfigMap dify-config**：存在，关键键值与清单一致
- **ConfigMap dify-ssrf-proxy-config**：存在，含 squid.conf.template 与 docker-entrypoint.sh
- **Secret dify-secrets**：10 个关键键全部存在

## 3. 存储
- **PV dify-storage-pv**：10Gi，local-storage，Bound，属性匹配
- **PV dify-plugin-storage-pv**：5Gi，local-storage，Bound，属性匹配
- **PVC dify-storage-pvc / dify-plugin-storage-pvc**：均 Bound，容量与 storageClass 匹配

## 4. 工作负载（Deployments）
- **dify-api**：2/2 可用，镜像 langgenius/dify-api:latest
- **dify-worker**：1/1 可用，镜像 langgenius/dify-api:latest
- **dify-web**：2/2 可用，镜像 langgenius/dify-web:latest
- **dify-sandbox**：1/1 可用，镜像 langgenius/dify-sandbox:0.2.12
- **dify-plugin-daemon**：1/1 可用，镜像 langgenius/dify-plugin-daemon:0.2.0-local
- **dify-ssrf-proxy**：1/1 可用，镜像 ubuntu/squid:latest

## 5. 服务（Services）
- **dify-api-service**：ClusterIP 5001/TCP
- **dify-web-service**：ClusterIP 3000/TCP
- **dify-sandbox-service**：ClusterIP 8194/TCP
- **dify-plugin-daemon-service**：ClusterIP 5002/5003 TCP
- **dify-ssrf-proxy-service**：ClusterIP 3128/TCP

## 6. 入口（Ingress）
- **dify-web-ingress**：class=higress，host=dify.maywzh.com，规则与注解匹配
- **dify-api-ingress**：class=higress，host=dify-api.maywzh.com，规则匹配
- **dify-ingress（已弃用）**：集群中未部署，仅仓库保留

## 7. 差异与建议
- 所有关键资源与配置均与仓库清单一致，运行状态健康。
- 唯一差异：仓库包含已弃用的 40-ingress.yaml，线上未部署。建议删除或重命名该文件，避免误 apply。
- 可选微调：api/worker 的 CODE_EXECUTION_API_KEY 可只从 Secret 注入，ConfigMap 可移除该键。

---

如需持续核查，可用脚本 `k8s-status-check.sh` 自动输出所有关键状态与差异。
