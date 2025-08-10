# Dify Kubernetes 部署与 Docker Compose 部署对比调研

本文档详细对比了 Dify 在 Kubernetes 和 Docker Compose 两种部署方式的异同，帮助用户了解两种部署方式的差异和迁移注意事项。

## 1. 服务完整性对比

### 相同点
两种部署方式都包含了 Dify 所需的核心服务组件：
- API 服务 (dify-api)
- Worker 服务 (dify-worker)
- Web 前端 (dify-web)
- 代码沙箱 (dify-sandbox)
- 插件守护进程 (dify-plugin-daemon)
- SSRF 代理 (dify-ssrf-proxy)
- 外部依赖：PostgreSQL 数据库、Redis 缓存、Milvus 向量数据库

### 不同点
- **Docker Compose**：所有服务作为容器在单个主机上运行
- **Kubernetes**：服务以 Deployment 形式部署，通过 Service 实现服务发现和负载均衡

## 2. 架构设计对比

### Docker Compose 架构
- 服务间通过 Docker 网络进行通信
- 使用服务名称进行服务发现
- 数据持久化通过 Docker 卷实现
- 外部访问通过端口映射实现

### Kubernetes 架构
- 服务间通过 Kubernetes DNS 进行通信 (`service.namespace.svc.cluster.local`)
- 数据持久化通过 PersistentVolumeClaim 实现
- 外部访问通过 Ingress 控制器实现
- 服务通过 Deployment 和 Service 资源进行管理

## 3. 配置一致性分析

### 环境变量配置
大部分核心配置在两种部署方式中保持一致，但存在以下差异：

#### Kubernetes 特有配置
- 服务发现地址采用 Kubernetes DNS 格式
- 存储配置使用 PersistentVolumeClaim
- 敏感信息存储在 Secret 中

#### Docker Compose 特有配置
- 部分配置通过 `.env` 文件管理
- 服务发现使用 Docker 内置 DNS
- 存储配置使用卷挂载

### 配置管理方式
- **Docker Compose**：通过 `environment` 和 `env_file` 指令配置环境变量
- **Kubernetes**：通过 ConfigMap 和 Secret 分别管理普通配置和敏感信息

## 4. 安全性对比

### Kubernetes 安全优势
- 敏感信息（如密码、API 密钥）存储在 Secret 中，而非环境变量
- 支持基于角色的访问控制（RBAC）
- 网络策略可限制服务间通信
- 更细粒度的资源配额管理

### 需要改进的安全点
根据项目规范，当前 Kubernetes 部署中仍存在以下安全问题：
- 部分敏感信息（如 SECRET_KEY）错误地存储在 ConfigMap 中，应移至 Secret

## 5. 可扩展性与高可用性对比

### Kubernetes 优势
- 支持水平扩展（通过修改 replicas 数量）
- 内置健康检查机制（liveness 和 readiness probes）
- 更好的资源管理（CPU 和内存请求/限制）
- 自动故障恢复能力

### Docker Compose 限制
- 扩展能力有限
- 缺少内置的健康检查机制
- 资源管理相对简单

## 6. 部署复杂度对比

### Kubernetes 部署复杂度
- 需要管理多个 YAML 文件
- 需要配置 Ingress、Service、Deployment 等多种资源
- 需要配置 PersistentVolumeClaim 和 StorageClass
- 需要配置 ConfigMap 和 Secret

### Docker Compose 部署复杂度
- 通过单一 docker-compose.yaml 文件管理
- 配置相对简单直观
- 适合快速部署和测试

## 7. 当前 Kubernetes 部署存在的问题

### 配置问题
1. 镜像引用使用占位符 `my-docker-registry/dify-*:custom-v1`，需要替换为实际镜像路径
2. 域名配置使用占位符 `your-dify-domain.com`，需要替换为实际域名
3. 部分敏感信息存储在 ConfigMap 中，违反安全规范

### 功能完整性问题
1. 缺少部分在 Docker Compose 中存在的环境变量（如 INIT_PASSWORD、ENABLE_REQUEST_LOGGING 等）
2. 存储配置不一致（Kubernetes 使用 local 存储，而 Docker Compose 配置为 S3）

## 8. 待办事项清单

根据前面的分析，我们需要执行以下改进任务：

### 优先级：高（安全相关）
- [x] 将 SECRET_KEY 从 ConfigMap 移至 Secret
- [x] 将 S3_ACCESS_KEY 和 S3_SECRET_KEY 添加到 Secret（如果使用 S3 存储）

### 优先级：高（功能完整性）
- [x] 更新镜像引用，替换占位符为实际镜像路径
- [x] 更新 Ingress 域名配置，替换占位符为实际域名
- [x] 添加缺失的环境变量到 ConfigMap（INIT_PASSWORD、ENABLE_REQUEST_LOGGING 等）

### 优先级：中（配置一致性）
- [x] 配置存储方案（选择 S3 或保持本地存储）
- [ ] 添加 TLS 配置到 Ingress（如需要 HTTPS）- 暂不处理

### 优先级：低（优化）
- [ ] 验证所有服务的资源请求和限制是否合理
- [ ] 确认所有服务的探针配置是否合适

## 9. 改进方案实施

### 9.1 添加 TLS 配置到 Ingress

#### 任务描述
为 Ingress 添加 TLS 配置以支持 HTTPS 访问。

#### 实施步骤
1. 准备 TLS 证书和私钥
2. 创建包含证书的 Secret
3. 更新 Ingress 配置以启用 TLS

#### 预期结果
应用可通过 HTTPS 安全访问。

#### 实施状态
⏹️ **暂不处理** - 根据最新要求，TLS 配置暂不处理。

## 10. 已完成的对齐项验证

通过详细检查，我们确认 Kubernetes 部署与 Docker Compose 部署在以下方面已对齐：

### 10.1 环境变量对齐验证
- ✅ 所有必要的环境变量都已添加到 ConfigMap 中
- ✅ 环境变量值与 Docker Compose 保持一致
- ✅ 特殊环境变量(如路径、超时设置)配置一致

### 10.2 敏感信息对齐验证
- ✅ 所有敏感信息都已从环境变量迁移到 Secret 中
- ✅ Secret 中的敏感数据值正确
- ✅ Deployment 中正确引用了 Secret 中的敏感信息

### 10.3 外部依赖配置验证
- ✅ 数据库配置一致(主机: dbnode0.maywzh.com, 端口: 5432, 数据库名: dify)
- ✅ Redis 配置一致(主机: dbnode0.maywzh.com, 端口: 6379)
- ✅ 向量数据库(Milvus)配置一致(主机: dbnode0.maywzh.com, 端口: 19530)

### 10.4 存储配置验证
- ✅ 存储类型配置为 S3，与 Docker Compose 一致
- ✅ S3 存储相关参数(端点、区域、存储桶名称)一致
- ✅ S3 访问凭证已正确配置在 Secret 中

### 10.5 服务完整性验证
- ✅ 所有必要的服务都已部署(API、Worker、Web、Sandbox、Plugin Daemon、SSRF Proxy)
- ✅ 服务间的依赖关系已正确配置
- ✅ 服务发现配置正确(使用 Kubernetes 内部 DNS)

### 10.6 服务配置对齐检查
- ✅ API 服务资源配置合理(请求: 512Mi内存/250mCPU, 限制: 1Gi内存/500mCPU)
- ✅ Worker 服务资源配置合理(请求: 512Mi内存/250mCPU, 限制: 1Gi内存/500mCPU)
- ✅ Web 服务资源配置合理(请求: 256Mi内存/100mCPU, 限制: 512Mi内存/200mCPU)
- ✅ API 服务副本数配置为 2，提供了高可用性
- ✅ Worker 服务副本数配置为 1，可根据需要扩展
- ✅ Web 服务副本数配置为 2，提供了高可用性
- ✅ 所有服务都配置了存活探针和就绪探针

### 10.7 网络配置对齐检查
- ✅ Service 配置与 Docker Compose 中的服务端口映射一致
  - API 服务端口: 5001
  - Web 服务端口: 3000
  - Plugin Daemon 服务端口: 5002
  - Sandbox 服务端口: 8194
- ✅ Ingress 配置已拆分为两个主机
   - dify.maywzh.com（Web）：/console(/|$)(.*) -> Web，/console/api -> API，/ -> Web
   - dify-api.maywzh.com（API）：/api 和 /console/api -> API
- ✅ 域名已拆分为 dify.maywzh.com（Web）与 dify-api.maywzh.com（API）

## 11. 部署脚本使用

为了简化部署流程，我们提供了一个自动化部署脚本 [deploy.sh](file:///Users/maywzh/Workspace/dify/k8s/deploy.sh)，它会按照正确的顺序部署所有 Kubernetes 资源。

### 11.1 使用方法

```bash
cd k8s
./deploy.sh
```

### 11.2 部署顺序说明

脚本将按照以下顺序部署资源：

1. 设置 Kubernetes 上下文
2. 创建命名空间
3. 部署 ConfigMap 和 Secrets
4. 部署存储资源
5. 部署核心服务（API、Worker、Web）
6. 部署辅助服务（Sandbox、Plugin Daemon、SSRF Proxy）
7. 部署 Ingress 资源（40-web-ingress.yaml 与 41-api-ingress.yaml）
8. 等待 Pod 就绪

### 11.3 验证部署

部署完成后，可以使用以下命令验证部署状态：

```bash
kubectl get pods -n dify
kubectl get services -n dify
kubectl get ingress -n dify
```

## 12. 验证部署

部署完成后，应验证以下内容：

1. 所有 Pod 是否正常运行：
   ```bash
   kubectl get pods -n dify
   ```

2. 所有服务是否正常：
   ```bash
   kubectl get services -n dify
   ```

3. Ingress 是否正常：
   ```bash
   kubectl get ingress -n dify
   ```

4. 访问应用验证功能是否正常

## 总结

通过以上改进方案，可以解决当前 Kubernetes 部署中存在的问题，使其更加安全、完整和符合最佳实践。实施这些改进后，Kubernetes 部署将与 Docker Compose 部署在功能上保持一致，同时具备 Kubernetes 平台的优势。
