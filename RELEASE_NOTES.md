# MeloX Release Notes / MeloX 更新日志

## iOS + Apple Watch

### 简体中文

- 迷你播放器封面缩小至 30pt 并向右微调 4pt，搜索与其他标签整合在同一个系统胶囊导航条内
- 标题与右侧头像同排放在页面内容顶部，随内容自然滚动
- 顶部的系统超薄模糊随滚动渐显，回到页面顶部时完全隐藏
- 搜索页与其他页面共用标题行，搜索栏在滚动后固定到状态栏下方，点击搜索时自动上移
- 歌曲列表采用 48pt 封面及上下各 4pt 间距，收紧歌单和音乐库歌曲行的分隔距离
- 播放页在更多按钮左侧显示星标收藏按钮，可直接收藏或取消收藏歌曲
- 应用显示名称改为 Music，并使用自定义音乐图标
- 增加了音乐库搜索框的独立显示开关，关闭时清除当前搜索筛选
- 增加了“页面与标签栏”中各页面的独立显示开关，支持隐藏首页、搜索、推荐及音乐库各项，并保留原有布局
- 移除了 iOS 安装包中的 Apple Watch App 和手机端手表同步服务，避免重签后的手表关联标识不匹配导致安装失败
- 增加了私信和听歌识曲工具栏按钮的独立显示开关，可在“设置 → 功能模块”中调整
- 增加了歌手关注与取消关注，以及可搜索的已关注歌手音乐库页面
- 增加了搜索联想与输入补全，可在通用设置中开启或关闭
- 增加了从自建歌单移除歌曲的功能
- 增加了自建歌单删除功能，支持删除前确认
- 增加了新建公开与私密歌单，支持在添加歌曲时直接创建歌单
- 修复了 Apple Music 歌词快速换句时滚动跟不上播放进度的问题
- 修复了 iPad 全屏歌词边缘露出播放器背景、退出按钮被状态栏遮挡的问题
- 修复了歌词跳转后与歌曲播放不同步的问题
- 修复了 EVA 歌词界面进入时未随背景渐入的问题
- 修复了 iPad 播放器收起与展开歌词按钮的尺寸和对齐问题
- 优化了全屏天际歌词的换句动画，衔接更自然
- 优化了搜索分类切换，返回已查看的分类时更快
- 优化了跳转、暂停与重播时的播放进度显示
- 优化了 iPad 播放器，采用桌面端样式的双栏布局与常驻播放控制

### English

- Reduced mini-player artwork to 30pt, shifted it 4pt to the right, and joined Search with the other tabs in one native capsule
- Placed large page titles and profile actions in the scrolling content so they move offscreen together
- Made the ultra-thin system status-bar blur fade in with scrolling and disappear at the top
- Reused the shared page title in Search, pinned the search field below the status bar when scrolling, and moved it up when editing starts
- Tightened song rows with 48pt artwork and 4pt vertical insets in playlists and the Library
- Added a Favorite star to the left of More in Now Playing to favorite or unfavorite the current song
- Renamed the app to Music and applied the supplied custom music icon
- Added an independent Library search visibility switch that clears the current filter when hidden
- Added independent visibility switches in Pages & Tab Bar for Home, Search, Recommended, and every Library page while preserving their layout
- Removed the embedded Apple Watch app and phone-to-watch sync service to avoid companion bundle identifier mismatches after re-signing the iOS package
- Added independent visibility toggles for the Private Messages and Song Recognition toolbar buttons in Settings → Feature Modules
- Added artist follow controls and a searchable Followed Artists library page
- Added search suggestions and text completion, with a toggle in General settings
- Added the ability to remove songs from your own playlists
- Added deletion of your own playlists with confirmation
- Added public and private playlist creation, including creating a playlist while adding a song
- Fixed Apple Music lyrics falling behind playback during rapid line changes
- Fixed the player background showing around iPad full-screen lyrics and the exit button overlapping the status bar
- Fixed lyrics falling out of sync with playback after seeking
- Fixed EVA lyrics appearing abruptly instead of fading in with the background
- Fixed the size and alignment of the iPad player's collapse and expand-lyrics buttons
- Improved full-screen Skyline lyrics with smoother transitions between lines
- Improved search category switching so previously viewed results appear faster
- Improved progress display when seeking, pausing, and replaying songs
- Improved the iPad player with a desktop-style two-column layout and persistent playback controls

## macOS

### 简体中文

- 增加了可搜索的已关注歌手音乐库页面
- 增加了搜索联想与输入补全，可在通用设置中开启或关闭
- 增加了从自建歌单移除歌曲的功能
- 增加了自建歌单删除功能，支持删除前确认
- 增加了新建公开与私密歌单，支持在添加歌曲时直接创建歌单
- 修复了 Apple Music 歌词快速换句时滚动跟不上播放进度的问题
- 修复了歌词跳转后与歌曲播放不同步的问题
- 优化了歌手关注与取消关注时的状态显示
- 优化了搜索分类切换，返回已查看的分类时更快
- 优化了重复提交搜索时的体验
- 优化了跳转、暂停与重播时的播放进度显示

### English

- Added a searchable Followed Artists library page
- Added search suggestions and text completion, with a toggle in General settings
- Added the ability to remove songs from your own playlists
- Added deletion of your own playlists with confirmation
- Added public and private playlist creation, including creating a playlist while adding a song
- Fixed Apple Music lyrics falling behind playback during rapid line changes
- Fixed lyrics falling out of sync with playback after seeking
- Improved follow-status updates when following or unfollowing artists
- Improved search category switching so previously viewed results appear faster
- Improved the experience when submitting the same search repeatedly
- Improved progress display when seeking, pausing, and replaying songs
