# Multi-stage build for gcli2api
FROM python:3.13-slim as base

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# -----------------------------------------------------------------------------
# [新增步骤 1] 安装基础工具并下载 Cloudflared
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared \
    && chmod +x /usr/local/bin/cloudflared \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# -----------------------------------------------------------------------------
# [新增步骤 2] 创建启动脚本 (包含 Token 检查逻辑)
# -----------------------------------------------------------------------------
COPY <<'EOF' /app/start.sh
#!/bin/bash
set -e

echo "🚀 [启动脚本] 正在启动 GCLI2API..."

# 1. 启动主程序 (在后台运行)
# 注意：你的 web.py 默认监听 7861，所以这里不需要改动
python web.py &
APP_PID=$!

# 等待一下确保主程序开始初始化
sleep 2

# 2. 检查 Cloudflare Tunnel Token 环境变量
if [ -n "$CLOUDFLARE_TUNNEL_TOKEN" ]; then
    echo "🔗 [启动脚本] 检测到 Tunnel Token，正在启动 Cloudflare Tunnel..."
    
    # 启动 Cloudflared (后台运行)
    # 这里的配置完全依赖 Cloudflare Zero Trust 后台设置
    # 请确保你在 CF 后台配置 Service 时指向 http://localhost:7861
    cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TUNNEL_TOKEN" &
    
    echo "✅ [启动脚本] Cloudflare Tunnel 已启动"
else
    echo "ℹ️  [启动脚本] 未设置 Token，仅启动本地服务"
fi

# 3. 核心：挂起脚本，等待主程序结束
# 只要 python web.py 还在跑，容器就不会退出
wait $APP_PID
EOF

# 给脚本添加执行权限
RUN chmod +x /app/start.sh

# Expose port (保持原样，方便本地测试)
EXPOSE 7861

# -----------------------------------------------------------------------------
# [修改步骤 3] 更改启动命令为我们的脚本
# -----------------------------------------------------------------------------
CMD ["/app/start.sh"]
