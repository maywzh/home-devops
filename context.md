# 本地局域网 Kubernetes 集群配置概览

- **集群名称**：`kubernetes-admin@kubernetes`
- **Kubernetes 版本**：v1.32.0 (服务端) / v1.33.3 (客户端)
- **用途**：局域网服务部署、测试与自动化
- **架构**：多节点（Debian/Ubuntu），多 control-plane，支持高可用
- **节点总数**：11 个节点
  - **Control Plane 节点**：3 个 (debian-node3, debian-node4, node)
  - **Worker 节点**：8 个 (6个 Debian + 4个 Ubuntu)
  - **操作系统**：Debian GNU/Linux 12 (bookworm) 和 Ubuntu 24.04.2 LTS
  - **容器运行时**：containerd 1.7.25-1.7.27
- **默认 Ingress 控制器**：Higress（多协议、可视化、支持 cert-manager 联动）
- **证书自动化**：cert-manager（ACME + Cloudflare DNS-01）
- **默认 LoadBalancer**：MetalLB（为裸金属集群提供 LoadBalancer 服务）
- **存储解决方案**：Longhorn（分布式块存储，默认 StorageClass）+ local-path（本地路径存储）
- **域名示例**：`*.maywzh.com` 通过 Cloudflare DNS 解析
- **网关入口 IP**：192.168.2.152 (MetalLB 分配)

## 集群节点详情

### Control Plane 节点
- **debian-node3** (192.168.2.110) - Debian 12, Ready
- **debian-node4** (192.168.2.109) - Debian 12, Ready
- **node** (192.168.2.111) - Debian 12, Ready,SchedulingDisabled

### Worker 节点
**Debian 节点：**
- **debian-node1** (192.168.2.112) - Debian 12, Ready
- **debian-node2** (192.168.2.113) - Debian 12, Ready
- **debian-node5** (192.168.2.114) - Debian 12, Ready
- **debian-node6** (192.168.2.116) - Debian 12, Ready (最新加入，33小时前)

**Ubuntu 节点：**
- **ubuntu-node0** (192.168.2.117) - Ubuntu 24.04.2 LTS, Ready
- **ubuntu-node1** (192.168.2.118) - Ubuntu 24.04.2 LTS, Ready
- **ubuntu-node2** (192.168.2.119) - Ubuntu 24.04.2 LTS, Ready
- **ubuntu-node4** (192.168.2.121) - Ubuntu 24.04.2 LTS, Ready

## 核心组件状态

### 命名空间概览
- **cert-manager** (121天) - 证书管理
- **dify** (2天16小时) - AI 应用平台
- **external-dns** (122天) - 外部 DNS 管理
- **higress-system** (4天4小时) - 网关系统
- **langfuse** (2天20小时) - LLM 应用监控
- **local-path-storage** (32小时) - 本地路径存储
- **longhorn-system** (29小时) - 分布式存储
- **metallb-system** (188天) - 负载均衡器
- **monitoring** (8天) - 监控系统

### 存储系统
- **Longhorn**：分布式块存储，默认 StorageClass，支持卷扩展
- **local-path**：本地路径存储，WaitForFirstConsumer 绑定模式
- **存储组件状态**：所有 Longhorn 组件运行正常，包括 CSI 驱动、管理器、UI 等

### 当前暴露的服务
通过 Higress 网关暴露的服务包括：
- **dify.maywzh.com** - Dify AI 应用平台
- **dify-api.maywzh.com** - Dify API 服务
- **langfuse.maywzh.com** - Langfuse 监控平台
- **langfuse-worker.maywzh.com** - Langfuse Worker 服务
- **higress.maywzh.com** - Higress 网关管理
- **higress-console.maywzh.com** - Higress 控制台
- **longhorn.maywzh.com** - Longhorn 存储管理界面

所有服务均通过 HTTPS (443) 和 HTTP (80) 端口暴露，证书由 cert-manager 自动管理。

---
## Higress 简介

Higress 是阿里巴巴开源的下一代云原生网关，基于开源 Istio + Envoy 构建，融合了流量网关、微服务网关和安全网关三大能力。

- **架构基础**：以 Envoy 和 Istio 为核心，结合阿里云生态实践，具备高集成、易扩展、热更新等特性。
- **主要功能**：
  - 遵循 Ingress/Gateway API 标准，支持流量调度、服务治理、安全防护三合一
  - 支持多注册中心（如 Nacos、Zookeeper、Eureka），可无缝集成 Spring Cloud 等主流微服务体系
  - 提供统一流量入口，简化网络架构，提升运维效率
  - 支持可视化控制台，降低使用门槛
  - 深度集成 cert-manager，实现 HTTPS 证书自动化
- **适用场景**：
  - 微服务架构下的 API 管理与安全控制
  - 多协议流量统一接入与治理
  - 企业级流量网关、零信任安全、API 网关等

Higress 通过统一入口和自动化能力，极大提升了云原生环境下的服务暴露、安全与运维效率。

集群 Higress 配置有如下关键特性和实际细节：

1. **默认 IngressClass**：higress 被设置为集群默认 IngressClass，所有未指定 ingressClassName 的 Ingress 也会被 Higress 接管。

2. **核心组件部署状态**：
   - **higress-gateway**：2 个副本运行中，LoadBalancer 类型，暴露 80/443 端口，MetalLB 分配 IP 192.168.2.152
   - **higress-controller**：1 个副本运行中，负责控制面管理
   - **higress-console**：1 个副本运行中，提供可视化管理界面
   - **监控栈组件**：
     - higress-console-grafana：可视化仪表盘
     - higress-console-loki：日志聚合存储
     - higress-console-prometheus：指标采集

3. **流量入口与证书**：
   - 所有 Ingress 资源（dify、langfuse、higress-console、longhorn 等）统一通过 higress-gateway 暴露
   - 统一入口 IP：192.168.2.152，支持 HTTP (80) 和 HTTPS (443)
   - 证书自动化：所有域名证书由 cert-manager 自动签发和续期
   - 当前活跃域名：
     - dify.maywzh.com / dify-api.maywzh.com
     - langfuse.maywzh.com / langfuse-worker.maywzh.com
     - higress.maywzh.com / higress-console.maywzh.com
     - longhorn.maywzh.com

4. **AI 智能路由**：
   - **ai-route-gemini-25-pro.internal**：Gemini 2.5 Pro 模型路由
   - **ai-route-glm-45.internal**：GLM-4.5 模型路由
   - 支持基于 header 的智能分流和模型映射
   - 统一 AI 服务入口：higress.maywzh.com

5. **高可用与负载均衡**：
   - Higress Gateway 采用 2 副本部署，分布在不同节点
   - MetalLB Speaker 在所有 11 个节点运行，确保负载均衡高可用
   - 控制器组件分布式部署，避免单点故障

6. **监控与可观测性**：
   - 完整的监控栈：Prometheus + Grafana + Loki
   - 实时日志采集和分析
   - 网关流量、性能指标监控
   - 可视化管理界面：higress-console.maywzh.com

---

如需将这些分析补充到 context.md，请确认需要聚焦哪些方面（如流量入口、AI 路由、证书自动化、监控等），我可直接写入文档。
## 关键自动化能力：Ingress 与 HTTPS 自动化

本集群通过 **Higress**、**cert-manager** 与 **Cloudflare** 的组合，实现了服务暴露和 HTTPS 证书的完全自动化。

- **Higress**：作为 IngressClass，负责流量入口、路由、HTTPS 跳转。
- **cert-manager**：负责证书签发与续期，自动生成 TLS Secret。
- **Cloudflare**：作为 DNS 提供商，支持 ACME DNS-01 验证，无需暴露80端口即可完成证书申请。

### 实践案例：以 `langfuse-web` 服务为例

#### 1. Ingress 配置

通过以下配置，将 `langfuse.maywzh.com` 的流量指向 `langfuse-web-svc` 服务，并声明使用 `letsencrypt-prod` 这个 ClusterIssuer 来自动申请证书。

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: langfuse-web-ingress
  namespace: langfuse
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: higress
  rules:
    - host: langfuse.maywzh.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: langfuse-web-svc
                port:
                  name: http-web
  tls:
    - hosts:
        - langfuse.maywzh.com
      secretName: langfuse-tls
```

#### 2. 证书资源（由 cert-manager 自动生成）

`cert-manager` 会根据 Ingress 的 `tls` 配置自动创建以下 `Certificate` 资源。

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: langfuse-tls
  namespace: langfuse
spec:
  secretName: langfuse-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
    - langfuse.maywzh.com
```

#### 3. ClusterIssuer 配置（全局证书签发器）

这是集群级别的证书签发器配置，定义了如何使用 Let's Encrypt 和 Cloudflare API 来完成 DNS-01 验证。

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: maywzh@gmail.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - dns01:
          cloudflare:
            email: maywzh@gmail.com
            apiTokenSecretRef:
              name: cloudflare-api-token-secret
              key: api-token
        selector:
          dnsZones:
            - maywzh.com
```

> 说明：
> - ClusterIssuer 需要由集群管理员手动创建（如 letsencrypt-prod），供所有 Ingress 使用。
> - Certificate 资源通常无需用户手动定义，cert-manager 会根据 Ingress 的注解和 tls 字段自动生成和管理。



### 总结

- **自动化流程**：开发者只需创建一个带有特定注解的 Ingress 资源，`cert-manager` 就会自动完成证书的申请、续期和配置，实现了 "一次配置，永久有效" 的 HTTPS 自动化。
- **推荐实践**：建议所有需要外网访问的服务都采用此模式，以统一集群的流量入口和证书管理策略。

---

## 集群当前状态总结

### 1. 集群健康状态
- **节点状态**：11 个节点全部 Ready，包括 3 个 control-plane 节点和 8 个 worker 节点
- **核心组件**：所有关键组件（Higress、cert-manager、MetalLB、Longhorn）运行正常
- **存储系统**：Longhorn 分布式存储已部署并设为默认 StorageClass，所有组件健康运行
- **网络**：MetalLB 在所有节点部署 Speaker，提供高可用负载均衡

### 2. 服务暴露现状
- **统一入口**：所有外部服务通过 Higress Gateway (192.168.2.152) 统一暴露
- **当前服务**：
  - **AI 平台**：Dify (dify.maywzh.com, dify-api.maywzh.com)
  - **监控工具**：Langfuse (langfuse.maywzh.com, langfuse-worker.maywzh.com)
  - **管理界面**：Higress Console (higress-console.maywzh.com), Longhorn UI (longhorn.maywzh.com)
  - **AI 路由**：智能模型路由 (higress.maywzh.com)
- **证书管理**：所有域名 HTTPS 证书由 cert-manager 自动管理，无需人工干预

### 3. 存储与持久化
- **主存储**：Longhorn 分布式块存储，支持副本、快照、备份
- **辅助存储**：local-path 本地路径存储，用于临时或测试用途
- **存储状态**：所有 CSI 组件、管理器、UI 组件运行正常

### 4. 监控与可观测性
- **网关监控**：Higress 集成 Prometheus + Grafana + Loki 完整监控栈
- **日志管理**：统一日志采集、存储和查询
- **可视化**：Grafana 仪表盘提供实时监控视图

### 5. 最新变化
- **新增节点**：debian-node6 (192.168.2.116) 于 33 小时前加入集群
- **存储升级**：Longhorn 系统于 29 小时前部署，替代原有存储方案
- **服务部署**：Dify 和 Langfuse 等 AI 相关服务近期部署完成

---

> **集群状态**：生产就绪，所有核心组件健康运行，具备高可用、自动化证书管理、统一流量入口和完整监控能力。适合部署各类云原生应用和 AI 服务。
