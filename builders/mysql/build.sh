#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-8.0.37}"
WORK_DIR="$(pwd)/mysql_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"

# 获取 MySQL 主版本号
MYSQL_MAJOR_VERSION=$(echo ${VERSION} | cut -d. -f1-2)

# MySQL安装相关配置
MYSQL_INSTALL_PREFIX="/usr/local/mysql"  # 安装目录
MYSQL_DATA_DIR="/data/mysql"            # 数据目录
MYSQL_CONFIG_DIR="/etc/mysql"           # 配置文件目录
MYSQL_LOG_DIR="/var/log/mysql"          # 日志目录

# 版本信息配置
MYSQL_PLATFORM="Enterprise Linux"  # 平台名称
MYSQL_VENDOR="Your Company"       # 供应商名称
MYSQL_SERVER_SUFFIX=""           # 服务器后缀
MYSQL_DISTRIBUTION="Custom Build" # 分发类型

# 根据网络情况设置镜像
if check_network; then
    MIRROR_TUNA="https://dev.mysql.com/get/Downloads"
    MIRROR_ALIYUN="archive.ubuntu.com"
else
    MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
    MIRROR_ALIYUN="mirrors.aliyun.com"
fi

MYSQL_BUILDER_TAG="mysql-builder:${VERSION}"

CMAKE_OPTS="-DCMAKE_INSTALL_PREFIX=${MYSQL_INSTALL_PREFIX} \
    -DMYSQL_DATADIR=${MYSQL_DATA_DIR} \
    -DSYSCONFDIR=${MYSQL_CONFIG_DIR} \
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \
    -DWITH_SSL=system \
    -DWITH_ZLIB=bundled \
    -DWITH_NUMA=ON \
    -DDOWNLOAD_BOOST=1 \
    -DWITH_BOOST=/tmp/boost \
    -DCMAKE_BUILD_TYPE=Release \
    -DWITHOUT_EXAMPLE_STORAGE_ENGINE=1 \
    -DWITHOUT_FEDERATED_STORAGE_ENGINE=1 \
    -DWITHOUT_ARCHIVE_STORAGE_ENGINE=1 \
    -DFORCE_INSOURCE_BUILD=1 \
    -DSYSTEM_TYPE='Generic' \
    -DMACHINE_TYPE='${MYSQL_PLATFORM}' \
    -DCOMPILER_VENDOR='${MYSQL_VENDOR}' \
    -DSERVER_SUFFIX='${MYSQL_SERVER_SUFFIX}' \
    -DMYSQL_SERVER_SUFFIX='${MYSQL_SERVER_SUFFIX}' \
    -DMYSQL_DISTRIBUTION='${MYSQL_DISTRIBUTION}'"

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
    cmake \\
    libncurses5-dev \\
    libssl-dev \\
    pkg-config \\
    bison \\
    wget \\
    git \\
    perl \\
    openssl \\
    numactl \\
    libnuma-dev \\
    libtirpc-dev \\
    gcc \\
    g++ \\
    libreadline-dev \\
    zlib1g-dev \\
    && rm -rf /var/lib/apt/lists/*

# 创建工作目录
RUN mkdir -p /build
WORKDIR /build
EOF
}

# 创建编译脚本
create_build_script() {
    cat > "${WORK_DIR}/build.sh" << EOF
#!/bin/bash
set -e

cd /tmp
wget ${MIRROR_TUNA}/mysql/downloads/MySQL-${MYSQL_MAJOR_VERSION}/mysql-${VERSION}.tar.gz || \\
wget https://dev.mysql.com/get/Downloads/MySQL-${MYSQL_MAJOR_VERSION}/mysql-${VERSION}.tar.gz || \\
error_exit "MySQL源码下载失败"

tar xzf mysql-${VERSION}.tar.gz
cd mysql-${VERSION}
mkdir build
cd build

# 设置编译优化
export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="\${CFLAGS}"

cmake .. ${CMAKE_OPTS}
make -j${MAKE_JOBS}
make DESTDIR=/tmp/mysql_install install

cd /tmp/mysql_install
tar czf /output/mysql-${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/mysql-${VERSION}-linux-x86_64.tar.gz > /output/mysql-${VERSION}-linux-x86_64.sha256
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
    docker build -t "${MYSQL_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译MySQL ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${MYSQL_BUILDER_TAG}" \
        /bin/bash /build/build.sh
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/mysql-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 