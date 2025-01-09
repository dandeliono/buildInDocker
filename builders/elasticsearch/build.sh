#!/bin/bash

# 加载公共函数
source "$(dirname "$0")/../common.sh"

# 设置变量
VERSION="${VERSION:-8.11.3}"
WORK_DIR="$(pwd)/es_build"
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

ES_BUILDER_TAG="es-builder:${VERSION}"

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
    openjdk-17-jdk \\
    && rm -rf /var/lib/apt/lists/*

# 设置JAVA_HOME
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
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
    git clone --branch v${VERSION} --depth 1 https://gitee.com/mirrors/elasticsearch.git || exit 1
else
    git clone --branch v${VERSION} --depth 1 https://github.com/elastic/elasticsearch.git || exit 1
fi

cd elasticsearch

# 配置Gradle镜像
if [ "${USE_MIRROR}" = true ]; then
    mkdir -p ~/.gradle
    cat > ~/.gradle/init.gradle << GRADLEEOF
allprojects {
    repositories {
        mavenLocal()
        maven { url 'https://maven.aliyun.com/repository/public' }
        maven { url 'https://maven.aliyun.com/repository/jcenter' }
        maven { url 'https://maven.aliyun.com/repository/google' }
        maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
        mavenCentral()
    }
    buildscript {
        repositories {
            maven { url 'https://maven.aliyun.com/repository/public' }
            maven { url 'https://maven.aliyun.com/repository/jcenter' }
            maven { url 'https://maven.aliyun.com/repository/google' }
            maven { url 'https://maven.aliyun.com/repository/gradle-plugin' }
            mavenCentral()
        }
    }
}
GRADLEEOF
fi

# 设置Gradle内存
export GRADLE_OPTS="-Xmx${TMPFS_SIZE}"

# 编译Elasticsearch
./gradlew :distribution:archives:linux-tar:build \\
    -Dbuild.snapshot=false \\
    -x test \\
    -x testingConventions \\
    -x spotlessCheck \\
    -x checkstyleMain \\
    -x checkstyleTest \\
    -x forbiddenApisMain \\
    -x forbiddenApisTest \\
    -x jacocoTestReport \\
    -x rat

# 准备安装目录
mkdir -p /tmp/es_install/usr/local/elasticsearch
cp distribution/archives/linux-tar/build/distributions/elasticsearch-${VERSION}-linux-x86_64.tar.gz /tmp/es_install/usr/local/elasticsearch/

# 创建必要的目录
mkdir -p /tmp/es_install/usr/local/elasticsearch/{data,logs,plugins}

cd /tmp/es_install
tar czf /output/elasticsearch-${VERSION}-linux-x86_64.tar.gz *
sha256sum /output/elasticsearch-${VERSION}-linux-x86_64.tar.gz > /output/elasticsearch-${VERSION}-linux-x86_64.sha256
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
    docker build -t "${ES_BUILDER_TAG}" "${WORK_DIR}"
    
    # 运行编译
    echo "开始编译Elasticsearch ${VERSION}..."
    docker run --rm \
        --privileged \
        -v "${OUTPUT_DIR}:/output" \
        -v "${WORK_DIR}:/build" \
        --cpuset-cpus="0-$((CPU_CORES-1))" \
        --memory="${TMPFS_SIZE}" \
        --memory-swap="${TMPFS_SIZE}" \
        "${ES_BUILDER_TAG}" \
        /bin/bash /build/build.sh
    
    echo "编译完成！"
    echo "编译后的文件位置: ${OUTPUT_DIR}/elasticsearch-${VERSION}-linux-x86_64.tar.gz"
}

# 运行主函数
main 