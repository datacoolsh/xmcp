# xmcp 使用指南：通过 AI 操作 X（Twitter）账户

> **xmcp** 是一个基于 [FastMCP](https://github.com/jlowin/fastmcp) 的本地 MCP 服务器，将 X（Twitter）官方 OpenAPI 规范自动转换为 MCP 工具，让 Claude、Grok 等 AI 助手可以直接操作你的 X 账户。

---

## 目录

- [架构概览](#架构概览)
- [环境配置](#环境配置)
- [启动服务](#启动服务)
- [功能分类与工具列表](#功能分类与工具列表)
- [实战案例](#实战案例)
- [工具白名单配置](#工具白名单配置)
- [OAuth2 Token 生成](#oauth2-token-生成)
- [Grok 测试客户端](#grok-测试客户端)
- [注意事项](#注意事项)

---

## 架构概览

```
AI 客户端（Claude / Grok）
        │
        │  MCP 协议
        ▼
  xmcp MCP 服务器（本地 http://127.0.0.1:8000/mcp）
        │
        │  HTTP + OAuth1/OAuth2
        ▼
   X（Twitter）官方 API（api.x.com）
```

xmcp 在启动时从 `https://api.twitter.com/2/openapi.json` 拉取最新 OpenAPI 规范，动态生成全部工具，无需手动维护 API 接口代码。

---

## 环境配置

### 1. 创建虚拟环境并安装依赖

```bash
# 推荐使用 uv（见项目约定）
uv sync

# 或传统方式
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. 配置环境变量

```bash
cp env.example .env
```

编辑 `.env` 文件，填写以下变量：

#### 必填项

| 变量名 | 说明 |
|--------|------|
| `X_OAUTH_CONSUMER_KEY` | X 开发者应用的 Consumer Key（API Key） |
| `X_OAUTH_CONSUMER_SECRET` | X 开发者应用的 Consumer Secret |
| `X_BEARER_TOKEN` | Bearer Token，即使使用 OAuth1 也需要设置 |

#### OAuth 回调配置（默认值即可）

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `X_OAUTH_CALLBACK_HOST` | `127.0.0.1` | 回调监听地址 |
| `X_OAUTH_CALLBACK_PORT` | `8976` | 回调监听端口 |
| `X_OAUTH_CALLBACK_PATH` | `/oauth/callback` | 回调路径 |
| `X_OAUTH_CALLBACK_TIMEOUT` | `300` | 等待授权超时（秒） |

#### 服务器配置（可选）

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `X_API_BASE_URL` | `https://api.x.com` | X API 地址 |
| `X_API_TIMEOUT` | `30` | 请求超时（秒） |
| `MCP_HOST` | `127.0.0.1` | MCP 服务监听地址 |
| `MCP_PORT` | `8000` | MCP 服务监听端口 |
| `X_API_DEBUG` | `1` | 是否开启调试输出 |

#### 工具过滤（可选）

```bash
# 仅启用指定工具，逗号分隔
X_API_TOOL_ALLOWLIST=getUsersByUsername,createPosts,searchPostsRecent
```

#### OAuth1 调试（可选）

```bash
X_OAUTH_PRINT_TOKENS=1         # 打印获取到的 Token
X_OAUTH_PRINT_AUTH_HEADER=1    # 打印请求的认证头
```

---

#### 如何从 X 开发者平台获取各项凭据

以下是逐步获取 `.env` 中每个必填值的详细操作指南。

##### 第一步：进入 X 开发者平台

1. 打开浏览器，访问 [developer.x.com](https://developer.x.com)
2. 点击右上角 **Sign in**，用你的 X 账号登录
3. 登录后点击右上角头像 → **Developer Portal**，进入开发者控制台

##### 第二步：创建或进入已有应用

- 如果你**已有应用**：在左侧菜单点击 **Projects & Apps**，找到你的应用，点击进入
- 如果你**没有应用**：
  1. 点击左侧 **+ Add App** 或 **Create Project**
  2. 填写项目名称（如 `xmcp`）、使用场景描述
  3. 完成创建后进入应用详情页

##### 第三步：获取 OAuth 1.0 Keys（Consumer Key / Secret）

1. 在应用详情页，找到 **Keys and Tokens** 标签页
2. 找到 **Consumer Keys** 区块（也称为 **OAuth 1.0 Keys**）
3. 点击 **Regenerate**（首次使用）或直接复制已有值：
   - **API Key** → 填入 `X_OAUTH_CONSUMER_KEY`
   - **API Key Secret** → 填入 `X_OAUTH_CONSUMER_SECRET`

> ⚠️ API Key Secret 只在生成时显示一次，请立即复制保存。若遗忘需点击 Regenerate 重新生成（旧 Secret 立即失效）。

##### 第四步：获取 Bearer Token

1. 仍在 **Keys and Tokens** 标签页
2. 找到 **Authentication Tokens** 区块下的 **Bearer Token**
3. 点击 **Regenerate** 生成（或复制已有值）
4. 将完整 Token 字符串（以 `AAAAAAAAAA` 开头）填入 `X_BEARER_TOKEN`

> ℹ️ Bearer Token 是 App-Only 认证凭据，用于公开数据访问。xmcp 即使采用 OAuth 1.0a 用户授权，也需要此 Token 来完成部分 API 请求。

##### 第五步：设置应用权限（重要）

`getUsersMe`、发帖、发私信等操作需要应用具备足够的权限：

1. 在应用详情页，点击 **Settings** 标签页
2. 找到 **User authentication settings**，点击 **Set up** 或 **Edit**
3. 按以下配置填写：

   | 项目 | 推荐配置 |
   |------|----------|
   | **App permissions** | `Read and write and Direct message`（读写及私信权限） |
   | **Type of App** | `Web App, Automated App or Bot` |
   | **Callback URI / Redirect URL** | `http://127.0.0.1:8976/oauth/callback` |
   | **Website URL** | 任意有效 URL，如 `http://127.0.0.1` |

4. 点击 **Save** 保存

> ⚠️ 修改权限后，已生成的 Access Token 不会自动更新权限范围，需要重新走 OAuth 授权流程（重启 `server.py`）才能生效。

##### 第六步：最终 .env 示例

完成以上步骤后，你的 `.env` 文件应类似：

```bash
X_OAUTH_CONSUMER_KEY=你的API_Key（约25位字母数字）
X_OAUTH_CONSUMER_SECRET=你的API_Key_Secret（约50位字母数字）
X_BEARER_TOKEN=AAAAAAAAAAAAAAAAAAAAAA...（以AAAA开头的长字符串）

X_OAUTH_CALLBACK_HOST=127.0.0.1
X_OAUTH_CALLBACK_PORT=8976
X_OAUTH_CALLBACK_PATH=/oauth/callback
X_OAUTH_CALLBACK_TIMEOUT=300

X_API_BASE_URL=https://api.x.com
X_API_TIMEOUT=30
X_API_DEBUG=1

MCP_HOST=127.0.0.1
MCP_PORT=8000
```

---

### 3. 在 X 开发者平台注册回调 URL

登录 [developer.x.com](https://developer.x.com)，在你的应用设置中添加回调 URL：

```
http://127.0.0.1:8976/oauth/callback
```

---

## 启动服务

```bash
# 使用 uv
uv run python server.py

# 或直接
python server.py
```

启动后：
1. 浏览器自动弹出 **OAuth1 授权页面**，点击授权
2. 授权成功后，服务器开始监听 `http://127.0.0.1:8000/mcp`

连接 MCP 客户端：
- **本地客户端**（如 Claude Code）：指向 `http://127.0.0.1:8000/mcp`
- **远程客户端**：用 ngrok 等工具暴露本地端口，使用公网 URL

---

## 功能分类与工具列表

xmcp 提供超过 **80 个工具**，按功能分为以下类别：

### 账户与用户信息

| 工具 | 说明 |
|------|------|
| `getUsersMe` | 获取当前认证账户信息 |
| `getUsersById` | 通过用户 ID 获取用户信息 |
| `getUsersByIds` | 批量通过 ID 获取用户信息 |
| `getUsersByUsername` | 通过用户名获取用户信息 |
| `getUsersByUsernames` | 批量通过用户名获取用户信息 |
| `getUsersFollowers` | 获取用户的粉丝列表 |
| `getUsersFollowing` | 获取用户的关注列表 |
| `getUsersAffiliates` | 获取用户的关联账户 |
| `getUsersBlocking` | 获取已屏蔽的用户列表 |
| `getUsersMuting` | 获取已静音的用户列表 |
| `searchUsers` | 搜索用户 |

### 帖子（Tweets/Posts）

| 工具 | 说明 |
|------|------|
| `createPosts` | 发布新帖子 |
| `deletePosts` | 删除帖子 |
| `getPostsById` | 通过 ID 获取帖子详情 |
| `getPostsByIds` | 批量获取帖子详情 |
| `getUsersPosts` | 获取用户发布的帖子 |
| `getUsersTimeline` | 获取用户时间线（含转发/回复） |
| `getUsersMentions` | 获取用户被提及的帖子 |
| `hidePostsReply` | 隐藏帖子回复 |
| `searchPostsRecent` | 搜索最近 7 天的帖子 |
| `searchPostsAll` | 搜索全量历史帖子（需学术权限） |
| `getPostsCountsRecent` | 获取近期帖子数量统计 |
| `getPostsCountsAll` | 获取全量帖子数量统计 |
| `getPostsQuotedPosts` | 获取引用某帖子的帖子 |
| `getPostsReposts` | 获取帖子的转发列表 |
| `getPostsRepostedBy` | 获取转发某帖子的用户列表 |
| `getPostsLikingUsers` | 获取点赞某帖子的用户列表 |

### 互动操作

| 工具 | 说明 |
|------|------|
| `likePost` | 点赞帖子 |
| `unlikePost` | 取消点赞 |
| `repostPost` | 转发帖子 |
| `unrepostPost` | 取消转发 |
| `followUser` | 关注用户 |
| `unfollowUser` | 取消关注 |
| `muteUser` | 静音用户 |
| `unmuteUser` | 取消静音 |
| `getUsersLikedPosts` | 获取用户点赞过的帖子 |
| `getUsersRepostsOfMe` | 获取转发了自己帖子的用户 |

### 直接消息（DM）

| 工具 | 说明 |
|------|------|
| `createDirectMessagesByParticipantId` | 向指定用户发送私信 |
| `createDirectMessagesByConversationId` | 在指定会话中发送消息 |
| `createDirectMessagesConversation` | 创建新私信会话 |
| `getDirectMessagesEvents` | 获取私信事件 |
| `getDirectMessagesEventsByConversationId` | 获取指定会话的消息 |
| `getDirectMessagesEventsById` | 通过 ID 获取私信事件 |
| `getDirectMessagesEventsByParticipantId` | 获取与指定用户的消息 |
| `deleteDirectMessagesEvents` | 删除私信事件 |
| `blockUsersDms` | 屏蔽用户私信 |
| `unblockUsersDms` | 解除私信屏蔽 |

### 加密聊天

| 工具 | 说明 |
|------|------|
| `getChatConversation` | 获取加密聊天会话 |
| `getChatConversations` | 获取所有加密聊天会话 |
| `sendChatMessage` | 发送加密聊天消息 |
| `markChatConversationRead` | 标记会话已读 |
| `initializeChatConversationKeys` | 初始化会话密钥 |
| `initializeChatGroup` | 初始化群组聊天 |
| `addChatGroupMembers` | 添加群组成员 |
| `sendChatTypingIndicator` | 发送正在输入指示 |

### 媒体

| 工具 | 说明 |
|------|------|
| `mediaUpload` | 上传媒体（图片/视频） |
| `initializeMediaUpload` | 初始化分块上传 |
| `appendMediaUpload` | 追加媒体数据块 |
| `finalizeMediaUpload` | 完成媒体上传 |
| `getMediaUploadStatus` | 查询媒体上传状态 |
| `createMediaMetadata` | 创建媒体元数据（如 Alt Text） |
| `createMediaSubtitles` | 创建媒体字幕 |
| `deleteMediaSubtitles` | 删除媒体字幕 |
| `getMediaByMediaKey` | 通过 Media Key 获取媒体信息 |
| `getMediaByMediaKeys` | 批量获取媒体信息 |
| `getMediaAnalytics` | 获取媒体分析数据 |

### 列表（Lists）

| 工具 | 说明 |
|------|------|
| `createLists` | 创建列表 |
| `deleteLists` | 删除列表 |
| `updateLists` | 更新列表信息 |
| `getListsById` | 通过 ID 获取列表详情 |
| `getListsMembers` | 获取列表成员 |
| `getListsFollowers` | 获取列表粉丝 |
| `getListsPosts` | 获取列表中的帖子 |
| `addListsMember` | 向列表添加成员 |
| `removeListsMemberByUserId` | 从列表移除成员 |
| `followList` | 关注列表 |
| `unfollowList` | 取消关注列表 |
| `pinList` | 置顶列表 |
| `unpinList` | 取消置顶列表 |
| `getUsersOwnedLists` | 获取用户创建的列表 |
| `getUsersFollowedLists` | 获取用户关注的列表 |
| `getUsersPinnedLists` | 获取用户置顶的列表 |
| `getUsersListMemberships` | 获取用户所属列表 |

### 书签

| 工具 | 说明 |
|------|------|
| `createUsersBookmark` | 添加书签 |
| `deleteUsersBookmark` | 删除书签 |
| `getUsersBookmarks` | 获取书签列表 |
| `getUsersBookmarkFolders` | 获取书签文件夹 |
| `getUsersBookmarksByFolderId` | 获取指定文件夹的书签 |

### 数据分析与统计

| 工具 | 说明 |
|------|------|
| `getPostsAnalytics` | 获取帖子分析数据 |
| `getInsights28Hr` | 获取近 28 小时洞察数据 |
| `getInsightsHistorical` | 获取历史洞察数据 |
| `getUsage` | 获取 API 用量统计 |
| `getTrendsByWoeid` | 获取指定地区的热门话题 |
| `getTrendsPersonalizedTrends` | 获取个性化热门话题 |

### 社区（Communities）

| 工具 | 说明 |
|------|------|
| `getCommunitiesById` | 通过 ID 获取社区信息 |
| `searchCommunities` | 搜索社区 |
| `createCommunityNotes` | 创建社区笔记 |
| `deleteCommunityNotes` | 删除社区笔记 |
| `evaluateCommunityNotes` | 评估社区笔记 |
| `searchCommunityNotesWritten` | 搜索已写社区笔记 |
| `searchEligiblePosts` | 搜索符合条件的帖子 |

### Spaces（音频直播）

| 工具 | 说明 |
|------|------|
| `getSpacesById` | 通过 ID 获取 Space 信息 |
| `getSpacesByIds` | 批量获取 Space 信息 |
| `getSpacesByCreatorIds` | 获取创作者的 Space |
| `getSpacesBuyers` | 获取 Space 付费用户 |
| `getSpacesPosts` | 获取 Space 关联帖子 |
| `searchSpaces` | 搜索 Space |

### 新闻与内容

| 工具 | 说明 |
|------|------|
| `getNews` | 获取新闻内容 |
| `searchNews` | 搜索新闻 |

### 合规与管理

| 工具 | 说明 |
|------|------|
| `createComplianceJobs` | 创建合规任务 |
| `getComplianceJobs` | 获取合规任务列表 |
| `getComplianceJobsById` | 获取指定合规任务 |
| `getActivitySubscriptions` | 获取活动订阅列表 |
| `updateActivitySubscription` | 更新活动订阅 |
| `deleteActivitySubscription` | 删除活动订阅 |
| `getAccountActivitySubscriptionCount` | 获取订阅数量统计 |

---

## 实战案例

以下案例展示如何通过 Claude Code 配合 xmcp 操作 X 账户。

### 案例 1：查看当前账户信息

**对话示例：**
> "查看我的 Twitter 账户信息"

**调用工具：** `getUsersMe`

**返回示例：**
```json
{
  "data": {
    "id": "123456789",
    "name": "张昊",
    "username": "zhanghao",
    "description": "Developer & Creator",
    "created_at": "2020-01-15T08:30:00Z",
    "public_metrics": {
      "followers_count": 1024,
      "following_count": 256,
      "tweet_count": 3891,
      "listed_count": 18
    }
  }
}
```

---

### 案例 2：发布一条帖子

**对话示例：**
> "发一条推文：'今天用 Claude + xmcp 实现了 AI 自动操作 Twitter，太酷了！'"

**调用工具：** `createPosts`

**参数：**
```json
{
  "text": "今天用 Claude + xmcp 实现了 AI 自动操作 Twitter，太酷了！"
}
```

---

### 案例 3：搜索最近的帖子

**对话示例：**
> "搜索最近关于 MCP 协议的推文"

**调用工具：** `searchPostsRecent`

**参数：**
```json
{
  "query": "MCP protocol",
  "max_results": 10,
  "tweet.fields": ["created_at", "author_id", "public_metrics", "text"]
}
```

---

### 案例 4：关注一个用户

**对话示例：**
> "帮我关注用户 @anthropic"

**流程：**
1. 先调用 `getUsersByUsername` 获取用户 ID
2. 再调用 `followUser` 执行关注

**步骤 1 参数：**
```json
{
  "username": "anthropic"
}
```

**步骤 2 参数（使用返回的 user.id）：**
```json
{
  "target_user_id": "987654321"
}
```

---

### 案例 5：向指定用户发送私信

**对话示例：**
> "给用户 ID 为 123456 的用户发私信：'你好，很高兴认识你'"

**调用工具：** `createDirectMessagesByParticipantId`

**参数：**
```json
{
  "participant_id": "123456",
  "text": "你好，很高兴认识你"
}
```

---

### 案例 6：查看帖子数据分析

**对话示例：**
> "分析帖子 ID 1234567890 的互动数据"

**调用工具：** `getPostsById`

**参数：**
```json
{
  "id": "1234567890",
  "tweet.fields": ["public_metrics", "non_public_metrics", "organic_metrics", "created_at"]
}
```

**返回的关键指标：**
```json
{
  "public_metrics": {
    "retweet_count": 42,
    "reply_count": 18,
    "like_count": 256,
    "quote_count": 7,
    "impression_count": 15000
  }
}
```

---

### 案例 7：创建并管理列表

**对话示例：**
> "创建一个名为 'AI 研究者' 的私有列表，并添加用户 @openai"

**步骤 1 - 创建列表：** `createLists`
```json
{
  "name": "AI 研究者",
  "private": true,
  "description": "关注 AI 领域的研究者和从业者"
}
```

**步骤 2 - 查询用户 ID：** `getUsersByUsername`
```json
{
  "username": "openai"
}
```

**步骤 3 - 添加成员：** `addListsMember`
```json
{
  "id": "<list_id>",
  "user_id": "<openai_user_id>"
}
```

---

### 案例 8：查看热门话题

**对话示例：**
> "查看全球热门话题"

**调用工具：** `getTrendsByWoeid`

**参数：**（WOEID 1 = 全球，2151330 = 中国，23424977 = 美国）
```json
{
  "woeid": 1
}
```

---

### 案例 9：上传图片并发布带图帖子

**对话示例：**
> "上传本地图片并发一条带图的推文"

**步骤 1 - 上传媒体：** `mediaUpload`
```json
{
  "media_category": "tweet_image",
  "media_data": "<base64编码的图片数据>"
}
```

**步骤 2 - 发布帖子：** `createPosts`
```json
{
  "text": "分享一张图片 📸",
  "media": {
    "media_ids": ["<media_id>"]
  }
}
```

---

### 案例 10：监控账户被提及情况

**对话示例：**
> "查看最近有谁 @ 了我"

**调用工具：** `getUsersMentions`

**参数：**
```json
{
  "id": "<your_user_id>",
  "max_results": 20,
  "tweet.fields": ["created_at", "author_id", "text", "public_metrics"],
  "expansions": ["author_id"],
  "user.fields": ["name", "username", "profile_image_url"]
}
```

---

## 工具白名单配置

对于特定用途场景，建议只启用必要的工具以减少暴露面：

### 内容创作场景

```bash
X_API_TOOL_ALLOWLIST=getUsersMe,createPosts,deletePosts,searchPostsRecent,getPostsById,mediaUpload,finalizeMediaUpload
```

### 社交监控场景

```bash
X_API_TOOL_ALLOWLIST=getUsersMe,getUsersFollowers,getUsersFollowing,getUsersMentions,getPostsLikingUsers,getPostsRepostedBy,getTrendsByWoeid
```

### 数据分析场景

```bash
X_API_TOOL_ALLOWLIST=getPostsAnalytics,getInsights28Hr,getInsightsHistorical,getUsage,getPostsCountsRecent,searchPostsAll
```

### 私信管理场景

```bash
X_API_TOOL_ALLOWLIST=getDirectMessagesEvents,createDirectMessagesByParticipantId,createDirectMessagesByConversationId,deleteDirectMessagesEvents
```

---

## OAuth2 Token 生成

如需 OAuth2 用户授权（适用于更高权限操作）：

1. 在 `.env` 中添加：
   ```
   CLIENT_ID=your_client_id
   CLIENT_SECRET=your_client_secret
   ```

2. 更新 `generate_authtoken.py` 中的 `redirect_uri`

3. 运行授权脚本：
   ```bash
   uv run python generate_authtoken.py
   ```

4. 将打印出的 Token 复制到 `.env`：
   ```
   X_OAUTH_ACCESS_TOKEN=your_access_token
   X_OAUTH_ACCESS_TOKEN_SECRET=your_access_token_secret  # 如有
   ```

---

## Grok 测试客户端

使用 xAI Grok 模型测试 xmcp 功能：

1. 设置 `XAI_API_KEY`
2. 确保 MCP 服务器正在运行
3. 远程测试时，使用 ngrok 暴露本地端口：
   ```bash
   ngrok http 8000
   # 然后设置：MCP_SERVER_URL=https://<id>.ngrok-free.dev/mcp
   ```
4. 运行测试：
   ```bash
   uv run python test_grok_mcp.py
   ```

---

## 注意事项

1. **不支持的接口**：含 `/stream` 或 `/webhooks` 路径的端点，以及标记为 `Stream`、`Webhooks`、`x-twitter-streaming: true` 的操作均被排除。

2. **Token 生命周期**：OAuth1 Token 仅在服务器进程运行期间保存在内存中，重启服务需重新授权。

3. **API 权限层级**：部分工具（如 `searchPostsAll`、`getInsightsHistorical`）需要 X Developer 的高级访问权限（Elevated 或 Academic Research）。

4. **速率限制**：X API 有严格的调用频率限制，批量操作时注意控制请求节奏。

5. **工具白名单在启动时生效**：修改 `X_API_TOOL_ALLOWLIST` 后需重启服务器。

6. **安全建议**：
   - 不要将 `.env` 文件提交到版本控制
   - 生产环境使用 `X_API_TOOL_ALLOWLIST` 限制工具范围
   - 定期轮换 API Token

---

*本文档基于 xmcp 项目 README 整理，工具列表以实际 X API OpenAPI 规范为准。*
