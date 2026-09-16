/* ==========================================================================
   一页时光 · 设计稿 · 参考设备
   尺寸都是「pt」，与真机/模拟器的逻辑分辨率一致。

   手机横屏的系统占位来自真机探针（UI 测试读 accessibility frame + 应用内日志），
   并且**用方向无关的方式复核过**：浮条中心 (32, 360) 与屏幕中心 (437, 201) 相距很远，
   所以它是贴在**左边缘、竖直居中**的一条竖排胶囊，不是底部横条。
   （中途一度被截图旋转搞反过结论，这里以 frame 数据为准。）

   实测（app 内读 safeAreaInsets）：
     竖屏 402 × 874   safe T=62 L=0  B=34 R=0
     横屏 874 × 402   safe T=0  L=62 B=20 R=62
   → 横屏的可用内容宽度是 874 − 62 − 62 = 750pt，内容左边界要 +62 让开系统浮条。
   ========================================================================== */

const DEVICES = {
  phoneP: { name: "iPhone 18 Pro · 竖屏", type: "phone", w: 402, h: 874, scale: 0.60, landscape: false },
  phoneL: { name: "iPhone 18 Pro · 横屏", type: "phone", w: 874, h: 402, scale: 0.86, landscape: true },

  duo: { name: "iPhone Duo · 内屏展开", type: "phone", w: 664, h: 750, scale: 0.60, landscape: false },

  padP: { name: "iPad Pro 13 · 竖屏", type: "pad", w: 1032, h: 1376, scale: 0.42, landscape: false },
  padL: { name: "iPad Pro 13 · 横屏", type: "pad", w: 1376, h: 1032, scale: 0.50, landscape: true },
  mac: { name: "Mac · 窗口 1432×900", type: "mac", w: 1432, h: 900, scale: 0.50, landscape: true },
};

/* 手机横屏的系统占位（真机实测，实现里从 safeAreaInsets 派生，不要写死） */
const PHONE_CHROME = {
  navBarH: 20,         /* 底部 home indicator（横屏 safe.bottom = 20） */
  contentInset: 62,    /* 左侧系统占位：横屏浮条 + 灵动岛所在的那一条（safe.leading） */
  /* 实现里左栏取可用宽的 52%：750 × 0.52 = 390pt（见 HomeView.splitCalendarArea） */
  trailingInset: 62,   /* 右侧对称安全区（safe.trailing） */
  gridInset: 62,       /* 月格/列表左边界 = contentInset */
  headInset: 62,       /* 标题行左边界同上 */
  /* 灵动岛在横屏竖转贴左边缘，占用区约 37（宽）× 132（高）、垂直居中，
     整块落在 x 0–37 内 —— 真正决定左边界的是系统浮条（62），不是它。 */
  islandShort: 37,
  islandLong: 132,
  islandCenterY: null,
};
