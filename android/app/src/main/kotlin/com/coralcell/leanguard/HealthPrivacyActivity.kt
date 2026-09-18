package com.coralcell.leanguard

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Health Connect opens this policy even when Flutter has not been initialized. */
class HealthPrivacyActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val layout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding * 2, padding, padding)
        }
        layout.addView(TextView(this).apply {
            text = "LeanGuard health data privacy"
            textSize = 26f
        })
        layout.addView(TextView(this).apply {
            text = "\nLeanGuard uses the health data you choose to share to show your activity and weight trends. Basic connection reads steps and weight. Pro can additionally read active energy and workouts. Writing completed strength workouts requires a separate choice.\n\nHealth data is used to provide your fitness features and, only with AI consent, your coaching insights. It is not sold, used for advertising, or included in analytics or crash reports.\n\nYour account data is stored in your private LeanGuard account. You can export your data, disconnect Health Connect, or delete your account from Profile → Privacy. Disconnecting stops future reads; you can also revoke permissions in Android Settings → Health Connect.\n\nNotification text does not include health measurements. LeanGuard does not diagnose conditions, prescribe medication, or recommend dosage changes.\n\nRead the complete privacy policy and contact information in LeanGuard Profile → Privacy.\n"
            textSize = 17f
        })
        layout.addView(Button(this).apply { text = "Close"; setOnClickListener { finish() } })
        setContentView(ScrollView(this).apply { addView(layout) })
    }
}
