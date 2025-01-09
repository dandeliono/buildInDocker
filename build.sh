#!/bin/bash

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <组件名称> [版本号]"
    echo "支持的组件: mysql nginx zabbix neo4j influxdb elasticsearch"
    exit 1
fi

COMPONENT=$1
VERSION=$2

# 检查组件是否存在
if [ ! -d "builders/${COMPONENT}" ]; then
    echo "错误: 不支持的组件 ${COMPONENT}"
    echo "支持的组件: mysql nginx zabbix neo4j influxdb elasticsearch"
    exit 1
fi

# 如果没有指定版本，使用默认版本
if [ -z "${VERSION}" ]; then
    case ${COMPONENT} in
        mysql)
            VERSION="8.0.37"
            ;;
        nginx)
            VERSION="1.24.0"
            ;;
        zabbix)
            VERSION="6.4.10"
            ;;
        neo4j)
            VERSION="5.13.0"
            ;;
        influxdb)
            VERSION="2.7.3"
            ;;
        elasticsearch)
            VERSION="8.11.3"
            ;;
        *)
            echo "错误: 未知的组件 ${COMPONENT}"
            exit 1
            ;;
    esac
fi

# 执行对应的构建脚本
BUILDER_SCRIPT="builders/${COMPONENT}/build.sh"
if [ -x "${BUILDER_SCRIPT}" ]; then
    echo "开始构建 ${COMPONENT} ${VERSION}..."
    VERSION="${VERSION}" "${BUILDER_SCRIPT}"
else
    echo "错误: 构建脚本不存在或没有执行权限: ${BUILDER_SCRIPT}"
    exit 1
fi 