/**
 * Cloudflare Worker for MinIO Proxy
 * 专门为MinIO服务设计的代理脚本，处理非标准端口和HTTPS转换
 */

// 配置常量
const CONFIG = {
  // 替换为您的实际公网IP地址
  TARGET_HOST: 'YOUR_PUBLIC_IP',
  TARGET_PORT: '19001',
  TARGET_PROTOCOL: 'http:', // 如果源服务器使用HTTPS，改为 'https:'
  
  // MinIO特定配置
  MINIO_CONSOLE_PATH: '/minio/',
  MINIO_API_PATH: '/minio/v2/',
  
  // 安全配置
  ALLOWED_ORIGINS: [
    'https://minio.maywzh.com',
    'http://localhost:3000', // 开发环境
  ],
  
  // 缓存配置
  CACHE_TTL: 300, // 5分钟
};

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
});

async function handleRequest(request) {
  const url = new URL(request.url);
  const method = request.method;
  
  // 处理预检请求
  if (method === 'OPTIONS') {
    return handleCORS(request);
  }
  
  // 构建目标URL
  const targetUrl = buildTargetUrl(url);
  
  try {
    // 创建代理请求
    const proxyRequest = createProxyRequest(request, targetUrl);
    
    // 发送请求到MinIO服务器
    const response = await fetch(proxyRequest);
    
    // 处理响应
    return processResponse(response, request);
    
  } catch (error) {
    console.error('Proxy error:', error);
    return new Response(JSON.stringify({
      error: 'Service Unavailable',
      message: 'Unable to connect to MinIO service',
      timestamp: new Date().toISOString()
    }), {
      status: 503,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      }
    });
  }
}

function buildTargetUrl(originalUrl) {
  const targetUrl = new URL(originalUrl.toString());
  targetUrl.hostname = CONFIG.TARGET_HOST;
  targetUrl.port = CONFIG.TARGET_PORT;
  targetUrl.protocol = CONFIG.TARGET_PROTOCOL;
  
  return targetUrl.toString();
}

function createProxyRequest(originalRequest, targetUrl) {
  // 复制原始请求头，但排除一些可能导致问题的头部
  const headers = new Headers();
  
  for (const [key, value] of originalRequest.headers.entries()) {
    // 跳过这些头部，让浏览器自动处理
    if (!['host', 'origin', 'referer'].includes(key.toLowerCase())) {
      headers.set(key, value);
    }
  }
  
  // 设置正确的Host头部
  headers.set('Host', `${CONFIG.TARGET_HOST}:${CONFIG.TARGET_PORT}`);
  
  // 如果是POST/PUT请求，确保Content-Type正确
  if (['POST', 'PUT', 'PATCH'].includes(originalRequest.method)) {
    if (!headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/octet-stream');
    }
  }
  
  return new Request(targetUrl, {
    method: originalRequest.method,
    headers: headers,
    body: originalRequest.body,
    redirect: 'manual' // 手动处理重定向
  });
}

async function processResponse(response, originalRequest) {
  const url = new URL(originalRequest.url);
  
  // 处理重定向
  if ([301, 302, 303, 307, 308].includes(response.status)) {
    const location = response.headers.get('Location');
    if (location) {
      const redirectUrl = rewriteRedirectUrl(location, url.origin);
      const newHeaders = new Headers(response.headers);
      newHeaders.set('Location', redirectUrl);
      
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: newHeaders
      });
    }
  }
  
  // 获取响应内容类型
  const contentType = response.headers.get('Content-Type') || '';
  
  // 处理HTML响应（MinIO控制台）
  if (contentType.includes('text/html')) {
    return processHtmlResponse(response, url.origin);
  }
  
  // 处理JSON响应
  if (contentType.includes('application/json')) {
    return processJsonResponse(response);
  }
  
  // 处理其他响应类型
  return processGenericResponse(response, originalRequest);
}

async function processHtmlResponse(response, origin) {
  let html = await response.text();
  
  // 替换HTML中的URL引用
  html = html.replace(
    new RegExp(`http://${CONFIG.TARGET_HOST}:${CONFIG.TARGET_PORT}`, 'g'),
    origin
  );
  
  // 替换相对路径为绝对路径
  html = html.replace(
    /src="\/([^"]*?)"/g,
    `src="${origin}/$1"`
  );
  
  html = html.replace(
    /href="\/([^"]*?)"/g,
    `href="${origin}/$1"`
  );
  
  const headers = createResponseHeaders(response.headers, 'text/html; charset=utf-8');
  
  return new Response(html, {
    status: response.status,
    statusText: response.statusText,
    headers: headers
  });
}

async function processJsonResponse(response) {
  const headers = createResponseHeaders(response.headers, 'application/json');
  
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: headers
  });
}

async function processGenericResponse(response, originalRequest) {
  const headers = createResponseHeaders(response.headers);
  
  // 设置缓存策略
  if (shouldCache(originalRequest)) {
    headers.set('Cache-Control', `public, max-age=${CONFIG.CACHE_TTL}`);
  } else {
    headers.set('Cache-Control', 'no-cache, no-store, must-revalidate');
  }
  
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: headers
  });
}

function createResponseHeaders(originalHeaders, contentType = null) {
  const headers = new Headers();
  
  // 复制原始响应头
  for (const [key, value] of originalHeaders.entries()) {
    // 跳过一些可能导致问题的头部
    if (!['connection', 'keep-alive', 'transfer-encoding'].includes(key.toLowerCase())) {
      headers.set(key, value);
    }
  }
  
  // 设置CORS头部
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, HEAD, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept, Origin, X-Amz-Date, X-Amz-Content-Sha256, X-Amz-Security-Token');
  headers.set('Access-Control-Expose-Headers', 'ETag, X-Amz-Request-Id, X-Amz-Id-2');
  headers.set('Access-Control-Max-Age', '86400');
  
  // 设置安全头部
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('X-Frame-Options', 'SAMEORIGIN');
  headers.set('X-XSS-Protection', '1; mode=block');
  
  // 设置内容类型
  if (contentType) {
    headers.set('Content-Type', contentType);
  }
  
  return headers;
}

function handleCORS(request) {
  const origin = request.headers.get('Origin');
  const headers = new Headers();
  
  // 检查来源是否被允许
  if (CONFIG.ALLOWED_ORIGINS.includes('*') || CONFIG.ALLOWED_ORIGINS.includes(origin)) {
    headers.set('Access-Control-Allow-Origin', origin || '*');
  } else {
    headers.set('Access-Control-Allow-Origin', CONFIG.ALLOWED_ORIGINS[0]);
  }
  
  headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, HEAD, OPTIONS');
  headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Requested-With, Accept, Origin, X-Amz-Date, X-Amz-Content-Sha256, X-Amz-Security-Token');
  headers.set('Access-Control-Max-Age', '86400');
  
  return new Response(null, {
    status: 204,
    headers: headers
  });
}

function rewriteRedirectUrl(location, origin) {
  // 如果是绝对URL，需要重写
  if (location.startsWith(`http://${CONFIG.TARGET_HOST}:${CONFIG.TARGET_PORT}`)) {
    return location.replace(`http://${CONFIG.TARGET_HOST}:${CONFIG.TARGET_PORT}`, origin);
  }
  
  // 如果是相对URL，添加origin
  if (location.startsWith('/')) {
    return `${origin}${location}`;
  }
  
  return location;
}

function shouldCache(request) {
  const url = new URL(request.url);
  const path = url.pathname;
  
  // 缓存静态资源
  if (path.match(/\.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$/)) {
    return true;
  }
  
  // 不缓存API请求
  if (path.startsWith(CONFIG.MINIO_API_PATH)) {
    return false;
  }
  
  // 不缓存控制台页面
  if (path.startsWith(CONFIG.MINIO_CONSOLE_PATH)) {
    return false;
  }
  
  return false;
}

// 错误处理和日志记录
function logRequest(request, response, startTime) {
  const duration = Date.now() - startTime;
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    method: request.method,
    url: request.url,
    status: response.status,
    duration: `${duration}ms`,
    userAgent: request.headers.get('User-Agent'),
    ip: request.headers.get('CF-Connecting-IP')
  }));
}