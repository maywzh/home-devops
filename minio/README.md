# Cloudflare MinIO 配置项目

通过Cloudflare免费服务将内网MinIO服务配置为使用自定义域名 `https://minio.maywzh.com` 访问的完整解决方案。

## 项目概述

### 网络架构
```
Internet → Cloudflare → Cloudflare Worker → 公网IP:19001 → 内网192.168.2.3:9001 (MinIO)
```

### 主要特性
- ✅ 通过Cloudflare Workers解决非标准端口限制
- ✅ 完整的HTTPS/SSL支持
- ✅ CORS问题解决方案
- ✅ 自动化部署脚本
- ✅ 详细的故障排除指南
- ✅ 性能优化配置

## 文件说明

| 文件名 | 描述 |
|--------|------|
| [`cloudflare-minio-config.md`](./cloudflare-minio-config.md) | 详细的配置指南和技术文档 |
| [`cloudflare-worker-minio.js`](./cloudflare-worker-minio.js) | 优化的Cloudflare Worker代理脚本 |
| [`deploy-script.sh`](./deploy-script.sh) | 自动化部署脚本 |
| [`minio-config.yml`](./minio-config.yml) | MinIO Docker Compose配置文件 |
| [`troubleshooting-guide.md`](./troubleshooting-guide.md) | 故障排除指南 |

## 快速开始

### 前提条件
- 拥有 `maywzh.com` 域名并在Cloudflare管理DNS
- 已配置端口转发：`公网IP:19001 → 192.168.2.3:9001`
- 安装了Docker和Docker Compose
- 获取了Cloudflare API Token和Zone ID

### 方法一：自动化部署（推荐）

1. **准备环境**
   ```bash
   # 克隆或下载项目文件
   chmod +x deploy-script.sh
   
   # 安装依赖
   sudo apt update
   sudo apt install curl jq -y  # Ubuntu/Debian
   # 或
   brew install curl jq          # macOS
   ```

2. **运行部署脚本**
   ```bash
   ./deploy-script.sh
   ```
   
   脚本会提示您输入：
   - 公网IP地址
   - Cloudflare API Token
   - Cloudflare Zone ID

3. **启动MinIO服务**
   ```bash
   docker-compose -f minio-config.yml up -d
   ```

4. **验证部署**
   ```bash
   # 检查服务状态
   docker ps
   
   # 测试访问
   curl -I https://minio.maywzh.com
   ```

### 方法二：手动配置

#### 步骤1：配置DNS记录
在Cloudflare DNS管理中添加：
```
类型: A
名称: minio
内容: [您的公网IP]
代理状态: 已代理（橙色云朵）
```

#### 步骤2：部署Cloudflare Worker
1. 进入Cloudflare控制台 → Workers & Pages
2. 创建新Worker
3. 复制 [`cloudflare-worker-minio.js`](./cloudflare-worker-minio.js) 内容
4. 修改配置中的 `TARGET_HOST` 为您的公网IP
5. 部署Worker

#### 步骤3：配置Worker路由
添加路由：`minio.maywzh.com/*`

#### 步骤4：配置SSL/TLS
- 加密模式：完全
- 启用"始终使用HTTPS"

#### 步骤5：启动MinIO服务
```bash
# 修改minio-config.yml中的配置
docker-compose -f minio-config.yml up -d
```

## 配置详情

### Cloudflare Worker配置
Worker脚本包含以下关键功能：
- 端口转换（443 → 19001）
- CORS头部处理
- SSL终止和重新加密
- 错误处理和日志记录
- 缓存策略优化

### MinIO服务配置
关键环境变量：
```yaml
- MINIO_SERVER_URL=https://minio.maywzh.com
- MINIO_BROWSER_REDIRECT_URL=https://minio.maywzh.com
- MINIO_API_CORS_ALLOW_ORIGIN=https://minio.maywzh.com
```

### 网络配置要求
- 端口转发：`公网IP:19001 → 192.168.2.3:9001`
- 防火墙开放19001端口
- 确保内网MinIO服务可访问

## 使用说明

### 访问MinIO控制台
浏览器访问：`https://minio.maywzh.com`

默认登录信息：
- 用户名：`minioadmin`
- 密码：`minioadmin123456`

### API访问
```bash
# 使用AWS CLI
aws configure set aws_access_key_id minioadmin
aws configure set aws_secret_access_key minioadmin123456
aws --endpoint-url https://minio.maywzh.com s3 ls

# 使用MinIO Client
mc alias set myminio https://minio.maywzh.com minioadmin minioadmin123456
mc ls myminio
```

### SDK集成示例

#### Python (boto3)
```python
import boto3

s3_client = boto3.client(
    's3',
    endpoint_url='https://minio.maywzh.com',
    aws_access_key_id='minioadmin',
    aws_secret_access_key='minioadmin123456',
    region_name='us-east-1'
)

# 列出存储桶
response = s3_client.list_buckets()
print(response['Buckets'])
```

#### JavaScript
```javascript
const AWS = require('aws-sdk');

const s3 = new AWS.S3({
    endpoint: 'https://minio.maywzh.com',
    accessKeyId: 'minioadmin',
    secretAccessKey: 'minioadmin123456',
    s3ForcePathStyle: true,
    signatureVersion: 'v4'
});

// 列出存储桶
s3.listBuckets((err, data) => {
    if (err) console.log(err);
    else console.log(data.Buckets);
});
```

## 性能优化

### Cloudflare优化
- 启用Brotli压缩
- 配置缓存规则
- 使用Argo Smart Routing（付费功能）

### MinIO优化
- 配置缓存驱动器
- 调整并发连接数
- 启用压缩

### 网络优化
- 使用CDN加速静态资源
- 优化上传/下载块大小
- 配置连接池

## 监控和维护

### 健康检查
```bash
# MinIO健康检查
curl https://minio.maywzh.com/minio/health/live

# 详细状态检查
curl https://minio.maywzh.com/minio/health/ready
```

### 日志监控
```bash
# 查看MinIO日志
docker logs minio-server

# 实时监控
docker logs -f minio-server
```

### 备份策略
```bash
# 数据备份
docker run --rm -v minio_data:/data -v $(pwd):/backup alpine tar czf /backup/minio-backup-$(date +%Y%m%d).tar.gz /data

# 配置备份
docker run --rm -v minio_config:/config -v $(pwd):/backup alpine tar czf /backup/minio-config-backup-$(date +%Y%m%d).tar.gz /config
```

## 安全建议

### 访问控制
1. 修改默认管理员密码
2. 创建专用的访问密钥
3. 配置IAM策略
4. 启用访问日志

### 网络安全
1. 配置IP白名单（如需要）
2. 启用Cloudflare防火墙规则
3. 使用强密码策略
4. 定期更新MinIO版本

### SSL/TLS安全
1. 使用最新的TLS版本
2. 配置HSTS头部
3. 启用证书透明度监控

## 故障排除

常见问题及解决方案请参考：[`troubleshooting-guide.md`](./troubleshooting-guide.md)

### 快速诊断命令
```bash
# 网络连通性测试
curl -I https://minio.maywzh.com

# DNS解析检查
nslookup minio.maywzh.com

# 端口检查
nc -zv YOUR_PUBLIC_IP 19001

# 服务状态检查
docker ps | grep minio
```

## 成本分析

### Cloudflare免费版限制
- Workers请求：100,000/天
- 页面规则：3个
- DNS查询：无限制
- SSL证书：免费

### 升级建议
如需更高性能或更多功能，考虑升级到：
- Cloudflare Pro ($20/月)
- Cloudflare Business ($200/月)

## 技术支持

### 文档资源
- [Cloudflare Workers文档](https://developers.cloudflare.com/workers/)
- [MinIO官方文档](https://docs.min.io/)
- [Docker Compose文档](https://docs.docker.com/compose/)

### 社区支持
- [MinIO Slack社区](https://slack.min.io/)
- [Cloudflare社区论坛](https://community.cloudflare.com/)

## 更新日志

### v1.0.0 (2025-01-09)
- 初始版本发布
- 完整的Cloudflare Workers代理解决方案
- 自动化部署脚本
- 详细的配置和故障排除文档

## 许可证

本项目采用 MIT 许可证。详情请参阅 LICENSE 文件。

## 贡献

欢迎提交Issue和Pull Request来改进这个项目。

---

**注意**: 请确保在生产环境中使用前，修改所有默认密码和安全配置。