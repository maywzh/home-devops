# Cloudflare MinIO 故障排除指南

## 常见问题及解决方案

### 1. 502 Bad Gateway 错误

**症状**: 访问 https://minio.maywzh.com 时显示 502 错误

**可能原因及解决方案**:

#### 1.1 MinIO服务未运行
```bash
# 检查MinIO服务状态
docker ps | grep minio

# 如果服务未运行，启动服务
docker-compose -f minio-config.yml up -d

# 查看服务日志
docker logs minio-server
```

#### 1.2 端口转发配置错误
```bash
# 检查端口是否被占用
netstat -tulpn | grep 19001

# 测试内网连接
curl -I http://192.168.2.3:9001

# 测试网关端口转发
curl -I http://YOUR_PUBLIC_IP:19001
```

#### 1.3 防火墙阻止连接
```bash
# 检查防火墙状态 (Ubuntu/Debian)
sudo ufw status

# 开放端口
sudo ufw allow 19001

# 检查iptables规则
sudo iptables -L -n | grep 19001
```

### 2. SSL/TLS 证书错误

**症状**: 浏览器显示证书错误或不安全连接

**解决方案**:

#### 2.1 检查Cloudflare SSL设置
1. 登录Cloudflare控制台
2. 进入 SSL/TLS → 概述
3. 确保加密模式设置为 "完全" 或 "完全（严格）"
4. 检查 "始终使用HTTPS" 是否启用

#### 2.2 验证DNS代理状态
```bash
# 检查DNS记录是否启用代理（橙色云朵）
dig minio.maywzh.com

# 应该返回Cloudflare的IP地址，而不是您的真实IP
```

### 3. Worker 脚本错误

**症状**: 服务间歇性不可用或响应异常

**解决方案**:

#### 3.1 检查Worker日志
1. 进入Cloudflare控制台 → Workers & Pages
2. 选择您的Worker
3. 查看 "日志" 选项卡中的实时日志

#### 3.2 验证Worker配置
```javascript
// 确保Worker脚本中的IP地址正确
const CONFIG = {
  TARGET_HOST: 'YOUR_ACTUAL_PUBLIC_IP', // 检查这里
  TARGET_PORT: '19001',
  // ...
};
```

#### 3.3 测试Worker响应
```bash
# 直接测试Worker
curl -H "Host: minio.maywzh.com" https://minio.maywzh.com/minio/health/live
```

### 4. CORS 错误

**症状**: 浏览器控制台显示CORS相关错误

**解决方案**:

#### 4.1 检查Worker CORS配置
确保Worker脚本包含正确的CORS头部：
```javascript
headers.set('Access-Control-Allow-Origin', '*');
headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, HEAD, OPTIONS');
headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept, Origin, X-Amz-Date, X-Amz-Content-Sha256, X-Amz-Security-Token');
```

#### 4.2 MinIO CORS配置
```bash
# 使用mc客户端配置CORS
docker exec -it minio-client mc admin config set myminio api cors_allow_origin="https://minio.maywzh.com"
docker exec -it minio-client mc admin service restart myminio
```

### 5. 上传/下载失败

**症状**: 文件上传或下载操作失败

**解决方案**:

#### 5.1 检查文件大小限制
```bash
# Cloudflare免费版限制
# 最大请求大小: 100MB
# 最大响应大小: 100MB

# 检查MinIO配置
docker exec -it minio-server printenv | grep MINIO
```

#### 5.2 检查存储空间
```bash
# 检查磁盘空间
df -h

# 检查MinIO数据目录
docker exec -it minio-server du -sh /data
```

### 6. 性能问题

**症状**: 访问速度慢或超时

**解决方案**:

#### 6.1 优化Worker脚本
```javascript
// 添加缓存策略
if (shouldCache(request)) {
  headers.set('Cache-Control', `public, max-age=${CONFIG.CACHE_TTL}`);
}
```

#### 6.2 检查网络延迟
```bash
# 测试到Cloudflare的延迟
ping minio.maywzh.com

# 测试到源服务器的延迟
ping YOUR_PUBLIC_IP

# 使用traceroute分析路由
traceroute minio.maywzh.com
```

### 7. 认证问题

**症状**: 无法登录MinIO控制台或API认证失败

**解决方案**:

#### 7.1 检查认证配置
```bash
# 查看MinIO环境变量
docker exec -it minio-server printenv | grep MINIO_ROOT

# 重置密码
docker exec -it minio-server minio admin user add myminio newuser newpassword
```

#### 7.2 验证API访问
```bash
# 测试API认证
curl -X GET \
  -H "Authorization: AWS4-HMAC-SHA256 ..." \
  https://minio.maywzh.com/
```

## 诊断工具和命令

### 网络诊断
```bash
# 完整的连接测试脚本
#!/bin/bash

echo "=== DNS解析测试 ==="
nslookup minio.maywzh.com

echo "=== HTTP连接测试 ==="
curl -I https://minio.maywzh.com

echo "=== SSL证书检查 ==="
openssl s_client -connect minio.maywzh.com:443 -servername minio.maywzh.com

echo "=== 端口连通性测试 ==="
nc -zv YOUR_PUBLIC_IP 19001

echo "=== MinIO健康检查 ==="
curl https://minio.maywzh.com/minio/health/live
```

### 日志收集
```bash
# 收集所有相关日志
mkdir -p logs
docker logs minio-server > logs/minio.log 2>&1
docker logs minio-client > logs/minio-client.log 2>&1

# 系统日志
journalctl -u docker > logs/docker.log

# 网络状态
netstat -tulpn > logs/netstat.log
```

### 性能监控
```bash
# 监控脚本
#!/bin/bash
while true; do
    echo "$(date): $(curl -o /dev/null -s -w '%{time_total}' https://minio.maywzh.com/minio/health/live)s"
    sleep 10
done
```

## 配置验证清单

### Cloudflare配置检查
- [ ] DNS记录已创建且启用代理（橙色云朵）
- [ ] SSL/TLS模式设置为"完全"
- [ ] "始终使用HTTPS"已启用
- [ ] Worker已部署且路由配置正确
- [ ] Worker脚本中的IP地址正确

### 网络配置检查
- [ ] 端口转发规则正确：公网IP:19001 → 192.168.2.3:9001
- [ ] 防火墙允许19001端口
- [ ] MinIO服务运行在192.168.2.3:9001

### MinIO配置检查
- [ ] MINIO_SERVER_URL设置为https://minio.maywzh.com
- [ ] MINIO_BROWSER_REDIRECT_URL设置正确
- [ ] 认证信息配置正确
- [ ] 存储目录有足够空间

## 联系支持

如果以上解决方案都无法解决问题，请收集以下信息：

1. 错误的详细描述和截图
2. 浏览器控制台错误信息
3. MinIO服务日志
4. Worker日志（如果可用）
5. 网络配置信息

### 有用的链接
- [Cloudflare Workers文档](https://developers.cloudflare.com/workers/)
- [MinIO官方文档](https://docs.min.io/)
- [Cloudflare SSL/TLS文档](https://developers.cloudflare.com/ssl/)

## 预防性维护

### 定期检查项目
1. **每周**：检查服务状态和日志
2. **每月**：验证SSL证书状态
3. **每季度**：检查存储空间使用情况
4. **每半年**：更新MinIO版本

### 监控建议
```bash
# 创建监控脚本
cat > monitor.sh << 'EOF'
#!/bin/bash
# MinIO服务监控脚本

LOG_FILE="/var/log/minio-monitor.log"

check_service() {
    if curl -f -s https://minio.maywzh.com/minio/health/live > /dev/null; then
        echo "$(date): Service OK" >> $LOG_FILE
    else
        echo "$(date): Service DOWN - Restarting..." >> $LOG_FILE
        docker-compose -f minio-config.yml restart
    fi
}

check_service
EOF

# 添加到crontab（每5分钟检查一次）
echo "*/5 * * * * /path/to/monitor.sh" | crontab -
```

这个故障排除指南应该能帮助您解决大部分常见问题。记住，大多数问题都与网络配置、SSL设置或Worker脚本配置有关。