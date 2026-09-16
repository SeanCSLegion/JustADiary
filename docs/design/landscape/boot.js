/* 设计稿页面启动：defer 脚本按顺序执行完（engine → devices → frames-*）后启动。
   每个页面（phone.html / wide.html / gallery.html）自己决定加载哪几个文件。 */
document.addEventListener("DOMContentLoaded", () => {
  if (typeof FRAMES === "undefined" || !FRAMES.length) {
    console.error("设计稿：FRAMES 为空 —— 检查 frames-*.js 是否加载成功");
    return;
  }
  bootMockupPage();
});
