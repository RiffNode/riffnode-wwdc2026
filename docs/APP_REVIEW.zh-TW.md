# RiffNode 專案審查與改善研究

審查日期：2026-10-17。以下保留修改前的審查結果；首批修正與驗證見 [實作進度](IMPLEMENTATION_PROGRESS.zh-TW.md)。

本次盤點 66 個 Swift 檔案、17,834 行，完成全專案結構與使用模式掃描，深入閱讀音訊引擎、DSP、分析、AI、Vision、播放、ViewModel、主要介面與雙語 README，也檢視 repo 現有截圖。工作目錄未找到 `CLAUDE.md` 或 `AGENTS.md`。以下是程式碼審查與局部演算法驗證；沒有進行 USB 錄音介面、相機、真實吉他或完整互動 UI 測試。

## 1. 這個 App 在做什麼

RiffNode 是 iPad / Mac 的吉他效果器與聲音教學工具。使用者可以接吉他，或播放內建原創合成 riff，讓訊號通過自組踏板、音箱與喇叭箱，再透過即時圖形理解聲音如何改變。

目前最完整的使用流程是：選輸入 → 選踏板／調旋鈕 → 聽音色 → 用 Signal Lab 對照處理前後 → 讀效果器解說。AI 幫使用者從文字找到設定，Vision 手勢在彈奏時提供免手控制。

| 模組 | 現有行為與技術 |
| --- | --- |
| 踏板盤 | 11 種效果，支援開關、拖曳排序與內建 preset |
| 自製 DSP | Overdrive / Distortion / Fuzz、Chorus / Flanger / Phaser / Tremolo、Wah、類比 delay、輸入級與音箱 |
| 系統效果 | Apple Dynamics Processor、AVAudioUnitEQ、AVAudioUnitReverb |
| 輸入級 | 導線／拾音器共振模型、buffer、音量、noise gate |
| 音箱與喇叭箱 | Clean / Crunch / Lead、濾波器式 cabinet、可匯入的 IR 卷積 |
| Signal Lab | 選定踏板前後的波形、包絡、頻譜與量測 |
| Learn | 聲音科學、效果器知識、單顆效果試聽及乾濕比較 |
| AI | Foundation Models 產生風格／gain／空間／踏板摘要，再由 ToneRecipeBook 轉成數值；明確指令走本機 parser；無模型時降級 |
| Vision | 點頭與歪頭事件、嘴巴連續控制 wah；挑眉有宣告但未看到實際偵測實作 |
| Play Along | 合成鼓貝斯 groove、音檔匯入、外部音樂 app 共播；iPad 可控制 Apple Music |
| Riff Notch / Stage Mode | 狀態提示、快捷控制與演奏用大踏板 |

架構是 SwiftUI + Observation，以 Presentation / Domain / Data 分層，透過小型 capability protocol 注入依賴。音訊服務大部分由 MainActor 管理，自製 AU render kernel 使用 atomics 傳參數。這個方向適合保留。

### 實際訊號路徑

```text
實體輸入 → 格式轉換 ┐
內建 Demo riff ─────┼→ FX input mixer → 輸入級 → Wah → 依排序的踏板 → Amp / Cabinet → Main mixer → 喇叭
伴奏（選擇 through FX）┘                                                    ↑
伴奏（預設 dry）────────────────────────────────────────────────────────────┘
```

注意：目前選 Demo 只改分析 tap 與播放狀態，實體輸入仍接在 mixer 上。介面呈現的 Guitar / Demo 選擇，還不是互斥的聲音來源切換。

## 2. 最值得保留的方向

1. **Signal Lab 與 Learn 的整合。** 使用者能把旋鈕、聽感、波形、解說連起來，是本專案最有辨識度的體驗。
2. **沒有吉他也能體驗。** 合成 riff 與 groove 不需要大型音訊資產，也能離線使用；但要解除目前的麥克風權限阻擋。
3. **AI 只解讀意圖，確定性程式設定旋鈕。** 比直接信任模型輸出任意 DSP 數值更可控；應先改善 command 與狀態模型。
4. **小型 protocol 與 Observable model。** 已有可替換服務的基礎，適合用 fake engine 測規則，不需要先更換整套架構。

## 3. 已確認或局部重現的問題

P1 表示建議在新增功能之前處理；P2 表示接著處理。沒有把未量測的效能風險當成已發生的爆音或卡頓。

### P1：音高演算法連基本低音 E 都可能失敗

位置：[ChordDetector.swift:135](../RiffNode.swiftpm/Data/Analysis/ChordDetector.swift#L135)。

演算法直接在未正規化的 autocorrelation 範圍取全域最大值。低頻在很短 lag 上仍高度相關，可能把搜尋範圍邊界當作週期。

用原始 `ChordDetector.swift` 編譯驗證，48 kHz、4096 samples、振幅 0.2、82.4069 Hz 正弦波得到 **1411.7646 Hz**。後續 `applyPitchResult` 會因超過 1400 Hz 而拒絕結果，讓低音 E 無法正常更新。另測 1108.7305 Hz 得 1116.279 Hz，誤差約 11.75 cents。

改善：採用 YIN 等具有週期候選與可信度判斷的單音演算法，加入次取樣插值、靜音／雜訊閘值和更新序號。YIN 是音高估測研究方向，不代表換演算法就已驗證所有吉他情境。[YIN 原始論文摘要](https://pubmed.ncbi.nlm.nih.gov/12002874/)

現有 confidence 只由訊號能量算出，沒有真正衡量週期性；和弦則由 0.5 秒內的單音歷史集合猜測，並非同時多音辨識。應把單音 tuner 與和弦辨識拆開：先讓 tuner 準確，再研究 chroma / harmonic features 與和弦模板。和弦模板同分時也需要確定性的 tie-break。

### P1：FFT 的 dB 換算錯誤

位置：[FFTAnalyzer.swift:173](../RiffNode.swiftpm/Data/Analysis/FFTAnalyzer.swift#L173)。

`vDSP_zvabs` 產生振幅，但後續 `vDSP_vdbcon(..., 0)` 使用功率模式。直接測振幅 0.1，目前 flag=0 得 -10 dB；振幅模式 flag=1 才是 -20 dB。Apple 文件明確區分這兩種模式。[vDSP_vdbcon](https://developer.apple.com/documentation/accelerate/vdsp_vdbcon)

另外，原始 FFT 類別對 2343.75 Hz、振幅 0.1、48 kHz 的整數 bin 正弦波，回報 log spectrum 最大值約 **-7.87 dB**，與理想 -20 dBFS 有差距。因此除了 flag，還需要校正 `vDSP_HANN_NORM` 的實際 coherent gain，不能只改 flag 就當作完成。

改善：用已知振幅的整數 bin sine 校正；測非整數 bin 與不同取樣率；保持 dBFS、頻譜圖、Tone Balance 的尺度一致。

### P1：AI 單一參數指令會覆蓋其他旋鈕

位置：[SemanticCommandProcessor.swift:503](../RiffNode.swiftpm/Data/AI/SemanticCommandProcessor.swift#L503)、[1288](../RiffNode.swiftpm/Data/AI/SemanticCommandProcessor.swift#L1288)。

以原始 processor、原始 Domain model 和 fake engine 驗證：

```text
原本 distortion: drive=80, tone=85, level=90
輸入 set distortion drive to 70
結果 distortion: drive=70, tone=50, level=50
```

原因是每次建立完整的預設參數，再把該效果的所有欄位全部寫回。

同樣驗證連續兩次 `more reverb`，兩次都得到 mix=75、decay=3.5；沒有根據目前值繼續增加。

改善：command 回傳不可變的 `ToneChange`，包含明確 target、只需更動的 parameter patch、relative / absolute 語意；由 engine 對當前值套用並 clamp。完整 preset 與局部 command 使用不同資料型別。

### P1：Demo 仍需要麥克風權限與有效輸入

位置：[WelcomeView.swift:181](../RiffNode.swiftpm/Presentation/Views/Welcome/WelcomeView.swift#L181)、[AudioEngineManager.swift:236](../RiffNode.swiftpm/Data/Audio/AudioEngineManager.swift#L236)。

拒絕麥克風會停在 welcome。引擎遇到無效 input format 又在建立效果、接 Demo player 之前返回。這與「沒有吉他也能玩」的產品承諾不一致。

改善：分成 Demo playback 與 Live guitar 模式；先建立 output + effects graph，再選擇性連接硬體 input。只有切 Live guitar 時要求麥克風。Demo 模式也應關閉實體輸入送往 FX mixer 的音量。

### P1：硬體格式改變後沒有完整恢復音訊圖

位置：[AudioEngineManager.swift:118](../RiffNode.swiftpm/Data/Audio/AudioEngineManager.swift#L118)。

目前只在 iOS / Catalyst 監聽 route change，handler 更新裝置名稱並重裝 tap。沒有對 macOS 的 engine configuration change 做相應處理，也沒有完整更新 processing format、來源 buffer、節點連線與播放狀態。

Apple 說明硬體 channel count / sample rate 改變時，engine 可能停止並保留舊格式，App 必須視需要重建連線。[AVAudioEngineConfigurationChangeNotification](https://developer.apple.com/documentation/avfaudio/avaudioengineconfigurationchangenotification)

改善：用單一音訊生命週期狀態機處理 permission、ready、running、interrupted、recovering、failed；序列化 route/configuration recovery，保留 preset 和 transport 意圖，再重接與重採樣。實測 USB 插拔、44.1↔48 kHz、耳機切換、背景返回、來電中斷。

### P2：Reset 與介面文字不一致

位置：[SettingsView.swift:191](../RiffNode.swiftpm/Presentation/Views/Settings/SettingsView.swift#L191)。

目前 Reset 只把關閉的踏板全部打開，沒有恢復原始 chain、順序或參數；文字卻宣稱 restore default / reset parameters。

改善：提供單一 `resetToDefaults()`，明確定義踏板、EQ、amp、input 哪些一起重設，並提供 Undo。

### P2：電平表無法顯示真正接近滿刻度的訊號

位置：[AudioEngineManager.swift:1060](../RiffNode.swiftpm/Data/Audio/AudioEngineManager.swift#L1060)、[InputSourceCard.swift:177](../RiffNode.swiftpm/Presentation/Views/Main/InputSourceCard.swift#L177)。

引擎先做 `min(1, rms * 5)`，畫面再除以 5 轉 dB。當原始 RMS 已到 1，畫面仍只得到 -13.98 dBFS，約 **76.7%**。超過 0.2 的 RMS 都已失去差異。

改善：保留原始 RMS / peak / peak hold，畫面最後才 clamp；加入 clipping indicator，區別能量與峰值。OutputLevelStore 目前也只讀第一個聲道，應評估雙聲道 peak / RMS 的顯示策略。

### P2：旋鈕拖曳會隨事件次數累積

位置：[DesignSystem.swift:379](../RiffNode.swiftpm/Presentation/DesignSystem/DesignSystem.swift#L379)。

每次 `onChanged` 把「從拖曳起點算的總 translation」加到已更新的 value 上，結果會受事件密度影響。

改善：記錄 drag 起點值，用起點值 + 總位移計算；增加 double click 輸入數值、鍵盤細調與 accessibility adjustable action。

### P2：AI 舊訊息沒有自己的音色快照

位置：[AIChatbotController.swift:135](../RiffNode.swiftpm/Presentation/ViewModels/AIChatbotController.swift#L135)。

`applyEffects(from:)` 只確認舊訊息有 effect names，實際呼叫的仍是 processor 的「最後一次」建議。對話中較舊的訊息若提供重新套用，會套到另一個結果。

改善：每個 assistant message 保存自己的 `ToneChange` / `ToneSnapshot`；套用與 Undo 都使用該訊息的資料。AI 指令也應包含完整當前參數，而不只有 pedal on/off 字串。

### P2：EQ 圖形、參數與 DSP 有多個事實來源

位置：[ParametricEQView.swift:426](../RiffNode.swiftpm/Presentation/Views/EQ/ParametricEQView.swift#L426)、[AudioEngineManager.swift:904](../RiffNode.swiftpm/Data/Audio/AudioEngineManager.swift#L904)。

曲線用 Gaussian / 分段近似，實際聲音用 AVAudioUnitEQ；Q / shelf / cutoff 的外觀未必對應真實響應。另外 engine 每次重套 EQ pedal 的 bass / mid / treble，會覆蓋 parametric bands 0、4、9 的設定，與曲線編輯／Tone Balance 的來源競爭。

改善：統一 EQ state；三顆粗調旋鈕明確映射 band，而不在無關 rebuild 時覆寫；由同一組濾波器係數或實測響應繪圖。定義 Tone Balance 的分析是原始輸入還是輸出：目前分析 tap 在麥克風／Demo，並不會隨輸出 EQ 改善而形成回饋量測。

## 4. 需要量測或互動驗證的風險

| 優先 | 位置／觀察 | 建議驗證或改善 |
| --- | --- | --- |
| P1 | AudioTapProcessing / SignalProbe 有 Array 配置、append/removeFirst、鎖，tap 還定期 print | 使用預配置 ring buffer 與 bounded SPSC 傳輸，consumer 做分析；先用 Allocations / Time Profiler 確認 callback 與 copy 成本，不宣稱已測出 dropout |
| P1 | AmpProcessor 的兩個 raw-memory bank 只有切換 index，沒有 reader 完成握手 | 快速連續更新可在讀者仍使用某 bank 時重寫它；IR count / bank index 也分開發布。設計完整 snapshot handoff，並跑並行壓力測試與 Thread Sanitizer；atomics 不自動保證整塊記憶體安全 |
| P1 | configureAudioSession 未要求 I/O buffer duration，沒有顯示實際 latency | 在支援平台提供 buffer preference，啟用後讀實際值；USB loopback 實測 round-trip latency，不能把偏好值當保證 |
| P2 | Vision start/stop 在 MainActor 呼叫同步 capture session 方法 | 搬到專用 serial executor / queue；設定失敗應 throw，只有 session 真正啟動才標 running |
| P2 | Stage Mode 取代 gesture callback，離開只 deactivate；主畫面可能透過 onAppear 重設，但沒明確 restore | 驗證進出 Stage 後手勢／wah／boost 狀態；改成單一 action router，明確管理作用域與復原 |
| P2 | Vision 沒有人臉結果時不更新 faceDetected / wah；全域強參照保存 controller | 加 face-lost timeout、wah release 與實例生命週期清理；多視窗時也不能共享最後一個 controller |
| P2 | eyebrowRaise 存在 enum / UI，但 detection 只看 pitch / roll / mouth | 實作 eyebrow landmark 判斷與校正，或先停用該選項與說明 |
| P2 | BackingTrackPlayer 在 MainActor 一次讀完整音檔、重採樣，seek 又複製剩餘 PCM | 改背景解碼與分段／串流播放；5 分鐘、48 kHz、stereo Float PCM 單份約 115 MB，原始＋轉換＋seek buffer 會增加峰值 |
| P2 | 伴奏時間用 Date + Timer；Demo 與 groove 分別即時 play | 使用 player render time 取得位置，並共用 AVAudioTime / musical transport 排程；同 BPM 不代表同拍開始 |
| P2 | SignalLabModel 每次 update 為 spectrum / brightness 重複做四次 DFT | 每側算一次 spectrum 再重用，移到 analysis worker；UI 只接不可變結果 |
| P2 | AmpResponse 在 body 針對 IR 做逐頻率 DFT | 依 IR generation / sample rate 快取響應，避免旋鈕拖動重算相同 IR 項 |
| P2 | AdaptiveBackground 常駐約 33 fps；主畫面維持固定左右欄，聊天固定 390 pt | Instruments 檢查能耗與 invalidation；Stage / Reduce Motion 靜態背景；窄視窗改上下或 sidebar，聊天改 sheet |
| P2 | 部分踏板以 tap gesture 操作，旋鈕只有 DragGesture | VoiceOver、Switch Control、鍵盤與較大文字實測；提供 Button 語意與 adjustable action |

Apple 的相機文件明確建議把阻塞的 `startRunning()` 放在 serial queue。[AVCaptureSession](https://developer.apple.com/documentation/avfoundation/avcapturesession)

音訊 callback 的配置／鎖屬於應避免的不確定耗時；Apple 的即時音訊範例也強調此限制。這裡的優化仍需依本 App 的 tap 與 render 實測判斷。[Creating an audio device driver](https://developer.apple.com/documentation/audiodriverkit/creating-an-audio-device-driver)

I/O buffer / sample rate preference 只是提示，必須在 session active 後查實際值；目前 `.mixWithOthers` 也需要納入硬體偏好與共播的取捨。[QA1631](https://developer.apple.com/library/archive/qa/qa1631/_index.html)、[Configuring Device Hardware](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/OptimizingForDeviceHardware/OptimizingForDeviceHardware.html)

## 5. 研究後的產品建議

### 優先強化「理解音色」這條完整體驗

GarageBand 已經提供 guitar amp、stompbox、tuner，甚至嘴巴控制 wah，也可錄下 pedal movement。因此 mouth wah 可以保留為互動特色，但主要定位更適合放在 Signal Lab + 可理解的音色教學。[GarageBand Amp 官方說明](https://support.apple.com/en-asia/guide/garageband-ipad/chs39281180/ipados)

建議把 Learn 做成一個可完成的短課程，例如：

1. 選 clean、單音／和弦／palm mute／留白的 riff。
2. 先聽原音，再啟用單一效果；比較前後時做音量匹配，避免單純把「比較大聲」當作「比較好」。
3. 高亮一個變化：失真增加諧波、壓縮降低 crest factor、delay 填滿留白。
4. 邀請使用者只調一顆旋鈕，預測與觀察結果。
5. 保存自己的版本，之後可以再比較。

這是產品建議，尚未做使用者研究驗證；應以新手能否正確說出效果、是否能完成一次比較來驗收。

### 真實吉他 Demo，應提供可比較的乾訊號素材

目前合成 riff 適合離線展示，但未必能代表真實琴弦、pick attack、palm mute 與動態。建議錄製或取得明確可用的 clean DI 素材，至少包括：單音、分散和弦、強弱刷弦、palm mute、長音＋停頓。

剛下載的兩段歌曲 riff 是有音箱處理的演奏片段，適合本機參考，不適合拿來當純乾訊號評估 pedal；目前也未接入 App。Demo library 需要描述素材音色、節奏、長度，並處理循環接點。公開打包前再處理素材授權。

### 能保存整個 Rig，比再多幾顆踏板更實用

現有 EffectPreset 只保存 effects，PresetService 只是記憶體陣列；沒有使用者 preset 的持久化。建議新增版本化 Codable `RigSnapshot`：effects + EQ bands + amp + cabinet / IR reference + input settings + tempo；保留全域 input level / 裝置設定的選項，支援 Save / Rename / Duplicate / Favorite / Export / Import。

Neural DSP 的官方操作說明把裝置／I/O channel、buffer、preset、MIDI、metronome、tap tempo 列為演奏工作流程；這些可以作為實用性參考。Global Lock 也顯示「換音色但保持自己的輸入設定」的價值。[Neural DSP 操作說明](https://neuraldsp.com/getting-started/tips-for-using-your-plugin)、[Misha Mansoor X Global Lock](https://neuraldsp.com/plugins/archetype-misha-mansoor)

建議順序：Save / Restore → Undo / A/B → shared transport / tap tempo → 短錄音 loop / export → MIDI CC / PC → 最後再評估 AUv3 整合。後兩項是較大的產品階段，不是修 bug 的前置條件。

### AI 應能解釋更動，也能復原

保留 ToneSketch → recipe 的模式，改用每則訊息的不可變 change / snapshot，加入完整 state、參數 patch、Undo 與前後音量匹配比較。串流目前顯示的是已生成欄位與進度，對使用者可稱為「調音色步驟」。

建立固定的英文指令資料集：單一參數、relative 增減、刪除／bypass、負向敘述、多效果、問答、模型 unavailable；每次系統／模型更新都重新驗證。Apple 也提供 Foundation Models prompt evaluation 指引。[Evaluating prompts](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses)

### DSP 音質要用量測決定下一步

Drive 目前把四個內插點削波後平均，是有限的抗 aliasing 近似；Amp 的非線性前後級則沒有同等 oversampling。可以研究 FIR / IIR half-band oversampling、參數平滑與 bypass crossfade。不能只因註解寫「4×」就視為已完成完整濾波／降採樣設計。[JUCE Oversampling 官方技術說明](https://docs.juce.com/develop/classjuce_1_1dsp_1_1Oversampling.html)

IR 目前上限 2048 taps，在 48 kHz 約 42.7 ms。先量測直接卷積在目標 iPad 的負載，再決定是否需要 partitioned FFT convolution。不要在沒有測出瓶頸前增加複雜度。

## 6. 建議執行順序與驗收

| 階段 | 範圍 | 驗收方式 |
| --- | --- | --- |
| 1：核心可信度 | Demo 不需麥克風、修 tuner / FFT / meter、修 command patch / Reset / knob | 拒絕麥克風仍可試聽；標準六弦與已知振幅測試通過；只改指定參數；操作可復原 |
| 2：演奏可靠度 | 路由／中斷恢復、來源互斥、buffer preference、callback / bank 交換、Vision lifecycle | USB 插拔與格式切換可恢復；量測 round-trip latency、CPU 與 dropout；相機／Stage 退出狀態正確 |
| 3：保存與練習 | RigSnapshot、Undo / A/B、DI library、shared transport、背景解碼 | 重開 App 音色一致；A/B 不覆蓋設定；groove / demo 同步；長音檔不阻塞 UI |
| 4：教學與整合 | 短課程、教學進度、錄音 loop、MIDI；再評估 AUv3 | 使用者能完成一次理解／調整／保存流程；整合需獨立規劃 |

SwiftUI 效能應用 Instruments 的 SwiftUI / Time Profiler / Hangs / Hitches 確認，再決定是否拆 state、快取或減少動畫；這次沒有取得執行中的 Instruments trace。[Apple WWDC25：Optimize SwiftUI performance with Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)

## 7. 本次實際驗證

- Xcode workspace 成功辨識 `RiffNode` scheme。
- `xcodebuild ... -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`：**BUILD SUCCEEDED**。看到 Assets.xcassets 重複 build file 與未使用 AppIntents metadata extraction 的 warning，未見阻止建置的錯誤。
- 原始 FFTAnalyzer / ChordDetector，搭配最小 protocol stubs 的 Swift CLI harness：重現低音 E 錯誤、dB 換算問題與靜音後殘留音名狀態。
- 原始 SemanticCommandProcessor / ToneRecipeBook / Domain，搭配 fake EffectsChainManaging：重現指定 drive 時覆寫 tone / level，以及連續 relative request 無增量。
- 電平表公式驗證：full-scale RMS 對應顯示上限約 0.767。
- 未修改 App 實作；沒有把 simulator build 視為實機音質、相機或低延遲驗證。
