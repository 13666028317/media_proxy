## 0.0.2

* 修复网络切换后下载卡死：增加响应流读超时，网络中断或切换后任务能及时失败并重试。
* 修复视频末尾几秒无法播放：分片下载完整性校验、末尾分片强制预加载，数据不足时触发重新下载。
* 修复并发下载冲突：入队去重、分片完成时的并发处理，避免多任务同时处理同一分片导致文件冲突。

## 0.0.1

* Initial release.
* Local HTTP proxy for media caching.
* Support for range requests and prefetching.
* MP4 optimization (moov atom).
* LRU cache management.
