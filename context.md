# 本地局域网 Kubernetes 集群配置概览

- **集群名称**：`kubernetes-admin@kubernetes`
- **用途**：局域网服务部署、测试与自动化
- **架构**：多节点（Debian/Ubuntu），多 control-plane，支持高可用
- **默认 Ingress 控制器**：Higress（多协议、可视化、支持 cert-manager 联动）
- **证书自动化**：cert-manager（ACME + Cloudflare DNS-01）
- **默认 LoadBalancer**：MetalLB（为裸金属集群提供 LoadBalancer 服务）
- **域名示例**：`*.maywzh.com` 通过 Cloudflare DNS 解析

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

2. **核心组件部署**：
   - higress-gateway（LoadBalancer 类型，暴露 80/443，分配了 MetalLB IP）
   - higress-controller（负责控制面）
   - higress-console（可视化管理，配套 Grafana/Prometheus/Loki 监控栈）

3. **流量入口与证书**：
   - 绝大多数 Ingress（如 dify、langfuse、higress-console 等）都通过 higress-gateway 统一暴露，域名均指向 192.168.2.152。
   - 证书 secretName 统一为 `*-tls`，通过 cert-manager 自动签发（如 higress-console-tls、higress-gateway-tls）。
   - 相关 ConfigMap（如 domain-higress.maywzh.com）开启了 enableHttps，绑定了证书。

4. **自定义路由与 AI 服务**：
   - 存在 ai-route-gemini-25-pro、ai-route-glm-45 等 Ingress，使用了 Higress 的自定义注解（如 higress.io/destination、higress.io/exact-match-header-x-higress-llm-model），实现了基于 header 的智能路由和后端服务动态分发。
   - 路由规则和模型映射通过 ConfigMap 动态配置，支持多 AI 服务统一入口。

5. **安全与可观测性**：
   - 配置了 CA 根证书（higress-ca-root-cert），支持 mTLS。
   - 配置了 Prometheus、Loki、Grafana 监控与日志采集，Promtail 负责日志推送。

6. **自动化与声明式管理**：
   - 绝大多数 Ingress 资源由 Higress 控制器自动生成和管理（带有 `PLEASE DO NOT EDIT DIRECTLY` 注解）。
   - 证书签发、路由、AI 服务注册等均声明式、自动化，无需手动干预。

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

## 集群 Higress 实际配置分析

### 1. 流量入口
- Higress 作为默认 IngressClass，统一接管所有 Ingress 资源。
- 流量通过 `higress-gateway`（LoadBalancer 类型 Service，80/443 端口，MetalLB 分配 IP 192.168.2.152）统一暴露。
- 主要业务域名（如 dify、langfuse、higress-console 等）均指向该入口，实现南北向流量统一管理。

### 2. AI 路由能力
- 存在多条 AI 服务路由（如 ai-route-gemini-25-pro、ai-route-glm-45），通过 Ingress 及 ConfigMap 动态配置。
- 支持基于 header（如 x-higress-llm-model）智能分流、路径前缀匹配、后端服务动态分发。
- 路由规则声明式管理，支持多 AI 服务统一入口和模型映射。

### 3. 证书自动化
- 所有 Ingress 通过 `tls.secretName` 及 cert-manager 注解实现自动签发证书（如 higress-gateway-tls、higress-console-tls）。
- 相关 ConfigMap（如 domain-higress.maywzh.com）开启 enableHttps，自动绑定证书。
- 证书生命周期、续期、分发全自动，无需人工干预。

### 4. 监控与可观测性
- Higress 配套部署了 Prometheus、Loki、Grafana 监控栈。
- Promtail 负责采集和推送网关日志，Loki 负责日志存储与查询。
- Grafana 提供可视化仪表盘，Prometheus 采集流量、性能等指标。
- 支持自定义 access log 格式和多维度监控。

---

> 以上为本集群 Higress 关键能力的实际落地情况，涵盖流量统一入口、AI 智能路由、证书自动化与全栈可观测。
