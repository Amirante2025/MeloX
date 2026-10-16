# MeloX Release Notes / MeloX 更新日志

## iOS + Apple Watch

### 简体中文

- 调整了音乐库页面切换入口，点击导航标题即可选择分类，腾出列表内容空间
- 修复了 iPad 全屏歌词上下露底与退出按钮被状态栏遮挡的问题
- 增加了歌手关注与取消关注，以及可搜索的已关注歌手音乐库页面
- 增加了原生搜索联想，支持输入补全与通用设置开关
- 优化了搜索分类切换，复用当前关键词的已加载结果并防止旧请求覆盖新搜索
- 增加了从自建歌单移除歌曲，操作后同步更新列表、歌曲数量与分页位置
- 增加了删除自建歌单，支持删除确认与音乐库同步更新
- 增加了新建公开与私密歌单，支持在添加歌曲时直接创建歌单
- 更换了 iOS 音频播放引擎，优化了跳转、暂停与重播的进度同步
- 修复了歌词跳转后与音频时间轴不同步的问题
- 修复了 EVA 歌词界面进入时未随背景渐入的问题
- 调整了 iPad 播放器布局，支持桌面端样式的双栏歌词、队列与常驻播放控制
- 修复了 iPad 播放器收起与展开歌词按钮的尺寸和对齐问题

### English

- Moved the library category picker into the navigation title menu to free up content space
- Fixed exposed background bands and the exit button overlapping the status bar in iPad full-screen lyrics
- Added artist follow controls and a searchable Followed Artists library page
- Added native search suggestions with text completion and a General settings toggle
- Improved search category switching with cached results and protection against stale responses
- Added removing songs from owned playlists with synchronized track counts and pagination
- Added deletion of owned playlists with confirmation and immediate library updates
- Added public and private playlist creation, including creating a playlist while adding a song
- Replaced the iOS audio playback engine to improve progress synchronization when seeking, pausing, and replaying tracks
- Fixed lyrics falling out of sync with audio after seeking
- Fixed EVA lyrics appearing abruptly instead of fading in with the background
- Updated the iPad player with a desktop-style two-column layout for lyrics, the queue, and persistent playback controls
- Fixed the size and alignment of the iPad player's collapse and expand-lyrics buttons

## macOS

### 简体中文

- 优化了搜索重复提交时的请求衔接，避免已被替代的等待请求继续发出
- 增加了已关注歌手音乐库页面，优化了歌手关注操作的状态同步
- 增加了原生搜索联想，支持输入补全与通用设置开关
- 优化了搜索分类切换，复用当前关键词的已加载结果并防止旧请求覆盖新搜索
- 增加了从自建歌单移除歌曲，操作后同步更新列表、歌曲数量与分页位置
- 增加了删除自建歌单，支持删除确认与音乐库同步更新
- 增加了新建公开与私密歌单，支持在添加歌曲时直接创建歌单
- 更换了音频播放引擎，优化了跳转、暂停与重播的进度同步
- 修复了歌词跳转后与音频时间轴不同步的问题

### English

- Improved repeated search submission by discarding superseded requests before they start
- Added a Followed Artists library page and improved follow-state updates
- Added native search suggestions with text completion and a General settings toggle
- Improved search category switching with cached results and protection against stale responses
- Added removing songs from owned playlists with synchronized track counts and pagination
- Added deletion of owned playlists with confirmation and immediate library updates
- Added public and private playlist creation, including creating a playlist while adding a song
- Replaced the audio playback engine to improve progress synchronization when seeking, pausing, and replaying tracks
- Fixed lyrics falling out of sync with audio after seeking
