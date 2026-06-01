# SingBoxManager - Swift Edition

一个用 Swift 编写的 Sing-Box 节点管理器，支持 CLI 和 SwiftUI 图形界面。

## 功能

- ✅ SSH 连接到远程路由器
- ✅ 解析 vmess:// 链接
- ✅ 列出所有配置的节点
- ✅ 添加新节点
- ✅ 删除节点
- ✅ 设置默认节点
- ✅ 自动重启 sing-box 服务
- ✅ 彩色 CLI 界面
- ✅ SwiftUI 图形界面（macOS/iOS）

## 项目结构

```
SingBoxManager/
├── Package.swift                 # Swift Package 配置
├── Sources/
│   ├── CLI/
│   │   └── main.swift           # CLI 应用入口
│   └── Library/
│       ├── Models.swift         # 数据模型
│       ├── SSHManager.swift     # SSH 管理
│       ├── ConfigManager.swift  # 配置和节点管理
│       └── SwiftUIApp.swift     # SwiftUI 应用
├── Tests/
│   └── SingBoxManagerTests.swift # 单元测试
└── README.md
```

## 安装

### 前置要求

- Swift 5.9+
- macOS 12+ 或 iOS 15+

### 构建

```bash
cd SingBoxManager
swift build
```

### 运行 CLI 版本

```bash
swift run SingBoxManager
```

### 运行 SwiftUI 版本

```bash
swift build -c release
# 然后在 Xcode 中打开项目
open Package.swift
```

## 使用

### CLI 模式

1. 启动应用
2. 输入路由器 IP（默认：192.168.50.1）
3. 输入 SSH 用户名（默认：root）
4. 输入密码
5. 选择操作：
   - **List nodes** - 显示所有节点
   - **Add node** - 添加新节点（粘贴 vmess:// 链接）
   - **Delete node** - 删除节点
   - **Set default node** - 设置默认节点
   - **Exit** - 退出

### SwiftUI 模式

1. 输入连接信息
2. 点击 Connect
3. 使用图形界面管理节点

## 配置

编辑 `Sources/Library/ConfigManager.swift` 中的常量：

```swift
private let configPath: String = "/etc/sing-box/config.json"
```

## 数据模型

### VMessNode

```swift
struct VMessNode {
    let type: String           // "vmess"
    let tag: String            // 节点名称
    let server: String         // 服务器地址
    let server_port: Int       // 端口
    let uuid: String           // UUID
    let security: String       // 安全方式
    let alter_id: Int          // Alter ID
    var transport: Transport?  // 传输配置
    var tls: TLSConfig?        // TLS 配置
}
```

### 支持的传输方式

- **TCP** - 直连
- **WebSocket (WS)** - 支持自定义路径和 Host 头
- **gRPC** - 支持自定义服务名

### 支持的 TLS 配置

- TLS 启用/禁用
- 自定义服务器名称

## SSH 连接

使用 `swift-nio-ssh` 库进行 SSH 连接：

- 支持密码认证
- 自动接受主机密钥
- 10 秒连接超时

## 错误处理

所有操作都包含完整的错误处理：

- SSH 连接失败
- 配置读写失败
- 无效的 vmess 链接
- 索引越界
- 缺少 selector 配置

## 测试

```bash
swift test
```

## 与 Python 版本的区别

| 功能 | Python | Swift |
|------|--------|-------|
| SSH 连接 | paramiko | swift-nio-ssh |
| 配置管理 | JSON 文件操作 | 结构化数据模型 |
| UI | 终端 CLI | CLI + SwiftUI |
| 异步处理 | 同步 | async/await |
| 类型安全 | 动态 | 静态类型 |

## 许可证

MIT

## 贡献

欢迎提交 Issue 和 Pull Request！
