package io.smartfinance.smart_finance

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Kênh đọc thông báo ngân hàng (BankChannel.java).
        BankChannel.register(flutterEngine, this)
    }

    override fun onDestroy() {
        BankChannel.unregister()
        super.onDestroy()
    }
}
