.pragma library
.import "ChinaLunarDates.js" as LunarDates

var lunarMonths = ["", "正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"];
var lunarDays = ["", "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
    "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
    "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"];
var lunarFestivals = { 101: "春节", 115: "元宵节", 505: "端午节", 707: "七夕", 815: "中秋节", 909: "重阳节", 1208: "腊八节" };
var civilFestivals = { 101: "元旦", 501: "劳动节", 1001: "国庆节" };

// State Council General Office notices. MMDD ranges are inclusive.
// https://www.gov.cn/zhengce/content/202411/content_6986382.htm
// https://www.gov.cn/gongbao/2025/issue_12406/material/gwygb202532.pdf
// https://chinajob.mohrss.gov.cn/h5/c/2026-11-09/635850.shtml
var schedules = {
    2025: {
        off: [[101, 101], [128, 204], [404, 406], [501, 505], [531, 602], [1001, 1008]],
        work: [126, 208, 427, 928, 1011]
    },
    2026: {
        off: [[101, 103], [215, 223], [404, 406], [501, 505], [619, 621], [925, 927], [1001, 1007]],
        work: [104, 214, 228, 509, 920, 1010]
    },
    2027: {
        off: [[101, 103], [205, 213], [403, 405], [501, 505], [609, 609], [915, 915], [1001, 1007]],
        work: [131, 214, 508, 926, 1009]
    }
};

var dayMs = 86400000;

function lunarDate(year, month, day) {
    var row = LunarDates.years[year];
    if (!row) return null;

    // The date is local to the grid. Count civil days in UTC to avoid DST transitions.
    var dayIndex = (Date.UTC(year, month, day) - Date.UTC(year, 0, 1)) / dayMs;
    var starts = row.starts;
    var index = starts.length - 2;
    while (starts[index] > dayIndex) index -= 2;

    var signedMonth = starts[index + 1];
    return {
        month: Math.abs(signedMonth),
        leap: signedMonth < 0,
        day: dayIndex - starts[index] + 1,
        eve: signedMonth === 12 && dayIndex + 1 === starts[index + 2] && starts[index + 3] === 1
    };
}

function scheduleLabel(year, mmdd) {
    var schedule = schedules[year];
    if (!schedule) return "";
    if (schedule.work.indexOf(mmdd) >= 0) return "班";
    for (var i = 0; i < schedule.off.length; i++) {
        var range = schedule.off[i];
        if (mmdd >= range[0] && mmdd <= range[1]) return "休";
    }
    return "";
}

function details(date) {
    var year = date.getFullYear();
    var month = date.getMonth();
    var day = date.getDate();
    var mmdd = (month + 1) * 100 + day;
    var lunar = lunarDate(year, month, day);
    var festival = civilFestivals[mmdd] || "";
    var lunarLabel = "";
    if (lunar) {
        lunarLabel = lunar.day === 1
            ? (lunar.leap ? "闰" : "") + lunarMonths[lunar.month]
            : lunarDays[lunar.day];
        if (!lunar.leap) {
            var traditional = lunar.eve ? "除夕" : lunarFestivals[lunar.month * 100 + lunar.day];
            if (traditional) festival = festival ? festival + "·" + traditional : traditional;
        }
        if (mmdd === LunarDates.years[year].qingming) {
            festival = festival ? festival + "·清明节" : "清明节";
        }
    }
    return { lunar: lunarLabel, festival: festival, status: scheduleLabel(year, mmdd) };
}
