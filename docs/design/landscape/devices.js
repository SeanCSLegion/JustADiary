/* ==========================================================================
   一页时光 · 设计稿 · 参考设备

   **只做 iPhone**（2026-10-01 决定：iPad 端与桌面端不再制作，对应的三栏宽屏稿
   `frames-wide.js` / `wide.html` / `screens/wide-*.png` 已删除；工程侧
   `TARGETED_DEVICE_FAMILY = "1"`、`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`）。

   尺寸都是「pt」，与真机/模拟器的逻辑分辨率一致。

   手机横屏的系统占位来自真机探针（UI 测试读 accessibility frame + 应用内日志）：
   系统浮条在横屏**仍在底部居中**、高 64pt（`app.tabBars` frame 实测 `(0, 338, 874, 64)`，
   紧贴屏幕底边），**没有**左侧竖排胶囊这回事；左侧那 62pt 是**安全区**
   （`safeArea.leading`），不是浮条。
   （中途一度被截图旋转搞反过结论，这里以 frame 数据为准。）

   实测（app 内读 safeAreaInsets）：
     竖屏 402 × 874   safe T=62 L=0  B=34 R=0
     横屏 874 × 402   safe T=0  L=62 B=20 R=62
   → 横屏的可用内容宽度是 874 − 62 − 62 = 750pt；几何原点已经落在 x = 62 的安全区里，
   内容左边界 = 62，页面只再加自己的 16pt 页边距（页头因此在 x ≈ 78），不要再避让一次。
   ========================================================================== */

const DEVICES = {
  phoneP: { name: "iPhone 18 Pro · 竖屏", type: "phone", w: 402, h: 874, scale: 0.60, landscape: false },
  phoneL: { name: "iPhone 18 Pro · 横屏", type: "phone", w: 874, h: 402, scale: 0.86, landscape: true },
  /* SE 横屏在 UI 测试里是第二档宽度（667pt，无安全区），稿子按同一套规则推导即可，
     没有单独出一张：`SplitLayoutTests` 断的是 307 / 311.5。 */
};

/* 手机横屏的安全区与系统浮条（真机实测，实现里从 safeAreaInsets / 方向派生，不要写死） */
const PHONE_CHROME = {
  navBarH: 20,         /* 底部 home indicator（横屏 safe.bottom = 20） */
  contentInset: 62,    /* 左侧安全区：safe.leading（横屏浮条仍在屏幕底部居中，与它无关） */
  /* 实现里左栏取**容器宽**（= 页面几何宽 750pt，不是屏宽 874）的 46%：
     750 × 0.46 ≈ 345pt，右栏吃剩下的 356.5pt（见 AdaptiveLayout.splitColumns）。
     SE 横屏同一条规则：667 × 0.46 ≈ 307pt，右栏 311.5pt。 */
  trailingInset: 62,   /* 右侧对称安全区（safe.trailing） */
  gridInset: 62,       /* 月格/列表左边界 = contentInset */
  headInset: 62,       /* 标题行左边界同上 */
  /* 灵动岛在横屏竖转贴左边缘，占用区约 37（宽）× 132（高）、垂直居中，
     整块落在 x 0–37 内 —— 它比安全区（62）窄，真正决定内容左边界的是安全区，不是它。 */
  islandShort: 37,
  islandLong: 132,
};
