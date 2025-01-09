#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-2.7.3}"
WORK_DIR="$(pwd)/influxdb_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"

# 根据网络情况设置镜像
if check_network; then
    MIRROR_ALIYUN="archive.ubuntu.com"
    USE_MIRROR=false
else
    MIRROR_ALIYUN="mirrors.aliyun.com"
    USE_MIRROR=true
fi

INFLUXDB_BUILDER_TAG="influxdb-builder:${VERSION}"

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
    curl \\
    pkg-config \\
    golang-1.19 \\
    protobuf-compiler \\
    python3 \\
    python3-pip \\
    nodejs \\
    npm \\
    && rm -rf /var/lib/apt/lists/*

# 设置Go环境
ENV PATH=/usr/lib/go-1.19/bin:\$PATH
ENV GOPATH=/go
ENV PATH=\$GOPATH/bin:\$PATH

WORKDIR /build
EOF
}

# 创建编译脚本
create_build_script() {
    cat > "${WORK_DIR}/build.sh" << EOF
#!/bin/bash
set -e

cd /tmp

# 克隆源码
if [ "${USE_MIRROR}" = true ]; then
    git clone --branch v${VERSION} --depth 1 https://gitee.com/mirrors/influxdb.git || exit 1
else
    git clone --branch v${VERSION} --depth 1 https://github.com/influxdata/influxdb.git || exit 1
fi

cd influxdb

# 设置Go代理
if [ "${USE_MIRROR}" = true ]; then
    export GOPROXY=https://goproxy.cn,direct
fi
export GO111MODULE=on

# 安装依赖
make deps

# 编译InfluxDB
make -j${MAKE_JOBS}

# 准备安装目录
mkdir -p /tmp/influxdb_install/usr/local/influxdb/{bin,etc,var}
cp -r bin/* /tmp/influxdb_install/usr/local/influxdb/bin/
cp -r etc/* /tmp/influxdb_install/usr/local/influxdb/etc/ || true

# 创建必要的目录
mkdir -p /tmp/influxdb_install/usr/local/influxdb/var/{data,wal}

cd /tmp/influxdb_install
tar czf /output/influxdb-${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/influxdb-${VERSION}-linux-x86_64.tar.gz > /output/influxdb-${VERSION}-linux-x86_64.sha256
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
    
    # 创建必要文件
    create_dockerfile
    create_build_script
    
    # 构建镜像
    echo "构建Docker镜像..."
    docker build -t "${INFLUXDB_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译InfluxDB ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${INFLUXDB_BUILDER_TAG}" \
        /bin/bash /build/build.sh
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/influxdb-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 