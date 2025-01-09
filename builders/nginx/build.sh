#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-1.24.0}"
WORK_DIR="$(pwd)/nginx_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"
CCACHE_DIR="${WORK_DIR}/ccache"

# 根据网络情况设置镜像
if check_network; then
    MIRROR_ALIYUN="archive.ubuntu.com"
    USE_MIRROR=false
else
    MIRROR_ALIYUN="mirrors.aliyun.com"
    USE_MIRROR=true
fi

NGINX_BUILDER_TAG="nginx-builder:${VERSION}"

# 创建Dockerfile
create_dockerfile() {
    cat > "${WORK_DIR}/Dockerfile" << EOF
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/ccache:\$PATH"
ENV CCACHE_DIR=/ccache
ENV CCACHE_SIZE=5G

# 使用镜像源
RUN sed -i "s/archive.ubuntu.com/${MIRROR_ALIYUN}/g" /etc/apt/sources.list && \
    sed -i "s/security.ubuntu.com/${MIRROR_ALIYUN}/g" /etc/apt/sources.list

# 安装编译依赖
RUN apt-get update && apt-get install -y \\
    build-essential \\
    wget \\
    git \\
    ccache \\
    libpcre3-dev \\
    libssl-dev \\
    zlib1g-dev \\
    libgd-dev \\
    libgeoip-dev \\
    libxml2-dev \\
    libxslt1-dev \\
    libperl-dev \\
    && rm -rf /var/lib/apt/lists/*

# 配置 ccache
RUN mkdir -p /ccache && chmod 777 /ccache
RUN ccache -M 5G

WORKDIR /build
EOF
}

# 创建编译脚本
create_build_script() {
    cat > "${WORK_DIR}/build.sh" << EOF
#!/bin/bash
set -e

# 挂载 tmpfs
mount -t tmpfs -o size=${TMPFS_SIZE} tmpfs /tmp
cd /tmp

# 下载源码
if [ "${USE_MIRROR}" = true ]; then
    wget https://mirrors.tuna.tsinghua.edu.cn/nginx/nginx-${VERSION}.tar.gz || \\
    wget https://nginx.org/download/nginx-${VERSION}.tar.gz || \\
    exit 1
else
    wget https://nginx.org/download/nginx-${VERSION}.tar.gz || \\
    wget https://mirrors.tuna.tsinghua.edu.cn/nginx/nginx-${VERSION}.tar.gz || \\
    exit 1
fi

tar xf nginx-${VERSION}.tar.gz
cd nginx-${VERSION}

# 配置编译优化参数
export CFLAGS="-O3 -pipe -fomit-frame-pointer -march=native"
export CXXFLAGS="\${CFLAGS}"
export LDFLAGS="-Wl,-O1 -Wl,--as-needed"

# 配置
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

# 编译(增加并行度)
make -j$((CPU_CORES * 2))

# 安装到临时目录
make DESTDIR=/tmp/nginx_install install

# 创建必要的目录
mkdir -p /tmp/nginx_install/usr/local/nginx/{conf,logs,run}

cd /tmp/nginx_install
tar czf /output/nginx-${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/nginx-${VERSION}-linux-x86_64.tar.gz > /output/nginx-${VERSION}-linux-x86_64.sha256
EOF
    chmod +x "${WORK_DIR}/build.sh"
}

main() {
    # 获取系统信息
    get_system_info
    
    # 运行检查
    check_system_requirements
    check_basic_tools
    check_docker
    setup_docker_mirror
    
    # 准备目录
    prepare_directories "${WORK_DIR}" "${OUTPUT_DIR}"
    mkdir -p "${CCACHE_DIR}"
    chmod 777 "${CCACHE_DIR}"
    
    # 创建必要文件
    create_dockerfile
    create_build_script
    
    # 构建镜像
    echo "构建Docker镜像..."
    docker build -t "${NGINX_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译Nginx ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        -v "${CCACHE_DIR}:/ccache" \
        --tmpfs /tmp:exec,size=${TMPFS_SIZE} \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${NGINX_BUILDER_TAG}" \
        /bin/bash /build/build.sh
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/nginx-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 