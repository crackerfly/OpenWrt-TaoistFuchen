# Taoist Fuchen 2.0.0 实施计划

1. 先增加 host 侧回归测试，覆盖公共校验器、上传边界、配置默认值、init 参数、主题注入、
   ACL、许可和二进制来源；确认旧版本按预期失败。
2. 新增公共 shell 校验库，重写 FakeHTTP/FakeSIP 默认 UCI、LuCI 页面、init 和 hotplug。
3. 移除文件日志与 cron，改用 logd，并加入 nft 兜底清理与受限 respawn。
4. 安装内置 SVG，新增受限上传 CGI，重写 Custom Logo 页面和主题注入服务。
5. 修正 Makefile 架构、依赖和许可，补充精确源代码归档、来源清单和 README。
6. 运行 shell/JS/JSON/ELF/静态策略/上传集成测试，进行独立代码复审后打包。

