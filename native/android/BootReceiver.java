package io.smartfinance.smart_finance;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Khởi động lại máy -> yêu cầu hệ thống kết nối lại dịch vụ đọc thông báo. */
public class BootReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null) return;
        String a = intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(a) || "android.intent.action.MY_PACKAGE_REPLACED".equals(a)) {
            if (BankStore.enabled(context)) BankNotificationListener.rebind(context);
        }
    }
}
