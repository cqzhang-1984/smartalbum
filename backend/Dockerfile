# SmartAlbum 后端 Dockerfile
FROM python:3.11

# 设置工作目录
WORKDIR /app

# 安装系统依赖（包括 dlib 编译所需的库）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    libopenblas-dev \
    liblapack-dev \
    libx11-dev \
    libgtk-3-dev \
    libboost-python-dev \
    libdlib-dev \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖
RUN pip install --no-cache-dir -r requirements.txt

# 复制应用代码
COPY app/ ./app/

# 创建必要的目录
RUN mkdir -p /app/data /app/storage/originals /app/storage/thumbnails

# 暴露端口
EXPOSE 9999

# 启动命令
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "9999"]
