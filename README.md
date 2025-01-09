# buildInDocker
使用docker 构建一些组件

## 功能特点

- 自动检测网络环境，根据网络情况选择合适的镜像源
- 在无法访问国际网络时自动切换到国内镜像源（清华镜像源和阿里云镜像源）
- 使用 Docker 容器进行隔离编译
- 支持 tmpfs 内存编译加速
- 智能的资源使用（CPU 核心数和内存）

## 输出文件

编译完成后，将在 `mysql_output` 目录下生成：
- `mysql-8.0.37-linux-x86_64.tar.gz`：已编译的 MySQL 二进制包

## 配置说明

脚本中的主要配置项：

- `MYSQL_VERSION`：MySQL 版本号
- `MYSQL_INSTALL_PREFIX`：MySQL 安装目录
- `MYSQL_DATA_DIR`：数据目录
- `MYSQL_CONFIG_DIR`：配置文件目录
- `MYSQL_LOG_DIR`：日志目录

## 网络环境

脚本会自动检测网络环境：
- 如果能访问国际网络，将使用官方源
- 如果无法访问国际网络，将自动切换到国内镜像源（清华镜像源和阿里云镜像源）

## 注意事项

1. 编译过程可能需要较长时间，请保持耐心
2. 确保网络连接稳定
3. 建议在专用的编译环境中运行此脚本

## 故障排除

如果遇到编译失败：

1. 检查系统资源是否充足
2. 确认网络连接是否正常
3. 查看日志输出了解具体错误信息

## 许可证

MIT License
