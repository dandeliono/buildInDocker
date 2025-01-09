#!/bin/bash

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

# 检查并安装Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        echo "Docker未安装，开始安装Docker..."
        
        # 根据网络环境选择安装源
        if check_network; then
            # 国际网络正常，使用官方源
            curl -fsSL https://get.docker.com | sh
        else
            # 使用阿里云镜像安装
            curl -fsSL https://get.docker.com | sh -s docker --mirror Aliyun
        fi

        # 等待 Docker 服务启动
        sleep 3

        # 启动Docker服务
        if systemctl list-unit-files | grep -q docker.service; then
            systemctl start docker
            systemctl enable docker
        else
            service docker start
            update-rc.d docker defaults
        fi

        # 验证安装
        if ! docker info >/dev/null 2>&1; then
            error_exit "Docker安装或启动失败"
        fi

        echo "Docker安装完成"
    else
        echo "Docker已安装"
    fi
}

# 配置Docker中国镜像
setup_docker_mirror() {
    # 根据网络环境决定是否配置镜像
    if ! check_network; then
        echo "配置Docker中国镜像..."
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json <<EOF
{
    "registry-mirrors": [
        "https://mirror.ccs.tencentyun.com",
        "https://hub-mirror.c.163.com",
        "https://mirror.baidubce.com"
    ]
}
EOF
        # 重启Docker服务
        if systemctl list-unit-files | grep -q docker.service; then
            systemctl daemon-reload
            systemctl restart docker
        else
            service docker restart
        fi
    else
        echo "网络正常，无需配置镜像加速"
    fi
}

# 错误处理函数
error_exit() {
    echo "错误: $1" >&2
    exit 1
}

# 获取系统信息
get_system_info() {
    # CPU核心数
    CPU_CORES=$(nproc)
    # 编译作业数，设置为CPU核心数的2倍
    MAKE_JOBS=$((CPU_CORES * 2))
    # 系统内存(GB)
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    # tmpfs大小(使用总内存的70%)
    TMPFS_SIZE=$(( MEMORY_GB * 70 / 100 ))G
    # CPU架构
    CPU_ARCH=$(uname -m)
    # 操作系统
    OS_NAME=$(uname -s | tr '[:upper:]' '[:lower:]')
}

# 检查系统要求
check_system_requirements() {
    # 检查root权限
    [ "$EUID" -eq 0 ] || error_exit "请使用root用户运行此脚本"
    
    # 检查内存
    if [ "$MEMORY_GB" -lt 4 ]; then
        error_exit "需要至少4GB内存才能编译"
    fi
    
    # 检查磁盘空间
    local required_space=10 # GB
    local available_space=$(df -BG . | awk 'NR==2 {print $4}' | tr -d 'G')
    if [ "$available_space" -lt "$required_space" ]; then
        error_exit "磁盘空间不足，需要至少 ${required_space}GB，当前可用 ${available_space}GB"
    fi
}

# 检查必要工具
check_basic_tools() {
    local tools="wget curl apt-get"
    for tool in $tools; do
        command -v $tool >/dev/null 2>&1 || error_exit "需要 $tool 但未安装"
    done
}

# 创建并检查目录
prepare_directories() {
    local work_dir=$1
    local output_dir=$2
    
    mkdir -p "${work_dir}" || error_exit "无法创建工作目录"
    mkdir -p "${output_dir}" || error_exit "无法创建输出目录"
    chmod 777 "${output_dir}" || error_exit "无法修改输出目录权限"
    
    # 检查写入权限
    if [ ! -w "${output_dir}" ]; then
        error_exit "没有输出目录的写入权限: ${output_dir}"
    fi
}

# 设置编译优化
setup_compilation_flags() {
    # 基础优化
    CFLAGS="-O3 -pipe -fomit-frame-pointer"
    
    # 根据CPU架构添加特定优化
    case $(uname -m) in
        x86_64)
            CFLAGS="$CFLAGS -march=native -mtune=native"
            ;;
        aarch64)
            CFLAGS="$CFLAGS -march=armv8-a+crypto+crc"
            ;;
    esac
    
    # 链接器优化
    LDFLAGS="-Wl,-O1 -Wl,--as-needed -Wl,--hash-style=gnu"
    
    # 导出变量
    export CFLAGS
    export CXXFLAGS="$CFLAGS"
    export LDFLAGS
    
    # 设置make参数
    export MAKEFLAGS="-j$MAKE_JOBS"
}

# 设置ccache
setup_ccache() {
    local ccache_dir=$1
    local ccache_size=${2:-"5G"}
    
    mkdir -p "$ccache_dir"
    chmod 777 "$ccache_dir"
    
    # 配置ccache环境变量
    export CCACHE_DIR="$ccache_dir"
    export CCACHE_SIZE="$ccache_size"
    export PATH="/usr/lib/ccache:$PATH"
}

# 创建基础Dockerfile内容
create_base_dockerfile() {
    local mirror_aliyun=$1
    cat << EOF
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH="/usr/lib/ccache:\$PATH"
ENV CCACHE_DIR=/ccache
ENV CCACHE_SIZE=5G

# 使用镜像源
RUN sed -i "s/archive.ubuntu.com/${mirror_aliyun}/g" /etc/apt/sources.list && \\
    sed -i "s/security.ubuntu.com/${mirror_aliyun}/g" /etc/apt/sources.list

# 安装基础编译工具
RUN apt-get update && apt-get install -y \\
    build-essential \\
    wget \\
    git \\
    ccache \\
    python3 \\
    cmake \\
    ninja-build \\
    pkg-config \\
    && rm -rf /var/lib/apt/lists/*

# 配置 ccache
RUN mkdir -p /ccache && chmod 777 /ccache
RUN ccache -M 5G

WORKDIR /build
EOF
}

# 运行Docker编译
run_docker_build() {
    local image_tag=$1
    local work_dir=$2
    local output_dir=$3
    local ccache_dir=$4
    local build_script=$5
    
    echo "开始Docker编译..."
    docker run --rm \
        --privileged \
        -v "${output_dir}:/output" \
        -v "${work_dir}:/build" \
        -v "${ccache_dir}:/ccache" \
        --tmpfs /tmp:exec,size=${TMPFS_SIZE} \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${image_tag}" \
        /bin/bash "${build_script}"
} 