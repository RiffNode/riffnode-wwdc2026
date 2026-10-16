# 首批實作與驗證

更新日期：2026-10-17。對應 [原始審查](APP_REVIEW.zh-TW.md) 的核心可信度階段，以及使用者要求的 clean Demo。

## Clean Demo

- 預設為原創合成分散和弦；也可匯入自己彈的 clean 錄音（複製到 App 的 Application Support），直接送入踏板前端。
- Input 卡片加入錄音選單與整組踏板旁通比較。旁通保留每顆踏板的設定，也保持相同來源與音箱，讓使用者比較前後。
- 新啟動與 Reset 時，六顆預設踏板皆關閉，先提供 clean 基準。
- Demo 錄音由使用者自行匯入，不打包進 App；本機測試音檔放在 `.gitignore` 的 `demo-riffs/`。

## 已修正

1. Demo 啟動不要求麥克風權限，也不需要有效的硬體 input；選 Guitar 時才要求權限並建立實體輸入。
2. 播放 Demo 時靜音實體輸入，避免兩個來源混在一起。切換來源會清除分析緩衝。
3. 單音調音改為 YIN cumulative mean normalized difference，加次取樣插值與週期可信度；拒絕靜音、DC 與不可靠訊號，清除殘留音名。
4. 每次只保留一個背景音高分析；重設／來源切換使舊結果失效。
5. FFT 使用振幅 dB 模式，依實際窗函數總和校正增益。
6. 電平保留原始 linear RMS；各電平表共用 −60…0 dBFS 尺度，不再先乘五截斷。
7. AI 明確參數指令只修改指定旋鈕；more / less 依目前值增減並限制範圍，支援 delay ms。
8. 舊 AI 訊息重新套用時使用該訊息自己的踏板快照，避免誤套最後一次指令。
9. Reset 恢復預設六顆踏板、順序、參數與 flat EQ，並清除整組旁通狀態；介面說明同步更新。
10. 旋鈕以拖曳起點＋總位移計算，避免事件頻率改變結果，新增輔助使用的增減操作。
11. EQ 圖形修改同步到粗調旋鈕；重建音訊鏈不再以舊的粗調值覆寫曲線。
12. Stop 會停止伴奏，重建 graph 時先卸載舊 player；Demo 錄音會轉換成引擎格式。
13. 移除音訊 tap 的定期 console 輸出；iPad audio session 加入 5 ms buffer 偏好（偏好值不代表實測延遲）。

## 驗證結果

- `scripts/test-core.sh`：**83/83 通過**。涵蓋六弦與高音、44.1/48 kHz、諧波、靜音、DC、雜訊、頻譜校正、電平、AI 局部與相對參數、舊訊息快照、免麥克風 setup。
- `scripts/test-audio.sh`：**3/3 通過**。用實際 DemoRiffPlayer、AVAudioConverter、自製 AU 與 AVAudioEngine offline rendering，以測試自動產生的 clean 錄音，驗證匯入錄音在 44.1/48 kHz 下的 stereo 輸出與加 distortion 的差異，也驗證原創合成來源仍可播放。
- iOS Simulator `xcodebuild`：**BUILD SUCCEEDED**。既有 Assets 重複 build file / AppIntents metadata warning 仍存在。
- 測試自行產生暫存 WAV，模擬使用者匯入的錄音；App 不內含音檔。
- `git diff --check` 通過。

## 仍待後續階段

尚未完成：硬體 route / interruption 的完整恢復、音訊分析 callback 的 ring buffer 與無鎖傳輸、amp bank 並行握手、Vision lifecycle、完整 RigSnapshot 持久化與 Undo、EQ 曲線精確響應、長音檔串流及 transport 同步。

本次沒有用真實吉他、USB 錄音介面或相機測試，也沒有量測實機 round-trip latency。離線渲染驗證了音檔與效果訊號差異，不能代替實機聽感與互動測試。
