# 云同步

OBooks 使用自部署 Go 服务同步书库, 阅读进度, 书签, 高亮, 笔记和阅读统计. EPUB 在打开时下载, 也可在云同步设置中下载全部书籍. 已下载书籍可离线阅读, 离线编辑会在下次连接时上传. 排版, 音色和窗口偏好保留在各设备上.

## 部署

服务端需要 Go 1.26 或更高版本. GitHub Release 提供各平台预编译的 `obooks-server` 归档. 本地构建在项目根目录执行:

```shell
just server-build
just server-admin user-create --username reader
just server-run
```

创建账号时在终端输入至少 12 字节的密码, 密码不会出现在命令参数或日志中. 默认数据目录是 `server/data/`, 默认监听 `127.0.0.1:8080`. 客户端本机调试可填写 `http://127.0.0.1:8080`, 远程连接必须使用 HTTPS.

服务端配置示例为 [settings.example.json](../server/settings.example.json). 配置文件必须声明 `schemaVersion: 1`, 可设置监听地址, 数据目录, TLS 证书和私钥路径, access token 与 refresh token 的有效秒数. 相对路径以服务端的工作目录为基准.

使用自定义配置启动:

```shell
just server-run --settings settings.json
```

生产环境可由反向代理终止 TLS, 将流量转发到回环监听地址. 如必须在容器中监听非回环 HTTP 地址, 使用 `--allow-http`, 并仅向可信的 TLS 代理开放该端口. 代理需要允许 512 MiB 的 EPUB 请求和较长的上传时间. 也可直接配置 `tlsCertificate` 与 `tlsKey` 启用 HTTPS. `/healthz` 提供进程健康检查.

服务以单实例运行, 元数据保存在 SQLite WAL 数据库中, 书籍文件保存在 `objects/` 内. 使用专用操作系统用户启动服务, 持久化整个数据目录. 服务端能读取书籍和标注内容.

## 账号和设备

在书库侧栏打开云同步设置, 填写服务地址, 用户名, 密码和设备名称. 同一账号可在多个设备登录, 不同账号的数据和文件相互隔离. refresh token 保存在 macOS Keychain 中, 同步文件不保存密码或 token.

```shell
just server-admin user-reset --username reader
just server-admin user-disable --username reader
```

重置密码或禁用账号会撤销该账号的全部会话. 重置密码也会重新启用账号. 客户端退出登录会先请求服务器撤销会话; 服务器不可达时仍清除本地会话. 本地书库和待上传变更继续保留.

第一版每份本地书库绑定一个服务地址和账号, 退出后只能重新登录该账号. 服务端支持多用户, 客户端暂不提供本地账号切换, 防止把原账号的数据上传到另一个账号.

## 同步行为

- 应用启动, 回到前台, 网络恢复和本地编辑后自动同步. 空闲时每 60 秒检查一次, 失败时按 2 到 60 秒退避重试, 应用退出后不再联网.
- 书籍身份由解压后文件清单的 SHA-256 决定, 与压缩顺序和 ZIP 时间戳无关. 不同内容版本视为不同书籍, 同名书籍不会仅因标题相同而合并.
- 旧书库在登录前计算指纹, 原始 EPUB 不在本机时从解压目录重新打包. 缺失或损坏的内容需重新导入. 本机相同内容的重复导入会合并标注和统计.
- 首次拉取先显示元数据和封面, 打开未下载书籍时校验并解压 EPUB. 单个 EPUB 上限为 512 MiB, 解压总量上限为 1 GiB, 单条目上限为 256 MiB, 封面上限为 10 MiB.
- 阅读位置以实际阅读时间较新的记录为准, 不取最大百分比. 客户端使用服务端时间校准新操作, 运行期间用单调时钟推进时间. 已发送操作保持不变, 网络重试不会改变其内容.
- 不同书签和标注按记录 ID 合并. 同一标注的并发编辑保留原记录和冲突副本, 副本在阅读器中标记, 可编辑或删除. 删除优先于旧设备的未同步编辑.
- 阅读统计按不可变事件 ID 去重, 同一事件重复上传不会重复计时. 日期和小时沿用记录时的本地日历分桶, 切换时区不会改写历史统计. 两台设备同时阅读产生的不同事件会累计.
- 删除图书会同步删除全部设备上的图书, 标注和统计. 云端墓碑阻止旧设备补传复活数据. 显式重新导入已删除内容可以创建新的阅读记录.

本地书库和统计迁移到 schema version 2. 统计迁移为已有时间桶生成稳定事件 ID, 后续新阅读按事件保存. `sync-state.json` 的 schema version 为 1, 包含设备身份, 变更队列, 已确认游标和本地合并状态. 本地持久化出错时显示错误, 不覆盖无法读取的数据.

## 协议

接口前缀为 `/v1`. 登录, 刷新和退出使用 POST, 已鉴权接口使用 `Authorization: Bearer ...`.

| 接口 | 用途 |
| --- | --- |
| `POST /auth/login` | 用户名和密码登录, 注册设备 |
| `POST /auth/refresh` | 轮换 refresh token 并取得 access token |
| `POST /auth/logout` | 撤销当前会话 |
| `POST /sync/push` | 原子提交最多 200 条变更, 请求体上限 4 MiB |
| `GET /sync/pull?cursor=...` | 按用户游标分页拉取, 每页最多 200 条 |
| `GET/HEAD/PUT /books/{bookID}/content` | 检查, 上传或下载 EPUB, 下载支持 Range |
| `GET/HEAD/PUT /books/{bookID}/cover` | 检查, 上传或下载 PNG 封面 |

变更包含 `deviceID`, `changeID`, `entity`, `entityID`, `bookID`, `baseRevision`, `revision`, `modifiedAt`, 可选 `deletedAt` 和 `payload`. 类型包括 `book`, `progress`, `bookmark`, `annotation`, `readingEvent`. 上传时 `revision` 为 0, `baseRevision` 是编辑所依据的服务端版本. 每次操作拥有固定 `changeID`, 重试复用相同内容, 服务端按用户和操作 ID 去重.

`modifiedAt`, `deletedAt`, `serverTime` 使用 Unix 秒, payload 中的日期使用 Unix 毫秒. 正文位置使用 spine ID 和 UTF-16 字符偏移, 标注范围编码为 `[location, length]`. 书籍元数据的目录和 spine 随 EPUB 内容传输, 本机文件夹路径不会上传.

拉取返回 `changes`, `cursor`, `hasMore` 和 `serverTime`. 客户端只在持久化该页之后推进游标, 下一次请求携带的游标表示已确认位置. 上传返回的游标仅供参考, 不能直接推进本地拉取游标. 拉取期间的本地编辑通过队列和本地视图快照保护, 不会把尚未应用的远端记录误判为本地删除.

## 维护和验证

备份前停止服务, 备份完整数据目录后再启动. 数据库和对象目录应成套恢复. 数据库初始迁移明确将 `PRAGMA user_version` 从 0 升级为 1, 未知未来版本会被拒绝. 从旧备份恢复服务端后, 客户端游标可能超出服务端数据, 需要恢复匹配的客户端状态或人工处理, 不会静默覆盖书库.

回收已删除书籍的服务器文件:

```shell
just server-admin gc --retention-days 30
```

回收仅处理超过保留期且所有已注册设备均已确认删除的书籍. 离线设备未确认时保留文件. 墓碑, 变更日志和幂等记录持续保留, 以支持旧设备重连和新设备首次同步, 暂不做日志压缩.

```shell
just build
just test
just server-test
just sync-integration
```

联调测试在临时目录中创建账号, SQLite 数据库, EPUB 和两份 Swift 本地书库, 验证真实 HTTP 传输, 文件指纹, 进度选择, 笔记冲突, 阅读事件去重, 重启恢复和删除传播. 测试结束后关闭临时服务并清理测试数据.
