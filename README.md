# Build In Docker

使用 Docker 构建各种开源组件。

## 目录结构

```
.
├── build.sh              # 主构建脚本
├── builders/             # 构建脚本目录
│   ├── mysql/           # MySQL 构建相关
│   ├── nginx/           # Nginx 构建相关
│   ├── zabbix/          # Zabbix 构建相关
│   ├── neo4j/           # Neo4j 构建相关
│   ├── influxdb/        # InfluxDB 构建相关
│   └── elasticsearch/   # Elasticsearch 构建相关
├── .github/             # GitHub Actions 配置
└── README.md            # 项目说明文档
```

## 功能特点

- 自动检测网络环境，根据网络情况选择合适的镜像源
- 在无法访问国际网络时自动切换到国内镜像源
- 使用 Docker 容器进行隔离编译
- 支持 tmpfs 内存编译加速
- 智能的资源使用（CPU 核心数和内存）

## 使用方法

1. 直接构建（本地）：
   ```bash
   # 构建指定版本
   ./build.sh mysql 8.0.37
   
   # 使用默认版本构建
   ./build.sh nginx
   ```

2. 通过 GitHub Actions 构建：
   - 访问 Actions 页面
   - 选择 "Build Components"
   - 点击 "Run workflow"
   - 选择要构建的组件和版本

## 支持的组件和默认版本

- MySQL (8.0.37)
- Nginx (1.24.0)
- Zabbix (6.4.10)
- Neo4j (5.13.0)
- InfluxDB (2.7.3)
- Elasticsearch (8.11.3)

## 构建产物

编译完成后，将在 `output` 目录下生成：
- 组件二进制包：`{组件名}-{版本号}-linux-x86_64.tar.gz`
- 校验和文件：`{组件名}-{版本号}-linux-x86_64.sha256`

## 网络环境

脚本会自动检测网络环境：
- 如果能访问国际网络，将使用官方源
- 如果无法访问国际网络，将自动切换到国内镜像源（清华镜像源和阿里云镜像源）

## 注意事项

1. 编译过程可能需要较长时间，请保持耐心
2. 确保网络连接稳定
3. 建议在专用的编译环境中运行此脚本
4. 需要 root 权限运行脚本

## 故障排除

如果遇到编译失败：

1. 检查系统资源是否充足
2. 确认网络连接是否正常
3. 查看日志输出了解具体错误信息

## 许可证

MIT License
