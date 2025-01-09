#!/bin/bash

# 设置变量
MYSQL_VERSION="8.0.37"
WORK_DIR="$(pwd)/mysql_build"
OUTPUT_DIR="$(pwd)/mysql_output"
BASE_IMAGE="ubuntu:20.04"

# 网络检测函数
check_network() {
    # 测试能否访问 GitHub
    if curl -s --connect-timeout 3 https://github.com > /dev/null; then
        echo "可以访问国际网络"
        return 0
    else
        echo "无法访问国际网络，将使用国内镜像"
        return 1
    fi
}

# 根据网络情况设置镜像
if check_network; then
    MIRROR_TUNA="https://dev.mysql.com/get/Downloads"
    MIRROR_ALIYUN="archive.ubuntu.com"
else
    MIRROR_TUNA="https://mirrors.tuna.tsinghua.edu.cn"
    MIRROR_ALIYUN="mirrors.aliyun.com"
fi

# 获取 MySQL 主版本号
MYSQL_MAJOR_VERSION=$(echo ${MYSQL_VERSION} | cut -d. -f1-2)

MYSQL_BUILDER_TAG="mysql-builder:${MYSQL_VERSION}"

# MySQL安装相关配置
MYSQL_INSTALL_PREFIX="/usr/local/mysql"  # 安装目录
MYSQL_DATA_DIR="/data/mysql"            # 数据目录
MYSQL_CONFIG_DIR="/etc/mysql"           # 配置文件目录
MYSQL_LOG_DIR="/var/log/mysql"          # 日志目录

# 获取CPU核心数
CPU_CORES=$(nproc)
# 设置make使用的作业数，通常设置为CPU核心数的1.5倍
MAKE_JOBS=$(( CPU_CORES * 3 / 2 ))
# 获取系统内存(GB)
MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
# 计算可用于tmpfs的内存大小(使用总内存的一半)
TMPFS_SIZE=$(( MEMORY_GB / 2 ))G

# 在变量定义部分添加版本信息配置
MYSQL_PLATFORM="Enterprise Linux"  # 平台名称
MYSQL_VENDOR="Your Company"       # 供应商名称
MYSQL_SERVER_SUFFIX=""           # 服务器后缀
MYSQL_DISTRIBUTION="Custom Build" # 分发类型

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

# 错误处理函数
error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 清理函数
cleanup() {
    echo "清理临时文件..."
    rm -rf "${WORK_DIR}"
}

# 设置trap
trap cleanup EXIT
trap 'error_exit "脚本被中断"' INT TERM

# 检查必要工具
check_requirements() {
    local tools="wget curl apt-get"
    for tool in $tools; do
        command -v $tool >/dev/null 2>&1 || error_exit "需要 $tool 但未安装"
    done
}

# 检查磁盘空间
check_disk_space() {
    local required_space=10 # GB
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$available_space" -lt "$required_space" ]; then
        error_exit "磁盘空间不足，需要至少 ${required_space}GB，当前可用 ${available_space}GB"
    fi
}

# 检查并安装Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker未安装，开始安装Docker..."
        # 安装依赖
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common

        # 添加Docker官方GPG密钥
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

        # 添加Docker源
        add-apt-repository "deb [arch=amd64] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable"

        # 安装Docker
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io

        # 启动Docker服务
        systemctl start docker
        systemctl enable docker

        echo "Docker安装完成"
    else
        echo "Docker已安装"
    fi
}

# 配置Docker中国镜像
setup_docker_mirror() {
    echo "配置Docker中国镜像..."
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com"
    ]
}
EOF
    # 重启Docker服务
    systemctl daemon-reload
    systemctl restart docker
}

# 添加内存检查函数
check_memory() {
    if [ "$MEMORY_GB" -lt 4 ]; then
        error_exit "需要至少4GB内存才能编译"
    fi
}

# 添加权限检查函数
check_permissions() {
    if [ ! -w "${OUTPUT_DIR}" ]; then
        error_exit "没有输出目录的写入权限: ${OUTPUT_DIR}"
    fi
}

# 创建Dockerfile
create_dockerfile() {
    cat > "${WORK_DIR}/Dockerfile" << EOF
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

# 使用阿里云源
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

# 添加错误处理函数
error_exit() {
    echo "错误: \$1" >&2
    exit 1
}

# 使用tmpfs加速编译
if ! mount -t tmpfs -o size=${TMPFS_SIZE} tmpfs /tmp; then
    error_exit "无法挂载tmpfs"
fi

echo "下载MySQL源码..."
cd /tmp
wget ${MIRROR_TUNA}/mysql/downloads/MySQL-${MYSQL_MAJOR_VERSION}/mysql-${MYSQL_VERSION}.tar.gz || \
wget https://dev.mysql.com/get/Downloads/MySQL-${MYSQL_MAJOR_VERSION}/mysql-${MYSQL_VERSION}.tar.gz || \
error_exit "MySQL源码下载失败"

echo "解压源码..."
tar xzf mysql-${MYSQL_VERSION}.tar.gz || error_exit "解压失败"

cd mysql-${MYSQL_VERSION}
mkdir build
cd build

# 设置编译优化
export CFLAGS="-O3 -pipe -march=native"
export CXXFLAGS="\${CFLAGS}"

echo "开始配置MySQL..."
cmake .. ${CMAKE_OPTS} || error_exit "CMAKE配置失败"

echo "开始编译MySQL (使用 ${MAKE_JOBS} 个作业)..."
make -j${MAKE_JOBS} || error_exit "编译失败"

echo "安装MySQL到临时目录..."
make DESTDIR=/tmp/mysql_install install || error_exit "安装失败"

echo "创建配置文件..."
cat > /tmp/mysql_install/MYSQL_PATHS.txt << PATHSEOF
MYSQL_INSTALL_PREFIX=${MYSQL_INSTALL_PREFIX}
MYSQL_DATA_DIR=${MYSQL_DATA_DIR}
MYSQL_CONFIG_DIR=${MYSQL_CONFIG_DIR}
MYSQL_LOG_DIR=${MYSQL_LOG_DIR}
PATHSEOF

echo "打包MySQL..."
cd /tmp/mysql_install
tar czf /mysql_output/mysql-${MYSQL_VERSION}-linux-x86_64.tar.gz * || error_exit "打包失败"

# 改进tmpfs清理
if mountpoint -q /tmp; then
    cd /
    umount /tmp || error_exit "无法卸载tmpfs"
fi
EOF
    chmod +x "${WORK_DIR}/build.sh"
}

main() {
    # 检查root权限
    [ "$EUID" -eq 0 ] || error_exit "请使用root用户运行此脚本"
      # 创建目录
    mkdir -p "${WORK_DIR}" || error_exit "无法创建工作目录"
    mkdir -p "${OUTPUT_DIR}" || error_exit "无法创建输出目录"
    # 设置目录权限
    chmod 777 "${OUTPUT_DIR}" || error_exit "无法修改输出目录权限"
    
    # 运行所有检查
    check_requirements
    check_disk_space
    check_memory
    check_permissions
    check_docker
    setup_docker_mirror
    
    
    # 创建必要文件
    create_dockerfile
    create_build_script
    
    # 构建镜像
    echo "构建Docker镜像..."
    docker build -t "${MYSQL_BUILDER_TAG}" "${WORK_DIR}" || error_exit "Docker构建失败"
    
    # 运行编译
    echo "开始编译MySQL ${MYSQL_VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/mysql_output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${MYSQL_BUILDER_TAG}" \
        /bin/bash /build/build.sh || error_exit "Docker运行失败"
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/mysql-${MYSQL_VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 