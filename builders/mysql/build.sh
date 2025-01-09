#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-8.0.35}"
WORK_DIR="$(pwd)/mysql_build"
OUTPUT_DIR="$(pwd)/output"
BASE_IMAGE="ubuntu:20.04"
CCACHE_DIR="${WORK_DIR}/ccache"

# MySQL安装相关配置
MYSQL_INSTALL_PREFIX="/usr/local/mysql"  # 安装目录
MYSQL_DATA_DIR="/usr/local/mysql/data"   # 数据目录
MYSQL_CONFIG_DIR="/etc/mysql"            # 配置文件目录
MYSQL_LOG_DIR="/var/log/mysql"           # 日志目录

# 版本信息配置
MYSQL_PLATFORM="${PLATFORM:-Enterprise Linux}"  # 平台名称
MYSQL_VENDOR="${VENDOR:-Your Company}"         # 供应商名称
MYSQL_SERVER_SUFFIX="${SERVER_SUFFIX:-}"       # 服务器后缀
MYSQL_DISTRIBUTION="${DISTRIBUTION:-Custom Build}" # 分发类型

# 根据网络情况设置镜像
if check_network; then
    MIRROR_ALIYUN="archive.ubuntu.com"
    USE_MIRROR=false
else
    MIRROR_ALIYUN="mirrors.aliyun.com"
    USE_MIRROR=true
fi

MYSQL_BUILDER_TAG="mysql-builder:${VERSION}"

# 创建Dockerfile
create_dockerfile() {
    # 使用基础Dockerfile
    create_base_dockerfile "${MIRROR_ALIYUN}" > "${WORK_DIR}/Dockerfile"
    
    # 添加MySQL特定依赖
    cat >> "${WORK_DIR}/Dockerfile" << EOF

# 安装MySQL编译依赖
RUN apt-get update && apt-get install -y \\
    bison \\
    libncurses5-dev \\
    libssl-dev \\
    libnuma-dev \\
    libreadline-dev \\
    zlib1g-dev \\
    && rm -rf /var/lib/apt/lists/*
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

# 提取主版本号
MAJOR_VERSION=\$(echo ${VERSION} | cut -d. -f1)

# 下载源码
if [ "${USE_MIRROR}" = true ]; then
    wget https://mirrors.tuna.tsinghua.edu.cn/mysql/downloads/MySQL-\${MAJOR_VERSION}.0/mysql-${VERSION}.tar.gz || \\
    wget https://mirrors.aliyun.com/mysql/MySQL-\${MAJOR_VERSION}.0/mysql-${VERSION}.tar.gz || \\
    wget https://dev.mysql.com/get/Downloads/MySQL-\${MAJOR_VERSION}.0/mysql-${VERSION}.tar.gz || \\
    exit 1
else
    wget https://dev.mysql.com/get/Downloads/MySQL-\${MAJOR_VERSION}.0/mysql-${VERSION}.tar.gz || \\
    wget https://mirrors.tuna.tsinghua.edu.cn/mysql/downloads/MySQL-\${MAJOR_VERSION}.0/mysql-${VERSION}.tar.gz || \\
    exit 1
fi

tar xf mysql-${VERSION}.tar.gz
cd mysql-${VERSION}

# 设置编译优化
setup_compilation_flags

# 创建构建目录
mkdir -p build
cd build

# 配置
cmake .. \\
    -DCMAKE_INSTALL_PREFIX=${MYSQL_INSTALL_PREFIX} \\
    -DMYSQL_DATADIR=${MYSQL_DATA_DIR} \\
    -DSYSCONFDIR=${MYSQL_CONFIG_DIR} \\
    -DWITH_INNOBASE_STORAGE_ENGINE=1 \\
    -DWITH_PARTITION_STORAGE_ENGINE=1 \\
    -DWITH_FEDERATED_STORAGE_ENGINE=1 \\
    -DWITH_BLACKHOLE_STORAGE_ENGINE=1 \\
    -DWITH_MYISAM_STORAGE_ENGINE=1 \\
    -DWITH_ARCHIVE_STORAGE_ENGINE=1 \\
    -DWITH_READLINE=1 \\
    -DWITH_SSL=system \\
    -DWITH_ZLIB=bundled \\
    -DWITH_NUMA=ON \\
    -DWITH_BOOST=boost \\
    -DENABLED_LOCAL_INFILE=1 \\
    -DWITH_DEBUG=0 \\
    -DENABLE_DTRACE=0 \\
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \\
    -DWITH_EMBEDDED_SERVER=OFF \\
    -DSYSTEM_TYPE='Generic' \\
    -DMACHINE_TYPE='${MYSQL_PLATFORM}' \\
    -DCOMPILER_VENDOR='${MYSQL_VENDOR}' \\
    -DSERVER_SUFFIX='${MYSQL_SERVER_SUFFIX}' \\
    -DMYSQL_SERVER_SUFFIX='${MYSQL_SERVER_SUFFIX}' \\
    -DMYSQL_DISTRIBUTION='${MYSQL_DISTRIBUTION}' \\
    -G Ninja

# 编译
ninja

# 安装到临时目录
DESTDIR=/tmp/mysql_install ninja install

# 创建必要的目录
mkdir -p /tmp/mysql_install${MYSQL_LOG_DIR}
mkdir -p /tmp/mysql_install${MYSQL_CONFIG_DIR}

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
    setup_ccache "${CCACHE_DIR}"
    
    # 创建必要文件
    create_dockerfile
    create_build_script
    
    # 构建镜像
    echo "构建Docker镜像..."
    docker build -t "${MYSQL_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译MySQL ${VERSION}..."
    run_docker_build \
        "${MYSQL_BUILDER_TAG}" \
        "${WORK_DIR}" \
        "${OUTPUT_DIR}" \
        "${CCACHE_DIR}" \
        "/build/build.sh"
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/mysql-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 