---
name: 照片详情页AI深度分析下移
overview: 将PhotoDetail.vue中DeepAnalysis组件从右侧信息面板底部移到图片+信息区域的下方，作为全宽区块独立展示，解决深度分析报告在窄面板中阅读体验差的问题。
design:
  styleKeywords:
    - Glassmorphism
    - 全宽报告
    - Markdown渲染
  fontSystem:
    fontFamily: system-ui
    heading:
      size: 14px
      weight: 600
    subheading:
      size: 13px
      weight: 600
    body:
      size: 14px
      weight: 400
  colorSystem:
    primary:
      - "#818cf8"
    background:
      - "#0f172a"
    text:
      - "#e2e8f0"
      - "#94a3b8"
    functional:
      - "#818cf8"
todos:
  - id: move-deep-analysis
    content: 将 DeepAnalysis 组件从 PhotoDetail 右侧面板移至 grid 下方全宽区域
    status: completed
  - id: adjust-deep-analysis-style
    content: 微调 DeepAnalysis 组件样式适配全宽展示
    status: completed
    dependencies:
      - move-deep-analysis
---

## Product Overview

优化照片详情页布局，将 AI 深度分析报告从右侧窄面板移至页面底部全宽区域展示。

## Core Features

- 将 DeepAnalysis 组件从右侧信息面板（1/3 宽度）中移出，独立为页面底部的全宽区块
- 调整 DeepAnalysis 组件的样式，适配全宽展示（增大字体、优化间距、改善可读性）
- 保持原有的三种状态交互不变：未生成（触发按钮）、分析中（loading）、已生成（Markdown 报告）

## Tech Stack

- Vue 3 + TypeScript + Tailwind CSS（与现有项目一致）

## Implementation Approach

将 `DeepAnalysis` 组件从三列 grid 的右侧面板 div 中移出，放置在 grid 闭合标签之后、`</main>` 之前，使其成为独立的全宽区块。同时微调 DeepAnalysis 组件内部的样式，使其在更宽的容器中拥有更好的阅读体验（适当增大字体和间距，利用全宽空间）。

## Implementation Notes

- 仅涉及两个文件的模板和样式修改，无逻辑变更
- DeepAnalysis 组件的 props 和 events 接口保持不变
- 右侧面板移除 DeepAnalysis 后，其余内容（评分、EXIF、标签、描述）保持原样

## Directory Structure

```
frontend/src/
├── views/
│   └── PhotoDetail.vue        # [MODIFY] 将 DeepAnalysis 从右侧面板移至 grid 下方全宽区域
├── components/
│   └── DeepAnalysis.vue       # [MODIFY] 微调样式适配全宽展示（字体、间距、布局）
```

将深度分析报告从右侧窄栏移至页面底部全宽展示，让长篇 Markdown 报告获得更大的阅读空间。底部区域使用 glass 面板风格，与页面整体设计语言一致，但在全宽下适当放宽字体和行距以提升可读性。