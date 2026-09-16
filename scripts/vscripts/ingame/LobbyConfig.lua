-- 本地 launcher 不能 HTTP，只负责跳到专服 wait。
-- 专服 wait 再连 81.69.160.233:8100 的大厅，开局后转 platform。
return {
    host = "81.69.160.233",
    port = 8100,
    mapKey = "dLbi0KfC6RjS-OfAqn1mrPxbiD_JVXNg",
    startTimeoutSeconds = 60,
    waitServer = {
        address = "81.69.160.233:27015",
        password = "",
    },
}
