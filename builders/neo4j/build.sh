#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-5.13.0}"
WORK_DIR="$(pwd)/neo4j_build"
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

NEO4J_BUILDER_TAG="neo4j-builder:${VERSION}"

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
    openjdk-11-jdk \\
    maven \\
    && rm -rf /var/lib/apt/lists/*

# 设置JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
ENV PATH=\$JAVA_HOME/bin:\$PATH

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
    git clone --branch ${VERSION} --depth 1 https://gitee.com/mirrors/neo4j.git || exit 1
else
    git clone --branch ${VERSION} --depth 1 https://github.com/neo4j/neo4j.git || exit 1
fi

cd neo4j

# 配置Maven镜像
if [ "${USE_MIRROR}" = true ]; then
    mkdir -p ~/.m2
    cat > ~/.m2/settings.xml << MAVENEOF
<settings>
    <mirrors>
        <mirror>
            <id>aliyun</id>
            <name>Aliyun Maven</name>
            <url>https://maven.aliyun.com/repository/public</url>
            <mirrorOf>central</mirrorOf>
        </mirror>
    </mirrors>
</settings>
MAVENEOF
fi

# 设置Maven内存
export MAVEN_OPTS="-Xmx${TMPFS_SIZE}"

# 编译Neo4j
mvn clean package -DskipTests -Dlicense.skip=true -T ${MAKE_JOBS}

# 准备安装目录
mkdir -p /tmp/neo4j_install/usr/local/neo4j
cp -r packaging/standalone/target/neo4j-community-${VERSION}-unix/neo4j-community-${VERSION}/* /tmp/neo4j_install/usr/local/neo4j/

# 创建必要的目录
mkdir -p /tmp/neo4j_install/usr/local/neo4j/{data,logs,plugins,import}

cd /tmp/neo4j_install
tar czf /output/neo4j-${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/neo4j-${VERSION}-linux-x86_64.tar.gz > /output/neo4j-${VERSION}-linux-x86_64.sha256
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
    docker build -t "${NEO4J_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译Neo4j ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${NEO4J_BUILDER_TAG}" \
        /bin/bash /build/build.sh
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/neo4j-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 