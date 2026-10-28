# 可独立构建的插件核心包

这些 MIT 包被主程序通过 path 依赖实际使用，不依赖私有 app_database 或主程序页面。每个目录可以单独执行 flutter pub get、flutter analyze 和 flutter test。

- learning_plugin_sdk：共享题目、积分协议模型。
- learning_whiteboard：笔迹、多页文档、撤销重做、本地存储、文档解析。
- learning_words：词语结构、词性、释义和标签归一化。
- learning_scoring：计分方案与本地配置服务。
- learning_challenge：挑战规则、方案及评分判断。

它们是编译时 Flutter 扩展库，不是运行时加载 Dart 源码的安装包。界面和数据库接入仍由宿主提供。JSON 插件中心继续安装声明式页面与规则。source/ 为旧版界面参考快照，不能单独构建；新开发以 packages/ 为准。
