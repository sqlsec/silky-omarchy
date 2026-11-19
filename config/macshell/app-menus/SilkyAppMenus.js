.pragma library

var navigation = [
    ["Back", "Alt+Left"],
    ["Forward", "Alt+Right"]
];
var restoreTab = ["Reopen Closed Tab", "Ctrl+Shift+t"];
var bookmarks = [
    ["Bookmark This Page…", "Ctrl+d"],
    ["Bookmark All Tabs…", "Ctrl+Shift+d"],
    null,
    ["Toggle Bookmarks Bar", "Ctrl+Shift+b"]
];

var chromium = [
    { id: "silkyMenuHistory", label: "History", items: [
        ["Show Full History", "Ctrl+h"],
        ["Downloads", "Ctrl+j"],
        null,
        restoreTab
    ].concat(navigation) },
    { id: "silkyMenuBookmarks", label: "Bookmarks", items: [
        ["Bookmark Manager", "Ctrl+Shift+o"],
        null
    ].concat(bookmarks) },
    { id: "silkyMenuTabs", label: "Tab", items: [
        ["Search Tabs", "Ctrl+Shift+a"],
        ["Select Previous Tab", "Ctrl+Shift+Tab"],
        ["Select Next Tab", "Ctrl+Tab"],
        null,
        ["New Tab", "Ctrl+t"],
        ["Close Tab", "Ctrl+w"]
    ] }
];

var firefox = [
    { id: "silkyMenuHistory", label: "History", items: [
        ["Show Full History", "Ctrl+Shift+h"],
        ["History Sidebar", "Ctrl+h"],
        null,
        restoreTab
    ].concat(navigation) },
    { id: "silkyMenuBookmarks", label: "Bookmarks", items: [
        ["Manage Bookmarks", "Ctrl+Shift+o"],
        ["Bookmarks Sidebar", "Ctrl+b"],
        null
    ].concat(bookmarks) },
    { id: "silkyMenuTools", label: "Tools", items: [
        ["Downloads", "Ctrl+j"],
        ["Add-ons and Themes", "Ctrl+Shift+a"],
        null,
        ["Developer Tools", "F12"],
        ["Page Source", "Ctrl+u"]
    ] }
];

var nautilus = [
    { id: "silkyMenuGo", label: "Go", items: navigation.concat([
        ["Parent Folder", "Alt+Up"],
        ["Home Folder", "Alt+Home"],
        null,
        ["Go to Location…", "Ctrl+l"]
    ]) }
];

function forApp(appId) {
    var id = appId.toLowerCase();
    switch (id) {
    case "google-chrome":
    case "google-chrome-stable":
    case "com.google.chrome":
    case "chromium":
    case "org.chromium.chromium":
        return chromium;
    case "firefox":
    case "org.mozilla.firefox":
        return firefox;
    case "nautilus":
    case "org.gnome.nautilus":
        return nautilus;
    default:
        return [];
    }
}

var chinese = {
    "History": "历史记录",
    "Bookmarks": "书签",
    "Tab": "标签页",
    "Tools": "工具",
    "Go": "前往",
    "Show Full History": "显示所有历史记录",
    "History Sidebar": "历史记录侧边栏",
    "Bookmark Manager": "书签管理器",
    "Manage Bookmarks": "管理书签",
    "Bookmarks Sidebar": "书签侧边栏",
    "Bookmark This Page…": "为此网页添加书签…",
    "Bookmark All Tabs…": "为所有标签页添加书签…",
    "Toggle Bookmarks Bar": "显示或隐藏书签栏",
    "Search Tabs": "搜索标签页",
    "Select Previous Tab": "选择上一个标签页",
    "Select Next Tab": "选择下一个标签页",
    "Add-ons and Themes": "扩展和主题",
    "Page Source": "查看网页源代码",
    "Back": "后退",
    "Forward": "前进",
    "Parent Folder": "上级文件夹",
    "Home Folder": "主文件夹",
    "Go to Location…": "前往位置…"
};

function label(text, language) {
    return /^zh(?:[-_]|$)/i.test(language) ? chinese[text] || text : text;
}
