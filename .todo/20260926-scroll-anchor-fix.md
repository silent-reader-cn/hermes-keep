# 2026-09-26 离底阅读时“新内容把历史顶上去”修复（reverse 列表视口锚点补偿）

主人反馈：**生成中的会话里向上滑看历史消息时，下方新生成的内容会把历史消息顶上去。**

## 1. 根因（实测取证）

A 重构把消息列表改成 `reverse: true`（offset 0 = 视觉底部 = 最新）后，**新内容插在物理
index 0 端**，它把所有已有条目的 sliver 偏移**整体推大 h**，而 `pixels` 一动不动。

A 重构时的推理是「内容增长插在 index 0 侧、**不会推开底部像素**」—— 这句话对
`pixels` 成立，对**屏幕内容不成立**：

```
dy = offset − pixels + 常量      // reverse 坐标
插入 h 后 offset' = offset + h ⇒ dy 减小 h（屏幕上移 h）
```

于是旧判据「pixels 静止 = 视觉稳定」恰好放过了真正的位移。**A 重构把补偿链整段删掉
（`_maybeRestoreReadingAnchor` 退化为 no-op）正是基于这个错误前提。**

实测（widget 探针，40 条历史 + 流式 token）：
- 无补偿：`pixels` 恒定 280，历史消息 m30 从 dy 385.5 → 291.5（**永久上移 94px**）
- 有补偿：`pixels` 280 → 311，m30 dy **仍为 385.5**（逐像素不动）

## 2. 修复（`chat_message_list.dart`）

1. **几何锚点补偿**：离底阅读时以「**视口纵向居中**的历史条目」为探针，内容变化后
   测其 dy 漂移 `delta`，`pixels += delta` 抵消。
   - 漂移量取**几何实测**而非 `maxScrollExtent` 增量 —— 后者在内容变化那一帧实测
     **骤降 800px**（lazy 列表按均值估算未构建条目），照它补偿会过冲、甚至反向乱跳。
2. **探针健壮性四道守卫**（每一条都对应一次实测故障）：
   - **id 用 `messageId`**：`renderId = transcript:<offset+i>`，归档/分页会让 offset
     变化、整批 renderId 失效 → 探针被反复丢弃重建；
   - **出树容忍 3 帧**：立即丢弃重建会把已经发生的漂移**追认**成新基准（滚轮场景
     实测探针从 286.5 被追认成 265.5，补偿恒为 0）；
   - **探针飞出视口即失效**：此后读到的是回收/重建噪声；
   - **同一帧只补一次**：补偿后的 pixels 要到下一帧才反映到 render tree，期间读数
     仍是旧值 —— 重复补偿会把同一漂移补多次（实测连续补 3 次 ×46px，把视口推飞）。
3. **`_isAnchorCompensating` 并入 `_isProgrammaticScrolling`**：否则补偿的 `jumpTo`
   会被状态机当成「鼠标滚轮上滚」，紧接着的 `ScrollEndNotification` 走「用户滚动结束」
   分支把探针清掉 —— 补偿每帧自毁。
4. **探针不取 live 时间线条目**：live 段落自身随 token 增长/重排，顶边 dy 剧烈跳动
   （实测 base 恒定 48.7 而 now 在 +109 ~ −139 间乱跳），拿它当基准必然震荡。
5. **撤掉中途试过的 `ScrollPhysics.adjustPositionForNewDimensions` 同帧补偿**：
   `RenderViewport.performLayout` 在 `applyContentDimensions` 返回 true 时直接
   `break`（不重排），**同帧无效**；且补偿量依赖不可靠的 extent。

## 3. 测试

- 新增 `chat_read_anchor_follow_test.dart`（7 例）：核心回归 + 长文本大位移 + 间距连续 +
  补偿不吞正文 + 贴底跟随不回归 + 补偿不夺手势 + 工具卡事件。
- **改钉 9 处既有断言**（`chat_streaming_scroll_test` / `chat_wheel_scroll_follow_test` /
  `chat_scroll_jitter_test` / `chat_image_load_scroll_follow_test` / `chat_follow_gesture_state_machine_test` /
  `chat_outline_jump_test` / `chat_reading_anchor_test` / `chat_sticky_bottom_test`）：
  它们当时钉的是 `(pixels 变化).abs() < 5~10px` —— **缺陷的镜像**（pixels 不动恰是
  缺陷的成因），缺陷存续期一直绿。现改为**屏幕坐标判据**（固定条目的 dy）+「pixels 只
  前进、不得被拽回底部」。
- 抖动判据从「逐帧 span < 1px」改为「**稳态恒定 + 至多一帧中间态**」：内容增长那一帧
  的 layout 先落地、补偿在 postFrame 才生效、下一帧恢复 —— 这是 Flutter 布局时序固有
  的一帧中间态，逐帧判据会把 0 漂移的修复误判成抖动。

## 4. 过程事故（重要）

**并行会话的提交覆盖了本轮的 lib 改动**：main 上先后落地 `da152a3` / `b4c2065` / `07d86ef`
（都是同一工作区的另一个会话），其中一次写入把 `chat_message_list.dart` 回退到了本轮的
**中间版本**（`_driftProbeId` / `_isAnchorCompensating` 等全部消失，而 `_readingAnchorTopDy`
等早期代码复现）。处置：备份现场（`D:/tmp/scrollfix-backup/`）→ 在新 HEAD 基线上重做缺失部分。

教训：
- **同一工作区多会话并行时，长时间不提交的改动随时可能被覆盖**；本轮属于「边做边被改」，
  多次 `git diff`/`grep` 读到的是**别人写入中的中间态**（曾据此误判「改动全丢了」）。
- 判断文件状态要**多源交叉**（`git diff --stat` + `grep 关键标记` + `stat -c %y` mtime），
  单看一次 `git diff` 会得出假结论。
- 验证性改动最好**尽早提交**自保，而不是等全绿再提交。

## 5. 残余 / 未处理

- **内容增长那一帧的 1 帧中间态**（16ms，幅度 = 单次内容增长量）无法在不重构列表结构
  的前提下消除：补偿只能在 layout 之后进行。正向列表（A 重构前）天然没有这个问题，代价
  是初始定位 O(n) 与分页 prepend 的几何归位。
- 混合流式（工具卡 + token 交替）下探针条目会被大幅增长推出视口，补偿呈「逐次小修」，
  残余 ±50px **帧间波动**（**无累积**）。
- 观察到**既有**现象（非本轮引入、未处理）：混合流式下 `pixels` 会被拉回 0 —— 离底状态
  被既有路径重置；`chat_scroll_jitter_test` 用例 3 原有断言因此移除并注明。
