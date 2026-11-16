# iTAG 找物

用 Android 手机让附近的 iTAG 蓝牙标签响铃，找回钥匙、耳机盒等随身物品。界面使用 Flutter，蓝牙连接由 Android 原生 BLE 实现。

<img src="res/itag-product.jpg" alt="五种颜色的 iTAG 蓝牙防丢器" width="360">

## 连接和响铃

需要支持低功耗蓝牙（BLE）的 Android 7.0（API 24）或以上手机，以及支持 Immediate Alert Service 的 iTAG 标签。项目以广播服务 `FFE0` 的 iTAG 样机验证，外观相同的标签可能使用不同的协议。

1. 长按标签约 3 秒，听到两声提示音后，在 App 中点「添加标签」。
2. 选择附近的 iTAG，连接后给物品取名，例如「耳机」。也可以跳过，之后通过卡片菜单重命名。
3. 点「响铃」开始找物，找到后点「停止响铃」。卡片菜单提供「断开连接」。

Android 12 及以上需要授予「附近的设备」权限。Android 11 及以下需要为蓝牙扫描授予位置权限。App 把标签和物品名保存在手机本地，可以保存多枚标签，每次连接一枚，并在打开或回到前台时尝试重连上次使用的标签。标签支持电量读取时，卡片会显示电量。

## 从源码运行

使用 [Flutter 3.50.0](https://github.com/flutter/flutter/releases/tag/3.50.0)（含 Dart 3.14.0）和 JDK 21。通过 Android Studio 的 SDK Manager 安装 Android SDK Platform 36、Build Tools 36.0.0 和 NDK 28.2.13676358。连接开启 USB 调试的 Android 真机，在仓库根目录运行：

```sh
flutter doctor --android-licenses
flutter pub get
flutter devices
flutter run -d <设备ID>
```

把 `<设备ID>` 换成 `flutter devices` 输出中的真机 ID。也可以用 `flutter build apk --debug` 生成 APK，输出到 `build/app/outputs/flutter-apk/app-debug.apk`。

## 开发与验证

```sh
flutter analyze
flutter test
```

GitHub Actions 会在向 `main` 推送和提交 Pull Request 时运行静态分析、测试和 Android ARM64 Debug APK 构建。BLE 端点和实测记录见 [iTAG BLE 协议](iTAG-BLE-Protocol.md)。响铃和停止采用无响应写入，请用实体标签确认声响。

欢迎在 GitHub Issues 报告兼容性问题。请附上手机型号、Android 版本、标签广播名和复现步骤。提交代码前请运行上述检查，涉及 BLE 行为的改动请注明真机验证结果。

## 许可证

项目原创代码和文档采用 [MIT 许可证](LICENSE)。商品主图用于辨识标签外观，图片权利归原权利人所有。
