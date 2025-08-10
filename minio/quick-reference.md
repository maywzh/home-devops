# Cloudflare MinIO 快速参考

## 🚀 一键部署
```bash
chmod +x deploy-script.sh && ./deploy-script.sh
```

## 📋 配置清单

### 必需信息
- [ ] 公网IP地址: `_________________`
- [ ] Cloudflare API Token: `_________________`
- [ ] Cloudflare Zone ID: `_________________`

### 网络配置
- [ ] 端口转发: `公网IP:19001 → 192.168.2.3:9001`
- [ ] 防火墙开放19001端口
- [ ] MinIO服务运行在192.168.2.3:9001

### Cloudflare配置
- [ ] DNS A记录: `minio.maywzh.com → 公网IP` (代理开启)
- [ ] SSL模式: 完全
- [ ] Always Use HTTPS: 开启
- [ ] Worker部署: `minio-proxy`
- [ ] Worker路由: `minio.maywzh.com/*`

## 🔧 关键命令

### 服务管理
```bash
# 启动MinIO
docker-compose -f minio-config.yml up -d

# 查看状态
docker ps | grep minio

# 查看日志
docker logs minio-server

# 重启服务
docker-compose -f minio-config.yml restart
```

### 测试命令
```bash
# DNS测试
nslookup minio.maywzh.com

# 连接测试
curl -I https://minio.maywzh.com

# 健康检查
curl https://minio.maywzh.com/minio/health/live

# 端口测试
nc -zv 公网IP 19001
```

## 🔑 默认登录
- **URL**: https://minio.maywzh.com
- **用户名**: minioadmin
- **密码**: minioadmin123456

## 🛠️ Worker配置要点
```javascript
const CONFIG = {
  TARGET_HOST: '你的公网IP',  // ⚠️ 必须修改
  TARGET_PORT: '19001',
  TARGET_PROTOCOL: 'http:',
};
```

## 🚨 常见问题

| 问题 | 解决方案 |
|------|----------|
| 502错误 | 检查MinIO服务和端口转发 |
| SSL错误 | 确认Cloudflare SSL模式为"完全" |
| CORS错误 | 检查Worker CORS配置 |
| 上传失败 | 检查文件大小限制(100MB) |

## 📞 紧急修复
```bash
# 重启所有服务
docker-compose -f minio-config.yml down
docker-compose -f minio-config.yml up -d

# 检查网络
ping minio.maywzh.com
traceroute minio.maywzh.com

# 查看完整日志
docker logs minio-server --tail 100
```

## 🔍 监控脚本
```bash
# 创建监控
cat > monitor.sh << 'EOF'
#!/bin/bash
while true; do
  if curl -f -s https://minio.maywzh.com/minio/health/live > /dev/null; then
    echo "$(date): ✅ Service OK"
  else
    echo "$(date): ❌ Service DOWN"
  fi
  sleep 60
done
EOF
chmod +x monitor.sh && ./monitor.sh
```

## 📚 文档链接
- 详细配置: [`cloudflare-minio-config.md`](./cloudflare-minio-config.md)
- 故障排除: [`troubleshooting-guide.md`](./troubleshooting-guide.md)
- 完整文档: [`README.md`](./README.md)

---
💡 **提示**: 生产环境请务必修改默认密码！