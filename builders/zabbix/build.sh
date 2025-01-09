#!/bin/bash

# 设置变量
VERSION="6.4.10"
WORK_DIR="$(pwd)/zabbix_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"
MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
MIRROR_ALIYUN="mirrors.aliyun.com"
BUILDER_TAG="zabbix-builder:${VERSION}"

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
    libpcre2-dev \\
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
wget https://cdn.zabbix.com/zabbix/sources/stable/\${VERSION%.*}/zabbix-\${VERSION}.tar.gz || \\
wget ${MIRROR_TUNA}/zabbix/zabbix/\${VERSION%.*}/zabbix-\${VERSION}.tar.gz || \\
exit 1

tar xf zabbix-\${VERSION}.tar.gz
cd zabbix-\${VERSION}

./configure \\
    --prefix=/usr/local/zabbix \\
    --enable-server \\
    --enable-agent \\
    --enable-proxy \\
    --enable-java \\
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

make -j${MAKE_JOBS}
make DESTDIR=/tmp/zabbix_install install

cd /tmp/zabbix_install
tar czf /output/zabbix-\${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/zabbix-\${VERSION}-linux-x86_64.tar.gz > /output/zabbix-\${VERSION}-linux-x86_64.sha256
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
    echo "开始编译Zabbix ${VERSION}..."
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
    echo "编译后的文件位置: ${OUTPUT_DIR}/zabbix-${VERSION}-linux-x86_64.tar.gz"
}

main 