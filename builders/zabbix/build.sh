#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-6.4.10}"
WORK_DIR="$(pwd)/zabbix_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"

# 获取 Zabbix 主版本号
ZABBIX_MAJOR_VERSION=$(echo ${VERSION} | cut -d. -f1-2)

# 根据网络情况设置镜像
if check_network; then
    MIRROR_ALIYUN="archive.ubuntu.com"
    USE_MIRROR=false
else
    MIRROR_ALIYUN="mirrors.aliyun.com"
    USE_MIRROR=true
fi

ZABBIX_BUILDER_TAG="zabbix-builder:${VERSION}"

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
    pkg-config \\
    libpcre3-dev \\
    libssl-dev \\
    libssh2-1-dev \\
    libldap2-dev \\
    libopenipmi-dev \\
    libsnmp-dev \\
    libcurl4-openssl-dev \\
    libxml2-dev \\
    libsqlite3-dev \\
    libmysqlclient-dev \\
    libpq-dev \\
    libevent-dev \\
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

# 下载源码
if [ "${USE_MIRROR}" = true ]; then
    wget https://mirrors.tuna.tsinghua.edu.cn/zabbix/zabbix/${ZABBIX_MAJOR_VERSION}/zabbix-${VERSION}.tar.gz || \\
    wget https://cdn.zabbix.com/zabbix/sources/stable/${ZABBIX_MAJOR_VERSION}/zabbix-${VERSION}.tar.gz || \\
    exit 1
else
    wget https://cdn.zabbix.com/zabbix/sources/stable/${ZABBIX_MAJOR_VERSION}/zabbix-${VERSION}.tar.gz || \\
    wget https://mirrors.tuna.tsinghua.edu.cn/zabbix/zabbix/${ZABBIX_MAJOR_VERSION}/zabbix-${VERSION}.tar.gz || \\
    exit 1
fi

tar xf zabbix-${VERSION}.tar.gz
cd zabbix-${VERSION}

# 配置
./configure \\
    --prefix=/usr/local/zabbix \\
    --enable-server \\
    --enable-agent \\
    --enable-proxy \\
    --with-mysql \\
    --with-postgresql \\
    --with-sqlite3 \\
    --with-openipmi \\
    --with-net-snmp \\
    --with-ssh2 \\
    --with-openssl \\
    --with-libcurl \\
    --with-libxml2 \\
    --with-ldap

# 编译
make -j${MAKE_JOBS}

# 安装到临时目录
make DESTDIR=/tmp/zabbix_install install

# 创建必要的目录
mkdir -p /tmp/zabbix_install/usr/local/zabbix/{logs,conf,scripts}

cd /tmp/zabbix_install
tar czf /output/zabbix-${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/zabbix-${VERSION}-linux-x86_64.tar.gz > /output/zabbix-${VERSION}-linux-x86_64.sha256
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
    docker build -t "${ZABBIX_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译Zabbix ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${ZABBIX_BUILDER_TAG}" \
        /bin/bash /build/build.sh
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/zabbix-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 