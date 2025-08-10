# Cloudflare配置MinIO服务详细指南

## 网络架构分析

### 当前架构
- **内网MinIO服务**: 192.168.2.3:9001
- **网关端口转发**: 公网IP:19001 → 192.168.2.3:9001
- **目标域名**: https://minio.maywzh.com
- **DNS管理**: Cloudflare

### 主要挑战
1. Cloudflare免费版不支持非标准端口19001的代理
2. 需要SSL/TLS终止和重新加密
3. MinIO需要正确的HTTPS配置以支持浏览器访问

## 解决方案概述

由于Cloudflare免费版的端口限制，我们将使用以下方案：
1. **方案A**: Cloudflare Workers代理（推荐）
2. **方案B**: 修改网关端口映射到标准端口

## 方案A: Cloudflare Workers代理（推荐）

### 步骤1: DNS记录配置

在Cloudflare DNS管理中添加：

```
类型: A
名称: minio
内容: 你的公网IP地址
代理状态: 已代理（橙色云朵）
TTL: 自动
```

或者使用CNAME（如果你有其他域名指向该IP）：

```
类型: CNAME
名称: minio
内容: your-domain.com
代理状态: 已代理（橙色云朵）
TTL: 自动
```

### 步骤2: SSL/TLS配置

1. 进入Cloudflare控制台 → SSL/TLS
2. 选择加密模式: **完全（严格）** 或 **完全**
   - 如果你的源服务器有有效SSL证书，选择"完全（严格）"
   - 如果没有或使用自签名证书，选择"完全"

### 步骤3: 创建Cloudflare Worker

1. 进入Cloudflare控制台 → Workers & Pages
2. 创建新的Worker
3. 使用以下代码：

```javascript
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  // 获取原始URL
  const url = new URL(request.url)
  
  // 构建目标URL，将请求转发到19001端口
  const targetUrl = new URL(request.url)
  targetUrl.hostname = '你的公网IP地址'  // 替换为实际IP
  targetUrl.port = '19001'
  targetUrl.protocol = 'http:'  // 如果源服务器使用HTTP
  
  // 创建新的请求
  const modifiedRequest = new Request(targetUrl.toString(), {
    method: request.method,
    headers: request.headers,
    body: request.body
  })
  
  // 转发请求
  try {
    const response = await fetch(modifiedRequest)
    
    // 创建新的响应，修复CORS和其他头部
    const modifiedResponse = new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: {
        ...response.headers,
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      }
    })
    
    return modifiedResponse
  } catch (error) {
    return new Response('Service Unavailable', { status: 503 })
  }
}
```

### 步骤4: 配置Worker路由

1. 在Worker设置中，添加路由：
   ```
   minio.maywzh.com/*
   ```

### 步骤5: MinIO服务配置

在MinIO服务器上，需要配置以下环境变量：

```bash
# MinIO配置
export MINIO_SERVER_URL="https://minio.maywzh.com"
export MINIO_BROWSER_REDIRECT_URL="https://minio.maywzh.com"

# 如果使用Docker
docker run -d \
  --name minio \
  -p 9001:9000 \
  -e MINIO_SERVER_URL="https://minio.maywzh.com" \
  -e MINIO_BROWSER_REDIRECT_URL="https://minio.maywzh.com" \
  -v /data:/data \
  minio/minio server /data --console-address ":9001"
```

## 方案B: 修改端口映射（备选方案）

如果可以修改网关配置，将端口映射改为标准端口：

### 支持的端口
Cloudflare免费版支持以下HTTP/HTTPS端口：
- HTTP: 80, 8080, 8880, 2052, 2082, 2086, 2095
- HTTPS: 443, 2053, 2083, 2087, 2096, 8443

### 配置步骤

1. **修改网关端口映射**:
   ```
   公网IP:8443 → 192.168.2.3:9001
   ```

2. **DNS记录配置**:
   ```
   类型: A
   名称: minio
   内容: 你的公网IP地址
   代理状态: 已代理（橙色云朵）
   ```

3. **页面规则配置**:
   - 进入Cloudflare → 页面规则
   - 创建规则：
     ```
     URL: minio.maywzh.com/*
     设置: 
     - 始终使用HTTPS: 开启
     - SSL: 完全
     ```

## 高级配置

### 页面规则优化

创建以下页面规则以优化性能：

1. **缓存规则**:
   ```
   URL: minio.maywzh.com/minio/v2/metrics/*
   设置: 缓存级别 = 绕过
   ```

2. **安全规则**:
   ```
   URL: minio.maywzh.com/*
   设置: 
   - 安全级别: 高
   - 始终使用HTTPS: 开启
   ```

### 防火墙规则

在Cloudflare防火墙中添加规则：

```
(http.host eq "minio.maywzh.com" and http.request.method eq "OPTIONS")
动作: 允许
```

## MinIO客户端配置

### AWS CLI配置

```bash
aws configure set aws_access_key_id YOUR_ACCESS_KEY
aws configure set aws_secret_access_key YOUR_SECRET_KEY
aws configure set default.region us-east-1
aws configure set default.s3.signature_version s3v4

# 使用自定义端点
aws --endpoint-url https://minio.maywzh.com s3 ls
```

### MinIO Client (mc)配置

```bash
mc alias set myminio https://minio.maywzh.com YOUR_ACCESS_KEY YOUR_SECRET_KEY

# 测试连接
mc ls myminio
```

## 故障排除

### 常见问题

1. **502 Bad Gateway错误**
   - 检查源服务器是否运行在正确端口
   - 验证网关端口转发配置
   - 检查防火墙设置

2. **SSL证书错误**
   - 确保Cloudflare SSL模式设置正确
   - 检查源服务器SSL配置

3. **CORS错误**
   - 确保Worker代码包含正确的CORS头部
   - 检查MinIO CORS配置

4. **连接超时**
   - 检查Cloudflare Worker是否正确配置
   - 验证目标IP和端口是否可达

### 调试命令

```bash
# 测试DNS解析
nslookup minio.maywzh.com

# 测试HTTP连接
curl -I https://minio.maywzh.com

# 测试MinIO API
curl -X GET https://minio.maywzh.com/minio/health/live

# 检查SSL证书
openssl s_client -connect minio.maywzh.com:443 -servername minio.maywzh.com
```

## 监控和维护

### Cloudflare Analytics

监控以下指标：
- 请求数量和响应时间
- 错误率（4xx, 5xx）
- 带宽使用情况
- Worker执行时间

### 日志监控

在Worker中添加日志记录：

```javascript
console.log(`Request: ${request.method} ${request.url}`)
console.log(`Response: ${response.status}`)
```

## 安全建议

1. **访问控制**
   - 使用强密码和访问密钥
   - 启用MinIO的IAM策略
   - 配置IP白名单（如需要）

2. **Cloudflare安全功能**
   - 启用DDoS保护
   - 配置速率限制
   - 使用Web应用防火墙(WAF)

3. **SSL/TLS最佳实践**
   - 使用最新的TLS版本
   - 启用HSTS头部
   - 配置安全的密码套件

## 成本考虑

### Cloudflare免费版限制
- Workers: 每天100,000个请求
- 页面规则: 3个规则
- DNS查询: 无限制

### 升级建议
如果需要更多功能，考虑升级到Cloudflare Pro版本：
- 更多Worker请求
- 更多页面规则
- 高级安全功能
- 更好的性能优化

## 总结

推荐使用方案A（Cloudflare Workers代理），因为它：
1. 不需要修改现有网络配置
2. 提供完整的HTTPS支持
3. 可以处理CORS和其他HTTP头部问题
4. 在Cloudflare免费版限制内工作

配置完成后，您应该能够通过 https://minio.maywzh.com 访问您的MinIO服务，享受Cloudflare提供的CDN、DDoS保护和SSL终止等功能。