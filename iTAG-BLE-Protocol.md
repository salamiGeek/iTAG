# iTAG BLE 协议与 Android 接入

本文基于标签随附说明书和 2026-11-16 在 Linux BlueZ 与 Android 上的实测。样机广播名为 `iTAG`。实测在未配对的情况下完成连接、服务发现和读取。表中的 `[地址]` 代表实测数据中出现的六字节样机地址。按键通知编码待验证。

## 1. 广播与设备识别

| 字段 | 样机观测值 |
| --- | --- |
| 本地名称 | `iTAG` |
| 地址类型 | BlueZ 报告为 public |
| 广播服务 UUID | `FFE0` |
| Manufacturer Specific Data | Company ID `0x0105`，数据 `[地址] 66 02 01 03 00` |

表内所有 16 位短 UUID 都按 `0000xxxx-0000-1000-8000-00805f9b34fb` 展开。例如 `FFE0` 对应 `0000ffe0-0000-1000-8000-00805f9b34fb`。广播中只观测到 `FFE0`。电量和报警服务在连接后发现。

Android 可先按 `FFE0` 扫描，把名称和地址展示给用户选择。样机的厂商数据前六字节恰好与其地址一致，后五字节含义未知。按用户选中的 `ScanResult.device` 连接，再根据发现的服务与特征判断可用功能。

若标签未出现，按说明书长按约 3 秒，听到两声提示音且指示灯闪烁即为开机。复测前可先在 iSearching 中断开标签连接。

## 2. GATT 端点

属性列来自服务发现。读取结果为一次会话的实际返回值，字节以十六进制表示。

| 服务 | 特征 | 声明属性 | 读取结果或用途 | 描述符 |
| --- | --- | --- | --- | --- |
| `180F` Battery Service | `2A19` Battery Level | 读、通知 | `64`，即 100% | `2902`、`2908` |
| `1802` Immediate Alert | `2A06` Alert Level | 写、无响应写 | 标签响铃控制 | `2902` |
| `FFE0` 厂商服务 | `FFE1` | 读、通知 | `01`。疑似按键事件通道，编码待验证 | `2902` |
| `FFE0` | `FFE2` | 写 | iSearching 用于设置标签端断连报警，未单独验证样机配置写入 | — |
| `FFE0` | `FFE3` | 读 | `[地址]`，与样机地址一致 | — |
| `FFE0` | `FFE4` | 读、写 | 读取返回 ATT `0x0A`（Attribute Not Found）。写入用途未知 | — |
| `FFE0` | `FFE5` | 写 | 用途未知 | — |
| `FFE0` | `FFE6` | 读 | `00 00 00`，含义未知 | — |
| `FFE0` | `FFE7` | 读、写 | `00 00 00`，含义未知 | — |

`2902` 是客户端特征配置描述符（CCCD）。当前可按通知属性订阅的端点是 `2A19` 和 `FFE1`。`2A06` 虽然也列出了 `2902`，特征本身未声明通知或指示属性。Android 通过服务 UUID 和特征 UUID 查找端点。 [Bluetooth SIG Assigned Numbers](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Assigned_Numbers/out/en/index-en.html) · [ATT 错误码](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/Core-54/out/en/host/attribute-protocol--att-.html)

## 3. 功能与数据格式

### 3.1 电量

读取 `180F / 2A19`，载荷是一个无符号字节，取值 `0–100`，单位为百分比。Kotlin 可用 `value.singleOrNull()?.toUByte()?.toInt()?.takeIf { it in 0..100 }` 解析。本次读到 `0x64`。端点声明支持通知，可用通知更新界面，实际推送行为待验证。 [Bluetooth Battery Service](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/BAS_v1.1/out/en/index-en.html)

### 3.2 手机让标签响铃

向 `1802 / 2A06` 发送一个二进制字节。iSearching 使用 `01` 响铃、`00` 停止。样机在初版 Android App 的 `02` 无响应写下无声。随后用 BlueZ 对照，`02` 和 `01` 分别用无响应写和普通写发送，四次中听到两次响铃。切换到 `01` 和 `00` 后，现场确认 Android App 可以让样机响铃及停止。

Android App 使用 `WRITE_TYPE_NO_RESPONSE`。例如 Android 13+ 可用 `gatt.writeCharacteristic(alertLevel, byteArrayOf(0x01), BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)` 开始响铃。

| 指令字节 | 标准含义 |
| --- | --- |
| `00` | 停止报警 |
| `01` | 低级报警 |
| `02` | 高级报警 |

样机声明支持标准的无响应写，也额外声明普通写。无响应写没有外设的 ATT 回复，Android 的写入状态无法确认标签是否已经响铃。 [Immediate Alert Service](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/IAS_v1.0/out/en/index-en.html) · [Alert Level 编码表](https://btprodspecificationrefs.blob.core.windows.net/gatt-specification-supplement/GATT_Specification_Supplement.pdf)

### 3.3 标签按键

说明书记载，双击标签切换手机铃声，在 iSearching 相机界面单击标签触发快门。优先订阅 `FFE0 / FFE1`，记录通知时间、完整字节和按键动作。当前读到的 `01` 是一次读取结果，单击和双击的通知载荷均待采集。应在重复测试后决定按通知值区分动作，还是由 App 按通知时间间隔识别双击。

### 3.4 超距报警与断点定位

- **手机端报警**由 App 根据活动 GATT 会话的断开事件处理。将意外断开与用户主动断开区分开。断开回调本身无法确定原因是否为超距。
- **标签端报警**见于说明书的双向报警描述。样机在首版 App 中主动断开时保持静音。本次服务发现未列出标准 Link Loss 服务 `1803`。iSearching 向 `FFE0 / FFE2` 写 `00` 关闭、`01` 开启标签端断连报警。首版 App 沿用样机已有状态。
- **断点定位**由手机记录 BLE 断开时的位置和时间。若使用最近的位置样本，同时保留样本时间，便于区分陈旧位置和断开时获取的位置。说明书还列有 Wi-Fi 勿扰、休眠时段、手机铃声、设备名称和头像。这些功能目前没有已确认的标签端点。

## 4. Android 接入

1. **权限与扫描。** 对 target SDK 31+，在 Android 12+ 声明并运行时申请 `BLUETOOTH_SCAN` 和 `BLUETOOTH_CONNECT`。兼容 Android 11 及以下时，声明旧版 `BLUETOOTH`、`BLUETOOTH_ADMIN`（`maxSdkVersion="30"`），常规 BLE 扫描按系统版本申请位置权限。实现断点定位时另外处理手机定位权限。只有 App 不用蓝牙扫描结果推导物理位置时，才考虑给 `BLUETOOTH_SCAN` 标记 `neverForLocation`，并在目标机型上复测扫描，因为该标记可能过滤部分 BLE 广播。用 `BluetoothLeScanner` 限时扫描，选定设备后停止扫描。 [Android 蓝牙权限](https://developer.android.com/develop/connectivity/bluetooth/bt-permissions) · [扫描 BLE 设备](https://developer.android.com/develop/connectivity/bluetooth/ble/find-ble-devices)
2. **连接与发现。** 前台首次连接可用 `device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)`。在 `onConnectionStateChange` 收到 `GATT_SUCCESS` 且进入 `STATE_CONNECTED` 后调用 `discoverServices()`。等待 `onServicesDiscovered` 成功，再按表查找端点。端点缺失时只禁用相应功能。 [连接 GATT 服务端](https://developer.android.com/develop/connectivity/bluetooth/ble/connect-gatt-server) · [读写 BLE 数据](https://developer.android.com/develop/connectivity/bluetooth/ble/transfer-ble-data)
3. **读取与订阅。** 用 `readCharacteristic()` 读取 `2A19`。为 `FFE1` 或 `2A19` 接收通知时，先调用 `setCharacteristicNotification(characteristic, true)`，再向该特征的 `2902` 写入 `ENABLE_NOTIFICATION_VALUE`（字节 `01 00`），等 `onDescriptorWrite` 成功后开始记录 `onCharacteristicChanged`。重连后重新发现端点并恢复订阅。 [Android BluetoothGatt](https://developer.android.com/reference/android/bluetooth/BluetoothGatt) · [Android BluetoothGattCallback](https://developer.android.com/reference/android/bluetooth/BluetoothGattCallback)
4. **串行执行 GATT 操作。** 每条连接同一时刻提交一个读、写或描述符写操作。检查 API 的即时返回值，并在对应回调、提交失败或超时后处理下一项。Android 13+ 使用直接接收或传入 `ByteArray` 的重载。兼容旧系统时，分别使用旧版 `writeCharacteristic(characteristic)` 和 `writeDescriptor(descriptor)`，提交前设置对象的值和所需的写入类型。断开时清理该连接的队列，结束会话时调用 `close()`。 [Android BluetoothGatt](https://developer.android.com/reference/android/bluetooth/BluetoothGatt)
5. **后台运行。** 若需要锁屏后接收按键或断连事件，通过支持的后台机制维持连接，例如 `connectedDevice` 类型的前台服务，或符合条件时使用 `CompanionDeviceService`。前台可用后，再分别验证退到后台、锁屏和进程重启的行为。 [Android BLE 后台通信](https://developer.android.com/develop/connectivity/bluetooth/ble/background)

## 5. 真机验证清单

| 用例 | 记录内容 |
| --- | --- |
| 扫描、连接、读电量 | Android 机型与系统版本、扫描是否命中、服务列表、`2A19` 原始值 |
| 响铃与停止 | 分别写 `01` 和 `00`，记录实体标签是否开始及停止蜂鸣 |
| 单击、双击、长按 | 订阅 `FFE1` 后采集每次操作的通知条数、时间间隔、载荷和连接状态。长按会开关机，放在最后测 |
| 断开报警 | 分别测试超距、关闭标签和 App 主动断开，记录手机与标签各自的反应。有条件时对照 iSearching 中断开报警开关的状态 |
| 厂商命令 | 在自有手机与标签的会话中，观察 iSearching 切换单项设置时涉及的服务、特征、写入类型和载荷。确认作用后再接入相应端点 |
