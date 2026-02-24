package com.roycommunication.fonex

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * Handles Android Managed Provisioning callbacks so an external provisioner
 * can set this app as Device Owner during setup.
 */
class ProvisioningActivity : Activity() {

    companion object {
        private const val TAG = "FonexProvisioning"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        when (intent?.action) {
            DevicePolicyManager.ACTION_GET_PROVISIONING_MODE -> handleGetProvisioningMode()
            DevicePolicyManager.ACTION_ADMIN_POLICY_COMPLIANCE -> handleAdminPolicyCompliance()
            else -> {
                Log.w(TAG, "Unknown provisioning action: ${intent?.action}")
                finish()
            }
        }
    }

    private fun handleGetProvisioningMode() {
        val resultIntent = Intent().apply {
            putExtra(
                DevicePolicyManager.EXTRA_PROVISIONING_MODE,
                DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE
            )
        }
        setResult(RESULT_OK, resultIntent)
        finish()
    }

    private fun handleAdminPolicyCompliance() {
        try {
            val manager = DeviceLockManager(applicationContext)
            val prefs = applicationContext.getSharedPreferences("fonex_device_prefs", MODE_PRIVATE)
            val isPaidInFull = prefs.getBoolean("is_paid_in_full", false)

            manager.enforceFactoryResetBlock()
            manager.enforceHomeLauncher(unpaidMode = !isPaidInFull)

            Log.i(TAG, "Admin policy compliance completed")
        } catch (e: Exception) {
            Log.e(TAG, "Policy compliance failed: ${e.message}", e)
        }

        setResult(RESULT_OK)
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            }
        )
        finish()
    }
}
