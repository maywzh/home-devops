#!/bin/bash

# Cloudflare MinIO部署脚本
# 自动化配置Cloudflare DNS、Workers和相关设置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
DOMAIN="maywzh.com"
SUBDOMAIN="minio"
FULL_DOMAIN="${SUBDOMAIN}.${DOMAIN}"
PUBLIC_IP=""
CLOUDFLARE_API_TOKEN=""
CLOUDFLARE_ZONE_ID=""
WORKER_NAME="minio-proxy"

# 函数定义
print_header() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Cloudflare MinIO 部署脚本${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
}

print_step() {
    echo -e "${GREEN}[步骤] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[警告] $1${NC}"
}

print_error() {
    echo -e "${RED}[错误] $1${NC}"
}

check_dependencies() {
    print_step "检查依赖项..."
    
    if ! command -v curl &> /dev/null; then
        print_error "curl 未安装，请先安装 curl"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        print_error "jq 未安装，请先安装 jq"
        exit 1
    fi
    
    echo "✓ 所有依赖项已安装"
}

get_user_input() {
    print_step "收集配置信息..."
    
    if [ -z "$PUBLIC_IP" ]; then
        read -p "请输入您的公网IP地址: " PUBLIC_IP
    fi
    
    if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
        read -p "请输入Cloudflare API Token: " CLOUDFLARE_API_TOKEN
    fi
    
    if [ -z "$CLOUDFLARE_ZONE_ID" ]; then
        read -p "请输入Cloudflare Zone ID: " CLOUDFLARE_ZONE_ID
    fi
    
    echo ""
    echo "配置信息确认:"
    echo "域名: $FULL_DOMAIN"
    echo "公网IP: $PUBLIC_IP"
    echo "Zone ID: $CLOUDFLARE_ZONE_ID"
    echo ""
    
    read -p "确认配置信息正确吗? (y/N): " confirm
    if [[ $confirm != [yY] ]]; then
        echo "部署已取消"
        exit 0
    fi
}

create_dns_record() {
    print_step "创建DNS记录..."
    
    # 检查DNS记录是否已存在
    existing_record=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$FULL_DOMAIN" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
    
    if [ -n "$existing_record" ]; then
        print_warning "DNS记录已存在，正在更新..."
        
        # 更新现有记录
        response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$existing_record" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$SUBDOMAIN\",
                \"content\": \"$PUBLIC_IP\",
                \"proxied\": true,
                \"ttl\": 1
            }")
    else
        # 创建新记录
        response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
            -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
            -H "Content-Type: application/json" \
            --data "{
                \"type\": \"A\",
                \"name\": \"$SUBDOMAIN\",
                \"content\": \"$PUBLIC_IP\",
                \"proxied\": true,
                \"ttl\": 1
            }")
    fi
    
    success=$(echo $response | jq -r '.success')
    if [ "$success" = "true" ]; then
        echo "✓ DNS记录创建/更新成功"
    else
        print_error "DNS记录创建失败: $(echo $response | jq -r '.errors[0].message')"
        exit 1
    fi
}

deploy_worker() {
    print_step "部署Cloudflare Worker..."
    
    # 读取Worker脚本并替换配置
    if [ ! -f "cloudflare-worker-minio.js" ]; then
        print_error "Worker脚本文件不存在: cloudflare-worker-minio.js"
        exit 1
    fi
    
    # 替换配置变量
    sed "s/YOUR_PUBLIC_IP/$PUBLIC_IP/g" cloudflare-worker-minio.js > worker-temp.js
    
    # 获取Worker脚本内容
    worker_script=$(cat worker-temp.js | jq -Rs .)
    
    # 部署Worker
    response=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/accounts/$(get_account_id)/workers/scripts/$WORKER_NAME" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/javascript" \
        --data-binary @worker-temp.js)
    
    success=$(echo $response | jq -r '.success')
    if [ "$success" = "true" ]; then
        echo "✓ Worker部署成功"
    else
        print_error "Worker部署失败: $(echo $response | jq -r '.errors[0].message')"
        exit 1
    fi
    
    # 清理临时文件
    rm -f worker-temp.js
}

create_worker_route() {
    print_step "创建Worker路由..."
    
    # 创建Worker路由
    response=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/workers/routes" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{
            \"pattern\": \"$FULL_DOMAIN/*\",
            \"script\": \"$WORKER_NAME\"
        }")
    
    success=$(echo $response | jq -r '.success')
    if [ "$success" = "true" ]; then
        echo "✓ Worker路由创建成功"
    else
        print_error "Worker路由创建失败: $(echo $response | jq -r '.errors[0].message')"
        exit 1
    fi
}

configure_ssl() {
    print_step "配置SSL/TLS设置..."
    
    # 设置SSL模式为Full
    response=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/settings/ssl" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"value": "full"}')
    
    success=$(echo $response | jq -r '.success')
    if [ "$success" = "true" ]; then
        echo "✓ SSL模式设置为Full"
    else
        print_warning "SSL设置可能失败，请手动检查"
    fi
    
    # 启用Always Use HTTPS
    response=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/settings/always_use_https" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data '{"value": "on"}')
    
    success=$(echo $response | jq -r '.success')
    if [ "$success" = "true" ]; then
        echo "✓ Always Use HTTPS已启用"
    else
        print_warning "Always Use HTTPS设置可能失败，请手动检查"
    fi
}

get_account_id() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/accounts" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" | jq -r '.result[0].id'
}

test_deployment() {
    print_step "测试部署..."
    
    echo "等待DNS传播..."
    sleep 10
    
    # 测试DNS解析
    if nslookup $FULL_DOMAIN > /dev/null 2>&1; then
        echo "✓ DNS解析正常"
    else
        print_warning "DNS解析可能还在传播中"
    fi
    
    # 测试HTTP连接
    if curl -s -I "https://$FULL_DOMAIN" > /dev/null 2>&1; then
        echo "✓ HTTPS连接正常"
    else
        print_warning "HTTPS连接测试失败，可能需要等待更长时间"
    fi
    
    echo ""
    echo "部署完成！"
    echo "您现在可以通过以下地址访问MinIO:"
    echo "https://$FULL_DOMAIN"
}

generate_minio_config() {
    print_step "生成MinIO配置..."
    
    cat > minio-docker-compose.yml << EOF
version: '3.8'

services:
  minio:
    image: minio/minio:latest
    container_name: minio
    ports:
      - "9001:9000"
      - "9002:9001"
    environment:
      - MINIO_ROOT_USER=minioadmin
      - MINIO_ROOT_PASSWORD=minioadmin123
      - MINIO_SERVER_URL=https://$FULL_DOMAIN
      - MINIO_BROWSER_REDIRECT_URL=https://$FULL_DOMAIN
    volumes:
      - minio_data:/data
    command: server /data --console-address ":9001"
    restart: unless-stopped

volumes:
  minio_data:
EOF
    
    echo "✓ MinIO Docker Compose配置已生成: minio-docker-compose.yml"
}

print_summary() {
    echo ""
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}       部署完成总结${NC}"
    echo -e "${GREEN}================================${NC}"
    echo ""
    echo "✓ DNS记录已创建: $FULL_DOMAIN -> $PUBLIC_IP"
    echo "✓ Cloudflare Worker已部署: $WORKER_NAME"
    echo "✓ Worker路由已配置: $FULL_DOMAIN/*"
    echo "✓ SSL/TLS设置已配置"
    echo ""
    echo "下一步操作:"
    echo "1. 确保您的网关已配置端口转发: $PUBLIC_IP:19001 -> 192.168.2.3:9001"
    echo "2. 使用生成的docker-compose.yml启动MinIO服务"
    echo "3. 访问 https://$FULL_DOMAIN 测试服务"
    echo ""
    echo "如果遇到问题，请检查:"
    echo "- 网关端口转发配置"
    echo "- MinIO服务是否正常运行"
    echo "- 防火墙设置"
    echo ""
}

# 主执行流程
main() {
    print_header
    check_dependencies
    get_user_input
    create_dns_record
    deploy_worker
    create_worker_route
    configure_ssl
    generate_minio_config
    test_deployment
    print_summary
}

# 执行主函数
main "$@"