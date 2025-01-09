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
        
        # 安装基础依赖
        apt-get update
        apt-get install -y \
            python3-minimal \
            lsb-release \
            python3-apt \
            command-not-found \
            systemd

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
        systemctl daemon-reload
        systemctl restart docker
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
    # 编译作业数，通常设置为CPU核心数的1.5倍
    MAKE_JOBS=$(( CPU_CORES * 3 / 2 ))
    # 系统内存(GB)
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    # tmpfs大小(使用总内存的一半)
    TMPFS_SIZE=$(( MEMORY_GB / 2 ))G
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