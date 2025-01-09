#!/bin/bash

# 设置变量
VERSION="1.24.0"
WORK_DIR="$(pwd)/nginx_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
MIRROR_ALIYUN="mirrors.aliyun.com"
BUILDER_TAG="nginx-builder:${VERSION}"

# 获取CPU核心数和内存信息
CPU_CORES=$(nproc)
MAKE_JOBS=$(( CPU_CORES * 3 / 2 ))
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
TMPFS_SIZE=$(( MEMORY_GB / 2 ))G

# 创建Dockerfile
create_dockerfile() {
    cat > "${WORK_DIR}/Dockerfile" << EOF
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

# 使用镜像源
RUN sed -i "s/archive.ubuntu.com/${MIRROR_ALIYUN}/g" /etc/apt/sources.list && \
    sed -i "s/security.ubuntu.com/${MIRROR_ALIYUN}/g" /etc/apt/sources.list

# 安装编译依赖
RUN apt-get update && apt-get install -y \\
    build-essential \\
    wget \\
    git \\
    libpcre3-dev \\
    libssl-dev \\
    zlib1g-dev \\
    libgd-dev \\
    libgeoip-dev \\
    libxml2-dev \\
    libxslt1-dev \\
    libperl-dev \\
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
EOF
}

# 创建编译脚本
create_build_script() {
    cat > "${WORK_DIR}/build.sh" << EOF
#!/bin/bash
set -e

cd /tmp
wget https://nginx.org/download/nginx-\${VERSION}.tar.gz || \\
wget ${MIRROR_TUNA}/nginx/nginx-\${VERSION}.tar.gz || \\
exit 1

tar xf nginx-\${VERSION}.tar.gz
cd nginx-\${VERSION}

./configure \\
    --prefix=/usr/local/nginx \\
    --user=nginx \\
    --group=nginx \\
    --with-http_ssl_module \\
    --with-http_v2_module \\
    --with-http_realip_module \\
    --with-http_addition_module \\
    --with-http_sub_module \\
    --with-http_dav_module \\
    --with-http_flv_module \\
    --with-http_mp4_module \\
    --with-http_gunzip_module \\
    --with-http_gzip_static_module \\
    --with-http_random_index_module \\
    --with-http_secure_link_module \\
    --with-http_stub_status_module \\
    --with-http_auth_request_module \\
    --with-http_xslt_module \\
    --with-http_image_filter_module \\
    --with-http_geoip_module \\
    --with-http_perl_module \\
    --with-threads \\
    --with-stream \\
    --with-stream_ssl_module \\
    --with-stream_realip_module \\
    --with-stream_geoip_module \\
    --with-http_slice_module \\
    --with-mail \\
    --with-mail_ssl_module \\
    --with-file-aio \\
    --with-http_v2_module \\
    --with-ipv6

make -j${MAKE_JOBS}
make DESTDIR=/tmp/nginx_install install

# 创建必要的目录和文件
mkdir -p /tmp/nginx_install/usr/local/nginx/{conf,logs,run}

cd /tmp/nginx_install
tar czf /output/nginx-\${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/nginx-\${VERSION}-linux-x86_64.tar.gz > /output/nginx-\${VERSION}-linux-x86_64.sha256
EOF
    chmod +x "${WORK_DIR}/build.sh"
}

main() {
    # 创建目录
    mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"
    chmod 777 "${OUTPUT_DIR}"

    # 创建必要文件
    create_dockerfile
    create_build_script

    # 构建镜像
    echo "构建Docker镜像..."
    docker build -t "${BUILDER_TAG}" "${WORK_DIR}"

    # 运行编译
    echo "开始编译Nginx ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${BUILDER_TAG}" \
        /bin/bash /build/build.sh

    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/nginx-${VERSION}-linux-x86_64.tar.gz"
}

main 