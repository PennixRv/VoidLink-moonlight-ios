# tvOS Hosts Home Spec

## Goal

为 `moonlight-ios-official` 的 tvOS `Hosts 首页` 提供第一版 tvOS 26 风格重构，解决当前首页“只有 glass 皮层、没有新版式系统、主机卡片仍是旧式方块 tile”的问题。

本轮仅覆盖 `Hosts 首页`：

- 顶部标题区与操作区
- 主机卡片的信息层级、比例与焦点行为
- Hosts 行的内容密度、留白和遥控器焦点路径

## Non-goals

- 不重做 `App Grid`
- 不重做 `Settings`
- 不重做串流中的统计条与播放层
- 不修改串流协议、编解码或输入链路

## Visual Direction

### 1. 页面结构

首页由三层组成：

1. 背景层：沿用现有渐变背景，继续作为全屏氛围底色。
2. 标题层：自定义 `Hosts Home chrome`，包含品牌眉题、主标题、副标题和三枚操作按钮。
3. 内容层：单行横向 `Hosts` 卡片轨道，主机卡从旧方块升级为宽卡。

### 2. 标题区

- 顶部保留明显留白，避免旧版导航栏式的挤压感。
- 主标题负责表达页面任务，不再只依赖 navigation bar title。
- 副标题负责解释当前状态与遥控器操作提示。
- 操作区使用 3 个横向按钮：
  - `设置`
  - `网络诊断`
  - `手动添加主机`

### 3. 主机卡片

- 卡片改为宽卡，目标视觉比例接近 `16:9`。
- 卡片内部采用“三层信息”：
  - 眉题：主机类型或入口性质
  - 主标题：主机名
  - 副标题：状态文案 + 地址/指引
- 右侧保留更大的主机图标区域，但不再占满整张卡片。
- 使用状态 badge 表达在线、离线、需配对、连接中。

### 4. 焦点行为

- 默认焦点优先落到第一张主机卡。
- 从顶部操作区按下方向键，必须稳定进入主机卡轨道。
- 从主机卡按上方向键，应能回到顶部按钮行。
- 焦点态不只依赖系统 scale：
  - 卡片信息层整体轻微上浮
  - 图标区轻微增强
  - badge 与文本对比度提升

## Layout System

### Global Insets

- 页面左右主边距：`88pt`
- 标题区顶部安全区外补白：`18pt`
- 标题区与卡片轨道之间的节距：`24pt`

### Hero Typography

- 眉题：`24pt semibold`
- 主标题：`60pt bold`
- 副标题：`24pt regular`
- 分区标题：`30pt semibold`
- 分区辅助文字：`22pt regular`

### Action Buttons

- 高度：`72pt`
- 内边距：`26pt` 左右
- 间距：`20pt`
- 使用 glass/material 作为底面，但只做轻量 chrome，不做整页玻璃化

### Host Cards

- 视觉主体尺寸：`540 x 304`
- 外围焦点缓冲：`28pt`
- 轨道内卡片间距：`56pt`
- 底部信息带高度：约 `124pt`

## Interaction Rules

- `设置`：沿用现有 `openTvSettings:`
- `网络诊断`：调用现有 Moonlight 客户端连通性测试
- `手动添加主机`：沿用现有 `addHostClicked`
- 主机卡 `Select`：沿用现有 `hostClicked`
- 主机卡长按：沿用现有 action sheet / 上下文能力

## Implementation Hooks

核心文件：

- `Limelight/ViewControllers/MainFrameViewController.m`
- `Limelight/UIComputerView.m`
- `Limelight/VLTVOSUI.h`

实现策略：

1. `MainFrameViewController`
   - 新增 tvOS-only 的 `Hosts Home chrome`
   - 负责按钮区、焦点桥接、显隐切换和布局
   - 在显示 Hosts 首页时隐藏旧 navigation bar

2. `UIComputerView`
   - 从正方形 icon tile 重构为宽卡
   - 增强信息层级与焦点动画
   - 添加更明确的状态 / 地址展示

3. `VLTVOSUI.h`
   - 补充首页布局和按钮/卡片的 tvOS 辅助常量

## Reference Sources

- Apple tvOS focus design guidance
- Apple tvOS 26 Liquid Glass guidance
- `ATV-Bilibili-demo`
- `AngelLive`

## Verification

本地最小验证：

- `git diff --check`
- 静态检查新增字符串、frame 计算与焦点路径是否自洽

后续验证：

- GitHub Actions `Build tvOS IPA`
- 真机遥控器焦点与客厅距离可读性验收
